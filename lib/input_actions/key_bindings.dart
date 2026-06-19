// Keyboard binding model: maps physical/logical keys -> [GameAction].
//
// Bindings are keyed by LogicalKeyboardKey.keyId (a stable int), which makes
// them trivially serializable for persistence. Defaults follow vanilla-style
// Doom controls (arrows + WASD, Ctrl fire, Space use, Shift run, 1-7 weapons,
// Tab automap, Esc menu, Enter confirm). Fully rebindable at runtime.

import 'package:flutter/services.dart';

import 'game_action.dart';

/// A mutable map of LogicalKeyboardKey.keyId -> [GameAction].
///
/// Multiple keys may map to the same action (e.g. ArrowUp and W both
/// moveForward). A single key maps to at most one action.
class KeyBindings {
  KeyBindings(Map<int, GameAction> bindings)
    : _map = Map<int, GameAction>.of(bindings);

  final Map<int, GameAction> _map;

  /// The action bound to [key], or null if unbound.
  GameAction? actionFor(LogicalKeyboardKey key) => _map[key.keyId];

  /// The action bound to a raw logical key id, or null.
  GameAction? actionForId(int keyId) => _map[keyId];

  /// All key ids currently bound to [action].
  List<int> keysFor(GameAction action) => _map.entries
      .where((e) => e.value == action)
      .map((e) => e.key)
      .toList(growable: false);

  /// Bind [key] to [action], replacing any existing binding for that key.
  void bind(LogicalKeyboardKey key, GameAction action) {
    _map[key.keyId] = action;
  }

  /// Remove the binding for [key].
  void unbind(LogicalKeyboardKey key) => _map.remove(key.keyId);

  /// Remove every key bound to [action].
  void clearAction(GameAction action) {
    _map.removeWhere((_, a) => a == action);
  }

  /// Immutable snapshot of the underlying map (keyId -> action name).
  Map<int, GameAction> get entries => Map<int, GameAction>.unmodifiable(_map);

  /// Serialize to a JSON-safe map: keyId(string) -> action.name.
  Map<String, String> toJson() => _map.map(
    (id, action) => MapEntry(id.toString(), action.name),
  );

  /// Deserialize. Unknown action names / malformed ids are skipped.
  factory KeyBindings.fromJson(Map<String, dynamic> json) {
    final Map<int, GameAction> map = <int, GameAction>{};
    json.forEach((idStr, actionName) {
      final int? id = int.tryParse(idStr);
      if (id == null) return;
      final GameAction? action = GameAction.values
          .where((a) => a.name == actionName)
          .cast<GameAction?>()
          .firstWhere((a) => true, orElse: () => null);
      if (action != null) map[id] = action;
    });
    return KeyBindings(map);
  }

  KeyBindings copy() => KeyBindings(_map);

  /// Vanilla-style default bindings.
  factory KeyBindings.defaults() {
    final Map<int, GameAction> m = <int, GameAction>{};
    void b(LogicalKeyboardKey k, GameAction a) => m[k.keyId] = a;

    // Movement — arrows + WASD.
    b(LogicalKeyboardKey.arrowUp, GameAction.moveForward);
    b(LogicalKeyboardKey.keyW, GameAction.moveForward);
    b(LogicalKeyboardKey.arrowDown, GameAction.moveBackward);
    b(LogicalKeyboardKey.keyS, GameAction.moveBackward);
    b(LogicalKeyboardKey.arrowLeft, GameAction.turnLeft);
    b(LogicalKeyboardKey.arrowRight, GameAction.turnRight);

    // Strafe — A/D + comma/period.
    b(LogicalKeyboardKey.keyA, GameAction.strafeLeft);
    b(LogicalKeyboardKey.keyD, GameAction.strafeRight);
    b(LogicalKeyboardKey.comma, GameAction.strafeLeft);
    b(LogicalKeyboardKey.period, GameAction.strafeRight);
    b(LogicalKeyboardKey.altLeft, GameAction.strafeModifier);

    // Run / speed.
    b(LogicalKeyboardKey.shiftLeft, GameAction.run);

    // Combat / interaction.
    b(LogicalKeyboardKey.controlLeft, GameAction.fire);
    b(LogicalKeyboardKey.space, GameAction.use);

    // Weapons 1-7.
    b(LogicalKeyboardKey.digit1, GameAction.weapon1);
    b(LogicalKeyboardKey.digit2, GameAction.weapon2);
    b(LogicalKeyboardKey.digit3, GameAction.weapon3);
    b(LogicalKeyboardKey.digit4, GameAction.weapon4);
    b(LogicalKeyboardKey.digit5, GameAction.weapon5);
    b(LogicalKeyboardKey.digit6, GameAction.weapon6);
    b(LogicalKeyboardKey.digit7, GameAction.weapon7);
    b(LogicalKeyboardKey.minus, GameAction.prevWeapon);
    b(LogicalKeyboardKey.equal, GameAction.nextWeapon);

    // Map / system.
    b(LogicalKeyboardKey.tab, GameAction.automap);
    b(LogicalKeyboardKey.escape, GameAction.menuToggle);
    b(LogicalKeyboardKey.pause, GameAction.pause);

    // Confirmation. Menu navigation reuses arrows (already bound to move/turn;
    // the playsim disambiguates by game state). Enter is the dedicated confirm.
    b(LogicalKeyboardKey.enter, GameAction.confirm);
    b(LogicalKeyboardKey.numpadEnter, GameAction.confirm);

    return KeyBindings(m);
  }
}
