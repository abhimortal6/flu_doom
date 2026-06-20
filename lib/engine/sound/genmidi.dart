// GENMIDI instrument-lump parser, ported 1:1 from Chocolate Doom
// src/i_oplmusic.c (the genmidi_op_t / genmidi_voice_t / genmidi_instr_t
// structs and LoadInstrumentTable).
//
// The GENMIDI lump is the DMX OPL-2 instrument bank: an 8-byte "#OPL_II#"
// header (which DMX itself does not check) followed by 175 packed
// genmidi_instr_t entries — 128 melodic (indexed by MIDI program 0..127)
// then 47 percussion (indexed by MIDI note 35..81 on channel 9). After the
// instruments come instrument name tables, which the OPL player ignores and
// which we do not parse here.
//
// Byte layout (little-endian, packed) per i_oplmusic.c:
//   genmidi_op_t   = 6 bytes : tremolo, attack, sustain, waveform, scale, level
//   genmidi_voice_t= 16 bytes: modulator(6), feedback(1), carrier(6),
//                              unused(1), base_note_offset(int16)
//   genmidi_instr_t= 36 bytes: flags(uint16), fine_tuning(1), fixed_note(1),
//                              voices[2](2 * 16)
//
// This is a faithful port; field names and the percussion indexing
// match the vanilla port exactly.

import 'dart:typed_data';

/// GENMIDI lump magic header ("#OPL_II#"). DMX does not validate it; we expose
/// validation but accept the lump regardless, matching vanilla behaviour.
const String genmidiHeader = '#OPL_II#';

/// Number of melodic instruments (MIDI programs 0..127).
const int genmidiNumInstrs = 128;

/// Number of percussion instruments (MIDI notes 35..81 on channel 9).
const int genmidiNumPercussion = 47;

/// flags & GENMIDI_FLAG_FIXED -> fixed pitch instrument.
const int genmidiFlagFixed = 0x0001;

/// flags & GENMIDI_FLAG_2VOICE -> double-voice (OPL3) instrument.
const int genmidiFlag2Voice = 0x0004;

const int _opSize = 6;
const int _voiceSize = 16;
const int _instrSize = 36;
const int _headerSize = 8; // strlen("#OPL_II#")

/// One OPL operator's GENMIDI parameter bytes (`genmidi_op_t`).
///
/// Each byte packs OPL register bitfields the player loads directly:
///   - [tremolo]  : AM/VIB/EG-type(sustain)/KSR/mult (reg 0x20+)
///   - [attack]   : attack rate (hi nibble) / decay rate (lo nibble) (reg 0x60+)
///   - [sustain]  : sustain level (hi nibble) / release rate (lo nibble)(reg 0x80+)
///   - [waveform] : waveform select (reg 0xE0+)
///   - [scale]    : key scale level (reg 0x40+, KSL bits)
///   - [level]    : output level / total level (reg 0x40+, TL bits)
class GenMidiOp {
  const GenMidiOp({
    required this.tremolo,
    required this.attack,
    required this.sustain,
    required this.waveform,
    required this.scale,
    required this.level,
  });

  final int tremolo;
  final int attack;
  final int sustain;
  final int waveform;
  final int scale;
  final int level;

  static GenMidiOp _read(ByteData d, int offset) {
    return GenMidiOp(
      tremolo: d.getUint8(offset + 0),
      attack: d.getUint8(offset + 1),
      sustain: d.getUint8(offset + 2),
      waveform: d.getUint8(offset + 3),
      scale: d.getUint8(offset + 4),
      level: d.getUint8(offset + 5),
    );
  }
}

/// One OPL voice (`genmidi_voice_t`): a modulator + carrier operator pair,
/// the feedback/connection byte, and a base note offset applied to played
/// notes. A `GENMIDI_FLAG_2VOICE` instrument uses both of its voices.
class GenMidiVoice {
  const GenMidiVoice({
    required this.modulator,
    required this.feedback,
    required this.carrier,
    required this.unused,
    required this.baseNoteOffset,
  });

  /// Modulator operator parameters.
  final GenMidiOp modulator;

  /// Feedback / connection byte (reg 0xC0+).
  final int feedback;

  /// Carrier operator parameters.
  final GenMidiOp carrier;

  /// Unused padding byte (kept for fidelity / exact layout).
  final int unused;

  /// Signed base note offset (int16) added to the played note.
  final int baseNoteOffset;

