// player_t and pspdef_t, ported from Chocolate Doom src/d_player.h /
// p_pspr.h.
//
// A [Player] holds the per-player state attached to a controlling [Mobj]:
// view height + bob, momentum bookkeeping for view calc, weapon sprites
// (pspdef_t), ammo/health/armor and the current command. THIS SLICE wires the
// fields needed for movement + view (P_PlayerThink/P_MovePlayer/P_CalcHeight);
// inventory/weapons/damage are present as faithful fields but their logic is
// deferred (stubbed).

import '../../engine/math/fixed.dart';
import '../world/ticcmd.dart';
import 'info.dart';
import 'info_tables.dart';
import 'mobj.dart';

/// Player life state, vanilla `playerstate_t`.
enum PlayerState {
  /// Playing or camping. PST_LIVE.
  live,

  /// Dead on the ground, view going down. PST_DEAD.
  dead,

  /// Ready to restart/respawn. PST_REBORN.
  reborn,
}

/// Vanilla VIEWHEIGHT: default eye height above the feet (fixed_t, 41 units).
const fixed_t kViewHeight = 41 * kFracUnit;

/// A weapon sprite definition, vanilla `pspdef_t` (p_pspr.h). One for the
/// weapon, one for the muzzle flash.
class Pspdef {
  Pspdef();

  /// Index into states[] of this sprite's current state; <=0 = inactive.
  int stateIndex = 0;

  /// Tics left in the current state. Vanilla `tics`.
  int tics = 0;

  /// Horizontal offset (fixed_t). Vanilla `sx`.
  fixed_t sx = 0;

  /// Vertical offset (fixed_t). Vanilla `sy`.
  fixed_t sy = 0;
}

/// Indices into [Player.psprites]: weapon and flash. Vanilla psprnum_t.
const int psWeapon = 0;
const int psFlash = 1;
const int numPsprites = 2;

/// Per-player state, vanilla `player_t`.
class Player {
  Player();

  /// The mobj this player controls. Vanilla `mo`.
  Mobj? mo;

  /// Life state. Vanilla `playerstate`.
  PlayerState playerState = PlayerState.live;

  /// This tic's command. Vanilla `cmd`.
  final TicCmd cmd = TicCmd();

  /// Eye height above feet (fixed_t). Vanilla `viewheight`.
  fixed_t viewHeight = kViewHeight;

  /// Bob/squat target delta toward [viewHeight]. Vanilla `deltaviewheight`.
  fixed_t deltaViewHeight = 0;

  /// Current view bob amount (fixed_t). Vanilla `bob`.
  fixed_t bob = 0;

  /// Final computed eye Z written to the viewpoint (fixed_t). Vanilla `viewz`.
  fixed_t viewZ = 0;

  /// Health (mirrors mo.health for HUD). Vanilla `health`.
  int health = 100;

  /// Armor points / type. Vanilla `armorpoints` / `armortype`.
  int armorPoints = 0;
  int armorType = 0;

  /// Frags/kills/items/secrets counters (intermission). Vanilla.
  int killCount = 0;
  int itemCount = 0;
  int secretCount = 0;

  /// "Fixed angle" for teleports etc. (0 = use mobj angle). Vanilla.
  int fixedColormap = 0;

  /// Damage-tint / bonus counters (palette flashes). Vanilla.
  int damageCount = 0;
  int bonusCount = 0;

  /// The mobj that last damaged us. Vanilla `attacker`.
  Mobj? attacker;

  /// Refire count for the current weapon. Vanilla `refire`.
  int refire = 0;

  /// Whether the player just attacked / used something (button latches).
  bool attackDown = false;
  bool useDown = false;

  /// The two player sprites (weapon + flash). Vanilla `psprites[NUMPSPRITES]`.
  final List<Pspdef> psprites =
      List<Pspdef>.generate(numPsprites, (_) => Pspdef(), growable: false);

  /// Convenience: the current sprite for the weapon psprite (renderer/HUD).
  SpriteNum? get weaponSprite {
    final int idx = psprites[psWeapon].stateIndex;
    if (idx <= 0) return null;
    return states[idx].sprite;
  }
}
