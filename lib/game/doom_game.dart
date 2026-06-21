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
import '../engine/video/widescreen.dart';
import '../engine/video/wipe.dart';
import '../engine/wad/wad.dart';
import '../input_actions/action_dispatcher.dart';
import '../input_actions/action_keyboard_listener.dart';
import '../input_actions/analog_input.dart';
import '../input_actions/controls_settings.dart';
import '../input_actions/graphics_settings.dart';
import '../input_actions/key_bindings.dart';
import '../ui/controls/touch_controls_overlay.dart';
import '../ui/debug_overlay.dart';
import '../ui/settings/controls_settings_screen.dart';
import '../ui/settings/graphics_settings_screen.dart';
import 'integration/key_state_bridge.dart';
import 'integration/player_status_adapter.dart';
import 'integration/psprite_adapter.dart';
import 'integration/sprite_adapter.dart';
import 'play/playsim.dart';
import 'play/sounds.dart';
import 'state/game_state.dart';
import 'state/level_flow.dart';
import 'world/world.dart';

// Bundled game IWAD: the shareware doom1.wad (© id Software), bundled for
// original-Doom compatibility testing. Freedoom Phase 1 (freedoom1.wad) — a
// BSD-licensed, vanilla-compatible IWAD that the engine loads exactly like
// doom1.wad — remains available in assets/ and can be swapped back by flipping
// this constant and the bundled asset in pubspec.yaml.
const String kWadAsset = 'assets/doom1.wad';

class DoomGame extends StatefulWidget {
  const DoomGame({super.key});

  @override
  State<DoomGame> createState() => _DoomGameState();
}

