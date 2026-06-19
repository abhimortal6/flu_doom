// The integrated Doom game widget ("base game up" milestone).
//
// Wires every subsystem into a playable E1M1:
//   doom1.wad -> World.fromWad(E1M1) -> PlaySim.spawnLevel()
//             -> Renderer + sprite adapter
//             -> GameState (status bar / HUD / automap / menu)
//             -> GameLoop (35Hz tic + render)
//             -> ActionKeyboardListener + EventQueueActionSink (+ touch overlay).
//
// Per-tic (onTic): drain events -> playsim ticcmd + advance (only in active
// GS_LEVEL play) -> gs.ticker(events) for menu/automap/pause.
// Per-frame (onRender): gs.render(fb) (D_Display: 3D view + HUD + menu) ->
// fb.toImage(palette) -> VideoView.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../engine/input/event.dart';
import '../engine/render/renderer.dart';
import '../engine/system/gameloop.dart';
import '../engine/video/framebuffer.dart';
import '../engine/video/palette.dart';
import '../engine/video/video_view.dart';
import '../engine/wad/wad.dart';
import '../input_actions/action_dispatcher.dart';
import '../input_actions/action_keyboard_listener.dart';
import '../input_actions/controls_settings.dart';
import '../input_actions/key_bindings.dart';
import '../ui/controls/touch_controls_overlay.dart';
import '../ui/debug_overlay.dart';
import '../ui/settings/controls_settings_screen.dart';
import 'integration/key_state_bridge.dart';
import 'integration/player_status_adapter.dart';
import 'integration/sprite_adapter.dart';
import 'play/playsim.dart';
import 'state/game_state.dart';
import 'world/world.dart';

const String kWadAsset = 'assets/doom1.wad';

class DoomGame extends StatefulWidget {
  const DoomGame({super.key});

  @override
  State<DoomGame> createState() => _DoomGameState();
}

