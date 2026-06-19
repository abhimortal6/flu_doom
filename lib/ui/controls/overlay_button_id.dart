// Stable string identifiers for repositionable overlay clusters/buttons.
// Used as keys in OverlaySettings.positions (drag-to-reposition overrides).

abstract final class OverlayButtonId {
  static const String movementStick = 'movementStick';
  static const String fire = 'fire';
  static const String use = 'use';
  static const String run = 'run';
  static const String automap = 'automap';
  static const String menu = 'menu';
  static const String prevWeapon = 'prevWeapon';
  static const String nextWeapon = 'nextWeapon';

  static const List<String> all = <String>[
    movementStick,
    fire,
    use,
    run,
    automap,
    menu,
    prevWeapon,
    nextWeapon,
  ];
}
