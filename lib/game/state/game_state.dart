// Game-state machine (g_game.c + d_main.c dispatch port).
//
// This owns the top-level Doom state machine: the [GameState.gamestate] enum
// (GS_LEVEL / GS_INTERMISSION / GS_FINALE / GS_DEMOSCREEN), the pending
// [GameAction], and the per-tic / per-frame entry points the integration loop
// calls (G_Ticker, G_Responder, and a D_Display-equivalent [render]).
//
// It does NOT depend on the concrete play-sim or 3D renderer. The 3D scene is
// drawn through the injected [WorldView] callback; player HUD values come from
// the injected [PlayerStatus]; intermission stats from [IntermissionStats].
//
// Event routing (D_ProcessEvents -> G_Responder) priority per vanilla:
//   1. menu (if active)         -> M_Responder
//   2. while GS_LEVEL: automap  -> AM_Responder, then HUD/player
//   3. intermission/finale own their responders
//   4. ESC anywhere opens the menu.

import '../../engine/input/doomkeys.dart';
import '../../engine/input/event.dart';
import '../../engine/video/framebuffer.dart';
import '../../engine/video/patch.dart';
import '../../engine/wad/wad.dart';
import '../../ui/automap/automap.dart';
import '../../ui/hud/graphics_cache.dart';
import '../../ui/hud/hud.dart';
import '../../ui/hud/status_bar.dart';
import '../../ui/menu/menu.dart';
import '../world/world.dart';
import 'interfaces.dart';
import 'intermission.dart';

/// Top-level game state (gamestate_t).
enum GameStateType {
  level, // GS_LEVEL
  intermission, // GS_INTERMISSION
  finale, // GS_FINALE
  demoScreen, // GS_DEMOSCREEN (title / demo loop)
}

/// Deferred top-level actions (gameaction_t subset relevant to this layer).
enum GameAction {
  nothing, // ga_nothing
  newGame, // ga_newgame
  loadLevel, // ga_loadlevel
  completed, // ga_completed (level done -> intermission)
  worldDone, // ga_worlddone (intermission done -> next level)
  victory, // ga_victory (-> finale)
}

/// Configuration / hooks the integration layer supplies.
class GameStateConfig {
  GameStateConfig({
    required this.wad,
    required this.world,
    required this.playerStatus,
    required this.worldView,
    this.onStartNewGame,
    this.onAdvanceLevel,
    this.statsProvider,
  });

  /// The merged WAD (for graphics lumps).
  final WadFile wad;

  /// The shared world (geometry + viewpoint). Read for automap; the playsim
  /// owns mutation.
  final World world;

  /// Source of HUD values (health/ammo/etc.).
  final PlayerStatus playerStatus;

  /// Renders the 3D scene into the framebuffer (R_RenderPlayerView).
  final WorldView worldView;

  /// Called when the menu confirms a new game (episode, skill). Integration
  /// wires this to the playsim's G_InitNew.
  final void Function(int episode, int skill)? onStartNewGame;

  /// Called when the intermission completes and the next level should load.
  /// Integration wires this to G_DoWorldDone / changeLevel.
  final void Function()? onAdvanceLevel;

  /// Supplies the end-of-level stats when a level completes. If null, a
  /// placeholder all-zero stats screen is shown.
  final IntermissionStats Function()? statsProvider;
}

/// The Doom game-state machine.
class GameState {
  GameState(this.config) : _gc = GraphicsCache(config.wad) {
    statusBar = StatusBar(_gc);
    hud = Hud(_gc);
    automap = Automap();
    menu = MenuController(_gc);
    intermission = Intermission(_gc);

    menu.onNewGame = (int ep, int sk) {
      config.onStartNewGame?.call(ep, sk);
      _deferAction(GameAction.newGame);
    };
    intermission.onComplete = () => _deferAction(GameAction.worldDone);
  }

  final GameStateConfig config;
  final GraphicsCache _gc;

  late final StatusBar statusBar;
  late final Hud hud;
  late final Automap automap;
  late final MenuController menu;
  late final Intermission intermission;

  /// Current top-level state. Starts on the demo/title screen like vanilla.
  GameStateType gamestate = GameStateType.demoScreen;

  /// Pending deferred action consumed at the top of [ticker].
  GameAction _action = GameAction.nothing;

  /// Whether gameplay is paused (BTS_PAUSE / Pause key).
  bool paused = false;

  /// Monotonic game tic counter (gametic). Bumped each [ticker] call.
  int gametic = 0;

  void _deferAction(GameAction a) => _action = a;

  // ------------------------------------------------------------------
  // Public lifecycle the integration loop drives.
  // ------------------------------------------------------------------

  /// Enter the level state directly (used after a new game / level load).
  void enterLevel() {
    gamestate = GameStateType.level;
    intermission.phase = IntermissionPhase.done;
    paused = false;
  }

  /// Begin the title/demo screen (the default boot state). Shows TITLEPIC.
  void enterDemoScreen() {
    gamestate = GameStateType.demoScreen;
  }

  /// Trigger the end-of-level intermission (G_CompleteLevel).
  void completeLevel() => _deferAction(GameAction.completed);

  /// Trigger the finale (e.g. end of episode 1 -> VICTORY screen).
  void triggerVictory() => _deferAction(GameAction.victory);

