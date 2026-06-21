// World data-layer tests: load the real shareware E1M1 from doom1.wad and
// assert sane counts, internal index consistency, and texture/flat resolution.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/data/textures.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/level.dart';
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/game/world/world.dart';

WadFile loadWad() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  return WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  late WadFile wad;
  late World world;
  late Level level;
  late Textures textures;

  setUpAll(() {
    wad = loadWad();
    world = World.fromWad(wad); // default E1M1
    level = world.level;
    textures = world.textures;
  });

  group('E1M1 map loading', () {
    test('default map is E1M1', () {
      expect(level.name, 'E1M1');
    });

    test('non-zero counts for every array', () {
      expect(level.vertexes, isNotEmpty);
      expect(level.sectors, isNotEmpty);
      expect(level.sides, isNotEmpty);
      expect(level.lines, isNotEmpty);
      expect(level.segs, isNotEmpty);
      expect(level.subsectors, isNotEmpty);
      expect(level.nodes, isNotEmpty);
      expect(level.things, isNotEmpty);
    });

    test('counts match the known shareware E1M1 layout', () {
      // Derived from the doom1.wad lump sizes (deterministic for the IWAD).
      expect(level.vertexes.length, 467);
      expect(level.sectors.length, 85);
      expect(level.sides.length, 648);
      expect(level.lines.length, 475);
      expect(level.segs.length, 732);
      expect(level.subsectors.length, 237);
      expect(level.nodes.length, 236);
      expect(level.things.length, 138);
    });

    test('root node is last', () {
      expect(level.rootNode, level.nodes.length - 1);
    });
  });

  group('internal consistency', () {
    test('side sector references are valid instances', () {
      for (final Side s in level.sides) {
        expect(level.sectors, contains(s.sector));
      }
    });

    test('line vertex/side references valid; front side always present', () {
      for (final Line l in level.lines) {
        expect(level.vertexes, contains(l.v1));
        expect(level.vertexes, contains(l.v2));
        expect(level.sides, contains(l.frontSide));
        expect(l.frontSector, l.frontSide.sector);
        if (l.backSide != null) {
          expect(level.sides, contains(l.backSide));
          expect(l.backSector, l.backSide!.sector);
        } else {
          expect(l.backSector, isNull);
        }
      }
    });

    test('seg side/line/sector references valid and self-consistent', () {
      for (final Seg s in level.segs) {
        expect(level.sides, contains(s.sidedef));
        expect(level.lines, contains(s.linedef));
        expect(s.frontSector, s.sidedef.sector);
        if (s.backSector != null) {
          expect(level.sectors, contains(s.backSector));
        }
      }
    });

    test('subsector seg ranges are within the segs array', () {
      for (final Subsector ss in level.subsectors) {
        expect(ss.firstLine, greaterThanOrEqualTo(0));
        expect(ss.numLines, greaterThan(0));
        expect(ss.firstLine + ss.numLines, lessThanOrEqualTo(level.segs.length));
        expect(level.sectors, contains(ss.sector));
      }
    });

    test('node children indices in range (subsector or node)', () {
      for (final Node n in level.nodes) {
        for (final int child in n.children) {
          if ((child & nfSubsector) != 0) {
            final int idx = child & ~nfSubsector;
            expect(idx, lessThan(level.subsectors.length));
          } else {
            expect(child, lessThan(level.nodes.length));
          }
        }
      }
    });

    test('every sector has at least one line after P_GroupLines', () {
      for (final Sector sec in level.sectors) {
        expect(sec.lineCount, greaterThan(0));
        // bbox is sane: left <= right, bottom <= top.
        expect(sec.blockBox[Box.left], lessThanOrEqualTo(sec.blockBox[Box.right]));
        expect(
            sec.blockBox[Box.bottom], lessThanOrEqualTo(sec.blockBox[Box.top]));
      }
    });

    test('there is a player-1 start (thing type 1)', () {
      expect(level.things.any((MapThing t) => t.type == 1), isTrue);
    });
  });

  group('texture / flat / sprite resolution', () {
    test('counts are non-zero', () {
      expect(textures.numTextures, greaterThan(0));
      expect(textures.numFlats, greaterThan(0));
      expect(textures.numSprites, greaterThan(0));
    });

    test('known wall texture resolves (STARTAN3)', () {
      final int n = textures.checkTextureNumForName('STARTAN3');
      expect(n, greaterThanOrEqualTo(0));
      final Texture t = textures.texture(n);
      expect(t.name, 'STARTAN3');
      expect(t.width, greaterThan(0));
      expect(t.height, greaterThan(0));
    });

    test('"-" texture name resolves to 0 (no texture)', () {
      expect(textures.checkTextureNumForName('-'), 0);
    });

    test('composited texture column data has the right size', () {
      final int n = textures.textureNumForName('STARTAN3');
      final Texture t = textures.texture(n);
      final Uint8List cols = textures.textureColumns(n);
      expect(cols.length, t.width * t.height);
      final Uint8List col0 = textures.textureColumn(n, 0);
      expect(col0.length, t.height);
      // Caching returns the identical buffer on a second call.
      expect(identical(textures.textureColumns(n), cols), isTrue);
    });

    test('known flat resolves and yields 4096 bytes (FLOOR4_8)', () {
      final int n = textures.checkFlatNumForName('FLOOR4_8');
      expect(n, greaterThanOrEqualTo(0));
      expect(textures.flatPixels(n).length, 4096);
    });

    test('a known sprite name resolves (PLAYA1)', () {
      // Player sprite frame A, rotation 1 — present in the shareware IWAD.
      expect(textures.checkSpriteNumForName('PLAYA1'),
          greaterThanOrEqualTo(0));
    });
  });

  group('ticcmd', () {
    test('clear and copyFrom behave', () {
      final TicCmd a = TicCmd()
        ..forwardMove = 50
        ..sideMove = -20
        ..angleTurn = 1024
        ..buttons = btAttack | btUse;
      final TicCmd b = TicCmd()..copyFrom(a);
      expect(b.forwardMove, 50);
      expect(b.sideMove, -20);
      expect(b.angleTurn, 1024);
      expect(b.buttons, btAttack | btUse);
      a.clear();
      expect(a.forwardMove, 0);
      expect(a.buttons, 0);
    });
  });

  group('viewpoint', () {
    test('set normalizes angle and stores position', () {
      world.viewpoint.set(x: 100, y: 200, z: 41 << 16, angle: 0x40000000);
      expect(world.viewpoint.x, 100);
      expect(world.viewpoint.y, 200);
      expect(world.viewpoint.z, 41 << 16);
      expect(world.viewpoint.angle, 0x40000000);
    });
  });
}
