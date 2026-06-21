// COMBAT-D integration test: drives the full live tic loop on the real
// shareware E1M1 world and asserts combat is interactive end-to-end:
//   (a) a monster wakes / changes out of its spawnstate when the player is in
//       sight,
//   (b) firing the pistol (a synthetic BT_ATTACK ticcmd) decrements ammo and
//       can damage / kill a nearby monster,
//   (c) no exceptions across ~200 tics with monsters active,
//   (d) walking the player onto a spawned item triggers a pickup (ammo/health
//       changes).
//
// This exercises the COMBAT-D wiring: registerEnemyActions/registerWeaponActions
// (before registerAllStubs), the per-tic Pspr.levelTime / EnemyAi.gametic drive,
// the BT_ATTACK -> A_WeaponReady -> P_FireWeapon path through P_PlayerThink, and
// the MapMove.onTouchSpecial -> P_TouchSpecialThing pickup hook.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/math/tables.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/game/world/ticcmd.dart';

import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/mobj_flags.dart';
import 'package:flu_doom/game/play/playsim.dart';

World loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

/// Every live Mobj currently in the thinker list.
Iterable<Mobj> liveMobjs(PlaySim sim) =>
    sim.thinkers.thinkers.whereType<Mobj>().where((Mobj m) => !m.removed);

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  test('monsters spawn shootable with full info-table flags', () {
    final PlaySim sim = PlaySim(loadWorld());
    sim.spawnLevel();

    final List<Mobj> monsters = liveMobjs(sim)
        .where((Mobj m) => (m.flags & mfCountKill) != 0)
        .toList();
    expect(monsters, isNotEmpty,
        reason: 'E1M1 must spawn counted monsters on medium skill');

    for (final Mobj m in monsters) {
      expect(m.flags & mfShootable, isNot(0),
          reason: 'monster ${m.type} must be MF_SHOOTABLE');
      expect(m.health, greaterThan(0));
      // Flags came from the full mobjInfo table, not a hand-built slice. (The
      // spawner may additionally OR MF_AMBUSH for "deaf" things; everything in
      // the info table must still be present.)
      expect(m.flags & mobjInfo[m.type].flags, mobjInfo[m.type].flags,
          reason: 'spawn flags must include the info-table flags');
    }
  });

  test('a monster wakes / leaves spawnstate over a live tic run', () {
    final PlaySim sim = PlaySim(loadWorld());
    sim.spawnLevel();

    // Record each counted monster's initial spawnstate.
    final List<Mobj> monsters = liveMobjs(sim)
        .where((Mobj m) => (m.flags & mfCountKill) != 0)
        .toList();
    final Map<Mobj, int> spawnStateOf = <Mobj, int>{
      for (final Mobj m in monsters) m: mobjInfo[m.type].spawnState,
    };

    // Run a couple hundred idle tics; A_Look should sight/hear the player and
    // move monsters into their seestate chain (chase).
    final TicCmd idle = TicCmd();
    bool anyWoke = false;
    for (int t = 0; t < 200; t++) {
      sim.tic(idle);
      for (final Mobj m in monsters) {
        if (m.removed) continue;
        // A monster has "woken" once it is no longer cycling its spawnstate
        // idle frames (A_Look) — i.e. it acquired a target or changed states.
        if (m.target != null || m.stateIndex != spawnStateOf[m]) {
          anyWoke = true;
        }
      }
      if (anyWoke) break;
    }

    expect(anyWoke, isTrue,
        reason: 'at least one monster should leave its spawnstate / acquire a '
            'target when the player is in the level');
  });

  test('firing the pistol decrements ammo and can damage a nearby monster', () {
    final PlaySim sim = PlaySim(loadWorld());
    sim.spawnLevel();

    final Mobj playerMo = sim.player.mo!;

    // Find the nearest counted monster and teleport the player next to it,
    // facing it, so the auto-aim hitscan connects.
    final List<Mobj> monsters = liveMobjs(sim)
        .where((Mobj m) => (m.flags & mfCountKill) != 0)
        .toList();
    expect(monsters, isNotEmpty);

    monsters.sort((Mobj a, Mobj b) {
      final int da =
          (a.x - playerMo.x).abs() + (a.y - playerMo.y).abs();
      final int db =
          (b.x - playerMo.x).abs() + (b.y - playerMo.y).abs();
      return da.compareTo(db);
    });
    final Mobj victim = monsters.first;

    // Place the player a short distance in front of the monster, facing it.
    final angle_t toMonster = _pointToAngle(
        playerMo.x, playerMo.y, victim.x, victim.y);
    final int an = angleToFineIndex(toMonster);
    // Stand 96 map units away from the monster along the line to it.
    final fixed_t dist = 96 * kFracUnit;
    sim.move.tryMove(
        playerMo,
        toInt32(victim.x - (dist >> kFracBits) * finecosineLookup(an)),
        toInt32(victim.y - (dist >> kFracBits) * finesineLookup(an)));
    playerMo.angle = _pointToAngle(
        playerMo.x, playerMo.y, victim.x, victim.y);

    final int startAmmo = sim.player.ammo[Am.clip];
    final int startHealth = victim.health;

    // Build a BT_ATTACK ticcmd and run enough tics for the pistol fire +
    // refire cycle to expend several rounds.
    final TicCmd fire = TicCmd()..buttons = btAttack;
    bool exploded = false;
    for (int t = 0; t < 120; t++) {
      try {
        sim.tic(fire);
      } catch (e) {
        exploded = true;
        fail('tic threw while firing: $e');
      }
    }
    expect(exploded, isFalse);

    expect(sim.player.ammo[Am.clip], lessThan(startAmmo),
        reason: 'firing the pistol must consume clip ammo');

    // The nearby monster should have taken damage (or died) from the hitscan.
    expect(victim.health, lessThan(startHealth),
        reason: 'a faced, nearby monster should be hit by the pistol');
  });

  test('no exceptions across ~200 tics with monsters active', () {
    final PlaySim sim = PlaySim(loadWorld());
    sim.spawnLevel();

    final TicCmd cmd = TicCmd();
    for (int t = 0; t < 200; t++) {
      // Alternate firing + moving to exercise psprites, attacks, and AI.
      cmd.buttons = (t % 4 == 0) ? btAttack : 0;
      cmd.forwardMove = (t % 8 < 4) ? 25 : 0;
      try {
        sim.tic(cmd);
      } catch (e, st) {
        fail('tic $t threw: $e\n$st');
      }
    }
    // Still alive and simulating.
    expect(sim.levelTime, 200);
  });

  test('walking onto a spawned item triggers a pickup', () {
    final PlaySim sim = PlaySim(loadWorld());
    sim.spawnLevel();

    final Mobj playerMo = sim.player.mo!;

    // Find a reachable ammo/health pickup (MF_SPECIAL). Prefer a clip / shells /
    // medikit so we can observe a concrete ammo or health change.
    final List<Mobj> specials = liveMobjs(sim)
        .where((Mobj m) => (m.flags & mfSpecial) != 0)
        .toList();
    expect(specials, isNotEmpty,
        reason: 'E1M1 places pickup items');

    // Try each special: teleport the player on top of it and run one tic with a
    // tiny nudge so PIT_CheckThing fires the touch-special hook. Stop at the
    // first one that changes ammo or health.
    bool pickedUp = false;
    for (final Mobj item in specials) {
      if (item.removed) continue;
      final List<int> beforeAmmo = List<int>.from(sim.player.ammo);
      final int beforeHealth = sim.player.health;
      final int beforeArmor = sim.player.armorPoints;
      final bool beforeBackpack = sim.player.backpack;

      // Move the player onto the item (P_TryMove relinks + runs PIT_CheckThing,
      // which calls onTouchSpecial -> P_TouchSpecialThing for MF_PICKUP).
      sim.move.tryMove(playerMo, item.x, item.y);

      final bool ammoChanged = !_listEq(sim.player.ammo, beforeAmmo);
      final bool healthChanged = sim.player.health != beforeHealth;
      final bool armorChanged = sim.player.armorPoints != beforeArmor;
      final bool backpackChanged = sim.player.backpack != beforeBackpack;
      final bool consumed = item.removed;

      if (ammoChanged ||
          healthChanged ||
          armorChanged ||
          backpackChanged ||
          consumed) {
        pickedUp = true;
        // The item must have been removed from the world (vanilla
        // P_RemoveMobj in P_TouchSpecialThing), unless it was a full pickup
        // that returned early — keep scanning in that case.
        if (consumed) break;
      }
    }

    expect(pickedUp, isTrue,
        reason: 'walking onto an item should give ammo/health/armor and remove '
            'the pickup');
  });
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int finecosineLookup(int fineIndex) => finecosine[fineIndex];
int finesineLookup(int fineIndex) => finesine[fineIndex];

// R_PointToAngle2 (octant logic), local copy to avoid a renderer dep.
angle_t _pointToAngle(fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2) {
  int x = toInt32(x2 - x1);
  int y = toInt32(y2 - y1);
  if (x == 0 && y == 0) return 0;
  if (x >= 0) {
    if (y >= 0) {
      if (x > y) {
        return tantoangle[slopeDiv(y, x)];
      }
      return normAngle(kAng90 - 1 - tantoangle[slopeDiv(x, y)]);
    } else {
      y = -y;
      if (x > y) {
        return normAngle(-tantoangle[slopeDiv(y, x)]);
      }
      return normAngle(kAng270 + tantoangle[slopeDiv(x, y)]);
    }
  } else {
    x = -x;
    if (y >= 0) {
      if (x > y) {
        return normAngle(kAng180 - 1 - tantoangle[slopeDiv(y, x)]);
      }
      return normAngle(kAng90 + tantoangle[slopeDiv(x, y)]);
    } else {
      y = -y;
      if (x > y) {
        return normAngle(kAng180 + tantoangle[slopeDiv(y, x)]);
      }
      return normAngle(kAng270 - 1 - tantoangle[slopeDiv(x, y)]);
    }
  }
}
