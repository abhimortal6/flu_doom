// Ticcmd builder, ported from Chocolate Doom src/g_game.c (G_BuildTiccmd).
//
// Turns the current key/button state into a [TicCmd] for one tic:
// forwardmove / sidemove / angleturn / buttons. It does NOT hard-depend on the
// controls module: it consumes a small injected [KeyState] (a set of action
// booleans) so the integration layer can drive it from the foundation
// EventQueue / DoomKey state however it likes.
//
// Input contract (what the controls layer must provide via [KeyState]):
//   forward / backward / turnLeft / turnRight / strafeLeft / strafeRight,
//   run (speed toggle), strafeModifier (turn keys act as strafe), use, attack,
//   plus optional analog turn (mouse) via [KeyState.analogTurn] and a requested
//   weapon slot. These map 1:1 to vanilla's key bindings.

import '../../engine/math/fixed.dart';
import '../world/ticcmd.dart';

/// Movement magnitude tables, vanilla g_game.c `forwardmove[]`/`sidemove[]`
/// (indexed by [0]=walk, [1]=run) and `angleturn[]` (indexed by tic-held).
const List<int> _forwardMove = <int>[0x19, 0x32]; // 25, 50
const List<int> _sideMove = <int>[0x18, 0x28]; // 24, 40
const List<int> _angleTurn = <int>[640, 1280, 320]; // fast, fast, slow (tic 0)

/// The set of player intents for the current tic, as booleans/analog values.
/// The integration layer fills this from the live key state each tic.
class KeyState {
  bool forward = false;
  bool backward = false;
  bool turnLeft = false;
  bool turnRight = false;
  bool strafeLeft = false;
  bool strafeRight = false;

  /// Speed (run) key held.
  bool run = false;

  /// Strafe modifier: while held, turnLeft/turnRight become strafe.
  bool strafeModifier = false;

  /// Action buttons.
  bool use = false;
  bool attack = false;

  /// Optional analog turn delta (e.g. mouse / touch look), as a vanilla
  /// `mousex`-equivalent value; added on top of keyboard turning. Positive =
  /// turn right (clockwise) in screen terms — applied as `angleturn -= mousex*8`
  /// exactly like vanilla mouse handling (g_game.c).
  int analogTurn = 0;

  /// Optional analog forward/back deflection from a movement stick, scaled to
  /// 16.16 fixed in [-FRACUNIT, FRACUNIT]. +FRACUNIT = full forward. Mirrors
  /// vanilla `joyymove`; the builder applies it via FixedMul(forwardmove[speed])
  /// and SUMS it on top of any keyboard forward/back before the MAXPLMOVE clamp.
  int analogForward = 0;

  /// Optional analog strafe deflection from a movement stick, scaled to 16.16
  /// fixed in [-FRACUNIT, FRACUNIT]. +FRACUNIT = full strafe right. Mirrors
  /// vanilla `joyxmove` (analog strafe path).
  int analogSide = 0;

  /// True when the analog stick is at the run tier (full deflection); selects
  /// `forwardmove[1]`/`sidemove[1]` for the analog contribution, independent of
  /// the keyboard [run] modifier.
  bool analogRun = false;

  /// Requested weapon slot 1..8, or 0 for "no change".
  ///
  /// Vanilla maps the number keys 1..7 directly here (G_BuildTiccmd's
  /// `key_weapon` block). For touch we additionally support cycling — see
  /// [prevWeapon]/[nextWeapon] — which the play-sim resolves into this same
  /// slot before the cmd is built, so the BT_CHANGE path stays single-source.
  int weapon = 0;

  /// Touch-only "previous weapon" request edge for this tic. Vanilla Doom has
  /// no prev/next mechanic; the play-sim ([PlaySim.buildTiccmd]) resolves this
  /// against the live inventory into a concrete [weapon] slot, then this is the
  /// same as a direct 1..7 select. Never read directly by [TicCmdBuilder].
  bool prevWeapon = false;

  /// Touch-only "next weapon" request edge for this tic. See [prevWeapon].
  bool nextWeapon = false;

  void clear() {
    forward = backward = turnLeft = turnRight = strafeLeft = strafeRight = false;
    run = strafeModifier = use = attack = false;
    analogTurn = 0;
    analogForward = 0;
    analogSide = 0;
    analogRun = false;
    weapon = 0;
    prevWeapon = false;
    nextWeapon = false;
  }
}

