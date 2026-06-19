// Play-simulation tests: load the real shareware E1M1, spawn things + the
// player, drive the player with a synthetic ticcmd and verify movement +
// collision, run the thinker list, and open a door via the door manager.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/game/world/world.dart';

import 'package:flu_doom/game/play/g_build.dart';
import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/player.dart';
import 'package:flu_doom/game/play/playsim.dart';

World loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

void main() {
  group('PlaySim — E1M1', () {
    late World world;
    late PlaySim sim;

    setUp(() {
      world = loadWorld();
      sim = PlaySim(world);
      sim.spawnLevel();
    });

    test('player 1 spawns at the player-1 start with correct sector/floorz',
        () {
      final Mobj mo = sim.player.mo!;
      // Start thing is at (1056, -3616) in whole units.
      expect(fixedToInt(mo.x), 1056);
      expect(fixedToInt(mo.y), -3616);
      // Angle 90 degrees -> ANG90.
      expect(mo.angle, kAng90);
      // Stands on its sector floor.
      final Sector sec = mo.subsectorSector!;
      expect(mo.z, sec.floorHeight);
      expect(mo.floorZ, sec.floorHeight);
      // Player health from mobjinfo.
      expect(mo.health, 100);
      expect(sim.player.playerState, PlayerState.live);
      // Viewpoint primed.
      expect(world.viewpoint.x, mo.x);
      expect(world.viewpoint.y, mo.y);
      expect(world.viewpoint.angle, mo.angle);
    });

    test('spawnMapThing populated the thinker list (mobjs spawned)', () {
      // Player + at least a handful of monsters/items.
      expect(sim.thinkers.count, greaterThan(5));
      // The sprite source exposes only the mobjs (not the light/door
      // thinkers), so it is <= the total thinker count but still > 5.
      final int mobjCount = sim.spriteSource.sprites.length;
      expect(mobjCount, greaterThan(5));
      expect(mobjCount, lessThanOrEqualTo(sim.thinkers.count));
    });

    test('forward ticcmd advances the player, wall stops it', () {
      final Mobj mo = sim.player.mo!;
      final fixed_t startX = mo.x;
      final fixed_t startY = mo.y;

      final TicCmd cmd = TicCmd()..forwardMove = 50; // run-speed forward

      // Run enough tics to slam into the far wall of the start room.
      for (int i = 0; i < 200; i++) {
        sim.tic(cmd);
      }

      final fixed_t movedX = (mo.x - startX).abs();
      final fixed_t movedY = (mo.y - startY).abs();
      // The player faces +Y (angle 90), so Y should change substantially.
      expect(movedY, greaterThan(64 * kFracUnit),
          reason: 'player should have advanced forward');

      // It must NOT have tunnelled out of the map: stays in a real sector and
      // its position is finite / within the level bounding extent.
      expect(mo.subsectorSector, isNotNull);

      // Record the wall-stopped position, then keep pushing: it should not
      // continue advancing without bound (collision holds it).
      final fixed_t afterY = mo.y;
      for (int i = 0; i < 100; i++) {
        sim.tic(cmd);
      }
      final fixed_t extra = (mo.y - afterY).abs();
      expect(extra, lessThan(64 * kFracUnit),
          reason: 'player should be blocked by a wall, not keep moving freely');

      // sanity: x drift small since we only moved along facing.
      expect(movedX, lessThan(movedY));
    });

    test('thinker list runs many tics without error', () {
      final TicCmd cmd = TicCmd();
      for (int i = 0; i < 70; i++) {
        sim.tic(cmd);
      }
      expect(sim.levelTime, 70);
      // Every live mobj still has a valid sector link.
      for (final s in sim.spriteSource.sprites) {
        expect(s.sector, isNotNull);
      }
    });

    test('opening a door line raises its sector ceiling', () {
      // Line index 151 carries manual door special 1 in shareware E1M1.
      final Line door = world.level.lines[151];
      expect(door.special, 1);
      expect(door.backSector, isNotNull);
      final Sector sec = door.backSector!;
      final fixed_t startCeil = sec.ceilingHeight;

      // Activate via the door manager (EV_VerticalDoor) and tick it.
      final bool opened = sim.doors.evVerticalDoor(door);
      expect(opened, isTrue);
      expect(sec.specialData, isNotNull);

      final TicCmd cmd = TicCmd();
      for (int i = 0; i < 35; i++) {
        sim.tic(cmd);
      }
      expect(sec.ceilingHeight, greaterThan(startCeil),
          reason: 'door ceiling should rise as it opens');
    });

    test('P_UseLines runs without error and returns a bool', () {
      // Smoke test: pressing use shouldn't throw even if nothing is in reach.
      final bool used = sim.doors.useLines(sim.player);
      expect(used, anyOf(isTrue, isFalse));
    });
  });

  group('TicCmd builder (G_BuildTiccmd)', () {
    test('forward + run produces run-speed forwardmove', () {
      final TicCmdBuilder b = TicCmdBuilder();
      final TicCmd cmd = TicCmd();
      final KeyState keys = KeyState()
        ..forward = true
        ..run = true;
      b.build(cmd, keys);
      expect(cmd.forwardMove, 0x32); // run forwardmove
      expect(cmd.sideMove, 0);
      expect(cmd.angleTurn, 0);
    });

    test('turn keys produce angleturn; strafe modifier turns them to sidemove',
        () {
      final TicCmdBuilder b = TicCmdBuilder();
      final TicCmd cmd = TicCmd();
      b.build(cmd, KeyState()..turnLeft = true);
      expect(cmd.angleTurn, greaterThan(0));

      final TicCmd cmd2 = TicCmd();
      b.build(
          cmd2,
          KeyState()
            ..turnRight = true
            ..strafeModifier = true);
      expect(cmd2.sideMove, greaterThan(0));
      expect(cmd2.angleTurn, 0);
    });

    test('weapon slot sets change-weapon button bits', () {
      final TicCmdBuilder b = TicCmdBuilder();
      final TicCmd cmd = TicCmd();
      b.build(cmd, KeyState()..weapon = 3);
      expect(cmd.buttons & btChangeWeapon, btChangeWeapon);
      expect((cmd.buttons & btWeaponMask) >> btWeaponShift, 2); // slot 3 -> 2
    });

    test('use + attack set their buttons', () {
      final TicCmdBuilder b = TicCmdBuilder();
      final TicCmd cmd = TicCmd();
      b.build(
          cmd,
          KeyState()
            ..use = true
            ..attack = true);
      expect(cmd.buttons & btUse, btUse);
      expect(cmd.buttons & btAttack, btAttack);
    });
  });

  group('info tables', () {
    test('every placeable E1M1 DoomEd number resolves to a mobjtype', () {
      const List<int> e1m1Types = <int>[
        3004, 9, 3001, 2035, 2018, 2019, 2014, 2015, 5, 13, 6,
        2011, 2012, 2007, 2048, 2008, 8, 2001, 2003, 35, 10, 12, 15, 24, 2049,
      ];
      for (final int t in e1m1Types) {
        expect(doomedToMobjType.containsKey(t), isTrue,
            reason: 'DoomEd $t should map to a mobjtype');
      }
    });

    test('player + effect states are present and self-consistent', () {
      // S_PLAY (149) is the player idle state; vanilla info.c sets its
      // nextstate to S_NULL (0) — it stays forever (tics == -1).
      expect(states[149].nextState, 0);
      expect(states[149].tics, -1);
      // Full vanilla states[] table (NUMSTATES == 967).
      expect(states.length, 967);
    });
  });
}
