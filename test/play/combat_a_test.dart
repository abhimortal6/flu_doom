// COMBAT-A tests: enemy AI (A_Look / A_Chase / A_FaceTarget / A_TroopAttack /
// A_Explode) and line-of-sight (P_CheckSight). Built on the real shareware
// E1M1 world so the BSP / blockmap / sector links / reject are all live.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/world.dart';

import 'package:flu_doom/game/play/actions.dart';
import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/mobj_flags.dart';
import 'package:flu_doom/game/play/p_enemy.dart';
import 'package:flu_doom/game/play/p_inter.dart';
import 'package:flu_doom/game/play/p_mobj.dart';
import 'package:flu_doom/game/play/p_random.dart';
import 'package:flu_doom/game/play/p_shoot.dart';
import 'package:flu_doom/game/play/p_sight.dart';
import 'package:flu_doom/game/play/player.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/play/sound_hook.dart';

World loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

/// A SoundHook that records every sfx id it is told to play.
class RecordingSound implements SoundHook {
  final List<int> sfx = <int>[];
  @override
  void startSound(Object? origin, int sfxId) => sfx.add(sfxId);
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  late PlaySim sim;
  late MobjSim mobjSim;
  late RecordingSound sound;
  late Interactions inter;
  late Shoot shoot;
  late Sight sight;
  late EnemyAi ai;

  setUp(() {
    sim = PlaySim(loadWorld());
    sim.spawnLevel();
    mobjSim = sim.mobjSim;
    sound = RecordingSound();
    inter = Interactions(mobjSim, sound);
    shoot = Shoot(sim.move, mobjSim, inter, sound);
    sight = Sight(sim.world.level);
    shoot.checkSight = (Mobj a, Mobj b) => sight.checkSight(a, b);
    ai = EnemyAi(mobjSim, sim.move, sight, shoot, inter, sound);
    // Wire the live player table (P_LookForPlayers / A_BossDeath need it).
    ai.players = <Player>[sim.player];
    ai.playerInGame = <bool>[true];
    clearRandom();
  });

  // Spawn a fresh imp (MT_TROOP) at the player's location.
  Mobj spawnImpAtPlayer() {
    final Mobj p = sim.player.mo!;
    final Mobj imp = mobjSim.spawnMobj(p.x, p.y, p.z, Mt.troop);
    imp.target = null;
    return imp;
  }

  group('P_CheckSight', () {
    test('true when looker and target share the same spot (unobstructed)', () {
      final Mobj p = sim.player.mo!;
      final Mobj imp =
          mobjSim.spawnMobj(toInt32(p.x + 32 * kFracUnit), p.y, p.z, Mt.troop);
      expect(sight.checkSight(imp, p), true);
    });

    test('false when an opaque one-sided wall separates the two', () {
      // Place the imp far across the map; with the real reject matrix /
      // geometry there is no LOS from one end of E1M1 to the far corner.
      final Mobj p = sim.player.mo!;
      final Mobj imp = mobjSim.spawnMobj(
          toInt32(p.x + 3000 * kFracUnit),
          toInt32(p.y + 3000 * kFracUnit),
          p.z,
          Mt.troop);
      expect(sight.checkSight(imp, p), false);
    });
  });

  group('A_Look', () {
    test('acquires the player when in sight + range, enters seestate', () {
      final Mobj imp = spawnImpAtPlayer();
      // Move the imp a little away so it is in front and visible.
      imp.x = toInt32(imp.x + 64 * kFracUnit);
      imp.angle = kAng180; // facing back toward the player
      ai.aLook(imp);
      expect(imp.target, isNotNull);
      expect(identical(imp.target, sim.player.mo), true);
      // Went into its see (chase) state chain.
      expect(imp.stateIndex, isNot(imp.info.spawnState));
    });

    test('does not acquire a player that is out of sight', () {
      final Mobj imp = spawnImpAtPlayer();
      // Move the imp to a far corner with no LOS to the player start.
      imp.x = toInt32(imp.x + 3000 * kFracUnit);
      imp.y = toInt32(imp.y + 3000 * kFracUnit);
      mobjSim.move.unsetThingPosition(imp);
      mobjSim.move.setThingPosition(imp);
      imp.floorZ = imp.subsectorSector!.floorHeight;
      imp.z = imp.floorZ;
      ai.aLook(imp);
      expect(imp.target, isNull);
    });
  });

