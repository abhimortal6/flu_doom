// Central action sink. Both the keyboard binding system and the on-screen
// overlay call into this to dispatch [GameAction]s. It translates each action
// into one or more [DoomEvent]s posted onto the foundation [EventQueue], and
// maintains a live key-state set (the down keycodes) that a future
// G_BuildTiccmd can read directly — mirroring vanilla's gamekeydown[] array.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;

import '../engine/input/event.dart';
import 'game_action.dart';

/// When true, the input layer prints `[touch]`-tagged lines for taps, the key
/// edges they post, the per-tic sampler, and applied weapon cycles. Read on the
/// phone via `adb logcat | grep '\[touch\]'`.
///
/// Gated on `!kReleaseMode` so it emits in BOTH debug AND **profile** builds
/// (the integration verifies on-device with a profile build) and is fully
/// compiled out of release. These logs are infrequent — only on discrete button
/// presses / weapon-affecting tics — so they do not spam.
const bool kTouchInputDebugLog = !kReleaseMode;

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
///
/// Named [EventQueueActionSink] (not "ActionDispatcher") to avoid clashing with
/// Flutter's widgets `ActionDispatcher`.
class EventQueueActionSink implements ActionSink {
  EventQueueActionSink(this.queue);

  /// The foundation event queue that downstream Doom code drains per tic.
  final EventQueue queue;

  /// Doom keycodes currently held down. Multiple actions may reference the same
  /// keycode (ref-counted) so releasing one held action does not clear a key
  /// still held by another.
  final Map<int, int> _refCounts = <int, int>{};

  /// Pending min-hold timers, keyed by Doom keycode. A momentary [tapAction]
  /// presses the key (ref-count++), then schedules its release after
  /// [tapMinHold] so the 35 Hz per-tic key-state sampler is GUARANTEED to
  /// observe the key as down for at least one tic. Without this, a touch tap's
  /// down+up completes inside a single frame (<16 ms) — well under one tic
  /// period (~28.6 ms) — and the per-tic sampler (KeyStateBridge) never sees it,
  /// so USE / weapon-switch taps silently do nothing. (The menu still works
  /// because it consumes discrete EventQueue events, not the sampled key-state.)
  final Map<int, Timer> _tapTimers = <int, Timer>{};

  /// How long a [tapAction] keeps its key down before auto-releasing. Two-to-
  /// three tics (tic period ~28.6 ms at 35 Hz) so at least one — typically two —
  /// tic samples observe the key. BT_USE / weapon select are edge-triggered in
  /// the playsim (useDown / first-press-wins), so holding for a few tics still
  /// produces exactly one action per tap.
  static const Duration tapMinHold = Duration(milliseconds: 100);

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
    // Momentary tap with a MINIMUM HOLD. We press the key NOW (posting the
    // keyDown edge immediately, so the menu — which reads discrete events —
    // still responds on key-down), bump the ref-count so isKeyDown() reports it
    // as held, then schedule the release after [tapMinHold]. That guarantees the
    // per-tic key-state sampler sees the key down for at least one tic; without
    // it the down/up would complete inside one frame and never be sampled.
    if (kTouchInputDebugLog) {
      debugPrint('[touch] tapAction ${action.name} '
          'keys=${ActionKeys.keysFor(action).map((c) => '0x${c.toRadixString(16)}').join(',')}');
    }
    for (final int code in ActionKeys.keysFor(action)) {
      final Timer? existing = _tapTimers[code];
      if (existing != null) {
        // Re-tap before the previous min-hold elapsed: refresh the hold window
        // WITHOUT a second ref-count increment, so the ref-count stays balanced
        // (exactly one pending release per key) and the key cannot get stuck.
        existing.cancel();
        if (kTouchInputDebugLog) {
          debugPrint('[touch] tap refresh hold 0x${code.toRadixString(16)}');
        }
      } else {
        final int prev = _refCounts[code] ?? 0;
        _refCounts[code] = prev + 1;
        if (prev == 0) {
          queue.postEvent(DoomEvent.keyDown(code));
          if (kTouchInputDebugLog) {
            debugPrint('[touch] tap keyDown 0x${code.toRadixString(16)}');
          }
        }
      }
      _tapTimers[code] = Timer(tapMinHold, () => _endTap(code));
    }
  }

  /// Releases a tap-held key after its min-hold elapses: drop the ref-count this
  /// tap added and, if it was the last holder, post the keyUp edge.
  void _endTap(int code) {
    _tapTimers.remove(code);
    final int prev = _refCounts[code] ?? 0;
    if (prev <= 0) return;
    final int next = prev - 1;
    _refCounts[code] = next;
    if (next == 0) {
      queue.postEvent(DoomEvent.keyUp(code));
      if (kTouchInputDebugLog) {
        debugPrint('[touch] tap keyUp 0x${code.toRadixString(16)}');
      }
    }
  }

  /// Release everything (e.g. on focus loss / app pause) to avoid stuck keys.
  void releaseAll() {
    for (final Timer t in _tapTimers.values) {
      t.cancel();
    }
    _tapTimers.clear();
    for (final entry in _refCounts.entries) {
      if (entry.value > 0) {
        queue.postEvent(DoomEvent.keyUp(entry.key));
      }
    }
    _refCounts.clear();
  }
}
