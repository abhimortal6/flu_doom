// Foundation tests: fixed-point math, trig tables, WAD parsing.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/math/tables.dart';
import 'package:flu_doom/engine/wad/wad.dart';

void main() {
  group('fixed-point', () {
    test('FRACUNIT and conversions', () {
      expect(kFracUnit, 65536);
      expect(intToFixed(3), 3 * 65536);
      expect(fixedToInt(intToFixed(7)), 7);
    });

    test('FixedMul known values', () {
      expect(fixedMul(intToFixed(2), intToFixed(3)), intToFixed(6));
      expect(fixedMul(kFracUnit ~/ 2, kFracUnit ~/ 2), kFracUnit ~/ 4);
      expect(fixedMul(-kFracUnit, kFracUnit), -kFracUnit);
    });

    test('FixedDiv known values and overflow guard', () {
      expect(fixedDiv(intToFixed(6), intToFixed(3)), intToFixed(2));
      // Overflow guard: abs(a)>>14 >= abs(b). a=1.0 (65536), b=1 triggers it.
      expect(fixedDiv(intToFixed(1), 1), kInt32Max);
      expect(fixedDiv(-intToFixed(1), 1), kInt32Min);
    });

    test('toInt32 wraparound', () {
      expect(toInt32(0x100000000), 0);
      expect(toInt32(0xFFFFFFFF), -1);
      expect(toInt32(0x7FFFFFFF), 0x7FFFFFFF);
    });
  });

  group('trig tables (verbatim from Chocolate Doom)', () {
    test('table sizes', () {
      expect(finesine.length, 10240);
      expect(finetangent.length, 4096);
      expect(tantoangle.length, 2049);
    });

    test('known finesine values', () {
      expect(finesine[0], 25);
      expect(finesine[1], 75);
      expect(finesine[2], 125);
    });

    test('known finetangent values', () {
      expect(finetangent[0], -170910304);
      expect(finetangent[4095], 170910304);
    });

    test('known tantoangle values', () {
      expect(tantoangle[0], 0);
      expect(tantoangle[1], 333772);
      expect(tantoangle[2048], 0x20000000);
    });

    test('finecosine is finesine offset by quarter circle', () {
      expect(finecosine[0], finesine[2048]);
    });

    test('BAM constants', () {
      expect(kAng45, 0x20000000);
      expect(kAng90, 0x40000000);
      expect(kAng180, 0x80000000);
      expect(kAng270, 0xC0000000);
    });

    test('angleToFineIndex', () {
      expect(angleToFineIndex(0), 0);
      expect(angleToFineIndex(kAng90), 2048);
    });
  });

  group('WAD parsing', () {
    WadFile buildWad() {
      final BytesBuilder bb = BytesBuilder();
      final List<int> foo = <int>[1, 2, 3];
      final List<int> bar = <int>[9, 8];
      const int headerSize = 12;
      final int fooPos = headerSize;
      final int barPos = fooPos + foo.length;
      final int dirPos = barPos + bar.length;

      final ByteData header = ByteData(12);
      header.setUint8(0, 'I'.codeUnitAt(0));
      header.setUint8(1, 'W'.codeUnitAt(0));
      header.setUint8(2, 'A'.codeUnitAt(0));
      header.setUint8(3, 'D'.codeUnitAt(0));
      header.setInt32(4, 2, Endian.little);
      header.setInt32(8, dirPos, Endian.little);
      bb.add(header.buffer.asUint8List());
      bb.add(foo);
      bb.add(bar);

      ByteData dirEntry(int pos, int size, String name) {
        final ByteData e = ByteData(16);
        e.setInt32(0, pos, Endian.little);
        e.setInt32(4, size, Endian.little);
        for (int i = 0; i < name.length && i < 8; i++) {
          e.setUint8(8 + i, name.codeUnitAt(i));
        }
        return e;
      }

      bb.add(dirEntry(fooPos, foo.length, 'FOO').buffer.asUint8List());
      bb.add(dirEntry(barPos, bar.length, 'BAR').buffer.asUint8List());
      return WadFile.fromBytes(bb.toBytes());
    }

    test('parses header and lumps', () {
      final WadFile wad = buildWad();
      expect(wad.identification, 'IWAD');
      expect(wad.isIwad, true);
      expect(wad.numLumps, 2);
    });

    test('lookup by name (case-insensitive)', () {
      final WadFile wad = buildWad();
      expect(wad.getLump('foo').bytes, Uint8List.fromList(<int>[1, 2, 3]));
      expect(wad.getLump('BAR').bytes, Uint8List.fromList(<int>[9, 8]));
      expect(wad.lumpByName('NOPE'), isNull);
    });
  });
}