class _DoomGameState extends State<DoomGame>
    with SingleTickerProviderStateMixin {
  final EventQueue _events = EventQueue();
  final Framebuffer _fb = Framebuffer();

  // Subsystems (assigned during _boot).
  late final EventQueueActionSink _sink = EventQueueActionSink(_events);
  PlaySim? _sim;
  GameState? _gs;
  Palette? _palette;
  KeyStateBridge? _keyBridge;
  GameLoop? _loop;
  ControlsSettingsStore? _store;

  KeyBindings _bindings = KeyBindings.defaults();
  OverlaySettings _overlay = const OverlaySettings();

  ui.Image? _frame;
  bool _decodingFrame = false;
  bool _ready = false;
  bool _showDebug = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      // Load persisted controls settings (overlay + bindings); never throws.
      try {
        final ControlsSettingsStore store = await ControlsSettingsStore.open();
        _store = store;
        _overlay = store.loadOverlay();
        _bindings = store.loadBindings();
      } catch (_) {
        // Fall back to defaults if persistence is unavailable.
      }

      final ByteData bytes = await rootBundle.load(kWadAsset);
      final WadFile wad = WadFile.fromBytes(bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ));

      final Palette palette = Palette.fromWad(wad);

      // World + play simulation.
      final PlaySim sim = PlaySim(World.fromWad(wad));
      sim.spawnLevel();

      // Renderer + sprite adapter.
      final Renderer renderer = Renderer(framebuffer: _fb, world: sim.world);
      final PlaySpriteAdapter sprites = PlaySpriteAdapter(sim, wad);

      // Game state (status bar / HUD / automap / menu) with injected adapters.
      final GameState gs = GameState(GameStateConfig(
        wad: wad,
        world: sim.world,
        playerStatus: PlayerStatusAdapter(sim.player),
        worldView: (Framebuffer fb) => renderer.renderPlayerView(sprites),
      ));
      // Jump straight into the level (this milestone boots into E1M1 rather
      // than the title/demo screen).
      gs.enterLevel();

      _palette = palette;
      _sim = sim;
      _gs = gs;
      _keyBridge = KeyStateBridge(_sink);

      _loop = GameLoop(vsync: this, onTic: _onTic, onRender: _onRender);
      _ready = true;
      // Render an initial frame, then start the loop.
      _onRender();
      _loop!.start();
      if (mounted) setState(() {});
    } catch (e, st) {
      _error = '$e\n$st';
      if (mounted) setState(() {});
    }
  }

  void _onTic(int gametic) {
    final GameState? gs = _gs;
    final PlaySim? sim = _sim;
    final KeyStateBridge? bridge = _keyBridge;
    if (gs == null || sim == null || bridge == null) return;

    // Drain this tic's input events once.
    final List<DoomEvent> evs = _events.drain();

    // Advance the play simulation only during active gameplay (not while a menu
    // is up, paused, or the automap has taken over). Otherwise the sim freezes,
    // mirroring vanilla's paused/menu behaviour.
    final bool activePlay = gs.gamestate == GameStateType.level &&
        !gs.paused &&
        !gs.menu.active;
    if (activePlay) {
      sim.buildTiccmd(bridge.build());
      sim.tic();
    }

    // Route events to the game-state machine (menu / automap / pause).
    gs.ticker(evs);
  }

  void _onRender() {
    final GameState? gs = _gs;
    if (gs == null) return;
    gs.render(_fb);
    _present();
  }

  Future<void> _present() async {
    final Palette? palette = _palette;
    if (palette == null || _decodingFrame) return;
    _decodingFrame = true;
    try {
      final ui.Image img = await _fb.toImage(palette);
      final ui.Image? old = _frame;
      _frame = img;
      old?.dispose();
      if (mounted) setState(() {});
    } finally {
      _decodingFrame = false;
    }
  }

  void _onAppPaused() => _sink.releaseAll();

  Future<void> _openControlsSettings() async {
    final ControlsSettingsStore? store = _store;
    if (store == null) return;
    // Release held keys so nothing sticks while the settings route is open.
    _sink.releaseAll();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ControlsSettingsScreen(
        store: store,
        onChanged: (OverlaySettings overlay, KeyBindings bindings) {
          setState(() {
            _overlay = overlay;
            _bindings = bindings;
          });
        },
      ),
    ));
    _sink.releaseAll();
  }

  @override
  void dispose() {
    _loop?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: const Color(0xFF200000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Boot error:\n$_error',
              style: const TextStyle(color: Color(0xFFFF8080), fontSize: 12),
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF000000),
        child: Center(
          child: Text('Loading…',
              style: TextStyle(color: Color(0xFF00FF00), fontSize: 14)),
        ),
      );
    }

    return _LifecycleHandler(
      onPaused: _onAppPaused,
      child: ActionKeyboardListener(
        bindings: _bindings,
        sink: _sink,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            VideoView(
              image: _frame,
              scaleMode: ScaleMode.fit,
              pixelAspectCorrection: true,
            ),
            TouchControlsOverlay(sink: _sink, settings: _overlay),
            if (_showDebug)
              DebugOverlay(
                fps: _loop?.fps ?? 0,
                gametic: _loop?.gametic ?? 0,
                extra: 'state ${_gs?.gamestate.name}',
              ),
            // Top-right utility buttons: settings gear + debug toggle.
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: <Widget>[
                      _MiniButton(
                        label: 'settings',
                        onTap: _openControlsSettings,
                      ),
                      const SizedBox(width: 8),
                      _MiniButton(
                        label: _showDebug ? 'dbg on' : 'dbg off',
                        onTap: () => setState(() => _showDebug = !_showDebug),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: const Color(0xAA000000),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF00FF00), fontSize: 11),
        ),
      ),
    );
  }
}

/// Calls [onPaused] when the app is backgrounded / loses focus, so the input
/// sink can release held keys (avoids stuck movement).
class _LifecycleHandler extends StatefulWidget {
  const _LifecycleHandler({required this.onPaused, required this.child});
  final VoidCallback onPaused;
  final Widget child;

  @override
  State<_LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<_LifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      widget.onPaused();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
