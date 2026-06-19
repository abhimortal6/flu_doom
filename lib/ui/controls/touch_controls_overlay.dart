// The composable on-screen control overlay. Drop this into a Stack over the
// game view. It emits the same [GameAction]s as the keyboard layer, funneled
// through an [ActionSink] (normally an [EventQueueActionSink] feeding the
// EventQueue). Layout is orientation-aware: movement cluster on one bottom
// corner, action buttons on the other, mirrored for left-handed mode.
//
// Construct with either an [ActionSink] (preferred — testable) or, for
// convenience, build one from an [EventQueue] via [TouchControlsOverlay.forQueue].

import 'package:flutter/material.dart';

import '../../engine/input/event.dart';
import '../../input_actions/action_dispatcher.dart';
import '../../input_actions/controls_settings.dart';
import '../../input_actions/game_action.dart';
import 'overlay_button_id.dart';
import 'overlay_widgets.dart';

class TouchControlsOverlay extends StatefulWidget {
  const TouchControlsOverlay({
    super.key,
    required this.sink,
    this.settings = const OverlaySettings(),
  });

  /// Convenience: wraps an [EventQueue] in a fresh [EventQueueActionSink].
  TouchControlsOverlay.forQueue({
    Key? key,
    required EventQueue queue,
    OverlaySettings settings = const OverlaySettings(),
  }) : this(key: key, sink: EventQueueActionSink(queue), settings: settings);

  /// Where overlay buttons dispatch their actions.
  final ActionSink sink;

  /// Visual/layout configuration (visibility, opacity, scale, handedness).
  final OverlaySettings settings;

  @override
  State<TouchControlsOverlay> createState() => _TouchControlsOverlayState();
}

class _TouchControlsOverlayState extends State<TouchControlsOverlay> {
  bool _strafeMode = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.visible) return const SizedBox.shrink();
    final OverlaySettings s = widget.settings;
    final double op = s.opacity;
    final bool leftHanded = s.handed == HandedLayout.left;

    return Positioned.fill(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool landscape =
                constraints.maxWidth >= constraints.maxHeight;
            // Scale down a touch in portrait to leave room.
            final double scale = s.scale * (landscape ? 1.0 : 0.9);
            final double stickSize = 140 * scale;
            final double btn = 60 * scale;
            final double smallBtn = 48 * scale;
            final double gap = 12 * scale;

            final Widget movement = OverlayMovementStick(
              sink: widget.sink,
              size: stickSize,
              opacity: op,
              strafeMode: _strafeMode,
            );

            // Primary action cluster (fire/use) — larger, thumb-reachable.
            final Widget primaryActions = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    OverlayHoldButton(
                      action: GameAction.use,
                      sink: widget.sink,
                      label: 'USE',
                      icon: Icons.touch_app,
                      size: btn,
                      opacity: op,
                    ),
                    SizedBox(width: gap),
                    OverlayHoldButton(
                      action: GameAction.fire,
                      sink: widget.sink,
                      label: 'FIRE',
                      icon: Icons.gps_fixed,
                      size: btn * 1.25,
                      opacity: op,
                    ),
                  ],
                ),
              ],
            );

            // Secondary cluster: weapon switch, run toggle, strafe toggle.
            final Widget secondaryActions = Wrap(
              spacing: gap,
              runSpacing: gap,
              alignment: WrapAlignment.end,
              children: <Widget>[
                OverlayHoldButton(
                  action: GameAction.prevWeapon,
                  sink: widget.sink,
                  label: 'W-',
                  icon: Icons.chevron_left,
                  size: smallBtn,
                  opacity: op,
                  momentary: true,
                ),
                OverlayHoldButton(
                  action: GameAction.nextWeapon,
                  sink: widget.sink,
                  label: 'W+',
                  icon: Icons.chevron_right,
                  size: smallBtn,
                  opacity: op,
                  momentary: true,
                ),
                OverlayHoldButton(
                  action: GameAction.run,
                  sink: widget.sink,
                  label: 'RUN',
                  icon: Icons.directions_run,
                  size: smallBtn,
                  opacity: op,
                ),
                _ToggleButton(
                  label: 'STR',
                  icon: Icons.swap_horiz,
                  active: _strafeMode,
                  size: smallBtn,
                  opacity: op,
                  onToggle: () => setState(() => _strafeMode = !_strafeMode),
                ),
              ],
            );

            // Top-edge utility cluster: menu / automap / pause.
            final Widget utility = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                OverlayHoldButton(
                  action: GameAction.menuToggle,
                  sink: widget.sink,
                  label: 'MENU',
                  icon: Icons.menu,
                  size: smallBtn,
                  opacity: op,
                  momentary: true,
                ),
                SizedBox(width: gap),
                OverlayHoldButton(
                  action: GameAction.automap,
                  sink: widget.sink,
                  label: 'MAP',
                  icon: Icons.map,
                  size: smallBtn,
                  opacity: op,
                  momentary: true,
                ),
                SizedBox(width: gap),
                OverlayHoldButton(
                  action: GameAction.pause,
                  sink: widget.sink,
                  label: 'II',
                  icon: Icons.pause,
                  size: smallBtn,
                  opacity: op,
                  momentary: true,
                ),
              ],
            );

            final EdgeInsets pad = EdgeInsets.all(16 * scale);

            // movementSide = bottom-left for right-handed, bottom-right for left.
            final Alignment movementAlign =
                leftHanded ? Alignment.bottomRight : Alignment.bottomLeft;
            final Alignment actionsAlign =
                leftHanded ? Alignment.bottomLeft : Alignment.bottomRight;

            return Stack(
              children: <Widget>[
                // Utility cluster: top-right (or top-left when left-handed).
                Align(
                  alignment:
                      leftHanded ? Alignment.topLeft : Alignment.topRight,
                  child: Padding(padding: pad, child: utility),
                ),
                // Movement cluster.
                Align(
                  alignment: movementAlign,
                  child: Padding(padding: pad, child: movement),
                ),
                // Action clusters: primary low, secondary stacked above it.
                Align(
                  alignment: actionsAlign,
                  child: Padding(
                    padding: pad,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: leftHanded
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.end,
                      children: <Widget>[
                        secondaryActions,
                        SizedBox(height: gap),
                        primaryActions,
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A latching toggle button (used for the overlay strafe-mode switch). Purely
/// local UI state; it does not itself emit a [GameAction] keycode.
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onToggle,
    required this.size,
    required this.opacity,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onToggle;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.05, 1.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE0A030) : const Color(0xFF202020),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFFFFFFF),
            size: size * 0.42,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}

// Re-export so callers needing the button-id constants get them via this file.
// ignore: unused_element
const List<String> kOverlayButtonIds = OverlayButtonId.all;
