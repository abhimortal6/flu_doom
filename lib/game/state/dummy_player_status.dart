// A simple mutable [PlayerStatus] implementation for testing and for the
// title/demo screen before a real playsim is wired. All fields are public and
// settable so tests can drive the status bar / HUD / face to known states.

import 'interfaces.dart';

/// A plain-data [PlayerStatus]. Defaults to a freshly-spawned player
/// (100 health, pistol with 50 bullets, fist + pistol owned, no keys).
class DummyPlayerStatus implements PlayerStatus {
  DummyPlayerStatus();

  @override
  int health = 100;

  @override
  int armor = 0;

  @override
  int armorType = 0;

  @override
  int readyWeapon = 1; // pistol

  /// Owned-weapon flags, indexed by slot 0..8.
  final List<bool> weapons = <bool>[
    true, // fist
    true, // pistol
    false, false, false, false, false, false, false,
  ];

  /// Ammo per [AmmoType].
  final Map<AmmoType, int> ammoCounts = <AmmoType, int>{
    AmmoType.clip: 50,
    AmmoType.shell: 0,
    AmmoType.cell: 0,
    AmmoType.misl: 0,
  };

  /// Max ammo per [AmmoType] (vanilla starting maxima).
  final Map<AmmoType, int> maxAmmoCounts = <AmmoType, int>{
    AmmoType.clip: 200,
    AmmoType.shell: 50,
    AmmoType.cell: 300,
    AmmoType.misl: 50,
  };

  /// Ammo the ready weapon consumes (null for fist/chainsaw).
  AmmoType? readyAmmo = AmmoType.clip;

  /// Held cards/skulls, indexed 0..5 (3 cards, 3 skulls).
  final List<bool> cards = List<bool>.filled(6, false);

  @override
  int fragCount = 0;

  /// Power-up tics by type.
  final Map<PowerType, int> powers = <PowerType, int>{};

  @override
  int damageCount = 0;

  @override
  int bonusCount = 0;

  @override
  bool attackDown = false;

  @override
  bool ownsWeapon(int slot) =>
      slot >= 0 && slot < weapons.length && weapons[slot];

  @override
  int ammo(AmmoType type) => ammoCounts[type] ?? 0;

  @override
  int maxAmmo(AmmoType type) => maxAmmoCounts[type] ?? 0;

  @override
  AmmoType? get readyWeaponAmmo => readyAmmo;

  @override
  bool ownsCard(int index) =>
      index >= 0 && index < cards.length && cards[index];

  @override
  int powerTics(PowerType power) => powers[power] ?? 0;

  @override
  bool get isDead => health <= 0;

  /// pw_ironfeet (radiation suit) tics. Settable in tests.
  int ironfeet = 0;

  @override
  int get ironfeetTics => ironfeet;

  @override
  int get paletteIndex => stPaletteIndex(
        damageCount: damageCount,
        bonusCount: bonusCount,
        strengthTics: powers[PowerType.strength] ?? 0,
        ironfeetTics: ironfeet,
      );
}
