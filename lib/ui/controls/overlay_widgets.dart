// Reusable overlay control primitives: a hold button and an analog-style
// movement stick. Both emit [GameAction]s through an [ActionSink].

import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../input_actions/action_dispatcher.dart';
import '../../input_actions/analog_input.dart';
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
    if (kTouchInputDebugLog) {
      debugPrint('[touch] button ${widget.label} '
          '(${widget.action.name}) ${widget.momentary ? "tap" : "press"}');
    }
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

/// A COMPACT weapon-switch button (prev / next). A small icon-only circle the
/// same size as the other small utility buttons — just a chevron, no wide text
/// pill — so the weapon controls stay visually minimal. It fires a single
/// momentary [ActionSink.tapAction] (clean DoomKey down/up), exactly what the
/// weapon-cycle keys ('-'/'=') expect; the play-sim resolves that into a real
/// weapon change against the live inventory (reaching the fist on prev-cycle).
///
/// Honors the overlay scale (via [size]) and [opacity]. Sibling of
/// [OverlayHoldButton] with identical tap/flash visuals and
/// `HitTestBehavior.opaque` so its hit-area wins over the look-drag region when
/// stacked above it. [label] is the semantic label only (e.g. 'PREV'/'NEXT').
class OverlayWeaponButton extends StatefulWidget {
  const OverlayWeaponButton({
    super.key,
    required this.action,
    required this.sink,
    required this.label,
    required this.icon,
    this.size = 42,
    this.opacity = 0.45,
  });

  /// Weapon action to fire on tap (prevWeapon / nextWeapon).
  final GameAction action;
  final ActionSink sink;

  /// Semantic label (e.g. 'PREV' / 'NEXT'). Not drawn as text.
  final String label;

  /// Chevron icon shown in the circle.
  final IconData icon;

  /// Diameter; drives sizing with the overlay scale (same scale as smallBtn).
  final double size;
  final double opacity;

  @override
  State<OverlayWeaponButton> createState() => _OverlayWeaponButtonState();
}

class _OverlayWeaponButtonState extends State<OverlayWeaponButton> {
  bool _down = false;

