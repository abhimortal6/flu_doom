// The composable on-screen control overlay — a modern PUBG-Mobile-style scheme.
//
// Layout (right-handed default; mirrored for left-handed):
//   * LEFT bottom corner: a floating ANALOG MOVEMENT STICK (forward/back +
//     strafe, analog magnitude -> MAXPLMOVE, run at full deflection). Movement
//     ONLY — it never turns. Writes an [AnalogInput] the play-sim bridge reads.
//   * RIGHT ~60% of the screen: a transparent DRAG-TO-LOOK "camera" region. A
//     horizontal drag turns the view (yaw); vertical is ignored. It accumulates
//     a look delta into the same [AnalogInput] (the analog of vanilla mousex).
//   * RIGHT cluster of ACTION BUTTONS over the look area: FIRE (large, bottom),
//     USE, weapon prev/next, plus top-edge MENU / MAP / PAUSE. Buttons sit
//     ABOVE the look region in the Stack, so their touches take priority over
//     the camera drag (Flutter hit-tests top-of-stack first).
//
// Buttons still funnel through the discrete [GameAction] -> [ActionSink] path
// (identical to the keyboard layer). Stick + look use the analog side channel.
//
// Construct with an [ActionSink] (+ an [AnalogInput]) or, for convenience,
// build a sink from an [EventQueue] via [TouchControlsOverlay.forQueue].

import 'package:flutter/material.dart';

import '../../engine/input/event.dart';
import '../../input_actions/action_dispatcher.dart';
import '../../input_actions/analog_input.dart';
import '../../input_actions/controls_settings.dart';
import '../../input_actions/game_action.dart';
import 'overlay_button_id.dart';
import 'overlay_widgets.dart';

class TouchControlsOverlay extends StatefulWidget {
  TouchControlsOverlay({
    super.key,
    required this.sink,
    AnalogInput? analog,
    this.settings = const OverlaySettings(),
  }) : analog = analog ?? AnalogInput();

  /// Convenience: wraps an [EventQueue] in a fresh [EventQueueActionSink].
  TouchControlsOverlay.forQueue({
    Key? key,
    required EventQueue queue,
    AnalogInput? analog,
    OverlaySettings settings = const OverlaySettings(),
  }) : this(
          key: key,
          sink: EventQueueActionSink(queue),
          analog: analog,
          settings: settings,
        );

  /// Where overlay buttons dispatch their (discrete) actions.
  final ActionSink sink;

  /// Analog side channel for the movement stick + drag-to-look camera. The
  /// play-sim bridge reads this each tic. When the overlay is idle every field
  /// stays zero, so keyboard-only behaviour is unaffected.
  final AnalogInput analog;

  /// Visual/layout configuration (visibility, opacity, scale, handedness,
  /// look sensitivity).
  final OverlaySettings settings;

  @override
  State<TouchControlsOverlay> createState() => _TouchControlsOverlayState();
}

class _TouchControlsOverlayState extends State<TouchControlsOverlay> {
  @override
  void initState() {
    super.initState();
    widget.analog.lookSensitivity = widget.settings.lookSensitivity;
  }

  @override
  void didUpdateWidget(TouchControlsOverlay old) {
    super.didUpdateWidget(old);
    widget.analog.lookSensitivity = widget.settings.lookSensitivity;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.visible) return const SizedBox.shrink();
    final OverlaySettings s = widget.settings;
    final double op = s.opacity;
    final bool leftHanded = s.handed == HandedLayout.left;

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool landscape =
              constraints.maxWidth >= constraints.maxHeight;
          // Scale down a touch in portrait to leave room.
          final double scale = s.scale * (landscape ? 1.0 : 0.9);
          final double stickSize = 160 * scale;
          final double fireBtn = 84 * scale;
          final double btn = 60 * scale;
          final double smallBtn = 48 * scale;
          final double gap = 12 * scale;

          // ---- LOOK region: the side of the screen WITHOUT the stick. For
          // right-handed, stick is left so the camera owns the right side;
          // mirrored for left-handed. It spans ~62% of the width and the full
          // height EXCEPT a band along the bottom where the stick sits (so a
          // stick drag isn't also read as a look drag). The action buttons are
          // stacked above this region and win its touches where they overlap.
          final double lookFraction = 0.62;
          final double lookWidth = constraints.maxWidth * lookFraction;
          final Widget lookRegion = Positioned(
            top: 0,
            bottom: 0,
            left: leftHanded ? 0 : constraints.maxWidth - lookWidth,
            width: lookWidth,
            child: LookCameraRegion(analog: widget.analog),
          );

          // ---- Movement stick (analog, movement only).
          final Widget movement = OverlayMoveStick(
            analog: widget.analog,
            size: stickSize,
            opacity: op,
          );

          // ---- Primary action cluster: FIRE (large) + USE.
          final Widget primaryActions = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
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
                size: fireBtn,
                opacity: op,
              ),
            ],
          );

          // ---- Secondary cluster: weapon switch (taps).
          final Widget secondaryActions = Row(
            mainAxisSize: MainAxisSize.min,
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
              SizedBox(width: gap),
              OverlayHoldButton(
                action: GameAction.nextWeapon,
                sink: widget.sink,
                label: 'W+',
                icon: Icons.chevron_right,
                size: smallBtn,
                opacity: op,
                momentary: true,
              ),
            ],
          );

          // ---- Top-edge utility cluster: menu / automap / pause.
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

          // movement = bottom-left (right-handed) / bottom-right (left-handed).
          final Alignment movementAlign =
              leftHanded ? Alignment.bottomRight : Alignment.bottomLeft;
          // action cluster opposite the stick.
          final Alignment actionsAlign =
              leftHanded ? Alignment.bottomLeft : Alignment.bottomRight;

          return SafeArea(
            child: Stack(
              children: <Widget>[
                // 1. LOOK region (bottom of the z-order so buttons win).
                lookRegion,
                // 2. Movement stick.
                Align(
                  alignment: movementAlign,
                  child: Padding(padding: pad, child: movement),
                ),
                // 3. Utility cluster: top of the action side.
                Align(
                  alignment:
                      leftHanded ? Alignment.topLeft : Alignment.topRight,
                  child: Padding(padding: pad, child: utility),
                ),
                // 4. Action clusters: weapons above, fire/use low. These are
                //    above the look region so their taps take priority.
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
            ),
          );
        },
      ),
    );
  }
}

// Re-export so callers needing the button-id constants get them via this file.
// ignore: unused_element
const List<String> kOverlayButtonIds = OverlayButtonId.all;
