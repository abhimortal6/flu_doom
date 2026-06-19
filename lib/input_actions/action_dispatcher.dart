// Central action sink. Both the keyboard binding system and the on-screen
// overlay call into this to dispatch [GameAction]s. It translates each action
// into one or more [DoomEvent]s posted onto the foundation [EventQueue], and
// maintains a live key-state set (the down keycodes) that a future
// G_BuildTiccmd can read directly — mirroring vanilla's gamekeydown[] array.

import '../engine/input/event.dart';
import 'game_action.dart';

/// Abstract sink for game actions. The overlay and keyboard layers depend on
/// this interface, not on [EventQueue] directly, so they can be tested with a
/// recording fake.
abstract interface class ActionSink {
  /// Action button/key pressed (begin holding).
  void pressAction(GameAction action);

  /// Action button/key released.
  void releaseAction(GameAction action);

  /// Momentary action (press immediately followed by release) — convenient for
  /// taps on weapon/menu buttons.
  void tapAction(GameAction action);
}

/// Default [ActionSink] that feeds the Doom [EventQueue] and tracks key-state.
///
/// Key-state ([downKeys]) is a set of Doom keycodes currently held. This is the
/// data G_BuildTiccmd consumes in vanilla (gamekeydown[]). The EventQueue gets
/// the discrete keyDown/keyUp events (used by the menu, weapon switch, etc.).
class ActionDispatcher implements ActionSink {
  ActionDispatcher(this.queue);

  /// The foundation event queue that downstream Doom code drains per tic.
  final EventQueue queue;

  /// Doom keycodes currently held down. Multiple actions may reference the same
  /// keycode (ref-counted) so releasing one held action does not clear a key
  /// still held by another.
  final Map<int, int> _refCounts = <int, int>{};

  /// Read-only view of currently-pressed Doom keycodes (for G_BuildTiccmd).
  Set<int> get downKeys =>
      _refCounts.entries.where((e) => e.value > 0).map((e) => e.key).toSet();

  /// True if [code] is currently held (key-state query).
  bool isKeyDown(int code) => (_refCounts[code] ?? 0) > 0;

  @override
  void pressAction(GameAction action) {
    for (final int code in ActionKeys.keysFor(action)) {
      final int prev = _refCounts[code] ?? 0;
      _refCounts[code] = prev + 1;
      if (prev == 0) {
        // First holder of this key: emit the edge.
        queue.postEvent(DoomEvent.keyDown(code));
      }
    }
  }

  @override
  void releaseAction(GameAction action) {
    for (final int code in ActionKeys.keysFor(action)) {
      final int prev = _refCounts[code] ?? 0;
      if (prev <= 0) continue;
      final int next = prev - 1;
      _refCounts[code] = next;
      if (next == 0) {
        queue.postEvent(DoomEvent.keyUp(code));
      }
    }
  }

  @override
  void tapAction(GameAction action) {
    // Momentary: emit a clean down/up pair without disturbing ref-counts for
    // keys that may be held by something else. We post edges directly.
    for (final int code in ActionKeys.keysFor(action)) {
      queue.postEvent(DoomEvent.keyDown(code));
      queue.postEvent(DoomEvent.keyUp(code));
    }
  }

  /// Release everything (e.g. on focus loss / app pause) to avoid stuck keys.
  void releaseAll() {
    for (final entry in _refCounts.entries) {
      if (entry.value > 0) {
        queue.postEvent(DoomEvent.keyUp(entry.key));
      }
    }
    _refCounts.clear();
  }
}
