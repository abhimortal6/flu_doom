// Stable string identifiers for repositionable overlay clusters/buttons.
// Used as keys in OverlaySettings.positionsPortrait / positionsLandscape
// (drag-to-reposition overrides). These match the GAMEPLAY-mode controls the
// live overlay and the layout-customizer screen draw.

abstract final class OverlayButtonId {
  static const String movementStick = 'movementStick';
  static const String fire = 'fire';
  static const String use = 'use';
  static const String prevWeapon = 'prevWeapon';
  static const String nextWeapon = 'nextWeapon';
  static const String automap = 'automap';
  static const String menu = 'menu';
  static const String pause = 'pause';

  /// Every repositionable id, in a stable draw/iteration order.
  static const List<String> all = <String>[
    movementStick,
    fire,
    use,
    prevWeapon,
    nextWeapon,
    automap,
    menu,
    pause,
  ];

  /// Human-readable label for the customizer UI.
  static String label(String id) {
    switch (id) {
      case movementStick:
        return 'MOVE';
      case fire:
        return 'FIRE';
      case use:
        return 'USE';
      case prevWeapon:
        return 'PREV';
      case nextWeapon:
        return 'NEXT';
      case automap:
        return 'MAP';
      case menu:
        return 'MENU';
      case pause:
        return 'PAUSE';
      default:
        return id;
    }
  }
}
