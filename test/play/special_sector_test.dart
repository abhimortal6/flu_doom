// P_PlayerInSpecialSector tests (p_spec.c): damaging floors (nukage/slime/
// lava), the radiation-suit (pw_ironfeet) immunity, secret-sector counting,
// and the leveltime &0x1f damage cadence. Uses the real shareware E1M1 via the
// full PlaySim so the player mobj sits on its sector floor with a working
// P_DamageMobj path.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/game/world/world.dart';

import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/player.dart';
import 'package:flu_doom/game/play/playsim.dart';

const int _pwIronfeet = 3;

World _loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

/// An empty command keeps the player standing still on its current sector so
/// the special-sector check fires against the same floor every tic.
final TicCmd _idle = TicCmd();

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  group('P_PlayerInSpecialSector — E1M1', () {
    late World world;
    late PlaySim sim;
    late Player player;
    late Mobj mo;
    late Sector sec;

    setUp(() {
      world = _loadWorld();
      sim = PlaySim(world);
      sim.spawnLevel();
      player = sim.player;
      mo = player.mo!;
      sec = mo.subsectorSector!;
      // Sanity: the player must be standing on its floor (the vanilla guard
      // `player->mo->z == sector->floorheight`).
      expect(mo.z, sec.floorHeight);
      // levelTime starts at 0, so the very first tic hits the (leveltime&31)==0
      // damage boundary.
      expect(sim.levelTime, 0);
    });

    test('special 7 (nukage): 5 damage on the leveltime&31 boundary', () {
      sec.special = 7;
      final int before = mo.health; // 100
      // levelTime == 0 during this think -> (0 & 31) == 0 -> 5 damage.
      sim.tic(_idle);
      expect(mo.health, before - 5);
      expect(player.health, before - 5);

      // levelTime is now 1..31 for the next 31 tics: NO further damage.
      for (int i = 0; i < 31; i++) {
        sim.tic(_idle);
      }
      expect(mo.health, before - 5);
      // levelTime == 32 during the next think -> (32 & 31) == 0 -> 5 more.
      expect(sim.levelTime, 32);
      sim.tic(_idle);
      expect(mo.health, before - 10);
    });

    test('special 7 (nukage) with pw_ironfeet: no damage', () {
      sec.special = 7;
      player.powers[_pwIronfeet] = 60; // radiation suit active
      final int before = mo.health;
      sim.tic(_idle);
      expect(mo.health, before);
    });

    test('special 5 (hellslime): 10 damage on the boundary', () {
      sec.special = 5;
      final int before = mo.health;
      sim.tic(_idle);
      expect(mo.health, before - 10);
    });

    test('special 9 (secret): secretCount++ and the special clears once', () {
      sec.special = 9;
      final int before = player.secretCount;
      sim.tic(_idle);
      expect(player.secretCount, before + 1);
      expect(sec.special, 0); // cleared so it cannot be re-counted

      // Standing in it again does nothing (special is now 0).
      sim.tic(_idle);
      expect(player.secretCount, before + 1);
    });
  });

  group('P_SpawnSpecials — E1M1', () {
    test('at least one sector carries a damaging special (the nukage pool)',
        () {
      final World world = _loadWorld();
      const Set<int> damaging = <int>{4, 5, 7, 11, 16};
      final bool hasDamaging =
          world.level.sectors.any((Sector s) => damaging.contains(s.special));
      expect(hasDamaging, true,
          reason: 'E1M1 should contain a nukage/slime damaging sector');
    });

    test('secret sectors (special 9) are counted into totalSecret', () {
      final World world = _loadWorld();
      final int secretSectors =
          world.level.sectors.where((Sector s) => s.special == 9).length;
      expect(secretSectors, greaterThan(0),
          reason: 'E1M1 has secret sectors');

      final PlaySim sim = PlaySim(world);
      sim.spawnLevel();
      // P_SpawnSpecials accumulated totalsecret; previously stuck at 0.
      expect(sim.totalSecret, secretSectors);
    });
  });
}
