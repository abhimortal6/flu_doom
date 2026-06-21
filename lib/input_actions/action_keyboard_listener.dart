// A rebindable hardware-keyboard listener. Unlike the foundation's
// DoomKeyboardListener (which uses a fixed mapLogicalKey table), this resolves
// each physical key through a runtime-configurable [KeyBindings] map into a
// [GameAction], then dispatches it through an [ActionSink] (normally an
// [EventQueueActionSink] feeding the EventQueue + key-state).
//
// This is the keyboard half of the input UX layer. The overlay is the touch
// half; both funnel through the same ActionSink.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'action_dispatcher.dart';
import 'key_bindings.dart';

/// Focus-grabbing widget that translates hardware key events into game actions
/// using [bindings] and forwards them to [sink].
class ActionKeyboardListener extends StatefulWidget {
  const ActionKeyboardListener({
    super.key,
    required this.bindings,
    required this.sink,
    required this.child,
    this.autofocus = true,
    this.enabled = true,
    this.onSystemKey,
  });

  /// Active key->action bindings (rebindable; updates apply immediately).
  final KeyBindings bindings;

  /// Where resolved actions are dispatched.
  final ActionSink sink;

  /// Optional hook for non-game "system" keys (e.g. F11 fullscreen) that are
  /// not part of the rebindable game bindings. Invoked on KeyDown only; return
  /// true to mark the event handled (swallowing it from the game bindings).
  /// Keeps the engine input path untouched while letting the shell own F11.
  final bool Function(KeyEvent event)? onSystemKey;

  final Widget child;
  final bool autofocus;

  /// When false, key events are ignored (e.g. while a rebind capture is open).
  final bool enabled;

  @override
  State<ActionKeyboardListener> createState() => _ActionKeyboardListenerState();
}

class _ActionKeyboardListenerState extends State<ActionKeyboardListener> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'DoomActionKeyboard');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;

    // System keys (e.g. F11 fullscreen) are handled before — and independently
    // of — the rebindable game bindings, on the KeyDown edge only.
    if (event is KeyDownEvent && widget.onSystemKey != null) {
      if (widget.onSystemKey!(event)) return KeyEventResult.handled;
    }

    final action = widget.bindings.actionFor(event.logicalKey);
    if (action == null) return KeyEventResult.ignored;

    // Edge-triggered, like vanilla Doom: a real KeyDownEvent is the only thing
    // that presses (one keyDown edge / one ref-count increment), and only a
    // KeyUpEvent releases. The OS delivers a KeyRepeatEvent for every
    // auto-repeat tick while a key is held; we must NOT treat those as fresh
    // presses, or each repeat would re-post DoomEvent.keyDown and re-trigger
    // sounds/actions while the key stays physically down. The key remains
    // "down" in the sink's key-state set from the initial KeyDownEvent until
    // the KeyUpEvent, so continuous movement / auto-fire still work.
    if (event is KeyDownEvent) {
      widget.sink.pressAction(action);
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      widget.sink.releaseAction(action);
      return KeyEventResult.handled;
    } else if (event is KeyRepeatEvent) {
      // OS auto-repeat: swallow it (so it doesn't bubble) but emit no edge.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