/// Resolves a touch prev/next-weapon request into a concrete weapon slot, the
/// faithful source-port approach (Crispy/PrBoom `P_SwitchWeapon`-style scan):
/// starting from [readyWeapon], step in [dir] (+1 = next, -1 = prev) over the
/// weapon slots, wrapping, and return the first OWNED & available weapon. This
/// reaches the fist (cycling prev from pistol) and wraps the full ring.
///
/// Faithful availability gates (mirroring P_PlayerThink's BT_CHANGE special
/// cases, g_game.c / p_user.c):
///   * super shotgun ([Wp.supershotgun]) is only reachable in commercial
///     (Doom II) — and only if owned;
///   * plasma / BFG are never reachable in shareware (matching the BT_CHANGE
///     guard), even if somehow owned;
///   * a weapon must be in [weaponOwned] (non-zero) to be selected.
///
/// Returns the chosen weapontype_t (0..numWeapons-1), or [readyWeapon]
/// unchanged if no other owned weapon exists (single-weapon player => no-op).
int resolveWeaponCycle({
  required int dir,
  required int readyWeapon,
  required List<int> weaponOwned,
  required bool commercial,
  required bool shareware,
}) {
  const int n = wpNumWeapons;
  int w = readyWeapon;
  for (int i = 0; i < n; i++) {
    w = (w + dir) % n;
    if (w < 0) w += n;
    if (weaponOwned[w] == 0) continue;
    // Super shotgun: Doom II only.
    if (w == wpSuperShotgun && !commercial) continue;
    // Plasma / BFG: never in shareware.
    if ((w == wpPlasma || w == wpBfg) && shareware) continue;
    return w;
  }
  return readyWeapon; // no other owned/available weapon: stay put
}

// Weapon slot constants mirrored locally so g_build has no dependency on the
// play-sim's info_tables (keeps the input/ticcmd layer self-contained). These
// MUST match Wp.* in info_tables.dart.
const int wpFist = 0;
const int wpPistol = 1;
const int wpPlasma = 5;
const int wpBfg = 6;
const int wpSuperShotgun = 8;
const int wpNumWeapons = 9;

/// Builds ticcmds from key state. Holds the small amount of cross-tic state
/// vanilla keeps (turnheld for acceleration).
class TicCmdBuilder {
  /// How many consecutive tics a turn key has been held (turn acceleration).
  int _turnHeld = 0;

  /// Build the command for this tic into [cmd] (cleared first) from [keys].
  /// Faithful to G_BuildTiccmd's structure (speed index, turn acceleration,
  /// strafe modifier, button assembly).
  void build(TicCmd cmd, KeyState keys) {
    cmd.clear();

    final int speed = keys.run ? 1 : 0;

    // Turn acceleration: slow for the first few tics, then fast.
    final bool turning = keys.turnLeft || keys.turnRight;
    if (turning) {
      _turnHeld++;
    } else {
      _turnHeld = 0;
    }
    final int tspeed = _turnHeld < 6 ? 2 : speed; // index into _angleTurn

    int forward = 0;
    int side = 0;
    int angle = 0;

    // Strafe modifier turns left/right keys into strafing.
    if (keys.strafeModifier) {
      if (keys.turnRight) side += _sideMove[speed];
      if (keys.turnLeft) side -= _sideMove[speed];
    } else {
      if (keys.turnRight) angle -= _angleTurn[tspeed];
      if (keys.turnLeft) angle += _angleTurn[tspeed];
    }

    if (keys.forward) forward += _forwardMove[speed];
    if (keys.backward) forward -= _forwardMove[speed];
    if (keys.strafeRight) side += _sideMove[speed];
    if (keys.strafeLeft) side -= _sideMove[speed];

    // Analog movement stick (touch / joystick). Mirrors vanilla g_game.c's
    // analog joystick path (use_analog): the deflection is a FRACUNIT-scaled
    // value in [-FRACUNIT, FRACUNIT], and the move is FixedMul(move[speed], v).
    // It SUMS on top of any keyboard movement before the MAXPLMOVE clamp, so
    // touch and keys cooperate rather than fight. The analog speed tier is
    // chosen by [analogRun] (full deflection), like a joystick that runs near
    // its edge. When the stick is centered both deltas are zero, leaving the
    // keyboard-only result untouched.
    if (keys.analogForward != 0 || keys.analogSide != 0) {
      final int aSpeed = keys.analogRun ? 1 : 0;
      // joyymove sign: pushing the stick UP (+1 forward) moves forward, so we
      // negate vanilla's `forward -= FixedMul(forwardmove, joyymove)` by feeding
      // a +forward deflection here (caller already uses +1 == forward).
      forward += fixedMul(_forwardMove[aSpeed], keys.analogForward);
      side += fixedMul(_sideMove[aSpeed], keys.analogSide);
    }

    // Analog (mouse / touch look) turn, like vanilla: `angleturn -= mousex*0x8`.
    angle -= keys.analogTurn * 0x8;

    // Clamp to vanilla MAXPLMOVE (== forwardmove[1]/sidemove[1]).
    final int fwdMax = _forwardMove[1];
    final int sideMax = _sideMove[1];
    if (forward > fwdMax) forward = fwdMax;
    if (forward < -fwdMax) forward = -fwdMax;
    if (side > sideMax) side = sideMax;
    if (side < -sideMax) side = -sideMax;

    cmd.forwardMove = forward;
    cmd.sideMove = side;
    cmd.angleTurn = angle;

    if (keys.attack) cmd.buttons |= btAttack;
    if (keys.use) cmd.buttons |= btUse;

    if (keys.weapon >= 1 && keys.weapon <= 8) {
      cmd.buttons |= btChangeWeapon;
      cmd.buttons |= ((keys.weapon - 1) << btWeaponShift) & btWeaponMask;
    }
  }
}
