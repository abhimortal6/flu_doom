// Top-level play simulation: the single object integration drives each tic.
//
// Ties together the thinker list, mobj/player simulation, movement/collision,
// the moving-sector (door/plat/floor/light) thinkers and the ticcmd builder.
//
// Integration entrypoints:
//   - PlaySim(world)            : construct against a loaded World.
//   - spawnLevel()              : P_SetupLevel-equivalent: spawn things + the
//                                 player, attach sector specials, set viewpoint.
//   - loadLevel(mapName)        : G_DoLoadLevel-equivalent: load a new map into
//                                 the shared World, rebuild every level-dependent
//                                 subsystem, then re-spawn the SAME player so its
//                                 inventory carries (G_PlayerFinishLevel), and
//                                 prime the viewpoint.
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
import 'p_switch.dart';
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
  PlaySim(this.world, {this.skill = Skill.medium, SoundHook? sound})
      : _injectedSound = sound ?? const NullSoundHook() {
    _buildSubsystems();
  }

  final World world;
  Skill skill;

  /// The SoundHook injected at construction (defaults to [NullSoundHook] so
  /// tests stay headless). Stored so [_buildSubsystems] re-wires it on every
  /// level change.
  final SoundHook _injectedSound;

  // Level-dependent subsystems. These are rebuilt by [_buildSubsystems] both at
  // construction and after a [loadLevel] (G_DoLoadLevel), because they hold a
  // reference to the specific [world.level] / thinker list of the active map.
  late ThinkerList thinkers;
  late MapMove move;
  late MobjSim mobjSim;
  late PlayerSim playerSim;
  late Spawner spawner;
  late DoorManager doors;
  late SwitchManager switches;
  late LightManager lights;
  late PlaySpriteSource spriteSource;

  // --- Combat subsystems (COMBAT-D). ---
  late SoundHook sound;
  late Interactions interactions;
  late Sight sight;
  late Shoot shoot;
  late EnemyAi enemyAi;
  late Pspr pspr;

  /// Player 1. This instance PERSISTS across [loadLevel] so its inventory
  /// (weapons/ammo/backpack) carries between maps (vanilla keeps players[] and
  /// only applies G_PlayerFinishLevel on the old map + a partial reset on load).
  final Player player = Player();

  /// Level time in tics (vanilla `leveltime`).
  int levelTime = 0;

  /// Level-exit hooks (vanilla G_ExitLevel / G_SecretExitLevel). The integration
  /// layer (LevelFlow) wires these to defer `ga_completed`. Until wired they are
  /// safe no-ops so the play-sim never crashes on a stand-alone playtest.
  void Function()? onExitLevel;
  void Function()? onSecretExitLevel;

  final TicCmdBuilder _cmdBuilder = TicCmdBuilder();

  // -------------------------------------------------------------------------
  // Build (or rebuild, after a level change) every level-dependent subsystem
  // and re-wire the play-sim hooks. The [player] instance and [onExitLevel] /
  // [onSecretExitLevel] hooks are NOT touched here — they survive a level
  // change (G_DoLoadLevel rebuilds the map, not the player or the game flow).
  // -------------------------------------------------------------------------
  void _buildSubsystems() {
    thinkers = ThinkerList();
    move = MapMove(world.level);
    mobjSim = MobjSim(move, thinkers);
    playerSim = PlayerSim(mobjSim);
    spawner = Spawner(mobjSim);
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

    sound = _injectedSound;
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

    // Switch textures/buttons + the door/use manager. DoorManager needs the
    // shared P_PathTraverse from [shoot], so it is built after [shoot]/[sound].
    switches = SwitchManager(world.textures, sound);
    doors = DoorManager(world.level, move, thinkers, shoot, switches, sound);

    // Register the real combat A_* bodies, then fill the rest with stubs.
    // (putIfAbsent semantics: re-registering after a level change is a no-op.)
    final ActionRegistry reg = ActionRegistry.instance;
    registerEnemyActions(reg, enemyAi, shoot, interactions);
    registerWeaponActions(reg, pspr, shoot);
    reg.registerAllStubs();

    _wireHooks();
  }

  /// Wire the play-sim hooks that drive combat + specials from the world layer.
  void _wireHooks() {
    // Player "use" action -> door manager.
    playerSim.onUse = (Player p) => doors.useLines(p);

    // PICKUPS: walking the player (or any MF_PICKUP mobj) over a special mobj
    // calls P_TouchSpecialThing (p_inter.c) via the collision hook.
    move.onTouchSpecial =
        (Mobj special, Mobj toucher) =>
            interactions.touchSpecialThing(special, toucher);

    // Drive weapon firing + weapon-change from the player think path.
    playerSim.pspr = pspr;
    // Wake monsters when the player fires (vanilla P_FireWeapon noise alert).
    playerSim.onPlayerFire = (Player p) => enemyAi.noiseAlert(p.mo!, p.mo!);

    // MONSTER door-opening: P_UseSpecialLine for monsters -> the door manager.
    enemyAi.useSpecialLine = (Mobj actor, Line line, int side) =>
        doors.useSpecialLine(actor, line, side);

    // Teleport relocation for A_PainShootSkull / lost-soul spawn.
    enemyAi.teleportMove = (Mobj thing, fixed_t x, fixed_t y) {
      move.tryMove(thing, x, y);
    };

    // -------------------------------------------------------------------
    // LEVEL EXIT (g_game.c G_ExitLevel / G_SecretExitLevel): the switch / line
    // / boss specials route through here. The integration LevelFlow installs
    // [onExitLevel] / [onSecretExitLevel] (deferring ga_completed); the play-sim
    // simply forwards to them so the map-change machinery lives one layer up.
    // -------------------------------------------------------------------
    void exit() => onExitLevel?.call();
    void secretExit() => (onSecretExitLevel ?? onExitLevel)?.call();
    enemyAi.exitLevel = exit; // boss-triggered exit (A_BossDeath etc.)
    doors.exitLevel = exit; // switch special 11 + walk-over exit lines
    doors.secretExitLevel = secretExit; // switch special 51

    // Boss / keen specials beyond a plain exit: no-ops (no E1M8 boss flow yet).
    enemyAi.bossDeathTrigger = (Mobj boss) {};
    enemyAi.keenDieTrigger = () {};
  }

  /// P_SetupLevel (playsim portion): spawn all map things, attach sector
  /// light specials, spawn player 1 at its start, and prime the viewpoint.
  ///
  /// [reborn] applies the full G_PlayerReborn starting loadout (the boot / new
  /// game case). When false (a level change) [spawnPlayer] still re-arms the
  /// psprites but the caller is responsible for preserving the inventory (see
  /// [loadLevel] -> G_PlayerFinishLevel).
  void spawnLevel() {
    thinkers.clear();
    levelTime = 0;
    spawner.reset();
    // M_ClearRandom: reset the shared gameplay rng at level start (vanilla).
    clearRandom();

    // 1) Spawn / record every map thing (also accumulates the intermission
    //    totals: totalkills / totalitems).
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

  /// G_DoLoadLevel: load [mapName] into the shared [World], rebuild every
  /// level-dependent subsystem against the new geometry, then re-spawn the
  /// SAME [player] so its inventory carries to the new map.
  ///
  /// Inventory carry semantics (vanilla): the OLD level already had
  /// G_PlayerFinishLevel applied (powers/cards cleared) before the intermission;
  /// G_DoLoadLevel only re-spawns the player mobj. To keep this one clean
  /// operation we snapshot the carried inventory here, re-spawn (which resets
  /// the player to the reborn loadout), then restore the carried fields and
  /// apply G_PlayerFinishLevel (clear keys/powers/tints) — matching the net
  /// vanilla result: weapons + ammo + backpack persist, keys + powers do not.
  void loadLevel(String mapName) {
    // Snapshot the inventory that must survive the map change.
    final List<int> savedAmmo = List<int>.of(player.ammo);
    final List<int> savedMaxAmmo = List<int>.of(player.maxAmmo);
    final List<int> savedWeaponOwned = List<int>.of(player.weaponOwned);
    final bool savedBackpack = player.backpack;
    final int savedReadyWeapon = player.readyWeapon;
    final int savedKillCount = player.killCount;
    final int savedItemCount = player.itemCount;
    final int savedSecretCount = player.secretCount;

    // Load the new map into the shared world (reuses the texture tables). The
    // renderer + adapters read world.level / sim.* live, so swapping here +
    // rebuilding the subsystems re-points everything at the new map.
    world.changeLevel(mapName);
    _buildSubsystems();

    // spawnLevel re-spawns the player via the reborn loadout (and rebuilds the
    // intermission totals for the NEW map).
    spawnLevel();

    // Restore the carried inventory over the reborn defaults.
    for (int i = 0; i < savedAmmo.length; i++) {
      player.ammo[i] = savedAmmo[i];
    }
    for (int i = 0; i < savedMaxAmmo.length; i++) {
      player.maxAmmo[i] = savedMaxAmmo[i];
    }
    for (int i = 0; i < savedWeaponOwned.length; i++) {
      player.weaponOwned[i] = savedWeaponOwned[i];
    }
    player.backpack = savedBackpack;
    player.readyWeapon = savedReadyWeapon;
    player.pendingWeapon = savedReadyWeapon;
    // Counters persist across the reborn in vanilla G_PlayerReborn; the new
    // map's stats start from these (intermission shows per-level deltas, but we
    // keep the vanilla carry for fidelity — they are zero at boot).
    player.killCount = savedKillCount;
    player.itemCount = savedItemCount;
    player.secretCount = savedSecretCount;

    // G_PlayerFinishLevel (applied to the FINISHED level in vanilla; the net
    // effect on entering the new map is keys + powers cleared, no tints):
    for (int i = 0; i < player.cards.length; i++) {
      player.cards[i] = false;
    }
    for (int i = 0; i < player.powers.length; i++) {
      player.powers[i] = 0;
    }
    player.extraLight = 0;
    player.fixedColormap = 0;
    player.damageCount = 0;
    player.bonusCount = 0;

    // Re-arm the psprite for the carried ready weapon (P_BringUpWeapon picks up
    // the restored readyWeapon rather than the reborn pistol).
    pspr.setupPsprites(player);
    _writeViewpoint();
  }

  /// Intermission totals for the CURRENTLY loaded level (vanilla totalkills /
  /// totalitems / totalsecret). Read when building the wbstartstruct.
  int get totalKills => spawner.totalKills;
  int get totalItems => spawner.totalItems;
  int get totalSecret => spawner.totalSecret;

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

    // P_UpdateSpecials (button countdown portion): revert pressed switch
    // textures after BUTTONTIME. The rest of P_UpdateSpecials (flat/texture
    // animation, scrollers, level timer) is out of scope for the playsim tic.
    switches.tickButtons();

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
