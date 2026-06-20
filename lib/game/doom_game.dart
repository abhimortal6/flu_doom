// The integrated Doom game widget ("base game up" milestone).
//
// Boots to the TITLE SCREEN (D_StartTitle: GS_DEMOSCREEN / TITLEPIC), then the
// main menu -> New Game -> episode -> skill -> G_InitNew starts E1M1 fresh.
//
// Wires every subsystem into a playable game:
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

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../engine/input/event.dart';
import '../engine/render/renderer.dart';
import '../engine/sound/audio_engine.dart';
import '../engine/sound/music.dart';
import '../engine/sound/sfx_sound_hook.dart';
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
import 'integration/psprite_adapter.dart';
import 'integration/sprite_adapter.dart';
import 'play/playsim.dart';
import 'play/sounds.dart';
import 'state/game_state.dart';
import 'state/level_flow.dart';
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
  PlaypalSet? _palettes;
  KeyStateBridge? _keyBridge;
  GameLoop? _loop;
  ControlsSettingsStore? _store;
  SfxSoundHook? _sfxHook;
  AudioEngine? _audio;
  MusicEngine? _music;

  // Common gameplay sounds to precache at boot (I_PrecacheSounds equivalent).
  static const List<int> _precacheSfx = <int>[
    Sfx.pistol,
    Sfx.shotgn,
    Sfx.sgcock,
    Sfx.doropn,
    Sfx.dorcls,
    Sfx.swtchn,
    Sfx.swtchx,
    Sfx.itemup,
    Sfx.wpnup,
    Sfx.barexp,
    Sfx.oof,
    Sfx.posit1,
    Sfx.popain,
    Sfx.podth1,
    Sfx.firsht,
    Sfx.firxpl,
    Sfx.telept,
  ];

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

      // All 14 PLAYPAL palettes; ST_doPaletteStuff selects one per frame to
      // tint the screen (damage red / pickup yellow / radsuit green).
      final PlaypalSet palettes = PlaypalSet.fromWad(wad);

      // ---------------------------------------------------------------------
      // AUDIO: initialize the flutter_soloud backend and build the real
      // SoundHook. If init fails (headless / CI / no audio device) we fall back
      // to NullSoundHook and log — the game NEVER crashes on audio failure.
      // The listener is the console player's mobj, read live via the closure.
      // ---------------------------------------------------------------------
      PlaySim? simRef; // captured by the listenerProvider closure.
      SfxSoundHook? sfxHook;
      final SoLoudAudioEngine audio = SoLoudAudioEngine();
      _audio = audio;
      final bool audioOk = await audio.init();
      if (audioOk) {
        sfxHook = SfxSoundHook(
          wad: wad,
          audio: audio,
          listenerProvider: () => simRef?.player.mo,
        );
        _sfxHook = sfxHook;
        // Precache the common gameplay sounds so the first trigger is instant
        // (vanilla I_PrecacheSounds). Best-effort; failures are swallowed.
        for (final int id in _precacheSfx) {
          unawaited(_sfxHook!.precache(id));
        }
        // MUSIC: the OPL MIDI player (i_oplmusic.c) wired to GENMIDI + OPL3.
        // Renders MUS songs to looping audio per game state. Silent no-op if
        // GENMIDI is missing or rendering fails — never crashes the game.
        _music = MusicEngine(wad: wad, audio: audio);
        debugPrint('[flu_doom] audio engine initialized; SFX enabled; '
            'music ${_music!.enabled ? "enabled" : "disabled"}');
      } else {
        debugPrint('[flu_doom] audio init failed; SFX disabled (NullSoundHook)');
      }

      // World + play simulation. A level is loaded so the renderer/adapters and
      // automap have valid geometry/viewpoint while on the title screen; the 3D
      // worldView is only invoked once a New Game enters GS_LEVEL. Inject the
      // real SoundHook when audio is available; else PlaySim uses NullSoundHook.
      final PlaySim sim = PlaySim(World.fromWad(wad), sound: sfxHook);
      simRef = sim;
      sim.spawnLevel();

      // Renderer + sprite adapters (world things + player weapon psprites).
      // The renderer reads world.level / sim.* live, so a level change (which
      // swaps world.level + rebuilds sim's subsystems) re-points it with no
      // re-wiring here.
      final Renderer renderer = Renderer(framebuffer: _fb, world: sim.world);
      final PlaySpriteAdapter sprites = PlaySpriteAdapter(sim, wad);
      // Share the built sprites[] resolver with the psprite adapter.
      final PlayPspriteAdapter psprites =
          PlayPspriteAdapter(sim, sprites.spriteResolver);

      // Level-completion flow (g_game.c: G_ExitLevel/G_DoCompleted/...).
      final LevelFlow flow = LevelFlow(
        sim: sim,
        mapExists: (String name) => wad.lumpNumForName(name) >= 0,
      );

      // Game state (status bar / HUD / automap / menu) with injected adapters.
      late final GameState gs;
      gs = GameState(GameStateConfig(
        wad: wad,
        world: sim.world,
        playerStatus: PlayerStatusAdapter(sim.player),
        worldView: (Framebuffer fb) =>
            renderer.renderPlayerView(sprites, psprites),
        // New Game from the menu (M_NewGame -> M_ChooseSkill -> G_DeferedInitNew
        // -> G_InitNew). The menu fires (episode, skill) 0-based; G_InitNew uses
        // a 1-based episode + map 1, then loads E<ep>M1 fresh (falling back to
        // E1M1 if that episode is absent from the WAD).
        onStartNewGame: (int episode, int skill) {
          sim.newGame(episode + 1, skill, 1); // fresh init: E<ep>M1
          // Sync the level-completion flow to whatever map newGame actually
          // loaded (it may have fallen back to E1M1), so the next intermission /
          // world-done advances from the right place. Map name is "E<ep>M<map>".
          final String loaded = sim.world.level.name; // e.g. "E1M1"
          final RegExpMatch? m =
              RegExp(r'^E(\d+)M(\d+)$').firstMatch(loaded);
          flow.episode = m != null ? int.parse(m.group(1)!) : 1;
          flow.map = m != null ? int.parse(m.group(2)!) : 1;
          flow.secretExit = false;
        },
        // Intermission stats are built from the REAL finished level + player.
        statsProvider: () => flow.buildStats(),
        // Intermission done -> load the next map (or finale after E1M8).
        onAdvanceLevel: () {
          final String? loaded = flow.worldDone();
          if (loaded == null) {
            gs.triggerVictory(); // end of episode 1 -> finale
          }
        },
        // Song-per-state cue (S_Start). Title/demoscreen -> D_INTRO; GS_LEVEL ->
        // the level's song (mus_e1m1 + (ep-1)*9 + map-1); intermission ->
        // D_INTER; finale -> the victory music. Best-effort; the MusicEngine is
        // itself failure-tolerant, so a null engine / failed render is silent.
        onMusicCue: (GameStateType state) {
          final MusicEngine? music = _music;
          if (music == null) return;
          switch (state) {
            case GameStateType.demoScreen:
              unawaited(music.changeMusic(Mus.intro));
              break;
            case GameStateType.level:
              unawaited(music.changeMusic(
                  musicForLevel(flow.episode, flow.map)));
              break;
            case GameStateType.intermission:
              unawaited(music.changeMusic(Mus.inter));
              break;
            case GameStateType.finale:
              unawaited(music.changeMusic(Mus.victor));
              break;
          }
        },
      ));

      // Level-exit hooks (switch special 11 -> normal, 51 -> secret, boss
      // death) -> G_ExitLevel/G_SecretExitLevel + defer ga_completed.
      sim.onExitLevel = () {
        flow.exitLevel();
        gs.completeLevel();
      };
      sim.onSecretExitLevel = () {
        flow.secretExitLevel();
        gs.completeLevel();
      };
      // D_StartTitle: boot to the TITLE SCREEN (GS_DEMOSCREEN / TITLEPIC), NOT
      // straight into a level. The GameState machine already defaults to
      // GameStateType.demoScreen; pressing any key / Esc opens the main menu
      // (M_Responder), and New Game -> episode -> skill fires onStartNewGame
      // (G_InitNew) which loads E1M1 fresh and enters GS_LEVEL.
      //
      // The attract DEMO LOOP (demo1/credits/demo2 via D_AdvanceDemo) and the
      // screen wipe are OUT OF SCOPE: the title is a static TITLEPIC that waits
      // for input. (No title music — SFX-only build.)
      gs.enterDemoScreen();

      _palettes = palettes;
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
    final PlaypalSet? palettes = _palettes;
    final GameState? gs = _gs;
    if (palettes == null || gs == null || _decodingFrame) return;
    _decodingFrame = true;
    try {
      // ST_doPaletteStuff: pick the damage/pickup/radsuit-tinted palette.
      final Palette palette = palettes[gs.paletteIndex];
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
    // Tear down the audio backend (no-op if it never initialized).
    _sfxHook = null;
    unawaited(_music?.dispose() ?? Future<void>.value());
    _music = null;
    unawaited(_audio?.dispose() ?? Future<void>.value());
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