  void _press() {
    if (kTouchInputDebugLog) {
      debugPrint('[touch] weaponButton ${widget.label} '
          '(${widget.action.name}) tap');
    }
    widget.sink.tapAction(widget.action);
    setState(() => _down = true);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _down = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double a = widget.opacity.clamp(0.05, 1.0);
    final double s = widget.size;
    return Semantics(
      label: widget.label,
      button: true,
      // Single semantics node carrying [label] so find.bySemanticsLabel matches.
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(),
        child: Opacity(
          opacity: a,
          child: Container(
            width: s,
            height: s,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _down ? const Color(0xFFE0A030) : const Color(0xFF202020),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
            ),
            child: Icon(
              widget.icon,
              color: const Color(0xFFFFFFFF),
              size: s * 0.62,
              semanticLabel: widget.label,
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

/// PUBG-style ANALOG movement stick. Unlike [OverlayMovementStick] (which emits
/// discrete 8-way GameAction key presses), this writes a continuous 2D vector
/// into an [AnalogInput] holder that the play-sim bridge reads each tic. It
/// drives MOVEMENT ONLY — forward/back + strafe — never turning (turning is the
/// right-side camera's job in this scheme).
///
/// The stick base is fixed where it's placed; the knob tracks the finger,
/// clamped to the radius. Output:
///   * forward = -ny  (screen y grows downward, so up == forward == +1)
///   * side    = +nx  (right == strafe right == +1)
/// with a deadzone; [AnalogInput.run] is set true at/near full deflection (the
/// run speed tier). Releasing recenters and clears the vector.
class OverlayMoveStick extends StatefulWidget {
  const OverlayMoveStick({
    super.key,
    required this.analog,
    this.size = 160,
    this.opacity = 0.45,
    this.deadzone = 0.16,
    this.runThreshold = 0.85,
  });

  /// Analog channel written with the normalized stick vector.
  final AnalogInput analog;

  /// Diameter of the stick base.
  final double size;

  /// Opacity of the rendered stick.
  final double opacity;

  /// Deadzone as a fraction of the radius (below this the vector is zero).
  final double deadzone;

  /// Normalized magnitude (0..1) at/above which the run speed tier engages.
  final double runThreshold;

  @override
  State<OverlayMoveStick> createState() => _OverlayMoveStickState();
}

class _OverlayMoveStickState extends State<OverlayMoveStick> {
  Offset _knob = Offset.zero; // relative to center, clamped to radius

  void _update(Offset local) {
    final double r = widget.size / 2;
    Offset v = local - Offset(r, r);
    final double dist = v.distance;
    if (dist > r) v = v * (r / dist);
    setState(() => _knob = v);

    // Normalized vector in [-1, 1] per axis.
    double nx = v.dx / r;
    double ny = v.dy / r;
    double mag = math.sqrt(nx * nx + ny * ny);
    if (mag < widget.deadzone) {
      widget.analog.clearStick();
      return;
    }
    // Re-scale so the deadzone edge maps to 0 and full deflection maps to 1
    // (smooth ramp out of the deadzone, like a calibrated joystick).
    final double scaled = ((mag - widget.deadzone) / (1.0 - widget.deadzone))
        .clamp(0.0, 1.0);
    if (mag > 0) {
      nx = nx / mag * scaled;
      ny = ny / mag * scaled;
    }
    // forward = up = -ny ; side = right = +nx.
    final bool running = scaled >= widget.runThreshold;
    widget.analog.setStick(-ny, nx, running: running);
  }

  void _end() {
    widget.analog.clearStick();
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

/// A 4-way directional pad for MENU navigation. Each arm is a momentary tap
/// that posts a clean DoomKey down/up pair through [ActionSink.tapAction] so
/// the menu responder (M_Responder) sees a discrete arrow-key press — item-by-
/// item cursor movement and slider adjust, no auto-repeat. Used only in the
/// overlay's MENU mode (title/demoScreen, intermission, finale, or while a menu
/// is open); the gameplay analog stick is hidden then.
///
/// Maps: Up -> [GameAction.menuUp] (upArrow), Down -> menuDown (downArrow),
/// Left -> menuLeft (leftArrow), Right -> menuRight (rightArrow). These share
/// keycodes with the movement arrows by design (vanilla disambiguates by state).
class OverlayMenuDpad extends StatelessWidget {
  const OverlayMenuDpad({
    super.key,
    required this.sink,
    this.size = 180,
    this.opacity = 0.45,
  });

  final ActionSink sink;

  /// Overall diameter of the square d-pad cluster.
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final double arm = size / 3;
    Widget btn(GameAction action, String label, IconData icon) {
      return _DpadArm(
        sink: sink,
        action: action,
        label: label,
        icon: icon,
        size: arm,
        opacity: opacity,
      );
    }

    final Widget spacer = SizedBox(width: arm, height: arm);
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              spacer,
              btn(GameAction.menuUp, 'UP', Icons.keyboard_arrow_up),
              spacer,
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              btn(GameAction.menuLeft, 'LEFT', Icons.keyboard_arrow_left),
              spacer,
              btn(GameAction.menuRight, 'RIGHT', Icons.keyboard_arrow_right),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              spacer,
              btn(GameAction.menuDown, 'DOWN', Icons.keyboard_arrow_down),
              spacer,
            ],
          ),
        ],
      ),
    );
  }
}

/// One arm of [OverlayMenuDpad]: a square momentary button posting a discrete
/// arrow-key tap. Kept square (not circular) so the four arms tile cleanly.
class _DpadArm extends StatefulWidget {
  const _DpadArm({
    required this.sink,
    required this.action,
    required this.label,
    required this.icon,
    required this.size,
    required this.opacity,
  });

  final ActionSink sink;
  final GameAction action;
  final String label;
  final IconData icon;
  final double size;
  final double opacity;

  @override
  State<_DpadArm> createState() => _DpadArmState();
}

class _DpadArmState extends State<_DpadArm> {
  bool _down = false;

  void _press() {
    if (kTouchInputDebugLog) {
      debugPrint('[touch] dpad ${widget.label} (${widget.action.name}) tap');
    }
    widget.sink.tapAction(widget.action);
    setState(() => _down = true);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _down = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double a = widget.opacity.clamp(0.05, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      child: Opacity(
        opacity: a,
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _down ? const Color(0xFFE0A030) : const Color(0xFF202020),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
          ),
          child: Icon(
            widget.icon,
            color: const Color(0xFFFFFFFF),
            size: widget.size * 0.6,
            semanticLabel: widget.label,
          ),
        ),
      ),
    );
  }
}

/// Right-side drag-to-look "camera". A transparent gesture region that turns
/// the view: horizontal drag delta is accumulated into an [AnalogInput] (the
/// analog of vanilla `mousex`), which the bridge converts to an angleturn each
/// tic. Vertical drag is ignored (Doom has no pitch). This consumes only the
/// region it occupies; ACTION BUTTONS are stacked ABOVE it in the parent Stack
/// so their touches win (Flutter hit-tests top-of-stack first), keeping a tap
/// on FIRE/USE from being stolen by the look-drag.
class LookCameraRegion extends StatelessWidget {
  const LookCameraRegion({super.key, required this.analog});

  /// Analog channel the horizontal drag delta is accumulated into.
  final AnalogInput analog;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Use the per-event delta so the accumulation matches finger travel; the
      // bridge clears it each tic (mousex = 0), so motion that stops stops the
      // turn immediately — no drift.
      onPanUpdate: (d) => analog.addLookDelta(d.delta.dx),
      child: const SizedBox.expand(),
    );
  }
}
