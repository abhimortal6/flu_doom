// Integration adapter: exposes the play-sim's player_t to the game-state /
// status-bar / HUD via the injected [PlayerStatus] interface.
//
// The status bar / HUD only READ values; this adapter maps the live play-sim
// [Player] fields onto the [PlayerStatus] contract (st_stuff.c source values).
//
// NOTE on the current play-sim slice: weapons/ammo/keys/powers are not yet
// simulated (firing + pickups are deferred — see CONTRACTS_PLAY.md §4). The
// player always starts with the vanilla initial loadout (fist + pistol, 50
// bullets). This adapter therefore reports that fixed starting arsenal for the
// inventory accessors while reflecting the LIVE health / armor / damage / bonus
// / attack state from the simulation. When the play-sim grows real inventory
// fields, swap the synthesized values for the real arrays — the interface is
// unchanged.

import '../play/player.dart';
import '../state/interfaces.dart';

/// Vanilla `maxammo[]` (am_clip, am_shell, am_cell, am_misl).
const List<int> _maxAmmo = <int>[200, 50, 300, 50];

/// Vanilla initial loadout ammo (player starts with 50 bullets).
const List<int> _startAmmo = <int>[50, 0, 0, 0];

/// Read-only [PlayerStatus] over a play-sim [Player].
class PlayerStatusAdapter implements PlayerStatus {
  PlayerStatusAdapter(this.player);

  final Player player;

  @override
  int get health => player.health;

  @override
  int get armor => player.armorPoints;

  @override
  int get armorType => player.armorType;

  // Pistol (slot 1) is the starting ready weapon. (Weapon switching is not yet
  // simulated; readyweapon stays pistol.)
  @override
  int get readyWeapon => 1;

  @override
  bool ownsWeapon(int slot) => slot == 0 || slot == 1; // fist + pistol.

  @override
  int ammo(AmmoType type) => _startAmmo[type.index];

  @override
  int maxAmmo(AmmoType type) => _maxAmmo[type.index];

  // Pistol consumes clip (bullets).
  @override
  AmmoType? get readyWeaponAmmo => AmmoType.clip;

  @override
  bool ownsCard(int index) => false; // No keys at level start.

  @override
  int get fragCount => 0;

  @override
  int powerTics(PowerType power) => 0;

  @override
  int get damageCount => player.damageCount;

  @override
  int get bonusCount => player.bonusCount;

  @override
  bool get attackDown => player.attackDown;

  @override
  bool get isDead =>
      player.health <= 0 || player.playerState == PlayerState.dead;
}
