// Touch-overlay STUB: a couple of on-screen buttons that enqueue Doom events.
//
// This is intentionally minimal plumbing to prove the input contract works on
// touch devices. A full, configurable virtual-gamepad overlay comes in a later
// phase. Each button posts keyDown on press and keyUp on release.

import 'package:flutter/widgets.dart';

import '../engine/input/doomkeys.dart';
import '../engine/input/event.dart';

/// Overlays a few translucent buttons (left/right/fire/use) that post Doom
/// events into [queue].
class TouchOverlay extends StatelessWidget {
  const TouchOverlay({super.key, required this.queue});

  final EventQueue queue;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _HoldButton(
                    label: '<',
                    queue: queue,
                    keyCode: DoomKey.leftArrow,
                  ),
                  const SizedBox(width: 12),
                  _HoldButton(
                    label: '>',
                    queue: queue,
                    keyCode: DoomKey.rightArrow,
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  _HoldButton(
                    label: 'USE',
                    queue: queue,
                    keyCode: DoomKey.spacebar,
                  ),
                  const SizedBox(width: 12),
                  _HoldButton(
                    label: 'FIRE',
                    queue: queue,
                    keyCode: DoomKey.rCtrl,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoldButton extends StatelessWidget {
  const _HoldButton({
    required this.label,
    required this.queue,
    required this.keyCode,
  });

  final String label;
  final EventQueue queue;
  final int keyCode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => queue.postEvent(DoomEvent.keyDown(keyCode)),
      onTapUp: (_) => queue.postEvent(DoomEvent.keyUp(keyCode)),
      onTapCancel: () => queue.postEvent(DoomEvent.keyUp(keyCode)),
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x66FFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x88FFFFFF)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
