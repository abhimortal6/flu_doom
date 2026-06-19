// Diagnostic: count monsters/barrels spawned on E1M1 (shareware) at skill 3.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/mobj_flags.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/play/spawn.dart';
import 'package:flu_doom/game/play/thinker.dart';
import 'package:flu_doom/game/world/world.dart';

void main() {
  test('E1M1 spawns monsters + barrels', () {
    final Uint8List bytes = File('assets/doom1.wad').readAsBytesSync();
    final World world = World.fromWad(WadFile.fromBytes(bytes), mapName: 'E1M1');
    final PlaySim sim = PlaySim(world, skill: Skill.medium);
    sim.spawnLevel();

    int kills = 0;
    int barrels = 0;
    final Map<int, int> byType = <int, int>{};
    for (final Thinker t in sim.thinkers.thinkers) {
      if (t is! Mobj) continue;
      final Mobj m = t;
      if ((m.flags & mfCountKill) != 0) {
        kills++;
        byType[m.type] = (byType[m.type] ?? 0) + 1;
      }
      if (m.type == Mt.barrel) barrels++;
    }
    stderr.writeln('=== E1M1 skill=medium spawn diagnosis ===');
    stderr.writeln('total things in level: ${world.level.things.length}');
    stderr.writeln('MF_COUNTKILL monsters: $kills');
    byType.forEach((int type, int n) {
      stderr.writeln('  type $type spawnerHealth='
          '${mobjInfo[type].spawnHealth} doomednum=${mobjInfo[type].doomedNum}'
          '  x$n');
    });
    stderr.writeln('MT_BARREL: $barrels');

    // Also dump a sample monster position/angle for the enemy.png render.
    for (final Thinker t in sim.thinkers.thinkers) {
      if (t is! Mobj) continue;
      if ((t.flags & mfCountKill) != 0) {
        stderr.writeln('sample monster: type=${t.type} sprite=${t.sprite}'
            ' frame=${t.frame}'
            ' x=${t.x >> kFracBits} y=${t.y >> kFracBits}'
            ' angleBAM=${t.angle}');
        break;
      }
    }
  });
}
