// Level-completion flow: a faithful port of the level-transition machinery in
// Chocolate Doom src/doom/g_game.c (G_ExitLevel / G_SecretExitLevel /
// G_DoCompleted / G_WorldDone / G_DoWorldDone / G_DoLoadLevel), scoped to the
// single-player shareware episode-1 game (doom1.wad: E1M1..E1M8 + secret E1M9).
//
// It bridges three layers:
//   - the play-sim, which fires the exit hooks (switch special 11/51, walk-over
//     exit lines, boss death) and owns the per-level kill/item/secret totals;
//   - the game-state machine, which owns GS_LEVEL / GS_INTERMISSION and pulls
//     the IntermissionStats when a level completes; and
//   - the map-load operation (PlaySim.loadLevel), which re-points the world /
//     play-sim / renderer / adapters at the next map and carries inventory.
//
// Vanilla uses file-scope globals (gameepisode/gamemap/secretexit/wminfo) and
// the deferred gameaction queue; here episode/map/secretexit are instance
// fields, and the deferral is delegated to GameState (completeLevel / the
// onAdvanceLevel hook), so this object holds no UI/rendering state.

import '../play/playsim.dart';
import 'interfaces.dart';

/// vanilla TICRATE.
const int _ticRate = 35;

/// Doom 1 par times, vanilla `pars[episode][map]` (g_game.c). 1-based on both
/// axes; index 0 rows/cols are unused (a leading 0). Episode 1 is the only one
/// present in shareware; 2/3 are kept for fidelity (a full IWAD uses them).
const List<List<int>> _pars = <List<int>>[
  <int>[0],
  <int>[0, 30, 75, 120, 90, 165, 180, 180, 30, 165],
  <int>[0, 90, 90, 90, 120, 90, 360, 240, 30, 170],
  <int>[0, 90, 45, 90, 150, 90, 90, 165, 30, 135],
];

/// Drives E1Mx -> intermission -> E1M(x+1) for the single-player game.
class LevelFlow {
  LevelFlow({
    required this.sim,
    this.episode = 1,
    this.map = 1,
    this.mapExists,
  });

  /// The play-sim whose level is being completed / reloaded.
  final PlaySim sim;

  /// Current episode (1-based, vanilla `gameepisode`). Shareware = 1.
  int episode;

  /// Current map (1-based, vanilla `gamemap`).
  int map;

  /// Whether a given map lump (e.g. "E1M9") is present in the loaded WAD. Used
  /// to clamp the secret-level branch when the lump is absent (shareware has
  /// E1M9, but a defensive check avoids a crash on a stripped WAD). If null,
  /// all maps are assumed present.
  final bool Function(String mapName)? mapExists;

  /// vanilla `secretexit` — set by [secretExitLevel], read by [completeLevel]
  /// and [computeNext].
  bool secretExit = false;

  /// The map index (0-based, like vanilla `wminfo.next`) selected for the next
  /// level, valid after [buildStats] / [completeLevel]. -1 means "episode over"
  /// (the finale, e.g. after E1M8).
  int next = -1;

  /// True when the just-finished level was the last of the episode (E1M8) and
  /// the game should show the finale instead of loading a next map.
  bool episodeComplete = false;

  /// vanilla map-lump name for the current (episode, map).
  String get mapName => 'E${episode}M$map';

  // ------------------------------------------------------------------------
  // G_ExitLevel / G_SecretExitLevel: the play-sim exit hooks call these. They
  // only flag the secret-exit state + request completion; the deferral to the
  // intermission is GameState's job (completeLevel -> ga_completed).
  // ------------------------------------------------------------------------

  /// G_ExitLevel: a normal level exit (switch special 11 / walk-over exit line).
  void exitLevel() {
    secretExit = false;
  }

  /// G_SecretExitLevel: a secret level exit (switch special 51).
  void secretExitLevel() {
    secretExit = true;
  }

  // ------------------------------------------------------------------------
  // G_DoCompleted: compute the next map + the wbstartstruct from the REAL
  // finished level + player. Returns the IntermissionStats GameState shows.
  // ------------------------------------------------------------------------

  /// G_DoCompleted (stats portion): build the [IntermissionStats] for the
  /// finished level. Also resolves [next] / [episodeComplete] for [worldDone].
  IntermissionStats buildStats() {
    // E1M8 (the episode end) goes to the finale, not a next map.
    episodeComplete = !secretExit && map == 8;
    next = computeNext();

    final int parSeconds = _parTime(episode, map);

    return IntermissionStats(
      episode: episode - 1, // wminfo.epsd is 0-based
      lastMap: map - 1, // wminfo.last is 0-based
      nextMap: next < 0 ? map : next, // 0-based; harmless when episodeComplete
      killCount: sim.player.killCount,
      totalKills: sim.totalKills,
      itemCount: sim.player.itemCount,
      totalItems: sim.totalItems,
      secretCount: sim.player.secretCount,
      totalSecrets: sim.totalSecret,
      levelTimeSeconds: sim.levelTime ~/ _ticRate,
      parTimeSeconds: parSeconds,
    );
  }

  /// vanilla G_DoCompleted next-map selection for episode 1 (gamemode != commercial):
  ///   - secret exit              -> map 9 (0-based 8)
  ///   - returning from map 9     -> map 4 (0-based 3)  [E1M9 -> E1M4]
  ///   - otherwise                -> the next sequential map
  /// Returns a 0-based map index (like `wminfo.next`), or -1 if the episode is
  /// complete (E1M8 normal exit). Clamps the secret branch when the secret map
  /// lump is absent (shareware safety).
  int computeNext() {
    if (episodeComplete) return -1;

    if (secretExit) {
      // go to the secret level (E1M9, 0-based 8)
      const int secret = 8;
      if (mapExists != null && !mapExists!('E${episode}M${secret + 1}')) {
        // Secret map missing: fall through to the normal next map.
        return map; // (map+1)-1 == map, 0-based next sequential
      }
      return secret;
    }

    if (map == 9) {
      // returning from the secret level (episode 1 -> E1M4)
      switch (episode) {
        case 1:
          return 3; // -> E1M4
        case 2:
          return 5;
        case 3:
          return 6;
        case 4:
          return 1;
      }
    }

    // normal: the next sequential level. wminfo.next = gamemap (0-based of
    // gamemap+1), i.e. the current 1-based map IS the 0-based next.
    return map;
  }

  // ------------------------------------------------------------------------
  // G_WorldDone / G_DoWorldDone: after the intermission, load the next map.
  // ------------------------------------------------------------------------

  /// G_DoWorldDone: advance to [next], load the map into the world + play-sim,
  /// and re-spawn the player carrying inventory. Returns the loaded map name, or
  /// null if the episode is complete (caller should show the finale).
  String? worldDone() {
    if (episodeComplete || next < 0) {
      return null; // finale
    }
    // gamemap = wminfo.next + 1 (back to 1-based).
    map = next + 1;
    final String name = mapName;
    sim.loadLevel(name);
    return name;
  }

  /// Par time in SECONDS for the (1-based) episode/map, vanilla
  /// `pars[gameepisode][gamemap]`. 0 (no par) for anything out of range
  /// (e.g. the secret-level / episode-4 cases the shareware game never hits).
  int _parTime(int episode, int map) {
    if (episode < 1 || episode >= _pars.length) return 0;
    final List<int> row = _pars[episode];
    if (map < 0 || map >= row.length) return 0;
    return row[map];
  }
}

/// Re-export for callers that only need the seconds conversion.
const int kTicRate = _ticRate;
