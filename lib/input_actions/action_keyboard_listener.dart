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
  });

  /// Active key->action bindings (rebindable; updates apply immediately).
  final KeyBindings bindings;

  /// Where resolved actions are dispatched.
  final ActionSink sink;

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
    final action = widget.bindings.actionFor(event.logicalKey);
    if (action == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      widget.sink.pressAction(action);
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      widget.sink.releaseAction(action);
      return KeyEventResult.handled;
    }
    // KeyRepeatEvent: Doom does its own auto-repeat; swallow but don't re-press.
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
