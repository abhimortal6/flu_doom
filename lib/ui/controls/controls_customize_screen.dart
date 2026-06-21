// Layout CUSTOMIZER — drag each on-screen control to a custom position.
//
// Reached from the controls settings screen ("Customize layout"). It paints the
// actual gameplay controls over a representative dark game backdrop, each one
// DRAGGABLE. Dragging updates the control's normalized position LIVE; the
// position is committed (clamped in-bounds) on every drag update so the
// preview tracks the finger. It edits the map for the CURRENT orientation only
// (portrait vs landscape are stored separately), so rotating the device lets
// the user tune each layout independently.
//
// SAVE persists via [ControlsSettingsStore] and pops with the new settings.
// RESET clears the current orientation's overrides (back to the built-in
// corner-cluster layout). Both call the live-apply [onChanged] hook so the
// game shell can update the running overlay immediately.
//
// Desktop note: Flutter routes mouse drags through the same pan gestures, so a
// mouse-drag on macOS validates the drag logic exactly as a touch drag would.

import 'package:flutter/material.dart';

import '../../input_actions/controls_settings.dart';
import 'overlay_button_id.dart';
import 'overlay_layout.dart';

class ControlsCustomizeScreen extends StatefulWidget {
  const ControlsCustomizeScreen({
    super.key,
    required this.store,
    required this.initial,
    this.onChanged,
  });

  /// Persistence backend (SAVE / RESET write through this).
  final ControlsSettingsStore store;

  /// Settings to start from (the live overlay settings).
  final OverlaySettings initial;

  /// Live-apply hook (the game shell rebuilds the running overlay).
  final void Function(OverlaySettings overlay)? onChanged;

  @override
  State<ControlsCustomizeScreen> createState() =>
      _ControlsCustomizeScreenState();
}

class _ControlsCustomizeScreenState extends State<ControlsCustomizeScreen> {
  late OverlaySettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
  }

  // Replace the override for [id] in the given orientation's map.
  void _setPosition(bool landscape, String id, ButtonPosition pos) {
    final Map<String, ButtonPosition> next =
        Map<String, ButtonPosition>.from(_settings.positionsFor(landscape));
    next[id] = pos;
    setState(() => _settings = _settings.withPositionsFor(landscape, next));
    // Live-apply to the running overlay every drag frame (in-memory only; the
    // disk write is deferred to SAVE so we don't thrash shared_preferences).
    widget.onChanged?.call(_settings);
  }

  Future<void> _save() async {
    await widget.store.saveOverlay(_settings);
    widget.onChanged?.call(_settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Layout saved'), duration: Duration(seconds: 1)),
    );
    Navigator.of(context).pop(_settings);
  }

  void _resetCurrent(bool landscape) {
    setState(() {
      _settings = _settings.withPositionsFor(
        landscape,
        const <String, ButtonPosition>{},
      );
    });
    // Reset is a live edit too — apply immediately and persist so it sticks
    // even if the user backs out without SAVE.
    widget.store.saveOverlay(_settings);
    widget.onChanged?.call(_settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101012),
      appBar: AppBar(
        title: const Text('Customize layout'),
        actions: <Widget>[
          TextButton(
            key: const Key('customizeSave'),
            onPressed: _save,
            child: const Text('SAVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool landscape =
              constraints.maxWidth >= constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Representative game backdrop.
              const _Backdrop(),
              // The draggable controls, laid out in the same coordinate space
              // the live overlay uses (inside SafeArea).
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, inner) {
                    final OverlayLayout layout = OverlayLayout(
                      area: Size(inner.maxWidth, inner.maxHeight),
                      landscape: landscape,
                      leftHanded: _settings.handed == HandedLayout.left,
                      scale: _settings.scale,
                    );
                    final Map<String, ButtonPosition> overrides =
                        _settings.positionsFor(landscape);
                    return Stack(
                      children: <Widget>[
                        for (final String id in OverlayButtonId.all)
                          _DraggableControl(
                            id: id,
                            layout: layout,
                            center: layout.centerFor(id, overrides),
                            opacity: _settings.opacity,
                            onMoved: (pos) =>
                                _setPosition(landscape, id, pos),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // Help banner + RESET, pinned to the top.
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              'Drag controls to reposition '
                              '(${landscape ? "landscape" : "portrait"}). '
                              'Rotate to edit the other layout.',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            key: const Key('customizeReset'),
                            onPressed: () => _resetCurrent(landscape),
                            child: const Text(
                              'RESET',
                              style: TextStyle(color: Color(0xFFE0A030)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A single draggable proxy for one control. Shows the control's label in a
/// circle of the control's real size; a pan drag moves it and reports the new
/// clamped normalized center on every update (live).
class _DraggableControl extends StatelessWidget {
  const _DraggableControl({
    required this.id,
    required this.layout,
    required this.center,
    required this.opacity,
    required this.onMoved,
  });

  final String id;
  final OverlayLayout layout;
  final ButtonPosition center;
  final double opacity;
  final void Function(ButtonPosition) onMoved;

  @override
  Widget build(BuildContext context) {
    final double size = layout.sizeFor(id);
    final Offset tl = layout.topLeftFor(id, center);
    return Positioned(
      left: tl.dx,
      top: tl.dy,
      width: size,
      height: size,
      child: GestureDetector(
        key: Key('drag_$id'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          // Move the control by the drag delta, then re-derive the clamped
          // normalized center from the new top-left.
          final Offset moved = tl + d.delta;
          onMoved(layout.centerFromTopLeft(id, moved));
        },
        child: Opacity(
          opacity: opacity.clamp(0.35, 1.0),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF202020),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE0A030), width: 2),
            ),
            child: Text(
              OverlayButtonId.label(id),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFFFFFFF),
                fontSize: (size * 0.22).clamp(9.0, 16.0),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple representative game backdrop (dark with a subtle grid) so the user
/// can judge placement against the play view.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint bg = Paint()..color = const Color(0xFF181820);
    canvas.drawRect(Offset.zero & size, bg);
    final Paint line = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    const double step = 48;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}
