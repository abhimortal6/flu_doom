// Integration adapter: exposes the play-sim's player_t to the game-state /
// status-bar / HUD via the injected [PlayerStatus] interface.
//
// The status bar / HUD only READ values; this adapter maps the live play-sim
// [Player] fields onto the [PlayerStatus] contract (st_stuff.c source values).
//
// COMBAT-D: now that the play-sim simulates real combat (firing, pickups,
// weapon switching), this adapter reads the LIVE inventory fields directly —
// health / armor / readyWeapon / weaponOwned / ammo / maxAmmo / readyWeaponAmmo
// / cards / powers / damageCount / bonusCount / isDead. The HUD therefore
// reflects real pickups and ammo, not a synthesized starting loadout.

import '../play/info_tables.dart';
import '../play/player.dart';
import '../state/interfaces.dart';

/// powertype_t (doomdef.h) indices the HUD surfaces. [PowerType] only exposes
/// invulnerability / strength / infrared; map them to the vanilla powers[]
/// slots (pw_invulnerability=0, pw_strength=1, pw_infrared=5).
const List<int> _powerSlot = <int>[
  0, // PowerType.invulnerability -> pw_invulnerability
  1, // PowerType.strength        -> pw_strength
  5, // PowerType.infrared        -> pw_infrared
];

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

  @override
  int get readyWeapon => player.readyWeapon;

  @override
  bool ownsWeapon(int slot) => player.weaponOwned[slot] != 0;

  @override
  int ammo(AmmoType type) => player.ammo[type.index];

  @override
  int maxAmmo(AmmoType type) => player.maxAmmo[type.index];

  @override
  AmmoType? get readyWeaponAmmo {
    final int a = weaponInfo[player.readyWeapon].ammo;
    return a == Am.noAmmo ? null : AmmoType.values[a];
  }

  @override
  bool ownsCard(int index) => player.cards[index];

  @override
  int get fragCount => player.frags[0];

  @override
  int powerTics(PowerType power) => player.powers[_powerSlot[power.index]];

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
