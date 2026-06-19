// Logical Doom actions. This is the stable contract that both the keyboard
// binding system and the on-screen overlay target. Actions are mapped to one
// or more Doom keycodes ([DoomKey]) and dispatched as [DoomEvent]s into the
// foundation [EventQueue]; the future G_BuildTiccmd reads those events / the
// derived key-state exactly as in vanilla Doom.
//
// IMPORTANT: This layer never touches ticcmd internals. It only produces
// DoomEvents (and a queryable key-state set) — the same contract vanilla's
// playsim consumes.

import '../engine/input/doomkeys.dart';

/// Every logical action the player / menu can trigger.
///
/// Grouped: movement, strafing, run modifier, combat, weapons, automap and
/// menu/navigation. Each maps to the Doom keycode(s) the playsim expects.
enum GameAction {
  // --- Movement ---
  moveForward,
  moveBackward,
  turnLeft,
  turnRight,
  strafeLeft,
  strafeRight,

  /// Hold to make turnLeft/turnRight strafe instead (vanilla "strafe on" key).
  strafeModifier,

  /// Hold to run (movement speed up). Vanilla "speed" / always-run modifier.
  run,

  // --- Combat / interaction ---
  fire,
  use,

  // --- Weapons ---
  weapon1,
  weapon2,
  weapon3,
  weapon4,
  weapon5,
  weapon6,
  weapon7,
  prevWeapon,
  nextWeapon,

  // --- Map / system ---
  automap,

  /// Toggle the menu / act as escape.
  menuToggle,
  pause,

  // --- Menu navigation / confirmation ---
  confirm,
  menuUp,
  menuDown,
  menuLeft,
  menuRight,
}

/// Maps each [GameAction] to the Doom keycode(s) it emits.
///
/// Most actions map to exactly one [DoomKey]. A few (e.g. [GameAction.confirm]
/// == enter) intentionally share a keycode with a navigation action because
/// vanilla Doom uses the same physical key for both contexts (menu enter and
/// in-game "enter"). The playsim disambiguates by game state, not by us.
///
/// Note: weapon switch via [GameAction.prevWeapon] / [GameAction.nextWeapon]
/// maps to the minus/equals keys, which vanilla binds to weapon cycling.
abstract final class ActionKeys {
  /// The canonical Doom keycode(s) emitted for [action].
  ///
  /// Returns the keys in the order they should be posted. For all current
  /// actions this is a single key, but the API is a list so future
  /// multi-key actions (e.g. chorded inputs) need no signature change.
  static List<int> keysFor(GameAction action) {
    switch (action) {
      case GameAction.moveForward:
        return const <int>[DoomKey.upArrow];
      case GameAction.moveBackward:
        return const <int>[DoomKey.downArrow];
      case GameAction.turnLeft:
        return const <int>[DoomKey.leftArrow];
      case GameAction.turnRight:
        return const <int>[DoomKey.rightArrow];
      case GameAction.strafeLeft:
        // Vanilla comma; doomdef maps strafe-left to ','.
        return const <int>[0x2c]; // ','
      case GameAction.strafeRight:
        return const <int>[0x2e]; // '.'
      case GameAction.strafeModifier:
        return const <int>[DoomKey.rAlt];
      case GameAction.run:
        return const <int>[DoomKey.rShift];
      case GameAction.fire:
        return const <int>[DoomKey.rCtrl];
      case GameAction.use:
        return const <int>[DoomKey.spacebar];
      case GameAction.weapon1:
        return const <int>[0x31]; // '1'
      case GameAction.weapon2:
        return const <int>[0x32];
      case GameAction.weapon3:
        return const <int>[0x33];
      case GameAction.weapon4:
        return const <int>[0x34];
      case GameAction.weapon5:
        return const <int>[0x35];
      case GameAction.weapon6:
        return const <int>[0x36];
      case GameAction.weapon7:
        return const <int>[0x37];
      case GameAction.prevWeapon:
        return const <int>[DoomKey.minus]; // '-'
      case GameAction.nextWeapon:
        return const <int>[DoomKey.equals]; // '='
      case GameAction.automap:
        return const <int>[DoomKey.tab];
      case GameAction.menuToggle:
        return const <int>[DoomKey.escape];
      case GameAction.pause:
        return const <int>[DoomKey.pause];
      case GameAction.confirm:
        return const <int>[DoomKey.enter];
      case GameAction.menuUp:
        return const <int>[DoomKey.upArrow];
      case GameAction.menuDown:
        return const <int>[DoomKey.downArrow];
      case GameAction.menuLeft:
        return const <int>[DoomKey.leftArrow];
      case GameAction.menuRight:
        return const <int>[DoomKey.rightArrow];
    }
  }

  /// Human-readable label for UI (overlay buttons, settings rows).
  static String label(GameAction action) {
    switch (action) {
      case GameAction.moveForward:
        return 'Move Forward';
      case GameAction.moveBackward:
        return 'Move Backward';
      case GameAction.turnLeft:
        return 'Turn Left';
      case GameAction.turnRight:
        return 'Turn Right';
      case GameAction.strafeLeft:
        return 'Strafe Left';
      case GameAction.strafeRight:
        return 'Strafe Right';
      case GameAction.strafeModifier:
        return 'Strafe Modifier';
      case GameAction.run:
        return 'Run';
      case GameAction.fire:
        return 'Fire';
      case GameAction.use:
        return 'Use / Open';
      case GameAction.weapon1:
        return 'Weapon 1';
      case GameAction.weapon2:
        return 'Weapon 2';
      case GameAction.weapon3:
        return 'Weapon 3';
      case GameAction.weapon4:
        return 'Weapon 4';
      case GameAction.weapon5:
        return 'Weapon 5';
      case GameAction.weapon6:
        return 'Weapon 6';
      case GameAction.weapon7:
        return 'Weapon 7';
      case GameAction.prevWeapon:
        return 'Previous Weapon';
      case GameAction.nextWeapon:
        return 'Next Weapon';
      case GameAction.automap:
        return 'Automap';
      case GameAction.menuToggle:
        return 'Menu / Escape';
      case GameAction.pause:
        return 'Pause';
      case GameAction.confirm:
        return 'Confirm / Enter';
      case GameAction.menuUp:
        return 'Menu Up';
      case GameAction.menuDown:
        return 'Menu Down';
      case GameAction.menuLeft:
        return 'Menu Left';
      case GameAction.menuRight:
        return 'Menu Right';
    }
  }
}
