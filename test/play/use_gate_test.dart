// Proves the ACTUAL E1M1 first gate opens through the full, faithfully-ported
// use chain.
//
// THE GATE: walking out of the E1M1 start room the first door the player
// reaches is the manual door formed by linedefs 151 & 152 (vanilla special 1,
// "DR Door Open Wait Close", tag 0 — a manual/local door, not a tagged remote).
// They are the two vertical jamb lines of a 16-unit door track running
// north-south at x=1536 / x=1552, y in [-2560,-2432]; the back sidedef faces
// into the closed door sector (floor==ceiling==0).
//
// This test positions the player flush in front of that gate at a realistic
// stance and presses Use through P_PlayerThink (BT_USE), exactly as live play,
// then asserts the gate's sector ceiling rises (the door opens). It runs the
// REAL path: ticcmd -> P_PlayerThink (BT_USE edge) -> P_UseLines (the 1:1
// PTR_UseTraverse over P_PathTraverse) -> P_UseSpecialLine -> EV_VerticalDoor.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/p_doors.dart';
import 'package:flu_doom/game/play/playsim.dart';

World _loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

void main() {
  group('E1M1 first gate (line 151/152, special 1) opens via Use', () {
    late World world;
    late PlaySim sim;

    setUp(() {
      world = _loadWorld();
      sim = PlaySim(world);
      sim.spawnLevel();
    });

    test('gate identity is the manual door special 1 at x=1536/1552', () {
      final Line l151 = world.level.lines[151];
      final Line l152 = world.level.lines[152];
      expect(l151.special, 1);
      expect(l152.special, 1);
      expect(l151.tag, 0, reason: 'manual/local door, not tagged remote');
      expect(l151.backSector, isNotNull);
      // The two jambs share the door sector on their back side.
      expect(identical(l151.backSector, l152.backSector), isTrue);
      // Closed door: ceiling == floor.
      expect(l151.backSector!.ceilingHeight, l151.backSector!.floorHeight);
    });

    test('player flush in front, facing the gate, BT_USE opens it', () {
      final Line gate = world.level.lines[151];
      final Sector sec = gate.backSector!;
      final fixed_t startCeil = sec.ceilingHeight;

      // Realistic stance: standing in the corridor just west of the door track
      // (player radius 16, so this is "flush"), facing east toward the door.
      final Mobj mo = sim.player.mo!;
      sim.move.unsetThingPosition(mo);
      mo.x = (1536 - 20) * kFracUnit; // 20 units west of the west jamb
      mo.y = -2496 * kFracUnit; // mid-height of the door track
      mo.angle = 0; // ANG0 = facing +x (east), straight at the gate
      sim.move.setThingPosition(mo);

      // Vanilla G_PlayerReborn spawns with usedown=true; one release tic clears
      // the edge latch, exactly as the live app does before the first press.
      sim.tic(TicCmd());
      expect(sim.player.useDown, isFalse);

      // Hold Use: the BT_USE edge fires P_UseLines -> EV_VerticalDoor; the door
      // thinker raises the ceiling over the following tics.
      final TicCmd use = TicCmd()..buttons = btUse;
      for (int i = 0; i < 35; i++) {
        sim.tic(use);
      }

      expect(sec.specialData, isA<VerticalDoor>(),
          reason: 'a VerticalDoor thinker must be attached to the gate sector');
      expect(sec.ceilingHeight, greaterThan(startCeil),
          reason: 'pressing Use on the first gate must raise its ceiling');
    });

    test('approached from the east (line 152 front) the gate also opens', () {
      final Sector sec = world.level.lines[152].backSector!;
      final fixed_t startCeil = sec.ceilingHeight;

      final Mobj mo = sim.player.mo!;
      sim.move.unsetThingPosition(mo);
      mo.x = (1552 + 20) * kFracUnit; // 20 units east of the east jamb
      mo.y = -2496 * kFracUnit;
      mo.angle = kAng180; // facing -x (west), straight at the gate
      sim.move.setThingPosition(mo);

      sim.tic(TicCmd());
      final TicCmd use = TicCmd()..buttons = btUse;
      for (int i = 0; i < 35; i++) {
        sim.tic(use);
      }

      expect(sec.specialData, isA<VerticalDoor>());
      expect(sec.ceilingHeight, greaterThan(startCeil));
    });

    test('faithful PTR_UseTraverse refuses to use through a solid wall', () {
      // Place the player facing a one-sided wall (line 44, a solid wall north
      // of the start room) with no special line in front: P_UseLines must NOT
      // crash and must not move any door (no usable special in reach).
      final Mobj mo = sim.player.mo!;
      sim.move.unsetThingPosition(mo);
      mo.x = 1055 * kFracUnit;
      mo.y = -2920 * kFracUnit; // just south of the solid wall at y=-2880
      mo.angle = kAng90; // facing the wall (north)
      sim.move.setThingPosition(mo);

      sim.tic(TicCmd());
      final TicCmd use = TicCmd()..buttons = btUse;
      // Should not throw; the gate sector must remain closed.
      sim.tic(use);
      final Sector gate = world.level.lines[151].backSector!;
      expect(gate.specialData, isNull,
          reason: 'using into a wall must not open the distant gate');
    });
  });
}
