// Tests for the Nuked-OPL3 Dart port (lib/engine/sound/opl3.dart).
//
// Verifies:
//   (a) non-silence — a programmed 2-op key-on produces non-zero output;
//   (b) determinism — two fresh chips with identical register streams produce
//       byte-identical output;
//   (c) table spot-checks — exp/logsin/mult ROM entries match Nuked exactly;
//   (d) resampler setup — reset() configures rateratio for the target rate.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flu_doom/engine/sound/opl3.dart';

const int _nativeRate = 49716;

/// Program a simple 2-op instrument and key on a note on channel 0.
///
/// Documented OPL register sequence:
///   * 0x20+ : AM/VIB/EG-type/KSR/multiplier (per operator slot).
///   * 0x40+ : KSL/total-level (operator output attenuation).
///   * 0x60+ : attack/decay rate.
///   * 0x80+ : sustain-level/release rate.
///   * 0xC0  : feedback/connection (channel).
///   * 0xA0  : frequency low byte (channel).
///   * 0xB0  : key-on bit + block + frequency high bits (channel).
///
/// Operator 0 of channel 0 is register-offset 0x00, operator 1 is 0x03.
void _programNote(Opl3 chip) {
  // Modulator (op0, offset 0x00).
  chip.writeReg(0x20, 0x01); // mult = 1
  chip.writeReg(0x40, 0x10); // ksl 0, total level (moderate attenuation)
  chip.writeReg(0x60, 0xf0); // attack 15, decay 0 (fast attack)
  chip.writeReg(0x80, 0x77); // sustain ~, release
  // Carrier (op1, offset 0x03).
  chip.writeReg(0x23, 0x01); // mult = 1
  chip.writeReg(0x43, 0x00); // total level 0 -> loud carrier
  chip.writeReg(0x63, 0xf0); // attack 15, decay 0
  chip.writeReg(0x83, 0x77); // sustain/release
  // Channel 0 connection/feedback: FM (con=0), feedback 0.
  chip.writeReg(0xc0, 0x00);
  // Frequency: F-number low + block/high + key on.
  chip.writeReg(0xa0, 0x98); // f-num low
  chip.writeReg(0xb0, 0x31); // key-on(0x20) | block 4 (0x10..) | f-num hi
}

/// Render [frames] interleaved stereo samples from a freshly reset chip that
/// has been programmed with [program].
Int16List _render(int frames, void Function(Opl3) program) {
  final Opl3 chip = Opl3();
  chip.reset(_nativeRate);
  program(chip);
  final Int16List buf = Int16List(frames * 2);
  chip.generateStream(buf, frames);
  return buf;
}

void main() {
  group('Opl3 table spot-checks', () {
    test('logsin ROM matches Nuked', () {
      final List<int> t = Opl3.debugLogsinRom();
      expect(t.length, 256);
      expect(t[0], 0x859);
      expect(t[1], 0x6c3);
      expect(t[128], 0x07f);
      expect(t[255], 0x000);
    });

    test('exp ROM matches Nuked', () {
      final List<int> t = Opl3.debugExpRom();
      expect(t.length, 256);
      expect(t[0], 0x7fa);
      expect(t[1], 0x7f5);
      expect(t[128], 0x5a4);
      expect(t[255], 0x400);
    });

    test('freq-mult table matches Nuked', () {
      final List<int> t = Opl3.debugMultTable();
      expect(t, <int>[
        1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30, //
      ]);
    });
  });

  group('Opl3 resampler setup', () {
    test('reset at native rate yields 1:1 rateratio', () {
      final Opl3 chip = Opl3();
      chip.reset(_nativeRate);
      // (49716 << 10) / 49716 == 1024 == 1<<RSM_FRAC.
      expect(chip.rateratio, 1 << 10);
    });

    test('reset at a higher rate scales rateratio', () {
      final Opl3 chip = Opl3();
      chip.reset(44100);
      expect(chip.rateratio, (44100 << 10) ~/ 49716);
    });
  });

  group('Opl3 generation', () {
    test('programmed 2-op key-on produces non-silence', () {
      final Int16List buf = _render(4096, _programNote);
      bool anyNonZero = false;
      int maxAbs = 0;
      for (final int s in buf) {
        if (s != 0) {
          anyNonZero = true;
        }
        final int a = s < 0 ? -s : s;
        if (a > maxAbs) {
          maxAbs = a;
        }
      }
      expect(anyNonZero, isTrue,
          reason: 'expected non-silent output from a keyed-on note');
      expect(maxAbs, greaterThan(64),
          reason: 'expected audible amplitude, got peak $maxAbs');
    });

    test('a silent (un-keyed) chip stays silent', () {
      final Int16List buf = _render(1024, (Opl3 c) {
        // No key-on: program instrument but never set the 0x20 key bit on 0xB0.
        c.writeReg(0x20, 0x01);
        c.writeReg(0x40, 0x00);
        c.writeReg(0x60, 0xf0);
        c.writeReg(0x80, 0x00);
      });
      for (final int s in buf) {
        expect(s, 0);
      }
    });

    test('output is deterministic across two fresh chips', () {
      final Int16List a = _render(4096, _programNote);
      final Int16List b = _render(4096, _programNote);
      expect(a.length, b.length);
      for (int i = 0; i < a.length; i++) {
        expect(a[i], b[i], reason: 'sample $i differs: ${a[i]} vs ${b[i]}');
      }
    });

    test('single-frame generate matches stream output', () {
      // generate() one frame at a time should equal generateStream() for the
      // same register program (same internal path).
      final Opl3 streamed = Opl3()..reset(_nativeRate);
      _programNote(streamed);
      final Int16List streamBuf = Int16List(512 * 2);
      streamed.generateStream(streamBuf, 512);

      final Opl3 framed = Opl3()..reset(_nativeRate);
      _programNote(framed);
      final Int16List one = Int16List(2);
      final Int16List frameBuf = Int16List(512 * 2);
      for (int i = 0; i < 512; i++) {
        framed.generate(one);
        frameBuf[i * 2] = one[0];
        frameBuf[i * 2 + 1] = one[1];
      }
      for (int i = 0; i < streamBuf.length; i++) {
        expect(frameBuf[i], streamBuf[i], reason: 'sample $i');
      }
    });

    test('buffered writes drive sound after delay', () {
      final Opl3 chip = Opl3()..reset(_nativeRate);
      // Use the buffered path for the whole program.
      chip.writeRegBuffered(0x20, 0x01);
      chip.writeRegBuffered(0x40, 0x10);
      chip.writeRegBuffered(0x60, 0xf0);
      chip.writeRegBuffered(0x80, 0x77);
      chip.writeRegBuffered(0x23, 0x01);
      chip.writeRegBuffered(0x43, 0x00);
      chip.writeRegBuffered(0x63, 0xf0);
      chip.writeRegBuffered(0x83, 0x77);
      chip.writeRegBuffered(0xc0, 0x00);
      chip.writeRegBuffered(0xa0, 0x98);
      chip.writeRegBuffered(0xb0, 0x31);
      final Int16List buf = Int16List(8192 * 2);
      chip.generateStream(buf, 8192);
      bool anyNonZero = false;
      for (final int s in buf) {
        if (s != 0) {
          anyNonZero = true;
          break;
        }
      }
      expect(anyNonZero, isTrue,
          reason: 'buffered register writes should eventually produce sound');
    });
  });
}
