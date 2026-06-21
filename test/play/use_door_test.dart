// Regression test for the full "Use" chain: pressing Use (Space) on a manual
// door must open it, going through the real input -> ticcmd -> P_PlayerThink
// (BT_USE edge) -> P_UseLines -> P_UseSpecialLine -> EV_VerticalDoor path.
//
// Background: the door MECHANIC (EV_VerticalDoor raising a sector ceiling) is
// covered in playsim_test.dart. This file exercises the CHAIN from the input
// key-state down to the door actually moving, including the vanilla `usedown`
// edge semantics (G_PlayerReborn spawns the player with usedown=true; a hold
// must not re-trigger; a release+press must re-trigger).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/game/world/world.dart';

import 'package:flu_doom/game/integration/key_state_bridge.dart';
import 'package:flu_doom/game/play/g_build.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/key_bindings.dart';

World _loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

/// Position the player 32 units in front of (the +y side of) a known E1M1
/// manual-door line, facing it. Line index 151 carries manual door special 1.
Line _placePlayerAtDoor(PlaySim sim) {
  final Line door = sim.world.level.lines[151];
  expect(door.special, 1, reason: 'E1M1 line 151 is manual door special 1');
  expect(door.backSector, isNotNull);

  final Mobj mo = sim.player.mo!;
  final fixed_t mx = (door.v1.x + door.v2.x) >> 1;
  final fixed_t my = (door.v1.y + door.v2.y) >> 1;
  sim.move.unsetThingPosition(mo);
  mo.x = mx;
  mo.y = toInt32(my + 32 * kFracUnit); // +y side, within USERANGE (64 units)
  mo.angle = kAng270; // face -y, toward the door line
  sim.move.setThingPosition(mo);
  return door;
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  group('Use chain — input -> BT_USE', () {
    test('Space key-state produces BT_USE via the real input/g_build path', () {
      final EventQueue queue = EventQueue();
      final EventQueueActionSink sink = EventQueueActionSink(queue);
      final KeyBindings bindings = KeyBindings.defaults();
      final KeyStateBridge bridge = KeyStateBridge(sink);
      final TicCmdBuilder builder = TicCmdBuilder();

      // Space resolves to the "use" action and ref-counts the Doom spacebar.
      final action = bindings.actionFor(LogicalKeyboardKey.space);
      expect(action, isNotNull);
      sink.pressAction(action!);

      // Bridge reads the held key-state; g_build sets BT_USE.
      final KeyState keys = bridge.build();
      expect(keys.use, isTrue);

      final TicCmd cmd = TicCmd();
      builder.build(cmd, keys);
      expect(cmd.buttons & btUse, btUse);

      // Releasing clears it.
      sink.releaseAction(action);
      final KeyState keys2 = bridge.build();
      expect(keys2.use, isFalse);
    });
  });

  group('Use chain — door opens through P_PlayerThink', () {
    late World world;
    late PlaySim sim;

    setUp(() {
      world = _loadWorld();
      sim = PlaySim(world);
      sim.spawnLevel();
    });

    test('Use at a manual door raises the door sector ceiling', () {
      final Line door = _placePlayerAtDoor(sim);
      final Sector sec = door.backSector!;
      final fixed_t startCeil = sec.ceilingHeight;

      // Vanilla G_PlayerReborn spawns with usedown=true ("don't do anything
      // immediately"). One release tic clears the edge latch, exactly as the
      // live app does before the player ever presses Use.
      final TicCmd release = TicCmd();
      sim.tic(release);
      expect(sim.player.useDown, isFalse);

      // Hold Use: the BT_USE edge fires P_UseLines -> EV_VerticalDoor, and the
      // door thinker raises the ceiling over the following tics.
      final TicCmd use = TicCmd()..buttons = btUse;
      for (int i = 0; i < 35; i++) {
        sim.tic(use);
      }

      expect(sec.specialData, isNotNull,
          reason: 'a VerticalDoor thinker should be attached');
      expect(sec.ceilingHeight, greaterThan(startCeil),
          reason: 'pressing Use on the door should raise its ceiling');
    });

    test('a continuous hold does NOT re-trigger the door (usedown edge)', () {
      final Line door = _placePlayerAtDoor(sim);
      final Sector sec = door.backSector!;

      // Clear the spawn latch, then press Use once (the edge).
      sim.tic(TicCmd());
      final TicCmd use = TicCmd()..buttons = btUse;
      sim.tic(use);
      expect(sim.player.useDown, isTrue);
      final Object? doorAfterFirst = sec.specialData;
      expect(doorAfterFirst, isNotNull);

      // Reverse the door manually so a *re-trigger* would be observable: a
      // second EV_VerticalDoor on an already-active door reverses direction.
      // While the button stays held, useDown stays true, so the edge must NOT
      // fire again and the door must remain the same opening thinker.
      final int dirBefore = (doorAfterFirst as dynamic).dir as int;
      for (int i = 0; i < 5; i++) {
        sim.tic(use);
      }
      final int dirAfter = (sec.specialData as dynamic).dir as int;
      expect(identical(sec.specialData, doorAfterFirst), isTrue,
          reason: 'held Use must not spawn/replace the door thinker');
      // dir may advance 1 -> 0 naturally as the door reaches the top, but it
      // must never have been flipped to closing (-1) by a spurious re-trigger
      // mid-opening.
      expect(dirAfter, isNot(equals(-1)),
          reason: 'held Use must not reverse the opening door (no re-trigger)');
      expect(dirBefore, 1);
    });

    test('release then press can use the door again (re-trigger on edge)', () {
      final Line door = _placePlayerAtDoor(sim);
      final Sector sec = door.backSector!;

      // First use: open the door.
      sim.tic(TicCmd());
      final TicCmd use = TicCmd()..buttons = btUse;
      sim.tic(use);
      final Object? firstDoor = sec.specialData;
      expect(firstDoor, isNotNull);
      expect((firstDoor as dynamic).dir as int, 1); // opening

      // Release Use (edge clears), then press again. The second edge calls
      // EV_VerticalDoor on the still-active door, which reverses it (vanilla:
      // an opening door re-used reverses to closing).
      sim.tic(TicCmd()); // release
      expect(sim.player.useDown, isFalse);
      sim.tic(use); // press again -> edge fires
      expect(sim.player.useDown, isTrue);

      expect(identical(sec.specialData, firstDoor), isTrue,
          reason: 're-use reverses the existing door thinker, not a new one');
      expect((sec.specialData as dynamic).dir as int, -1,
          reason: 're-using an opening door reverses it to closing');
    });
  });
}
