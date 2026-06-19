// Bridges Flutter hardware keyboard events into the Doom [EventQueue].
//
// Wrap your game widget in a [DoomKeyboardListener]; it requests focus and
// translates Flutter KeyDownEvent/KeyUpEvent into DoomEvent keyDown/keyUp
// using [mapLogicalKey]. Unmapped keys are ignored.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'doomkeys.dart';
import 'event.dart';

/// Map a Flutter [LogicalKeyboardKey] to a Doom keycode, or null if unmapped.
int? mapLogicalKey(LogicalKeyboardKey key) {
  // Direct table for control keys.
  const Map<int, int> table = <int, int>{};
  // Switch is clearer than a const map for the LogicalKeyboardKey ids.
  if (key == LogicalKeyboardKey.arrowRight) return DoomKey.rightArrow;
  if (key == LogicalKeyboardKey.arrowLeft) return DoomKey.leftArrow;
  if (key == LogicalKeyboardKey.arrowUp) return DoomKey.upArrow;
  if (key == LogicalKeyboardKey.arrowDown) return DoomKey.downArrow;
  if (key == LogicalKeyboardKey.escape) return DoomKey.escape;
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return DoomKey.enter;
  }
  if (key == LogicalKeyboardKey.tab) return DoomKey.tab;
  if (key == LogicalKeyboardKey.space) return DoomKey.spacebar;
  if (key == LogicalKeyboardKey.backspace) return DoomKey.backspace;
  if (key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight) {
    return DoomKey.rCtrl;
  }
  if (key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight) {
    return DoomKey.rShift;
  }
  if (key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight) {
    return DoomKey.rAlt;
  }
  if (key == LogicalKeyboardKey.f1) return DoomKey.f1;
  if (key == LogicalKeyboardKey.f2) return DoomKey.f2;
  if (key == LogicalKeyboardKey.f3) return DoomKey.f3;
  if (key == LogicalKeyboardKey.f4) return DoomKey.f4;
  if (key == LogicalKeyboardKey.f5) return DoomKey.f5;

  // Printable ASCII: use the key label's lowercase first char.
  final String? label = key.keyLabel.isNotEmpty ? key.keyLabel : null;
  if (label != null && label.length == 1) {
    final int code = label.toLowerCase().codeUnitAt(0);
    if (code >= 0x20 && code < 0x7F) return code;
  }
  // Unused; placeholder for future direct-id mapping.
  // ignore: unused_local_variable
  final _ = table;
  return null;
}

/// A focus-grabbing widget that forwards hardware key events into [queue].
class DoomKeyboardListener extends StatefulWidget {
  const DoomKeyboardListener({
    super.key,
    required this.queue,
    required this.child,
    this.autofocus = true,
  });

  final EventQueue queue;
  final Widget child;
  final bool autofocus;

  @override
  State<DoomKeyboardListener> createState() => _DoomKeyboardListenerState();
}

class _DoomKeyboardListenerState extends State<DoomKeyboardListener> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'DoomKeyboard');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final int? code = mapLogicalKey(event.logicalKey);
    if (code == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      widget.queue.postEvent(DoomEvent.keyDown(code));
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      widget.queue.postEvent(DoomEvent.keyUp(code));
      return KeyEventResult.handled;
    }
    // Ignore repeat events (Doom handles its own auto-repeat).
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
