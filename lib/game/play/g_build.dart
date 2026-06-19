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

  /// Optional analog turn delta (e.g. mouse), in raw angleturn units; added on
  /// top of keyboard turning. Positive = turn right (clockwise) in screen terms
  /// — applied as a negative angleturn like vanilla mouse handling.
  int analogTurn = 0;

  /// Requested weapon slot 1..8, or 0 for "no change".
  int weapon = 0;

  void clear() {
    forward = backward = turnLeft = turnRight = strafeLeft = strafeRight = false;
    run = strafeModifier = use = attack = false;
    analogTurn = 0;
    weapon = 0;
  }
}

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

    // Analog (mouse) turn, like vanilla: subtract from angleturn.
    angle -= keys.analogTurn;

    // Clamp to vanilla signed-char / short ranges.
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