  static GenMidiVoice _read(ByteData d, int offset) {
    return GenMidiVoice(
      modulator: GenMidiOp._read(d, offset),
      feedback: d.getUint8(offset + _opSize),
      carrier: GenMidiOp._read(d, offset + _opSize + 1),
      unused: d.getUint8(offset + _opSize + 1 + _opSize),
      // int16, little-endian (SHORT()).
      baseNoteOffset: d.getInt16(offset + _voiceSize - 2, Endian.little),
    );
  }
}

/// One GENMIDI instrument (`genmidi_instr_t`): flags, fine tuning, a fixed
/// note (for fixed-pitch instruments such as percussion), and two voices.
class GenMidiInstr {
  const GenMidiInstr({
    required this.flags,
    required this.fineTuning,
    required this.fixedNote,
    required this.voices,
  });

  /// flags (uint16, little-endian). Test with [genmidiFlagFixed] /
  /// [genmidiFlag2Voice].
  final int flags;

  /// Fine tuning value (`fine_tuning`).
  final int fineTuning;

  /// Fixed note (`fixed_note`), used when [isFixedPitch] is true.
  final int fixedNote;

  /// The two voices (`voices[2]`). Voice 1 is only used by 2-voice instruments.
  final List<GenMidiVoice> voices;

  /// True if this is a fixed-pitch instrument (flags & GENMIDI_FLAG_FIXED).
  bool get isFixedPitch => (flags & genmidiFlagFixed) != 0;

  /// True if this is a double-voice (OPL3) instrument (flags & GENMIDI_FLAG_2VOICE).
  bool get isDoubleVoice => (flags & genmidiFlag2Voice) != 0;

  static GenMidiInstr _read(ByteData d, int offset) {
    return GenMidiInstr(
      flags: d.getUint16(offset, Endian.little),
      fineTuning: d.getUint8(offset + 2),
      fixedNote: d.getUint8(offset + 3),
      voices: <GenMidiVoice>[
        GenMidiVoice._read(d, offset + 4),
        GenMidiVoice._read(d, offset + 4 + _voiceSize),
      ],
    );
  }
}

/// Thrown when a GENMIDI lump is too small to parse.
class GenMidiException implements Exception {
  GenMidiException(this.message);
  final String message;
  @override
  String toString() => 'GenMidiException: $message';
}

/// Parsed GENMIDI instrument bank. Holds all 175 instruments
/// (128 melodic + 47 percussion), mirroring `main_instrs` /
/// `percussion_instrs` in i_oplmusic.c.
class GenMidi {
  GenMidi._(this.magicValid, this._instruments);

  /// True if the lump began with the "#OPL_II#" magic. DMX itself ignores the
  /// header, so parsing succeeds even when this is false.
  final bool magicValid;

  final List<GenMidiInstr> _instruments;

  /// Total number of instruments (always [genmidiNumInstrs] +
  /// [genmidiNumPercussion] = 175 on success).
  int get numInstruments => _instruments.length;

  /// Parse the GENMIDI lump. Reads 175 packed instrument entries beginning
  /// after the 8-byte header.
  static GenMidi parse(Uint8List lump) {
    const int total = genmidiNumInstrs + genmidiNumPercussion; // 175
    final int needed = _headerSize + total * _instrSize;
    if (lump.length < needed) {
      throw GenMidiException(
        'GENMIDI lump too small: ${lump.length} < $needed bytes',
      );
    }

    bool magicValid = true;
    for (int i = 0; i < _headerSize; i++) {
      if (lump[i] != genmidiHeader.codeUnitAt(i)) {
        magicValid = false;
        break;
      }
    }

    final ByteData d = ByteData.sublistView(lump);
    final List<GenMidiInstr> instruments = <GenMidiInstr>[];
    int offset = _headerSize; // main_instrs = lump + strlen(GENMIDI_HEADER)
    for (int i = 0; i < total; i++) {
      instruments.add(GenMidiInstr._read(d, offset));
      offset += _instrSize;
    }

    return GenMidi._(magicValid, instruments);
  }

  /// The instrument at index [i] (0..174): 0..127 melodic, 128..174 percussion.
  GenMidiInstr instrument(int i) => _instruments[i];

  /// The melodic instrument for MIDI program [program] (0..127).
  /// Mirrors `main_instrs[program]`.
  GenMidiInstr melodic(int program) => _instruments[program];

  /// The percussion instrument for MIDI [note] (35..81) on channel 9.
  /// Mirrors `percussion_instrs[key - 35]` from KeyOnEvent. Throws if the note
  /// is outside the valid percussion range.
  GenMidiInstr percussion(int note) {
    if (note < 35 || note > 81) {
      throw GenMidiException('Percussion note out of range: $note (35..81)');
    }
    return _instruments[genmidiNumInstrs + (note - 35)];
  }
}
