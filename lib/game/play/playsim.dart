// Top-level play simulation: the single object integration drives each tic.
//
// Ties together the thinker list, mobj/player simulation, movement/collision,
// the moving-sector (door/plat/floor/light) thinkers and the ticcmd builder.
//
// Integration entrypoints:
//   - PlaySim(world)            : construct against a loaded World.
//   - spawnLevel()              : P_SetupLevel-equivalent: spawn things + the
//                                 player, attach sector specials, set viewpoint.
//   - buildTiccmd(keys)         : fill world.cmd from KeyState (G_BuildTiccmd).
//   - tic([cmd])                : advance one 35Hz tic (G_Ticker -> P_Ticker),
//                                 applying world.cmd (or the supplied cmd) and
//                                 updating world.viewpoint for the renderer.
//   - spriteSource              : drawable mobjs for the renderer.
//
// Read/mutate boundary: this class is the sole writer of world.viewpoint and
// the dynamic Level fields (per CONTRACTS_WORLD.md).

import '../../engine/math/fixed.dart';
import '../world/ticcmd.dart';
import '../world/world.dart';
import 'actions.dart';
import 'g_build.dart';
import 'p_random.dart';
import 'mobj.dart';
import 'p_doors.dart';
import 'p_lights.dart';
import 'p_map.dart';
import 'p_mobj.dart';
import 'p_user.dart';
import 'player.dart';
import 'spawn.dart';
import 'sprite_source.dart';
import 'thinker.dart';

/// The play simulation for one game on one [World].
class PlaySim {
  PlaySim(this.world, {this.skill = Skill.medium}) {
    // Register a log-once no-op stub for every A_* name in the info.c tables so
    // the full vanilla state machine runs before the combat wave lands. Real
    // implementations REPLACE these via ActionRegistry.register (idempotent).
    ActionRegistry.instance.registerAllStubs();
    thinkers = ThinkerList();
    move = MapMove(world.level);
    mobjSim = MobjSim(move, thinkers);
    playerSim = PlayerSim(mobjSim);
    spawner = Spawner(mobjSim);
    doors = DoorManager(world.level, move, thinkers);
    lights = LightManager(world.level, thinkers);
    spriteSource = PlaySpriteSource(thinkers);
    // Wire the player's "use" action to the door manager.
    playerSim.onUse = (Player p) => doors.useLines(p);
  }

  final World world;
  final Skill skill;

  late final ThinkerList thinkers;
  late final MapMove move;
  late final MobjSim mobjSim;
  late final PlayerSim playerSim;
  late final Spawner spawner;
  late final DoorManager doors;
  late final LightManager lights;
  late final PlaySpriteSource spriteSource;

  /// Player 1, valid after [spawnLevel].
  final Player player = Player();

  /// Level time in tics (vanilla `leveltime`).
  int levelTime = 0;

  final TicCmdBuilder _cmdBuilder = TicCmdBuilder();

  /// P_SetupLevel (playsim portion): spawn all map things, attach sector
  /// light specials, spawn player 1 at its start, and prime the viewpoint.
  void spawnLevel() {
    thinkers.clear();
    levelTime = 0;
    // M_ClearRandom: reset the shared gameplay rng at level start (vanilla).
    clearRandom();

    // 1) Spawn / record every map thing.
    for (final dynamic mt in world.level.things) {
      spawner.spawnMapThing(mt, skill: skill);
    }

    // 2) Spawn player 1 at the recorded start (DoomEd type 1).
    final start = spawner.playerStarts[0];
    if (start == null) {
      throw StateError('No player-1 start in ${world.level.name}');
    }
    spawner.spawnPlayer(start, player);

    // 3) Attach sector light specials so the world is alive.
    lights.spawnSpecials();

    // 4) Prime the viewpoint from the player so the renderer has a camera.
    playerSim.calcHeight(player);
    _writeViewpoint();
  }

  /// G_BuildTiccmd: fill [world.cmd] from the current [keys]. Returns the cmd.
  TicCmd buildTiccmd(KeyState keys) {
    _cmdBuilder.build(world.cmd, keys);
    return world.cmd;
  }

  /// Advance the simulation one tic. If [cmd] is null, consumes [world.cmd].
  /// Mirrors G_Ticker -> P_Ticker: copy the command into the player, run the
  /// player think, then all thinkers (mobjs + movers + lights), then refresh
  /// the viewpoint.
  void tic([TicCmd? cmd]) {
    final TicCmd source = cmd ?? world.cmd;
    player.cmd.copyFrom(source);

    // Player think first (vanilla P_PlayerThink is called from P_MobjThinker's
    // path via the player mobj, but ordering relative to other thinkers does
    // not matter for the single-player movement we simulate here).
    if (player.mo != null && !player.mo!.removed) {
      playerSim.advanceTime();
      playerSim.playerThink(player);
    }

    // Run every thinker (mobjs, doors, plats, floors, lights).
    thinkers.runThinkers();

    levelTime++;
    _writeViewpoint();
  }

  /// Copy the player mobj's position + view height into world.viewpoint.
  /// Vanilla R_SetupFrame.
  void _writeViewpoint() {
    final Mobj? mo = player.mo;
    if (mo == null) return;
    world.viewpoint.set(
      x: mo.x,
      y: mo.y,
      z: player.viewZ != 0 ? player.viewZ : toInt32(mo.z + player.viewHeight),
      angle: mo.angle,
    );
  }
}