  group('A_FaceTarget / A_Chase', () {
    test('A_FaceTarget points the actor at its target', () {
      final Mobj imp = spawnImpAtPlayer();
      final Mobj p = sim.player.mo!;
      // Put the target due east of the imp.
      imp.x = toInt32(p.x - 128 * kFracUnit);
      imp.y = p.y;
      imp.target = p;
      ai.aFaceTarget(imp);
      // Due east is angle 0.
      expect(imp.angle, 0);
    });

    test('A_Chase moves the actor toward and keeps a valid target', () {
      final Mobj imp = spawnImpAtPlayer();
      final Mobj p = sim.player.mo!;
      // Place the imp some distance from the player, with a chase direction.
      imp.x = toInt32(p.x - 256 * kFracUnit);
      imp.y = p.y;
      imp.target = p;
      imp.moveCount = 0;
      imp.reactionTime = 0;

      final fixed_t startDist = (imp.x - p.x).abs();
      ai.aChase(imp);
      final fixed_t endDist = (imp.x - p.x).abs();

      // Target retained (still shootable player) and the imp picked/moved a
      // chase direction (movedir is a valid 0..7 or it newly chose one).
      expect(identical(imp.target, p), true);
      expect(imp.moveDir, isNot(diNoDir));
      // It should have closed distance (or at least attempted a move).
      expect(endDist <= startDist, true);
    });
  });

  group('A_TroopAttack', () {
    test('in melee range, deals damage and plays the claw sound', () {
      final Mobj imp = spawnImpAtPlayer();
      final Mobj p = sim.player.mo!;
      // Adjacent so checkMeleeRange + checkSight succeed.
      imp.x = toInt32(p.x - 24 * kFracUnit);
      imp.y = p.y;
      imp.target = p;
      final int before = sim.player.health;
      ai.aTroopAttack(imp);
      expect(sim.player.health < before, true, reason: 'melee dealt damage');
      expect(sound.sfx.isNotEmpty, true);
    });

    test('at range, launches an MT_TROOPSHOT missile', () {
      final Mobj imp = spawnImpAtPlayer();
      final Mobj p = sim.player.mo!;
      // Far enough that melee fails -> missile path.
      imp.x = toInt32(p.x - 512 * kFracUnit);
      imp.y = p.y;
      imp.target = p;
      ai.aTroopAttack(imp);
      // A troopshot now exists on the thinker list.
      bool found = false;
      for (final dynamic t in sim.thinkers.thinkers) {
        if (t is Mobj && t.type == Mt.troopshot) found = true;
      }
      expect(found, true, reason: 'spawned an MT_TROOPSHOT');
    });
  });

  group('A_Explode', () {
    test('radius-attack damages a nearby mobj', () {
      final Mobj p = sim.player.mo!;
      // Always-visible LOS so the falloff (not sight) is what we test.
      shoot.checkSight = (Mobj a, Mobj b) => true;

      final Mobj victim = mobjSim.spawnMobj(
          toInt32(p.x + 16 * kFracUnit), p.y, p.z, Mt.troop);
      final int hp = victim.health;

      // The barrel/missile spot.
      final Mobj spot = mobjSim.spawnMobj(p.x, p.y, p.z, Mt.troop);
      spot.flags &= ~mfShootable; // spot itself irrelevant
      spot.target = null; // A_Explode passes thingy->target as source

      ai.aExplode(spot);
      expect(victim.health < hp, true, reason: 'nearby mobj took blast damage');
    });
  });

  group('registerEnemyActions', () {
    test('registers all 52 A_* names into a fresh registry', () {
      final ActionRegistry r = ActionRegistry.instance;
      registerEnemyActions(r, ai, shoot, inter);
      // A spot-check across the set (full list is registered in the call).
      for (final String name in <String>[
        'A_Look',
        'A_Chase',
        'A_FaceTarget',
        'A_TroopAttack',
        'A_Explode',
        'A_BossDeath',
        'A_BrainSpit',
        'A_Tracer',
        'A_VileChase',
        'A_Metal',
      ]) {
        // resolve() returns a callable; registered names are not warned-stubs.
        expect(r.resolve(name), isNotNull);
      }
    });
  });
}
