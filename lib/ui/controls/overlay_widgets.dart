// Reusable overlay control primitives: a hold button and an analog-style
// movement stick. Both emit [GameAction]s through an [ActionSink].

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../input_actions/action_dispatcher.dart';
import '../../input_actions/game_action.dart';

/// A momentary / hold button. Posts press on down, release on up/cancel.
/// If [momentary] is true, fires a single [ActionSink.tapAction] instead
/// (used for weapon switch / menu where Doom expects a clean key tap).
class OverlayHoldButton extends StatefulWidget {
  const OverlayHoldButton({
    super.key,
    required this.action,
    required this.sink,
    required this.label,
    this.icon,
    this.size = 64,
    this.opacity = 0.45,
    this.momentary = false,
  });

  final GameAction action;
  final ActionSink sink;
  final String label;
  final IconData? icon;
  final double size;
  final double opacity;
  final bool momentary;

  @override
  State<OverlayHoldButton> createState() => _OverlayHoldButtonState();
}

class _OverlayHoldButtonState extends State<OverlayHoldButton> {
  bool _down = false;

  void _press() {
    if (widget.momentary) {
      widget.sink.tapAction(widget.action);
      setState(() => _down = true);
      // Brief visual flash for taps.
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _down = false);
      });
      return;
    }
    setState(() => _down = true);
    widget.sink.pressAction(widget.action);
  }

  void _release() {
    if (widget.momentary) return;
    if (!_down) return;
    setState(() => _down = false);
    widget.sink.releaseAction(widget.action);
  }

  @override
  Widget build(BuildContext context) {
    final double a = widget.opacity.clamp(0.05, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      child: Opacity(
        opacity: a,
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _down ? const Color(0xFFE0A030) : const Color(0xFF202020),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
          ),
          child: widget.icon != null
              ? Icon(
                  widget.icon,
                  color: const Color(0xFFFFFFFF),
                  size: widget.size * 0.42,
                  semanticLabel: widget.label,
                )
              : Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: widget.size * 0.24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 8-direction movement stick. Drag from center; resolves the touch vector into
/// up to two simultaneous movement/strafe actions (e.g. forward + strafe-right
/// for diagonals). Releases all when lifted.
///
/// [strafeMode]: when true, left/right emit strafe actions instead of turns
/// (driven by the overlay-level strafe modifier toggle).
class OverlayMovementStick extends StatefulWidget {
  const OverlayMovementStick({
    super.key,
    required this.sink,
    this.size = 140,
    this.opacity = 0.45,
    this.strafeMode = false,
  });

  final ActionSink sink;
  final double size;
  final double opacity;
  final bool strafeMode;

  @override
  State<OverlayMovementStick> createState() => _OverlayMovementStickState();
}

class _OverlayMovementStickState extends State<OverlayMovementStick> {
  Offset _knob = Offset.zero; // relative to center, clamped to radius
  final Set<GameAction> _active = <GameAction>{};

  // Deadzone as fraction of radius.
  static const double _deadzone = 0.28;

  void _update(Offset local) {
    final double r = widget.size / 2;
    Offset v = local - Offset(r, r);
    final double dist = v.distance;
    if (dist > r) v = v * (r / dist);
    setState(() => _knob = v);

    final Set<GameAction> wanted = <GameAction>{};
    if (dist >= r * _deadzone) {
      final double nx = v.dx / r;
      final double ny = v.dy / r;
      // Vertical => forward/back. Doom screen y grows downward.
      if (ny < -_deadzone) wanted.add(GameAction.moveForward);
      if (ny > _deadzone) wanted.add(GameAction.moveBackward);
      // Horizontal => turn or strafe.
      if (nx < -_deadzone) {
        wanted.add(
          widget.strafeMode ? GameAction.strafeLeft : GameAction.turnLeft,
        );
      }
      if (nx > _deadzone) {
        wanted.add(
          widget.strafeMode ? GameAction.strafeRight : GameAction.turnRight,
        );
      }
    }
    _applyDiff(wanted);
  }

  void _applyDiff(Set<GameAction> wanted) {
    for (final a in _active.difference(wanted)) {
      widget.sink.releaseAction(a);
    }
    for (final a in wanted.difference(_active)) {
      widget.sink.pressAction(a);
    }
    _active
      ..clear()
      ..addAll(wanted);
  }

  void _end() {
    _applyDiff(<GameAction>{});
    setState(() => _knob = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final double a = widget.opacity.clamp(0.05, 1.0);
    final double r = widget.size / 2;
    return Opacity(
      opacity: a,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _update(d.localPosition),
        onPanUpdate: (d) => _update(d.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        onTapDown: (d) => _update(d.localPosition),
        onTapUp: (_) => _end(),
        onTapCancel: _end,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _StickPainter(knob: _knob, radius: r),
          ),
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter({required this.knob, required this.radius});
  final Offset knob;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(radius, radius);
    final base = Paint()
      ..color = const Color(0xFF202020)
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, base);
    canvas.drawCircle(center, radius, ring);

    // Direction ticks.
    final tick = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 2;
    for (int i = 0; i < 4; i++) {
      final double ang = i * math.pi / 2;
      final Offset o = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(center + o * (radius * 0.6), center + o * (radius * 0.85), tick);
    }

    final knobPaint = Paint()
      ..color = const Color(0xFFE0A030)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center + knob, radius * 0.42, knobPaint);
    canvas.drawCircle(center + knob, radius * 0.42, ring);
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.knob != knob;
}
