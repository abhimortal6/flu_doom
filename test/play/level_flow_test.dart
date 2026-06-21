// Level-completion flow test: E1M1 -> intermission -> E1M2, with the player's
// weapons/ammo carried and keys cleared across the transition.
//
// This exercises the full wiring used by doom_game.dart:
//   PlaySim (E1M1) + LevelFlow + GameState, with the exit hooks routed through
//   G_ExitLevel -> ga_completed -> intermission -> ga_worlddone -> load E1M2.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/state/game_state.dart';
import 'package:flu_doom/game/state/level_flow.dart';
import 'package:flu_doom/game/integration/player_status_adapter.dart';
import 'package:flu_doom/game/world/world.dart';

WadFile loadWad() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  return WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
}

/// Build the same integration graph doom_game.dart wires, minus the renderer
/// (the worldView hook is a no-op for this behaviour test).
({PlaySim sim, GameState gs, LevelFlow flow}) buildGame(WadFile wad) {
  final PlaySim sim = PlaySim(World.fromWad(wad));
  sim.spawnLevel();

  final LevelFlow flow = LevelFlow(
    sim: sim,
    mapExists: (String name) => wad.lumpNumForName(name) >= 0,
  );

  late final GameState gs;
  gs = GameState(GameStateConfig(
    wad: wad,
    world: sim.world,
    playerStatus: PlayerStatusAdapter(sim.player),
    worldView: (Framebuffer fb) {},
    statsProvider: () => flow.buildStats(),
    onAdvanceLevel: () {
      final String? loaded = flow.worldDone();
      if (loaded == null) gs.triggerVictory();
    },
  ));
  sim.onExitLevel = () {
    flow.exitLevel();
    gs.completeLevel();
  };
  sim.onSecretExitLevel = () {
    flow.secretExitLevel();
    gs.completeLevel();
  };
  gs.enterLevel();
  return (sim: sim, gs: gs, flow: flow);
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  group('Level completion flow — E1M1 -> E1M2', () {
    test('exit -> intermission with stats; advance -> E1M2 carrying inventory',
        () {
      final WadFile wad = loadWad();
      final game = buildGame(wad);
      final PlaySim sim = game.sim;
      final GameState gs = game.gs;

      expect(sim.world.level.name, 'E1M1');
      expect(gs.gamestate, GameStateType.level);

      // Give the player some carried inventory: a shotgun + extra shells, and
      // a (red) key card that must be cleared on the new level.
      sim.player.weaponOwned[Wp.shotgun] = 1;
      sim.player.readyWeapon = Wp.shotgun;
      sim.player.ammo[Am.shell] = 17;
      sim.player.backpack = true;
      sim.player.cards[0] = true; // a key card

      // Sanity: the finished level has real intermission totals (E1M1 has
      // monsters + items on medium skill).
      expect(sim.totalKills, greaterThan(0));
      expect(sim.totalItems, greaterThan(0));

      // Run a few tics so leveltime is non-zero (the intermission Time stat).
      for (int i = 0; i < 70; i++) {
        sim.tic();
      }
      final int finishTics = sim.levelTime;

      // TRIGGER THE EXIT via the wired play-sim hook (switch special 11 path).
      sim.onExitLevel!.call();

      // GameState consumes the deferred ga_completed on the next ticker.
      gs.ticker(const <DoomEvent>[]);
      expect(gs.gamestate, GameStateType.intermission);

      // Stats reflect the REAL finished level + player.
      final stats = game.flow.buildStats();
      expect(stats.episode, 0);
      expect(stats.lastMap, 0); // E1M1
      expect(stats.nextMap, 1); // E1M2
      expect(stats.totalKills, sim.totalKills);
      expect(stats.totalItems, sim.totalItems);
      expect(stats.killCount, sim.player.killCount);
      expect(stats.levelTimeSeconds, finishTics ~/ kTicRate);
      expect(stats.parTimeSeconds, 30); // E1M1 par = 30s

      // Advance through the intermission: snap the count-up, then accept.
      final accept = const DoomEvent.keyDown(DoomKey.enter);
      gs.ticker(<DoomEvent>[accept]); // snap to final
      gs.ticker(<DoomEvent>[accept]); // accept -> ga_worlddone (deferred)
      gs.ticker(const <DoomEvent>[]); // consume ga_worlddone -> load E1M2

      // New map loaded + back in GS_LEVEL.
      expect(gs.gamestate, GameStateType.level);
      expect(sim.world.level.name, 'E1M2');
      expect(game.flow.map, 2);

      // Player re-spawned at E1M2's start with a valid mobj + full health.
      expect(sim.player.mo, isNotNull);
      expect(sim.player.mo!.removed, false);
      expect(sim.player.health, 100);

      // CARRIED: shotgun + shells + backpack + ready weapon persist.
      expect(sim.player.weaponOwned[Wp.shotgun], 1);
      expect(sim.player.ammo[Am.shell], 17);
      expect(sim.player.backpack, true);
      expect(sim.player.readyWeapon, Wp.shotgun);

      // CLEARED: keys + powers wiped on the new level (G_PlayerFinishLevel).
      expect(sim.player.cards.every((bool c) => !c), true);
      expect(sim.player.powers.every((int p) => p == 0), true);

      // The new level has its own intermission totals (recomputed by spawn).
      expect(sim.totalKills, greaterThan(0));

      // No exception advancing the new level a few tics.
      expect(() {
        for (int i = 0; i < 35; i++) {
          sim.tic();
        }
      }, returnsNormally);
    });

    test('episode-1 next-map table: secret exit + E1M9 return + E1M8 finale',
        () {
      final WadFile wad = loadWad();
      final game = buildGame(wad);
      final LevelFlow flow = game.flow;

      // Normal exit from E1M1 -> E1M2 (0-based next == 1).
      flow.exitLevel();
      expect(flow.computeNext(), 1);

      // Secret exit from any map -> E1M9 (0-based 8).
      flow.secretExitLevel();
      expect(flow.computeNext(), 8);

      // Returning from the secret level E1M9 -> E1M4 (0-based 3).
      flow.map = 9;
      flow.exitLevel();
      expect(flow.computeNext(), 3);

      // E1M8 normal exit -> episode complete (finale).
      flow.map = 8;
      flow.exitLevel();
      final stats = flow.buildStats();
      expect(flow.episodeComplete, true);
      expect(flow.computeNext(), -1);
      expect(stats.parTimeSeconds, 30); // E1M8 par = 30s
      expect(flow.worldDone(), isNull); // -> finale, no map load
    });
  });
}
