// MUS->MIDI conversion + GENMIDI parsing unit tests, run against the REAL
// shareware doom1.wad (pure parsing — no audio device required).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/sound/genmidi.dart';
import 'package:flu_doom/engine/sound/mus2mid.dart';
import 'package:flu_doom/engine/wad/wad.dart';

// Read a 32-bit big-endian int from [b] at [offset] (MIDI uses big-endian).
int _be32(Uint8List b, int offset) =>
    (b[offset] << 24) | (b[offset + 1] << 16) | (b[offset + 2] << 8) | b[offset + 3];

void main() {
  late WadFile wad;

  setUpAll(() {
    final File f = File('assets/doom1.wad');
    expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
    wad = WadFile.fromBytes(f.readAsBytesSync());
  });

  group('mus2mid', () {
    test('D_E1M1 converts to a well-formed type-0 MIDI', () {
      final Lump lump = wad.getLump('D_E1M1');
      final Uint8List midi = mus2mid(Uint8List.fromList(lump.bytes));

      // Starts with the 'MThd' chunk id.
      expect(String.fromCharCodes(midi.sublist(0, 4)), 'MThd');

      // MThd length is 6, type 0, one track, resolution 0x0046.
      expect(_be32(midi, 4), 6);
      expect((midi[8] << 8) | midi[9], 0); // type 0
      expect((midi[10] << 8) | midi[11], 1); // 1 track
      expect((midi[12] << 8) | midi[13], 0x0046); // resolution

      // The 'MTrk' chunk follows at offset 14.
      expect(String.fromCharCodes(midi.sublist(14, 18)), 'MTrk');

      // Track length field (offset 18) must equal the remaining bytes.
      final int trackSize = _be32(midi, 18);
      expect(trackSize, midi.length - 22);

      // Sane overall length: header + track header + non-empty body.
      expect(midi.length, greaterThan(22));
      expect(midi.length, greaterThan(lump.size ~/ 2));

      // Ends with the end-of-track meta event (FF 2F 00).
      expect(midi.sublist(midi.length - 3),
          orderedEquals(<int>[0xFF, 0x2F, 0x00]));
    });

    test('D_INTRO and D_INTER convert without exception', () {
      for (final String name in <String>['D_INTRO', 'D_INTER']) {
        final Lump lump = wad.getLump(name);
        final Uint8List midi = mus2mid(Uint8List.fromList(lump.bytes));
        expect(String.fromCharCodes(midi.sublist(0, 4)), 'MThd',
            reason: '$name should start with MThd');
        expect(String.fromCharCodes(midi.sublist(14, 18)), 'MTrk',
            reason: '$name should contain MTrk');
        expect(_be32(midi, 18), midi.length - 22,
            reason: '$name track length must match body size');
      }
    });
  });

  group('GenMidi.parse', () {
    test('parses the GENMIDI lump: valid magic, 175 instruments', () {
      final Lump lump = wad.getLump('GENMIDI');
      final GenMidi gm = GenMidi.parse(Uint8List.fromList(lump.bytes));

      expect(gm.magicValid, true, reason: 'GENMIDI magic "#OPL_II#"');
      expect(gm.numInstruments, 175);
      expect(gm.numInstruments, genmidiNumInstrs + genmidiNumPercussion);
    });

    test('every instrument has two voices with in-range bytes', () {
      final Lump lump = wad.getLump('GENMIDI');
      final GenMidi gm = GenMidi.parse(Uint8List.fromList(lump.bytes));

      for (int i = 0; i < gm.numInstruments; i++) {
        final GenMidiInstr instr = gm.instrument(i);
        expect(instr.voices.length, 2);
        expect(instr.flags, inInclusiveRange(0, 0xFFFF));
        expect(instr.fineTuning, inInclusiveRange(0, 0xFF));
        expect(instr.fixedNote, inInclusiveRange(0, 0xFF));
        for (final GenMidiVoice v in instr.voices) {
          for (final GenMidiOp op in <GenMidiOp>[v.modulator, v.carrier]) {
            expect(op.tremolo, inInclusiveRange(0, 0xFF));
            expect(op.attack, inInclusiveRange(0, 0xFF));
            expect(op.sustain, inInclusiveRange(0, 0xFF));
            expect(op.waveform, inInclusiveRange(0, 0xFF));
            expect(op.scale, inInclusiveRange(0, 0xFF));
            expect(op.level, inInclusiveRange(0, 0xFF));
          }
          expect(v.feedback, inInclusiveRange(0, 0xFF));
          expect(v.baseNoteOffset, inInclusiveRange(-32768, 32767));
        }
      }
    });

    test('spot-check instrument 0 (piano) is non-degenerate', () {
      final Lump lump = wad.getLump('GENMIDI');
      final GenMidi gm = GenMidi.parse(Uint8List.fromList(lump.bytes));

      final GenMidiInstr piano = gm.instrument(0);
      // A real instrument has at least some non-zero operator data across its
      // first voice (not all zeros).
      final GenMidiVoice v0 = piano.voices[0];
      final int sum = v0.modulator.tremolo +
          v0.modulator.attack +
          v0.modulator.sustain +
          v0.modulator.waveform +
          v0.modulator.scale +
          v0.modulator.level +
          v0.carrier.tremolo +
          v0.carrier.attack +
          v0.carrier.sustain +
          v0.carrier.level;
      expect(sum, greaterThan(0), reason: 'piano voice should not be all-zero');

      // Percussion entry for the acoustic bass drum (MIDI note 35) is reachable
      // and equals instrument 128.
      expect(identical(gm.percussion(35), gm.instrument(genmidiNumInstrs)), true);
      // Note 81 is the top of the percussion range -> instrument 174.
      expect(identical(gm.percussion(81), gm.instrument(174)), true);
      expect(() => gm.percussion(34), throwsA(isA<GenMidiException>()));
      expect(() => gm.percussion(82), throwsA(isA<GenMidiException>()));
    });
  });
}