  // ------------------------------------------------------------------
  // Per-tic logic (G_Ticker). Called once per 35Hz tic by the GameLoop's
  // onTic, AFTER the playsim has advanced for this tic. [events] are the
  // input events drained for this tic; they are routed through G_Responder
  // here (vanilla drains them in D_ProcessEvents before G_Ticker, but the
  // ordering within a tic is equivalent for our purposes).
  // ------------------------------------------------------------------
  void ticker(List<DoomEvent> events) {
    // 1. Drain & route input.
    for (final DoomEvent ev in events) {
      responder(ev);
    }

    // 2. Consume any deferred action (G_DoLoadLevel / G_DoCompleted / ...).
    switch (_action) {
      case GameAction.newGame:
      case GameAction.loadLevel:
        enterLevel();
        break;
      case GameAction.completed:
        _doCompleted();
        break;
      case GameAction.worldDone:
        gamestate = GameStateType.level;
        config.onAdvanceLevel?.call();
        break;
      case GameAction.victory:
        gamestate = GameStateType.finale;
        break;
      case GameAction.nothing:
        break;
    }
    _action = GameAction.nothing;

    // 3. Tick the active state.
    menu.tick();
    switch (gamestate) {
      case GameStateType.level:
        if (!paused && !menu.active) {
          statusBar.tick(config.playerStatus);
          hud.tick();
        }
        break;
      case GameStateType.intermission:
        intermission.tick();
        break;
      case GameStateType.finale:
      case GameStateType.demoScreen:
        break;
    }

    gametic++;
  }

  void _doCompleted() {
    gamestate = GameStateType.intermission;
    final IntermissionStats stats = config.statsProvider?.call() ??
        IntermissionStats(
          episode: 0,
          lastMap: 0,
          nextMap: 1,
          killCount: 0,
          totalKills: 0,
          itemCount: 0,
          totalItems: 0,
          secretCount: 0,
          totalSecrets: 0,
          levelTimeSeconds: 0,
          parTimeSeconds: 0,
        );
    intermission.start(stats);
  }

  // ------------------------------------------------------------------
  // Input routing (G_Responder). Returns true if the event was consumed.
  // ------------------------------------------------------------------
  bool responder(DoomEvent ev) {
    // Menu has top priority while active (M_Responder).
    if (menu.active) {
      return menu.responder(ev);
    }

    // ESC opens the menu from anywhere (M_StartControlPanel).
    if (ev.type == EventType.keyDown && ev.data1 == DoomKey.escape) {
      menu.open();
      return true;
    }

    switch (gamestate) {
      case GameStateType.level:
        // Pause toggle.
        if (ev.type == EventType.keyDown && ev.data1 == DoomKey.pause) {
          paused = !paused;
          return true;
        }
        // Automap (Tab + pan/zoom) intercepts when active or on toggle.
        if (automap.responder(ev)) return true;
        // Otherwise the event would fall through to G_BuildTiccmd (owned by
        // the input/playsim agent); we report not-consumed.
        return false;
      case GameStateType.intermission:
        return intermission.responder(ev);
      case GameStateType.finale:
        // Any key advances the finale back to the demo screen.
        if (ev.type == EventType.keyDown) {
          enterDemoScreen();
          return true;
        }
        return false;
      case GameStateType.demoScreen:
        // Any key opens the menu (vanilla starts a game via the menu).
        if (ev.type == EventType.keyDown) {
          menu.open();
          return true;
        }
        return false;
    }
  }

  // ------------------------------------------------------------------
  // Per-frame draw (D_Display). Called once per rendered frame by the
  // GameLoop's onRender. Writes the full 320x200 [fb]; the caller converts it
  // to a ui.Image via the palette.
  // ------------------------------------------------------------------
  void render(Framebuffer fb) {
    switch (gamestate) {
      case GameStateType.level:
        if (automap.active) {
          automap.draw(fb, config.world);
        } else {
          // 3D scene via the injected renderer, then HUD overlays.
          config.worldView(fb);
        }
        // Status bar overlays the bottom 32 rows (always, in vanilla, when the
        // screen size shows it). HUD message line overlays the top.
        statusBar.draw(fb, config.playerStatus);
        hud.draw(fb, player: config.playerStatus);
        if (paused) _drawPause(fb);
        break;
      case GameStateType.intermission:
        intermission.draw(fb);
        break;
      case GameStateType.finale:
        _drawFinale(fb);
        break;
      case GameStateType.demoScreen:
        _drawTitle(fb);
        break;
    }

    // The menu draws on top of everything (M_Drawer after D_Display states).
    if (menu.active) menu.draw(fb);
  }

  void _drawTitle(Framebuffer fb) {
    if (_gc.has('TITLEPIC')) {
      _gc.draw(fb, 'TITLEPIC', 0, 0);
    } else {
      fb.clear(0);
    }
  }

  void _drawFinale(Framebuffer fb) {
    // Shareware end-of-episode-1 uses the HELP/CREDIT style text screen; we
    // show CREDIT as a placeholder finale background.
    if (_gc.has('CREDIT')) {
      _gc.draw(fb, 'CREDIT', 0, 0);
    } else {
      fb.clear(0);
    }
  }

  void _drawPause(Framebuffer fb) {
    final Patch? p = _gc.patch('M_PAUSE');
    if (p != null) {
      p.draw(fb, (kScreenWidth - p.width) ~/ 2, 4);
    }
  }
}
