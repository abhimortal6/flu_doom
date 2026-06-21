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

/// Which control scheme the overlay presents.
///
/// The game shell picks this from the game-state machine each frame (see
/// [DoomGame] reading `gs.isActiveLevelPlay`): GAMEPLAY only during active level
/// play (gamestate == level AND no menu up), MENU everywhere else (title/
/// demoScreen, intermission, finale, or while a menu is open).
enum OverlayMode {
  /// Stick / drag-to-look / fire / use / weapon / utility (active level play).
  gameplay,

  /// D-pad + Confirm + Back navigation cluster (menus & non-level screens).
  menu,
}

class TouchControlsOverlay extends StatefulWidget {
  TouchControlsOverlay({
    super.key,
    required this.sink,
    AnalogInput? analog,
    this.settings = const OverlaySettings(),
    this.mode = OverlayMode.gameplay,
  }) : analog = analog ?? AnalogInput();

  /// Convenience: wraps an [EventQueue] in a fresh [EventQueueActionSink].
  TouchControlsOverlay.forQueue({
    Key? key,
    required EventQueue queue,
    AnalogInput? analog,
    OverlaySettings settings = const OverlaySettings(),
    OverlayMode mode = OverlayMode.gameplay,
  }) : this(
          key: key,
          sink: EventQueueActionSink(queue),
          analog: analog,
          settings: settings,
          mode: mode,
        );

  /// Where overlay buttons dispatch their (discrete) actions.
  final ActionSink sink;

  /// Which control scheme to show this frame. Driven by the game-state machine
  /// (the shell rebuilds the overlay when the gamestate / menu-active signal
  /// changes), so the overlay flips between the gameplay stick/look/fire scheme
  /// and the menu D-pad navigation cluster automatically.
  final OverlayMode mode;

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
    // Leaving gameplay mode (e.g. a menu just opened): drop any in-flight
    // analog move/look so movement/turning doesn't stick while the gameplay
    // stick/look region is unmounted and unable to release it.
    if (old.mode == OverlayMode.gameplay &&
        widget.mode != OverlayMode.gameplay) {
      widget.analog.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.visible) return const SizedBox.shrink();
    if (widget.mode == OverlayMode.menu) return _buildMenu(context);
    return _buildGameplay(context);
  }

  // ---- MENU mode: a touch navigation cluster (D-pad + Confirm + Back). ----
  //
  // D-pad bottom-left, Confirm/Back bottom-right (mirrored when left-handed),
  // honoring opacity / scale / handedness. Each button posts a discrete arrow /
  // enter / escape DoomKey via the existing tapAction path, so M_Responder sees
  // clean per-tap presses (item-by-item nav, slider adjust, select, back-out).
  Widget _buildMenu(BuildContext context) {
    final OverlaySettings s = widget.settings;
    final double op = s.opacity;
    final bool leftHanded = s.handed == HandedLayout.left;

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool landscape =
              constraints.maxWidth >= constraints.maxHeight;
          final double scale = s.scale * (landscape ? 1.0 : 0.9);
          final double dpadSize = 180 * scale;
          final double btn = 72 * scale;
          final double gap = 16 * scale;
          final EdgeInsets pad = EdgeInsets.all(16 * scale);

          final Alignment dpadAlign =
              leftHanded ? Alignment.bottomRight : Alignment.bottomLeft;
          final Alignment actionsAlign =
              leftHanded ? Alignment.bottomLeft : Alignment.bottomRight;

          final Widget dpad = OverlayMenuDpad(
            sink: widget.sink,
            size: dpadSize,
            opacity: op,
          );

          // Confirm (Enter) + Back (Esc). Both momentary taps. Back maps to
          // GameAction.menuToggle == DoomKey.escape (open/close/back-out).
          final Widget confirmBack = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: leftHanded
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: <Widget>[
              OverlayHoldButton(
                action: GameAction.menuToggle,
                sink: widget.sink,
                label: 'BACK',
                icon: Icons.arrow_back,
                size: btn,
                opacity: op,
                momentary: true,
              ),
              SizedBox(height: gap),
              OverlayHoldButton(
                action: GameAction.confirm,
                sink: widget.sink,
                label: 'CONFIRM',
                icon: Icons.check,
                size: btn,
                opacity: op,
                momentary: true,
              ),
            ],
          );

          return SafeArea(
            child: Stack(
              children: <Widget>[
                Align(
                  alignment: dpadAlign,
                  child: Padding(padding: pad, child: dpad),
                ),
                Align(
                  alignment: actionsAlign,
                  child: Padding(padding: pad, child: confirmBack),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- GAMEPLAY mode: the existing stick / look / fire / use / weapon /
  // utility overlay, shown only during active level play. ----
  Widget _buildGameplay(BuildContext context) {
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
          final double weaponBtn = 56 * scale;
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

          // ---- Secondary cluster: weapon switch. Prominent, clearly-LABELED
          // pill buttons (not bare chevron circles) so they're recognizable and
          // thumb-reachable on a phone. Each is a momentary tap posting the
          // prev/next-weapon DoomKey. Sits ABOVE the look region in the Stack
          // (same as FIRE/USE) so its taps win over the camera drag.
          final Widget secondaryActions = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OverlayWeaponButton(
                action: GameAction.prevWeapon,
                sink: widget.sink,
                label: 'PREV',
                icon: Icons.chevron_left,
                iconLeading: true,
                height: weaponBtn,
                opacity: op,
              ),
              SizedBox(width: gap),
              OverlayWeaponButton(
                action: GameAction.nextWeapon,
                sink: widget.sink,
                label: 'NEXT',
                icon: Icons.chevron_right,
                iconLeading: false,
                height: weaponBtn,
                opacity: op,
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
