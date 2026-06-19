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
import '../world/defs.dart' show Line;
import '../world/ticcmd.dart';
import '../world/world.dart';
import 'actions.dart';
import 'g_build.dart';
import 'p_random.dart';
import 'mobj.dart';
import 'p_doors.dart';
import 'p_enemy.dart';
import 'p_inter.dart';
import 'p_lights.dart';
import 'p_map.dart';
import 'p_mobj.dart';
import 'p_pspr.dart';
import 'p_shoot.dart';
import 'p_sight.dart';
import 'p_user.dart';
import 'player.dart';
import 'sound_hook.dart';
import 'spawn.dart';
import 'sprite_source.dart';
import 'thinker.dart';

/// The play simulation for one game on one [World].
class PlaySim {
  PlaySim(this.world, {this.skill = Skill.medium}) {
    thinkers = ThinkerList();
    move = MapMove(world.level);
    mobjSim = MobjSim(move, thinkers);
    playerSim = PlayerSim(mobjSim);
    spawner = Spawner(mobjSim);
    doors = DoorManager(world.level, move, thinkers);
    lights = LightManager(world.level, thinkers);
    spriteSource = PlaySpriteSource(thinkers);

    // -------------------------------------------------------------------
    // COMBAT-D: construct + inject the combat subsystems.
    //
    // Construction order mirrors the dependency graph: SoundHook (leaf) ->
    // Interactions -> Sight -> Shoot (needs Interactions) -> EnemyAi (needs
    // all of the above) -> Pspr (needs Shoot). Then the A_* action bodies are
    // registered BEFORE registerAllStubs() (the stubs use putIfAbsent, so the
    // real bodies must already be present to win).
    // -------------------------------------------------------------------
    final int skyFlat = world.textures.checkFlatNumForName('F_SKY1');

    sound = const NullSoundHook();
    interactions = Interactions(mobjSim, sound);
    sight = Sight(world.level);
    shoot = Shoot(move, mobjSim, interactions, sound)
      ..checkSight = sight.checkSight
      ..skyFlatNum = skyFlat;
    enemyAi = EnemyAi(mobjSim, move, sight, shoot, interactions, sound)
      ..level = world.level
      // Shareware Doom (episode 1): not the DOOM II commercial gamemode.
      ..commercial = false
      // Player table for P_LookForPlayers; filled in spawnLevel once the
      // player mobj exists.
      ..players = <Player>[player]
      ..playerInGame = <bool>[true];
    pspr = Pspr(mobjSim, shoot, sound)..gameMode = GameMode.shareware;

    // Register the real combat A_* bodies, then fill the rest with stubs.
    final ActionRegistry reg = ActionRegistry.instance;
    registerEnemyActions(reg, enemyAi, shoot, interactions);
    registerWeaponActions(reg, pspr, shoot);
    reg.registerAllStubs();

    // -------------------------------------------------------------------
    // Wire the play-sim hooks that drive combat from the world layer.
    // -------------------------------------------------------------------
    // Player "use" action -> door manager (unchanged).
    playerSim.onUse = (Player p) => doors.useLines(p);

    // PICKUPS: walking the player (or any MF_PICKUP mobj) over a special mobj
    // calls P_TouchSpecialThing (p_inter.c) via the collision hook.
    move.onTouchSpecial =
        (Mobj special, Mobj toucher) =>
            interactions.touchSpecialThing(special, toucher);

    // Drive weapon firing + weapon-change from the player think path.
    playerSim.pspr = pspr;
    // Optionally wake monsters when the player fires (vanilla P_FireWeapon
    // calls P_NoiseAlert(player->mo, player->mo); COMBAT-B deferred it).
    playerSim.onPlayerFire =
        (Player p) => enemyAi.noiseAlert(p.mo!, p.mo!);

    // MONSTER door-opening: P_UseSpecialLine for monsters -> the door manager.
    enemyAi.useSpecialLine = (Mobj actor, Line line, int side) =>
        doors.useSpecialLine(line, actor.player as Player?);

    // Teleport relocation for A_PainShootSkull / lost-soul spawn (P_TeleportMove
    // -> P_TryMove without the dropoff/blocking re-link). Use the plain move.
    enemyAi.teleportMove = (Mobj thing, fixed_t x, fixed_t y) {
      move.tryMove(thing, x, y);
    };

    // Level-exit / boss / keen specials: no game-state level-transition system
    // exists yet for the shareware E1M1 playtest (out of scope per the wiring
    // brief). Leave safe no-ops so the AI never crashes if it fires them.
    enemyAi.exitLevel = () {};
    enemyAi.bossDeathTrigger = (Mobj boss) {};
    enemyAi.keenDieTrigger = () {};
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

  // --- Combat subsystems (COMBAT-D). ---
  late final SoundHook sound;
  late final Interactions interactions;
  late final Sight sight;
  late final Shoot shoot;
  late final EnemyAi enemyAi;
  late final Pspr pspr;

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

    // 2) Spawn player 1 at the recorded start (DoomEd type 1). spawnPlayer
    //    applies the G_PlayerReborn loadout and P_SetupPsprites via [pspr].
    final start = spawner.playerStarts[0];
    if (start == null) {
      throw StateError('No player-1 start in ${world.level.name}');
    }
    spawner.spawnPlayer(start, player, pspr);

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

    // Per-tic global state the combat subsystems read (vanilla file-scope
    // globals: leveltime, gametic). Sight/EnemyAi/Pspr are injected, not
    // recreated, so we refresh the clocks here each tic.
    pspr.levelTime = levelTime;
    enemyAi.gametic = levelTime;

    // Player think first (vanilla P_PlayerThink is called from P_MobjThinker's
    // path via the player mobj, but ordering relative to other thinkers does
    // not matter for the single-player movement we simulate here).
    if (player.mo != null && !player.mo!.removed) {
      playerSim.advanceTime();
      playerSim.playerThink(player);
    }

    // Run every thinker (mobjs, doors, plats, floors, lights). With the real
    // A_* bodies registered, monster mobjs now think (A_Look/A_Chase/attacks)
    // and missiles/puffs/blood advance through states[].
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