class _DoomGameState extends State<DoomGame>
    with SingleTickerProviderStateMixin {
  final EventQueue _events = EventQueue();

  // The indexed framebuffer. Its WIDTH depends on the aspect mode: 320 (4:3) or
  // a wider true-widescreen width (height always 200). Rebuilt when the aspect
  // toggles (see [_rebuildRenderer]). Starts 4:3; widescreen is applied in _boot
  // once the device aspect is known.
  Framebuffer _fb = Framebuffer();
  int _renderWidth = kBaseWidth;

  // The 3D renderer, held mutably so the worldView closure renders through the
  // CURRENT renderer after a width rebuild. Built in _boot, swapped on toggle.
  Renderer? _renderer;
  // Sprite adapters captured so a width rebuild can re-create the renderer with
  // the same sprite sources.
  PlaySpriteAdapter? _sprites;
  PlayPspriteAdapter? _psprites;

  // Subsystems (assigned during _boot).
  late final EventQueueActionSink _sink = EventQueueActionSink(_events);

  // Analog touch side channel (PUBG-style movement stick + drag-to-look). The
  // overlay writes it; the KeyStateBridge reads it into the ticcmd each tic.
  // Idle (all-zero) when no touch input is present, so keyboard play is
  // unaffected.
  final AnalogInput _analog = AnalogInput();
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
  GraphicsSettingsStore? _gfxStore;
  GraphicsSettings _gfx = GraphicsSettings.defaults();

  // In-game Options "Screen Size" (0..8). Wired to a PRESENT-layer inset of the
  // displayed image (cosmetic letterbox shrink of the 320x200 view) — the 3D
  // renderer stays full-size and its math is untouched. 8 = full (no inset).
  int _screenSize = 8;

  ui.Image? _frame;
  bool _decodingFrame = false;
  bool _ready = false;

  // ---- Screen-melt wipe (f_wipe.c / D_Display driving logic) ----
  // wipegamestate tracks the last *presented* gamestate; when gs.gamestate
  // differs we trigger a melt (D_Display's `wipe = gamestate != wipegamestate`).
  // While [_wipe] is non-null the melt runs across frames and game logic is
  // FROZEN (vanilla blocks in D_RunFrame until the wipe completes).
  GameStateType? _wipegamestate;
  WipeMelt? _wipe;
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

      // Load persisted graphics/video (present-layer) settings; defaults are the
      // mobile-friendly Smooth + 4:3 aspect, CRT off. Never throws.
      try {
        final GraphicsSettingsStore gstore =
            await GraphicsSettingsStore.open();
        _gfxStore = gstore;
        _gfx = gstore.load();
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

      // Determine the render width from the aspect mode. Widescreen renders a
      // WIDER FOV (height stays 200) sized to a 16:9 device by default; the live
      // device aspect refines it on the first build (see [_maybeRefineWidth]).
      // 4:3 keeps the vanilla 320.
      _renderWidth = _gfx.aspectMode == AspectMode.widescreen
          ? widescreenWidthFor(16 / 9)
          : kBaseWidth;
      _fb = Framebuffer(width: _renderWidth);

      // Renderer + sprite adapters (world things + player weapon psprites).
      // The renderer reads world.level / sim.* live, so a level change (which
      // swaps world.level + rebuilds sim's subsystems) re-points it with no
      // re-wiring here. The renderer is held in [_renderer] so a width rebuild
      // can swap it; the worldView closure renders through the current one.
      final PlaySpriteAdapter sprites = PlaySpriteAdapter(sim, wad);
      // Share the built sprites[] resolver with the psprite adapter.
      final PlayPspriteAdapter psprites =
          PlayPspriteAdapter(sim, sprites.spriteResolver);
      _sprites = sprites;
      _psprites = psprites;
      _renderer = Renderer(framebuffer: _fb, world: sim.world);

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
            _renderer?.renderPlayerView(_sprites!, _psprites!),
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
        // Pause/resume music when the menu opens or gameplay is paused
        // (S_PauseSound / S_ResumeSound). Best-effort; null engine is a no-op.
        onMusicPause: (bool paused) {
          if (paused) {
            _music?.pause();
          } else {
            _music?.resume();
          }
        },
        // Sound Volume menu -> live audio (S_SetSfxVolume / S_SetMusicVolume).
        // User-scale 0..15; the engines map to their own internal scale.
        onSfxVolume: (int v) {
          debugPrint('[flu_doom] menu -> SFX volume $v/15');
          _sfxHook?.setSfxVolume(v);
        },
        onMusicVolume: (int v) {
          debugPrint('[flu_doom] menu -> music volume $v/15');
          _music?.setMusicVolume(v);
        },
        // Options "End Game" returns to the title screen (GameState already
        // performs enterDemoScreen(); nothing extra to do here).
        onEndGame: () {
          debugPrint('[flu_doom] menu -> End Game (return to title)');
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
      // In-game Options menu -> present layer. The 3D renderer is untouched.
      //  * Graphic Detail (M_ChangeDetail): HIGH(0)=Smooth filter, LOW(1)=Sharp.
      //    Seed the label from the persisted filter so it reflects the real state.
      //  * Screen Size (M_SizeDisplay): cosmetic letterbox inset of the view.
      gs.menu.detailLevel =
          _gfx.filter == UpscaleFilter.smooth ? 0 : 1;
      gs.menu.screenSize = _screenSize;
      gs.menu.onDetailChanged = (int detail) {
        // detail 0 = HIGH -> smooth; 1 = LOW -> sharp.
        final UpscaleFilter f =
            detail == 0 ? UpscaleFilter.smooth : UpscaleFilter.sharp;
        _applyGraphics(_gfx.copyWith(filter: f));
      };
      gs.menu.onScreenSize = (int size) {
        setState(() => _screenSize = size);
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
      _analog.lookSensitivity = _overlay.lookSensitivity;
      _keyBridge = KeyStateBridge(_sink, analog: _analog);
      // wipegamestate starts at the boot state (GS_DEMOSCREEN), matching the
      // first presented frame so no spurious wipe fires before any transition.
      _wipegamestate = gs.gamestate;

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

    // FREEZE game logic/ticking while a melt is in progress (vanilla blocks in
    // D_RunFrame until wipe_ScreenWipe reports done before resuming play). We
    // still keep events queued; they are drained once the wipe finishes.
    if (_wipe != null) return;

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

    // --- Screen-melt wipe driver (D_Display + D_RunFrame logic) ---
    final WipeMelt? wipe = _wipe;
    if (wipe != null) {
      // A melt is running: advance it one tic (wipe_ScreenWipe with ticks==1),
      // compose the melted frame into the live framebuffer, and present that.
      // Game logic stays frozen (see _onTic) until the melt completes.
      final bool done = wipe.update();
      wipe.compose(_fb);
      _present();
      if (done) {
        // Melt finished: resume normal rendering from the next frame. The new
        // screen is now fully shown; mark it as the presented gamestate.
        _wipe = null;
        _wipegamestate = gs.gamestate;
      }
      return;
    }

    // Detect a gamestate transition that should wipe. At this point _fb still
    // holds the PREVIOUSLY presented frame (the wipe START screen).
    if (gs.gamestate != _wipegamestate) {
      // Capture the old (currently-presented) screen as the START screen.
      final Uint8List startBytes = Uint8List.fromList(_fb.pixels);
      // Render the NEW screen into _fb as the END screen.
      gs.render(_fb);
      final Uint8List endBytes = Uint8List.fromList(_fb.pixels);
      // Begin the melt (wipe_StartScreen + wipe_EndScreen + wipe_initMelt). The
      // first composed frame is ~all-START; subsequent update()s melt to END.
      final WipeMelt melt = WipeMelt.start(startBytes, endBytes);
      melt.compose(_fb); // present the all-old first frame
      _wipe = melt;
      _present();
      return;
    }

    // Normal frame: render the live screen and present.
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

  void _onAppPaused() {
    _sink.releaseAll();
    _analog.reset();
  }

  /// Apply (and persist) new graphics/present settings live, and keep the
  /// in-game Options "Graphic Detail" label in sync with the upscale filter.
  void _applyGraphics(GraphicsSettings g) {
    final AspectMode prevAspect = _gfx.aspectMode;
    setState(() => _gfx = g);
    unawaited(_gfxStore?.save(g) ?? Future<void>.value());
    // Keep the menu's detail label consistent (smooth=HIGH, sharp=LOW).
    _gs?.menu.detailLevel = g.filter == UpscaleFilter.smooth ? 0 : 1;
    // Aspect-mode change -> rebuild the framebuffer + renderer at the new width.
    if (g.aspectMode != prevAspect) {
      final int width = g.aspectMode == AspectMode.widescreen
          ? widescreenWidthFor(_deviceAspect())
          : kBaseWidth;
      _rebuildRenderer(width);
    }
  }

  /// The current device landscape aspect (>= 1.0) used to size the widescreen
  /// render width. Falls back to 16:9 before the first layout is available.
  double _deviceAspect() {
    final Size? size =
        WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
            ? WidgetsBinding.instance.platformDispatcher.views.first.physicalSize
            : null;
    if (size == null || size.width <= 0 || size.height <= 0) return 16 / 9;
    return landscapeAspect(size.width, size.height);
  }

  /// Rebuild the framebuffer + 3D renderer at [width] (height stays 200) and
  /// re-render a frame. The worldView closure renders through [_renderer], so
  /// swapping it here re-points the 3D view with no other re-wiring. No-op if
  /// the width is unchanged.
  void _rebuildRenderer(int width) {
    if (width == _renderWidth) return;
    final PlaySim? sim = _sim;
    final PlaySpriteAdapter? sprites = _sprites;
    if (sim == null || sprites == null) return;
    _renderWidth = width;
    _fb = Framebuffer(width: width);
    _renderer = Renderer(framebuffer: _fb, world: sim.world);
    // A pending wipe references the OLD-width buffer; drop it (the next frame
    // renders cleanly at the new width).
    _wipe = null;
    _wipegamestate = _gs?.gamestate;
    // Render + present a fresh frame at the new width.
    if (_gs != null) {
      _onRender();
    }
    if (mounted) setState(() {});
  }

  Future<void> _openGraphicsSettings() async {
    final GraphicsSettingsStore? store = _gfxStore;
    if (store == null) return;
    _sink.releaseAll();
    _analog.reset();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GraphicsSettingsScreen(
        store: store,
        onChanged: (GraphicsSettings g) => _applyGraphics(g),
      ),
    ));
    _sink.releaseAll();
    _analog.reset();
  }

  Future<void> _openControlsSettings() async {
    final ControlsSettingsStore? store = _store;
    if (store == null) return;
    // Release held keys/analog so nothing sticks while the settings route is open.
    _sink.releaseAll();
    _analog.reset();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ControlsSettingsScreen(
        store: store,
        onChanged: (OverlaySettings overlay, KeyBindings bindings) {
          setState(() {
            _overlay = overlay;
            _bindings = bindings;
            _analog.lookSensitivity = overlay.lookSensitivity;
          });
        },
      ),
    ));
    _sink.releaseAll();
    _analog.reset();
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

    // Refine the widescreen render width to the ACTUAL device aspect once a
    // layout is available (boot used a 16:9 default). Runs after the frame so we
    // don't rebuild mid-build. No-op in 4:3 mode or when the width is unchanged.
    if (_gfx.aspectMode == AspectMode.widescreen) {
      final double aspect = _deviceAspect();
      final int want = widescreenWidthFor(aspect);
      if (want != _renderWidth) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _gfx.aspectMode == AspectMode.widescreen) {
            _rebuildRenderer(want);
          }
        });
      }
    }

    return _LifecycleHandler(
      onPaused: _onAppPaused,
      child: ActionKeyboardListener(
        bindings: _bindings,
        sink: _sink,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Present the framebuffer with the live graphics settings. The
            // "screen size" Options thermometer shrinks the view via a cosmetic
            // letterbox inset (8 = full; each step below insets ~3% per side),
            // leaving the renderer full 320x200.
            Padding(
              padding: EdgeInsets.all(
                _screenSize >= 8 ? 0.0 : (8 - _screenSize) * 14.0,
              ),
              child: VideoView(
                image: _frame,
                scaleMode: _gfx.scaleMode,
                pixelAspectCorrection: _gfx.pixelAspectCorrection,
                filterQuality: _gfx.filter.filterQuality,
                crtScanlines: _gfx.crtScanlines,
                crtIntensity: _gfx.effectiveCrtIntensity,
              ),
            ),
            TouchControlsOverlay(
              sink: _sink,
              analog: _analog,
              settings: _overlay,
              // Context-aware mode: GAMEPLAY only during active level play
              // (gamestate == level AND no menu up); MENU everywhere else
              // (title/demoScreen, intermission, finale, or while a menu is
              // open). Read live from the game-state machine each build; the
              // per-frame _present() setState rebuilds this when it changes, so
              // the overlay swaps the stick/look scheme for the menu D-pad nav
              // cluster (and back) automatically.
              mode: (_gs?.isActiveLevelPlay ?? false)
                  ? OverlayMode.gameplay
                  : OverlayMode.menu,
            ),
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
                        label: 'graphics',
                        onTap: _openGraphicsSettings,
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
