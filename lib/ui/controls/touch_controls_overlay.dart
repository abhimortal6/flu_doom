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
import 'overlay_layout.dart';
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

  // ---- GAMEPLAY mode: the stick / look / fire / use / weapon / utility
  // overlay, shown only during active level play. ----
  //
  // Each control is placed ABSOLUTELY via [OverlayLayout]: its normalized
  // center is the saved per-orientation override if the user has dragged it
  // (settings.positionsFor(landscape)), else the built-in corner-cluster
  // default. The layout clamps every body fully on-screen. scale / opacity /
  // handedness still apply (they feed the layout + the widgets).
  Widget _buildGameplay(BuildContext context) {
    final OverlaySettings s = widget.settings;
    final double op = s.opacity;
    final bool leftHanded = s.handed == HandedLayout.left;

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool landscape =
              constraints.maxWidth >= constraints.maxHeight;
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, inner) {
                final OverlayLayout layout = OverlayLayout(
                  area: Size(inner.maxWidth, inner.maxHeight),
                  landscape: landscape,
                  leftHanded: leftHanded,
                  scale: s.scale,
                );
                final Map<String, ButtonPosition> overrides =
                    s.positionsFor(landscape);

                // ---- LOOK region: the side of the screen WITHOUT the stick.
                // Sits at the BOTTOM of the z-order so the action buttons win
                // their overlapping touches (Flutter hit-tests top-of-stack
                // first). Independent of per-button positions — it's the broad
                // drag-to-turn camera band, not a repositionable control.
                final double lookFraction = 0.62;
                final double lookWidth = inner.maxWidth * lookFraction;
                final Widget lookRegion = Positioned(
                  top: 0,
                  bottom: 0,
                  left: leftHanded ? 0 : inner.maxWidth - lookWidth,
                  width: lookWidth,
                  child: LookCameraRegion(analog: widget.analog),
                );

                // Build each repositionable control (id -> widget).
                final Map<String, Widget> controls = <String, Widget>{
                  OverlayButtonId.movementStick: OverlayMoveStick(
                    analog: widget.analog,
                    size: layout.sizeFor(OverlayButtonId.movementStick),
                    opacity: op,
                  ),
                  OverlayButtonId.use: OverlayHoldButton(
                    action: GameAction.use,
                    sink: widget.sink,
                    label: 'USE',
                    icon: Icons.touch_app,
                    size: layout.sizeFor(OverlayButtonId.use),
                    opacity: op,
                    momentary: true,
                  ),
                  OverlayButtonId.fire: OverlayHoldButton(
                    action: GameAction.fire,
                    sink: widget.sink,
                    label: 'FIRE',
                    icon: Icons.gps_fixed,
                    size: layout.sizeFor(OverlayButtonId.fire),
                    opacity: op,
                  ),
                  OverlayButtonId.prevWeapon: OverlayWeaponButton(
                    action: GameAction.prevWeapon,
                    sink: widget.sink,
                    label: 'PREV',
                    icon: Icons.chevron_left,
                    size: layout.sizeFor(OverlayButtonId.prevWeapon),
                    opacity: op,
                  ),
                  OverlayButtonId.nextWeapon: OverlayWeaponButton(
                    action: GameAction.nextWeapon,
                    sink: widget.sink,
                    label: 'NEXT',
                    icon: Icons.chevron_right,
                    size: layout.sizeFor(OverlayButtonId.nextWeapon),
                    opacity: op,
                  ),
                  OverlayButtonId.menu: OverlayHoldButton(
                    action: GameAction.menuToggle,
                    sink: widget.sink,
                    label: 'MENU',
                    icon: Icons.menu,
                    size: layout.sizeFor(OverlayButtonId.menu),
                    opacity: op,
                    momentary: true,
                  ),
                  OverlayButtonId.automap: OverlayHoldButton(
                    action: GameAction.automap,
                    sink: widget.sink,
                    label: 'MAP',
                    icon: Icons.map,
                    size: layout.sizeFor(OverlayButtonId.automap),
                    opacity: op,
                    momentary: true,
                  ),
                  OverlayButtonId.pause: OverlayHoldButton(
                    action: GameAction.pause,
                    sink: widget.sink,
                    label: 'II',
                    icon: Icons.pause,
                    size: layout.sizeFor(OverlayButtonId.pause),
                    opacity: op,
                    momentary: true,
                  ),
                };

                final List<Widget> stack = <Widget>[lookRegion];
                for (final String id in OverlayButtonId.all) {
                  final ButtonPosition center =
                      layout.centerFor(id, overrides);
                  final Offset tl = layout.topLeftFor(id, center);
                  stack.add(
                    Positioned(
                      left: tl.dx,
                      top: tl.dy,
                      child: controls[id]!,
                    ),
                  );
                }

                return Stack(children: stack);
              },
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
