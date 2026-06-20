// Nuked OPL3 emulator — faithful pure Dart port to pure Dart.
//
// Ported from Nuked-OPL3 (opl3.c / opl3.h), version 1.8.
// Copyright (C) 2013-2020 Nuke.YKT
//
// Original C is licensed under the GNU LGPL v2.1 (or later). This Dart port
// preserves the exact integer math (int16/int32/uint8/uint16 semantics),
// table values, register decoding, envelope/phase generators, 4-op/2-op
// connections, rhythm mode, tremolo/vibrato, the exp/logsin ROMs, and the
// OPL3L resampler (rateratio/samplecnt). It exposes a stable interface for a
// music player driver.
//
// Integer-width notes:
//   * C `int16_t`/`uint16_t`/`uint8_t`/`uint32_t` overflow & wrap are
//     replicated by masking. Helpers `_i16`, `_u16`, `_u8` do the truncation.
//   * Pointer-based modulation/output routing in the C (int16_t* mod,
//     uint8_t* trem, int16_t* out[4]) is modeled with closures (`_IntRef`)
//     that read the current value at dereference time — bit-identical.

import 'dart:typed_data';

/// Reads an integer value at "dereference" time, mirroring a C pointer.
typedef _IntRef = int Function();

// RSM_FRAC
const int _rsmFrac = 10;

// Channel types
const int _ch2op = 0;
const int _ch4op = 1;
const int _ch4op2 = 2;
const int _chDrum = 3;

// Envelope key types
const int _egkNorm = 0x01;
const int _egkDrum = 0x02;

// Envelope gen num
const int _egNumAttack = 0;
const int _egNumDecay = 1;
const int _egNumSustain = 2;
const int _egNumRelease = 3;

// logsin table
const List<int> _logsinrom = <int>[
  0x859, 0x6c3, 0x607, 0x58b, 0x52e, 0x4e4, 0x4a6, 0x471, //
  0x443, 0x41a, 0x3f5, 0x3d3, 0x3b5, 0x398, 0x37e, 0x365,
  0x34e, 0x339, 0x324, 0x311, 0x2ff, 0x2ed, 0x2dc, 0x2cd,
  0x2bd, 0x2af, 0x2a0, 0x293, 0x286, 0x279, 0x26d, 0x261,
  0x256, 0x24b, 0x240, 0x236, 0x22c, 0x222, 0x218, 0x20f,
  0x206, 0x1fd, 0x1f5, 0x1ec, 0x1e4, 0x1dc, 0x1d4, 0x1cd,
  0x1c5, 0x1be, 0x1b7, 0x1b0, 0x1a9, 0x1a2, 0x19b, 0x195,
  0x18f, 0x188, 0x182, 0x17c, 0x177, 0x171, 0x16b, 0x166,
  0x160, 0x15b, 0x155, 0x150, 0x14b, 0x146, 0x141, 0x13c,
  0x137, 0x133, 0x12e, 0x129, 0x125, 0x121, 0x11c, 0x118,
  0x114, 0x10f, 0x10b, 0x107, 0x103, 0x0ff, 0x0fb, 0x0f8,
  0x0f4, 0x0f0, 0x0ec, 0x0e9, 0x0e5, 0x0e2, 0x0de, 0x0db,
  0x0d7, 0x0d4, 0x0d1, 0x0cd, 0x0ca, 0x0c7, 0x0c4, 0x0c1,
  0x0be, 0x0bb, 0x0b8, 0x0b5, 0x0b2, 0x0af, 0x0ac, 0x0a9,
  0x0a7, 0x0a4, 0x0a1, 0x09f, 0x09c, 0x099, 0x097, 0x094,
  0x092, 0x08f, 0x08d, 0x08a, 0x088, 0x086, 0x083, 0x081,
  0x07f, 0x07d, 0x07a, 0x078, 0x076, 0x074, 0x072, 0x070,
  0x06e, 0x06c, 0x06a, 0x068, 0x066, 0x064, 0x062, 0x060,
  0x05e, 0x05c, 0x05b, 0x059, 0x057, 0x055, 0x053, 0x052,
  0x050, 0x04e, 0x04d, 0x04b, 0x04a, 0x048, 0x046, 0x045,
  0x043, 0x042, 0x040, 0x03f, 0x03e, 0x03c, 0x03b, 0x039,
  0x038, 0x037, 0x035, 0x034, 0x033, 0x031, 0x030, 0x02f,
  0x02e, 0x02d, 0x02b, 0x02a, 0x029, 0x028, 0x027, 0x026,
  0x025, 0x024, 0x023, 0x022, 0x021, 0x020, 0x01f, 0x01e,
  0x01d, 0x01c, 0x01b, 0x01a, 0x019, 0x018, 0x017, 0x017,
  0x016, 0x015, 0x014, 0x014, 0x013, 0x012, 0x011, 0x011,
  0x010, 0x00f, 0x00f, 0x00e, 0x00d, 0x00d, 0x00c, 0x00c,
  0x00b, 0x00a, 0x00a, 0x009, 0x009, 0x008, 0x008, 0x007,
  0x007, 0x007, 0x006, 0x006, 0x005, 0x005, 0x005, 0x004,
  0x004, 0x004, 0x003, 0x003, 0x003, 0x002, 0x002, 0x002,
  0x002, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001,
  0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000,
];

// exp table
const List<int> _exprom = <int>[
  0x7fa, 0x7f5, 0x7ef, 0x7ea, 0x7e4, 0x7df, 0x7da, 0x7d4, //
  0x7cf, 0x7c9, 0x7c4, 0x7bf, 0x7b9, 0x7b4, 0x7ae, 0x7a9,
  0x7a4, 0x79f, 0x799, 0x794, 0x78f, 0x78a, 0x784, 0x77f,
  0x77a, 0x775, 0x770, 0x76a, 0x765, 0x760, 0x75b, 0x756,
  0x751, 0x74c, 0x747, 0x742, 0x73d, 0x738, 0x733, 0x72e,
  0x729, 0x724, 0x71f, 0x71a, 0x715, 0x710, 0x70b, 0x706,
  0x702, 0x6fd, 0x6f8, 0x6f3, 0x6ee, 0x6e9, 0x6e5, 0x6e0,
  0x6db, 0x6d6, 0x6d2, 0x6cd, 0x6c8, 0x6c4, 0x6bf, 0x6ba,
  0x6b5, 0x6b1, 0x6ac, 0x6a8, 0x6a3, 0x69e, 0x69a, 0x695,
  0x691, 0x68c, 0x688, 0x683, 0x67f, 0x67a, 0x676, 0x671,
  0x66d, 0x668, 0x664, 0x65f, 0x65b, 0x657, 0x652, 0x64e,
  0x649, 0x645, 0x641, 0x63c, 0x638, 0x634, 0x630, 0x62b,
  0x627, 0x623, 0x61e, 0x61a, 0x616, 0x612, 0x60e, 0x609,
  0x605, 0x601, 0x5fd, 0x5f9, 0x5f5, 0x5f0, 0x5ec, 0x5e8,
  0x5e4, 0x5e0, 0x5dc, 0x5d8, 0x5d4, 0x5d0, 0x5cc, 0x5c8,
  0x5c4, 0x5c0, 0x5bc, 0x5b8, 0x5b4, 0x5b0, 0x5ac, 0x5a8,
  0x5a4, 0x5a0, 0x59c, 0x599, 0x595, 0x591, 0x58d, 0x589,
  0x585, 0x581, 0x57e, 0x57a, 0x576, 0x572, 0x56f, 0x56b,
  0x567, 0x563, 0x560, 0x55c, 0x558, 0x554, 0x551, 0x54d,
  0x549, 0x546, 0x542, 0x53e, 0x53b, 0x537, 0x534, 0x530,
  0x52c, 0x529, 0x525, 0x522, 0x51e, 0x51b, 0x517, 0x514,
  0x510, 0x50c, 0x509, 0x506, 0x502, 0x4ff, 0x4fb, 0x4f8,
  0x4f4, 0x4f1, 0x4ed, 0x4ea, 0x4e7, 0x4e3, 0x4e0, 0x4dc,
  0x4d9, 0x4d6, 0x4d2, 0x4cf, 0x4cc, 0x4c8, 0x4c5, 0x4c2,
  0x4be, 0x4bb, 0x4b8, 0x4b5, 0x4b1, 0x4ae, 0x4ab, 0x4a8,
  0x4a4, 0x4a1, 0x49e, 0x49b, 0x498, 0x494, 0x491, 0x48e,
  0x48b, 0x488, 0x485, 0x482, 0x47e, 0x47b, 0x478, 0x475,
  0x472, 0x46f, 0x46c, 0x469, 0x466, 0x463, 0x460, 0x45d,
  0x45a, 0x457, 0x454, 0x451, 0x44e, 0x44b, 0x448, 0x445,
  0x442, 0x43f, 0x43c, 0x439, 0x436, 0x433, 0x430, 0x42d,
  0x42a, 0x428, 0x425, 0x422, 0x41f, 0x41c, 0x419, 0x416,
  0x414, 0x411, 0x40e, 0x40b, 0x408, 0x406, 0x403, 0x400,
];

// freq mult table multiplied by 2
const List<int> _mt = <int>[
  1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30,
];

// ksl table
const List<int> _kslrom = <int>[
  0, 32, 40, 45, 48, 51, 53, 55, 56, 58, 59, 60, 61, 62, 63, 64,
];

const List<int> _kslshift = <int>[8, 1, 2, 0];

// envelope generator constants
const List<List<int>> _egIncstep = <List<int>>[
  <int>[0, 0, 0, 0],
  <int>[1, 0, 0, 0],
  <int>[1, 0, 1, 0],
  <int>[1, 1, 1, 0],
];

// address decoding
const List<int> _adSlot = <int>[
  0, 1, 2, 3, 4, 5, -1, -1, 6, 7, 8, 9, 10, 11, -1, -1, //
  12, 13, 14, 15, 16, 17, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
];

const List<int> _chSlot = <int>[
  0, 1, 2, 6, 7, 8, 12, 13, 14, 18, 19, 20, 24, 25, 26, 30, 31, 32,
];

// ---------------------------------------------------------------------------
// Integer width helpers (replicate C truncation/sign semantics).
// ---------------------------------------------------------------------------

int _u8(int v) => v & 0xff;
int _u16(int v) => v & 0xffff;

/// Truncate to signed 16-bit, matching C `(int16_t)` cast.
int _i16(int v) {
  v &= 0xffff;
  if (v >= 0x8000) {
    v -= 0x10000;
  }
  return v;
}

const int _oplWritebufSize = 1024;
const int _oplWritebufDelay = 2;

// Some FM channels output one sample later on the left side (quirk, default on
// since STEREOEXT is disabled).
const bool _quirkChannelSampleDelay = true;

class _Slot {
  _Slot(this.chip, this.slotNum);

  final Opl3 chip;
  late _Channel channel;

  int out = 0; // int16_t
  int fbmod = 0; // int16_t
  // mod: int16_t* — read current modulation value at dereference time.
  late _IntRef mod;
  int prout = 0; // int16_t
  int egRout = 0; // uint16_t
  int egOut = 0; // uint16_t
  int egInc = 0; // uint8_t
  int egGen = 0; // uint8_t
  int egRate = 0; // uint8_t
  int egKsl = 0; // uint8_t
  // trem: uint8_t* — &chip.tremolo (real) or &chip.zeromod (always 0).
  late _IntRef trem;
  int regVib = 0; // uint8_t
  int regType = 0; // uint8_t
  int regKsr = 0; // uint8_t
  int regMult = 0; // uint8_t
  int regKsl = 0; // uint8_t
  int regTl = 0; // uint8_t
  int regAr = 0; // uint8_t
  int regDr = 0; // uint8_t
  int regSl = 0; // uint8_t
  int regRr = 0; // uint8_t
  int regWf = 0; // uint8_t
  int key = 0; // uint8_t
  int pgReset = 0; // uint32_t
  int pgPhase = 0; // uint32_t
  int pgPhaseOut = 0; // uint16_t
  int slotNum; // uint8_t
}

class _Channel {
  _Channel(this.chip, this.chNum);

  final Opl3 chip;
  final List<_Slot?> _slotz = List<_Slot?>.filled(2, null, growable: false);
  // Non-null view: entries are always assigned during Opl3.reset() before use.
  late final _SlotzView slotz = _SlotzView(_slotz);
  late _Channel pair;

  // out[4]: int16_t* each — read at dereference time.
  final List<_IntRef> out = List<_IntRef>.filled(4, _zero, growable: false);

  int chtype = 0; // uint8_t
  int fNum = 0; // uint16_t
  int block = 0; // uint8_t
  int fb = 0; // uint8_t
  int con = 0; // uint8_t
  int alg = 0; // uint8_t
  int ksv = 0; // uint8_t
  int cha = 0; // uint16_t
  int chb = 0; // uint16_t
  int chc = 0; // uint16_t
  int chd = 0; // uint16_t
  int chNum; // uint8_t

  static int _zero() => 0;
}

/// Non-null indexed view over a `_Channel`'s slot pair. The backing entries are
/// assigned during reset before any generation; reading an unassigned slot is a
/// programming error and throws.
class _SlotzView {
  _SlotzView(this._backing);
  final List<_Slot?> _backing;
  _Slot operator [](int i) => _backing[i]!;
  void operator []=(int i, _Slot v) => _backing[i] = v;
}

class _WriteBuf {
  int time = 0; // uint64_t
  int reg = 0; // uint16_t
  int data = 0; // uint8_t
}

/// Pure-Dart Nuked-OPL3 FM synthesis chip.
///
/// Stable interface for the music player:
///   * [Opl3] — construct, then call [reset].
///   * [reset] — initialize at the target output sample rate (Hz). Native chip
///     rate is 49716 Hz; the internal OPL3L resampler converts.
///   * [writeReg] — immediate register write.
///   * [writeRegBuffered] — time-delayed (buffered) register write.
///   * [generate] — produce one stereo (L,R) resampled frame into `out2`.
///   * [generateStream] — produce `numFrames` interleaved stereo frames.
///
/// Output is signed 16-bit stereo.
class Opl3 {
  Opl3();

  final List<_Channel> _chan = <_Channel>[];
  final List<_Slot> _slotArr = <_Slot>[];

  int timer = 0; // uint16_t
  int egTimer = 0; // uint64_t
  int egTimerrem = 0; // uint8_t
  int egState = 0; // uint8_t
  int egAdd = 0; // uint8_t
  int egTimerLo = 0; // uint8_t
  int newm = 0; // uint8_t
  int nts = 0; // uint8_t
  int rhy = 0; // uint8_t
  int vibpos = 0; // uint8_t
  int vibshift = 0; // uint8_t
  int tremolo = 0; // uint8_t
  int tremolopos = 0; // uint8_t
  int tremoloshift = 0; // uint8_t
  int noise = 0; // uint32_t
  int zeromod = 0; // int16_t (always 0)
  final List<int> mixbuff = List<int>.filled(4, 0); // int32_t[4]
  int rmHhBit2 = 0; // uint8_t
  int rmHhBit3 = 0; // uint8_t
  int rmHhBit7 = 0; // uint8_t
  int rmHhBit8 = 0; // uint8_t
  int rmTcBit3 = 0; // uint8_t
  int rmTcBit5 = 0; // uint8_t

  // OPL3L resampler
  int rateratio = 0; // int32_t
  int samplecnt = 0; // int32_t
  final List<int> oldsamples = List<int>.filled(4, 0); // int16_t[4]
  final List<int> samples = List<int>.filled(4, 0); // int16_t[4]

  int writebufSamplecnt = 0; // uint64_t
  int writebufCur = 0; // uint32_t
  int writebufLast = 0; // uint32_t
  int writebufLasttime = 0; // uint64_t
  late List<_WriteBuf> _writebufArr;

  /// Testing-only access to the ROM tables, to guard against transcription
  /// errors. Returns copies; not part of the runtime audio path.
  static List<int> debugLogsinRom() => List<int>.unmodifiable(_logsinrom);
  static List<int> debugExpRom() => List<int>.unmodifiable(_exprom);
  static List<int> debugMultTable() => List<int>.unmodifiable(_mt);

  // ---- _IntRef helpers (model C pointers) -----------------------------------

  _IntRef _refZeromod() => () => zeromod;
  _IntRef _refTremolo() => () => tremolo; // uint8_t* &tremolo
  // &zeromod read as uint8_t* — zeromod is always 0, so value is 0.
  _IntRef _refZeromodTrem() => () => zeromod & 0xff;
  _IntRef _refSlotOut(_Slot s) => () => s.out;
  _IntRef _refSlotFbmod(_Slot s) => () => s.fbmod;

  // ===========================================================================
  // Envelope generator
  // ===========================================================================

  static int _envelopeCalcExp(int level) {
    if (level > 0x1fff) {
      level = 0x1fff;
    }
    return _i16((_exprom[level & 0xff] << 1) >> (level >> 8));
  }

  static int _envelopeCalcSin0(int phase, int envelope) {
    int out = 0;
    int neg = 0;
    phase &= 0x3ff;
    if ((phase & 0x200) != 0) {
      neg = 0xffff;
    }
    if ((phase & 0x100) != 0) {
      out = _logsinrom[(phase & 0xff) ^ 0xff];
    } else {
      out = _logsinrom[phase & 0xff];
    }
    return _i16(_envelopeCalcExp(out + (envelope << 3)) ^ neg);
  }

  static int _envelopeCalcSin1(int phase, int envelope) {
    int out = 0;
    phase &= 0x3ff;
    if ((phase & 0x200) != 0) {
      out = 0x1000;
    } else if ((phase & 0x100) != 0) {
      out = _logsinrom[(phase & 0xff) ^ 0xff];
    } else {
      out = _logsinrom[phase & 0xff];
    }
    return _envelopeCalcExp(out + (envelope << 3));
  }

  static int _envelopeCalcSin2(int phase, int envelope) {
    int out = 0;
    phase &= 0x3ff;
    if ((phase & 0x100) != 0) {
      out = _logsinrom[(phase & 0xff) ^ 0xff];
    } else {
      out = _logsinrom[phase & 0xff];
    }
    return _envelopeCalcExp(out + (envelope << 3));
  }

  static int _envelopeCalcSin3(int phase, int envelope) {
    int out = 0;
    phase &= 0x3ff;
    if ((phase & 0x100) != 0) {
      out = 0x1000;
    } else {
      out = _logsinrom[phase & 0xff];
    }
    return _envelopeCalcExp(out + (envelope << 3));
  }

  static int _envelopeCalcSin4(int phase, int envelope) {
    int out = 0;
    int neg = 0;
    phase &= 0x3ff;
    if ((phase & 0x300) == 0x100) {
      neg = 0xffff;
    }
    if ((phase & 0x200) != 0) {
      out = 0x1000;
    } else if ((phase & 0x80) != 0) {
      out = _logsinrom[((phase ^ 0xff) << 1) & 0xff];
    } else {
      out = _logsinrom[(phase << 1) & 0xff];
    }
    return _i16(_envelopeCalcExp(out + (envelope << 3)) ^ neg);
  }

  static int _envelopeCalcSin5(int phase, int envelope) {
    int out = 0;
    phase &= 0x3ff;
    if ((phase & 0x200) != 0) {
      out = 0x1000;
    } else if ((phase & 0x80) != 0) {
      out = _logsinrom[((phase ^ 0xff) << 1) & 0xff];
    } else {
      out = _logsinrom[(phase << 1) & 0xff];
    }
    return _envelopeCalcExp(out + (envelope << 3));
  }

  static int _envelopeCalcSin6(int phase, int envelope) {
    int neg = 0;
    phase &= 0x3ff;
    if ((phase & 0x200) != 0) {
      neg = 0xffff;
    }
    return _i16(_envelopeCalcExp(envelope << 3) ^ neg);
  }

  static int _envelopeCalcSin7(int phase, int envelope) {
    int out = 0;
    int neg = 0;
    phase &= 0x3ff;
    if ((phase & 0x200) != 0) {
      neg = 0xffff;
      phase = (phase & 0x1ff) ^ 0x1ff;
    }
    out = phase << 3;
    return _i16(_envelopeCalcExp(out + (envelope << 3)) ^ neg);
  }

  static const List<int Function(int, int)> _envelopeSin =
      <int Function(int, int)>[
    _envelopeCalcSin0,
    _envelopeCalcSin1,
    _envelopeCalcSin2,
    _envelopeCalcSin3,
    _envelopeCalcSin4,
    _envelopeCalcSin5,
    _envelopeCalcSin6,
    _envelopeCalcSin7,
  ];

  static void _envelopeUpdateKsl(_Slot slot) {
    // int16_t ksl = (kslrom[f_num>>6] << 2) - ((0x08 - block) << 5);
    int ksl = _i16((_kslrom[slot.channel.fNum >> 6] << 2) -
        ((0x08 - slot.channel.block) << 5));
    if (ksl < 0) {
      ksl = 0;
    }
    slot.egKsl = _u8(ksl);
  }

  void _envelopeCalc(_Slot slot) {
    int nonzero;
    int rate;
    int rateHi;
    int rateLo;
    int regRate = 0;
    int ks;
    int egShift, shift;
    int egRout;
    int egInc;
    int egOff;
    int reset = 0;
    slot.egOut = _u16(slot.egRout +
        (slot.regTl << 2) +
        (slot.egKsl >> _kslshift[slot.regKsl]) +
        slot.trem());
    if (slot.key != 0 && slot.egGen == _egNumRelease) {
      reset = 1;
      regRate = slot.regAr;
    } else {
      switch (slot.egGen) {
        case _egNumAttack:
          regRate = slot.regAr;
          break;
        case _egNumDecay:
          regRate = slot.regDr;
          break;
        case _egNumSustain:
          if (slot.regType == 0) {
            regRate = slot.regRr;
          }
          break;
        case _egNumRelease:
          regRate = slot.regRr;
          break;
      }
    }
    slot.pgReset = reset;
    ks = slot.channel.ksv >> ((slot.regKsr ^ 1) << 1);
    nonzero = (regRate != 0) ? 1 : 0;
    rate = _u8(ks + (regRate << 2));
    rateHi = rate >> 2;
    rateLo = rate & 0x03;
    if ((rateHi & 0x10) != 0) {
      rateHi = 0x0f;
    }
    egShift = _u8(rateHi + egAdd);
    shift = 0;
    if (nonzero != 0) {
      if (rateHi < 12) {
        if (egState != 0) {
          switch (egShift) {
            case 12:
              shift = 1;
              break;
            case 13:
              shift = (rateLo >> 1) & 0x01;
              break;
            case 14:
              shift = rateLo & 0x01;
              break;
            default:
              break;
          }
        }
      } else {
        shift = _u8((rateHi & 0x03) + _egIncstep[rateLo][egTimerLo]);
        if ((shift & 0x04) != 0) {
          shift = 0x03;
        }
        if (shift == 0) {
          shift = egState;
        }
      }
    }
    egRout = slot.egRout;
    egInc = 0;
    egOff = 0;
    // Instant attack
    if (reset != 0 && rateHi == 0x0f) {
      egRout = 0x00;
    }
    // Envelope off
    if ((slot.egRout & 0x1f8) == 0x1f8) {
      egOff = 1;
    }
    if (slot.egGen != _egNumAttack && reset == 0 && egOff != 0) {
      egRout = 0x1ff;
    }
    switch (slot.egGen) {
      case _egNumAttack:
        if (slot.egRout == 0) {
          slot.egGen = _egNumDecay;
        } else if (slot.key != 0 && shift > 0 && rateHi != 0x0f) {
          egInc = _i16((~slot.egRout & 0xffff) >> (4 - shift));
        }
        break;
      case _egNumDecay:
        if ((slot.egRout >> 4) == slot.regSl) {
          slot.egGen = _egNumSustain;
        } else if (egOff == 0 && reset == 0 && shift > 0) {
          egInc = 1 << (shift - 1);
        }
        break;
      case _egNumSustain:
      case _egNumRelease:
        if (egOff == 0 && reset == 0 && shift > 0) {
          egInc = 1 << (shift - 1);
        }
        break;
    }
    slot.egRout = (egRout + egInc) & 0x1ff;
    // Key off
    if (reset != 0) {
      slot.egGen = _egNumAttack;
    }
    if (slot.key == 0) {
      slot.egGen = _egNumRelease;
    }
  }

  static void _envelopeKeyOn(_Slot slot, int type) {
    slot.key |= type;
  }

  static void _envelopeKeyOff(_Slot slot, int type) {
    slot.key &= (~type) & 0xff;
  }

  // ===========================================================================
  // Phase Generator
  // ===========================================================================

  void _phaseGenerate(_Slot slot) {
    int fNum;
    int basefreq;
    int rmXor, nBit;
    int noiseLocal;
    int phase;

    fNum = slot.channel.fNum;
    if (slot.regVib != 0) {
      int range; // int8_t
      int vibpos;

      range = (fNum >> 7) & 7;
      vibpos = this.vibpos;

      if ((vibpos & 3) == 0) {
        range = 0;
      } else if ((vibpos & 1) != 0) {
        range >>= 1;
      }
      range >>= vibshift;

      if ((vibpos & 4) != 0) {
        range = -range;
      }
      fNum += range;
      fNum &= 0xffff; // f_num is uint16_t
    }
    basefreq = ((fNum << slot.channel.block) >> 1) & 0xffffffff;
    phase = _u16(slot.pgPhase >> 9);
    if (slot.pgReset != 0) {
      slot.pgPhase = 0;
    }
    slot.pgPhase =
        (slot.pgPhase + ((basefreq * _mt[slot.regMult]) >> 1)) & 0xffffffff;
    // Rhythm mode
    noiseLocal = noise;
    slot.pgPhaseOut = phase;
    if (slot.slotNum == 13) {
      // hh
      rmHhBit2 = (phase >> 2) & 1;
      rmHhBit3 = (phase >> 3) & 1;
      rmHhBit7 = (phase >> 7) & 1;
      rmHhBit8 = (phase >> 8) & 1;
    }
    if (slot.slotNum == 17 && (rhy & 0x20) != 0) {
      // tc
      rmTcBit3 = (phase >> 3) & 1;
      rmTcBit5 = (phase >> 5) & 1;
    }
    if ((rhy & 0x20) != 0) {
      rmXor = (rmHhBit2 ^ rmHhBit7) |
          (rmHhBit3 ^ rmTcBit5) |
          (rmTcBit3 ^ rmTcBit5);
      switch (slot.slotNum) {
        case 13: // hh
          slot.pgPhaseOut = _u16(rmXor << 9);
          if ((rmXor ^ (noiseLocal & 1)) != 0) {
            slot.pgPhaseOut |= 0xd0;
          } else {
            slot.pgPhaseOut |= 0x34;
          }
          break;
        case 16: // sd
          slot.pgPhaseOut = _u16(
              (rmHhBit8 << 9) | ((rmHhBit8 ^ (noiseLocal & 1)) << 8));
          break;
        case 17: // tc
          slot.pgPhaseOut = _u16((rmXor << 9) | 0x80);
          break;
        default:
          break;
      }
    }
    nBit = ((noiseLocal >> 14) ^ noiseLocal) & 0x01;
    noise = ((noiseLocal >> 1) | (nBit << 22)) & 0xffffffff;
  }

  // ===========================================================================
  // Slot
  // ===========================================================================

  void _slotWrite20(_Slot slot, int data) {
    if (((data >> 7) & 0x01) != 0) {
      slot.trem = _refTremolo();
    } else {
      slot.trem = _refZeromodTrem();
    }
    slot.regVib = (data >> 6) & 0x01;
    slot.regType = (data >> 5) & 0x01;
    slot.regKsr = (data >> 4) & 0x01;
    slot.regMult = data & 0x0f;
  }

  void _slotWrite40(_Slot slot, int data) {
    slot.regKsl = (data >> 6) & 0x03;
    slot.regTl = data & 0x3f;
    _envelopeUpdateKsl(slot);
  }

  void _slotWrite60(_Slot slot, int data) {
    slot.regAr = (data >> 4) & 0x0f;
    slot.regDr = data & 0x0f;
  }

  void _slotWrite80(_Slot slot, int data) {
    slot.regSl = (data >> 4) & 0x0f;
    if (slot.regSl == 0x0f) {
      slot.regSl = 0x1f;
    }
    slot.regRr = data & 0x0f;
  }

  void _slotWriteE0(_Slot slot, int data) {
    slot.regWf = data & 0x07;
    if (newm == 0x00) {
      slot.regWf &= 0x03;
    }
  }

  void _slotGenerate(_Slot slot) {
    slot.out = _envelopeSin[slot.regWf](
        _u16(slot.pgPhaseOut + slot.mod()), slot.egOut);
  }

  static void _slotCalcFb(_Slot slot) {
    if (slot.channel.fb != 0x00) {
      slot.fbmod = _i16((slot.prout + slot.out) >> (0x09 - slot.channel.fb));
    } else {
      slot.fbmod = 0;
    }
    slot.prout = slot.out;
  }

  // ===========================================================================
  // Channel
  // ===========================================================================

  void _channelUpdateRhythm(int data) {
    _Channel channel6;
    _Channel channel7;
    _Channel channel8;
    int chnum;

    rhy = data & 0x3f;
    if ((rhy & 0x20) != 0) {
      channel6 = _chan[6];
      channel7 = _chan[7];
      channel8 = _chan[8];
      channel6.out[0] = _refSlotOut(channel6.slotz[1]);
      channel6.out[1] = _refSlotOut(channel6.slotz[1]);
      channel6.out[2] = _refZeromod();
      channel6.out[3] = _refZeromod();
      channel7.out[0] = _refSlotOut(channel7.slotz[0]);
      channel7.out[1] = _refSlotOut(channel7.slotz[0]);
      channel7.out[2] = _refSlotOut(channel7.slotz[1]);
      channel7.out[3] = _refSlotOut(channel7.slotz[1]);
      channel8.out[0] = _refSlotOut(channel8.slotz[0]);
      channel8.out[1] = _refSlotOut(channel8.slotz[0]);
      channel8.out[2] = _refSlotOut(channel8.slotz[1]);
      channel8.out[3] = _refSlotOut(channel8.slotz[1]);
      for (chnum = 6; chnum < 9; chnum++) {
        _chan[chnum].chtype = _chDrum;
      }
      _channelSetupAlg(channel6);
      _channelSetupAlg(channel7);
      _channelSetupAlg(channel8);
      // hh
      if ((rhy & 0x01) != 0) {
        _envelopeKeyOn(channel7.slotz[0], _egkDrum);
      } else {
        _envelopeKeyOff(channel7.slotz[0], _egkDrum);
      }
      // tc
      if ((rhy & 0x02) != 0) {
        _envelopeKeyOn(channel8.slotz[1], _egkDrum);
      } else {
        _envelopeKeyOff(channel8.slotz[1], _egkDrum);
      }
      // tom
      if ((rhy & 0x04) != 0) {
        _envelopeKeyOn(channel8.slotz[0], _egkDrum);
      } else {
        _envelopeKeyOff(channel8.slotz[0], _egkDrum);
      }
      // sd
      if ((rhy & 0x08) != 0) {
        _envelopeKeyOn(channel7.slotz[1], _egkDrum);
      } else {
        _envelopeKeyOff(channel7.slotz[1], _egkDrum);
      }
      // bd
      if ((rhy & 0x10) != 0) {
        _envelopeKeyOn(channel6.slotz[0], _egkDrum);
        _envelopeKeyOn(channel6.slotz[1], _egkDrum);
      } else {
        _envelopeKeyOff(channel6.slotz[0], _egkDrum);
        _envelopeKeyOff(channel6.slotz[1], _egkDrum);
      }
    } else {
      for (chnum = 6; chnum < 9; chnum++) {
        _chan[chnum].chtype = _ch2op;
        _channelSetupAlg(_chan[chnum]);
        _envelopeKeyOff(_chan[chnum].slotz[0], _egkDrum);
        _envelopeKeyOff(_chan[chnum].slotz[1], _egkDrum);
      }
    }
  }

  void _channelWriteA0(_Channel channel, int data) {
    if (newm != 0 && channel.chtype == _ch4op2) {
      return;
    }
    channel.fNum = (channel.fNum & 0x300) | data;
    channel.ksv = _u8((channel.block << 1) |
        ((channel.fNum >> (0x09 - nts)) & 0x01));
    _envelopeUpdateKsl(channel.slotz[0]);
    _envelopeUpdateKsl(channel.slotz[1]);
    if (newm != 0 && channel.chtype == _ch4op) {
      channel.pair.fNum = channel.fNum;
      channel.pair.ksv = channel.ksv;
      _envelopeUpdateKsl(channel.pair.slotz[0]);
      _envelopeUpdateKsl(channel.pair.slotz[1]);
    }
  }

  void _channelWriteB0(_Channel channel, int data) {
    if (newm != 0 && channel.chtype == _ch4op2) {
      return;
    }
    channel.fNum = (channel.fNum & 0xff) | ((data & 0x03) << 8);
    channel.block = (data >> 2) & 0x07;
    channel.ksv = _u8((channel.block << 1) |
        ((channel.fNum >> (0x09 - nts)) & 0x01));
    _envelopeUpdateKsl(channel.slotz[0]);
    _envelopeUpdateKsl(channel.slotz[1]);
    if (newm != 0 && channel.chtype == _ch4op) {
      channel.pair.fNum = channel.fNum;
      channel.pair.block = channel.block;
      channel.pair.ksv = channel.ksv;
      _envelopeUpdateKsl(channel.pair.slotz[0]);
      _envelopeUpdateKsl(channel.pair.slotz[1]);
    }
  }

  void _channelSetupAlg(_Channel channel) {
    if (channel.chtype == _chDrum) {
      if (channel.chNum == 7 || channel.chNum == 8) {
        channel.slotz[0].mod = _refZeromod();
        channel.slotz[1].mod = _refZeromod();
        return;
      }
      switch (channel.alg & 0x01) {
        case 0x00:
          channel.slotz[0].mod = _refSlotFbmod(channel.slotz[0]);
          channel.slotz[1].mod = _refSlotOut(channel.slotz[0]);
          break;
        case 0x01:
          channel.slotz[0].mod = _refSlotFbmod(channel.slotz[0]);
          channel.slotz[1].mod = _refZeromod();
          break;
      }
      return;
    }
    if ((channel.alg & 0x08) != 0) {
      return;
    }
    if ((channel.alg & 0x04) != 0) {
      channel.pair.out[0] = _refZeromod();
      channel.pair.out[1] = _refZeromod();
      channel.pair.out[2] = _refZeromod();
      channel.pair.out[3] = _refZeromod();
      switch (channel.alg & 0x03) {
        case 0x00:
          channel.pair.slotz[0].mod = _refSlotFbmod(channel.pair.slotz[0]);
          channel.pair.slotz[1].mod = _refSlotOut(channel.pair.slotz[0]);
          channel.slotz[0].mod = _refSlotOut(channel.pair.slotz[1]);
          channel.slotz[1].mod = _refSlotOut(channel.slotz[0]);
          channel.out[0] = _refSlotOut(channel.slotz[1]);
          channel.out[1] = _refZeromod();
          channel.out[2] = _refZeromod();
          channel.out[3] = _refZeromod();
          break;
        case 0x01:
          channel.pair.slotz[0].mod = _refSlotFbmod(channel.pair.slotz[0]);
          channel.pair.slotz[1].mod = _refSlotOut(channel.pair.slotz[0]);
          channel.slotz[0].mod = _refZeromod();
          channel.slotz[1].mod = _refSlotOut(channel.slotz[0]);
          channel.out[0] = _refSlotOut(channel.pair.slotz[1]);
          channel.out[1] = _refSlotOut(channel.slotz[1]);
          channel.out[2] = _refZeromod();
          channel.out[3] = _refZeromod();
          break;
        case 0x02:
          channel.pair.slotz[0].mod = _refSlotFbmod(channel.pair.slotz[0]);
          channel.pair.slotz[1].mod = _refZeromod();
          channel.slotz[0].mod = _refSlotOut(channel.pair.slotz[1]);
          channel.slotz[1].mod = _refSlotOut(channel.slotz[0]);
          channel.out[0] = _refSlotOut(channel.pair.slotz[0]);
          channel.out[1] = _refSlotOut(channel.slotz[1]);
          channel.out[2] = _refZeromod();
          channel.out[3] = _refZeromod();
          break;
        case 0x03:
          channel.pair.slotz[0].mod = _refSlotFbmod(channel.pair.slotz[0]);
          channel.pair.slotz[1].mod = _refZeromod();
          channel.slotz[0].mod = _refSlotOut(channel.pair.slotz[1]);
          channel.slotz[1].mod = _refZeromod();
          channel.out[0] = _refSlotOut(channel.pair.slotz[0]);
          channel.out[1] = _refSlotOut(channel.slotz[0]);
          channel.out[2] = _refSlotOut(channel.slotz[1]);
          channel.out[3] = _refZeromod();
          break;
      }
    } else {
      switch (channel.alg & 0x01) {
        case 0x00:
          channel.slotz[0].mod = _refSlotFbmod(channel.slotz[0]);
          channel.slotz[1].mod = _refSlotOut(channel.slotz[0]);
          channel.out[0] = _refSlotOut(channel.slotz[1]);
          channel.out[1] = _refZeromod();
          channel.out[2] = _refZeromod();
          channel.out[3] = _refZeromod();
          break;
        case 0x01:
          channel.slotz[0].mod = _refSlotFbmod(channel.slotz[0]);
          channel.slotz[1].mod = _refZeromod();
          channel.out[0] = _refSlotOut(channel.slotz[0]);
          channel.out[1] = _refSlotOut(channel.slotz[1]);
          channel.out[2] = _refZeromod();
          channel.out[3] = _refZeromod();
          break;
      }
    }
  }

  void _channelUpdateAlg(_Channel channel) {
    channel.alg = channel.con;
    if (newm != 0) {
      if (channel.chtype == _ch4op) {
        channel.pair.alg =
            _u8(0x04 | (channel.con << 1) | (channel.pair.con));
        channel.alg = 0x08;
        _channelSetupAlg(channel.pair);
      } else if (channel.chtype == _ch4op2) {
        channel.alg = _u8(0x04 | (channel.pair.con << 1) | (channel.con));
        channel.pair.alg = 0x08;
        _channelSetupAlg(channel);
      } else {
        _channelSetupAlg(channel);
      }
    } else {
      _channelSetupAlg(channel);
    }
  }

  void _channelWriteC0(_Channel channel, int data) {
    channel.fb = (data & 0x0e) >> 1;
    channel.con = data & 0x01;
    _channelUpdateAlg(channel);
    if (newm != 0) {
      channel.cha = ((data >> 4) & 0x01) != 0 ? 0xffff : 0;
      channel.chb = ((data >> 5) & 0x01) != 0 ? 0xffff : 0;
      channel.chc = ((data >> 6) & 0x01) != 0 ? 0xffff : 0;
      channel.chd = ((data >> 7) & 0x01) != 0 ? 0xffff : 0;
    } else {
      channel.cha = channel.chb = 0xffff;
      channel.chc = channel.chd = 0;
    }
  }

  void _channelKeyOn(_Channel channel) {
    if (newm != 0) {
      if (channel.chtype == _ch4op) {
        _envelopeKeyOn(channel.slotz[0], _egkNorm);
        _envelopeKeyOn(channel.slotz[1], _egkNorm);
        _envelopeKeyOn(channel.pair.slotz[0], _egkNorm);
        _envelopeKeyOn(channel.pair.slotz[1], _egkNorm);
      } else if (channel.chtype == _ch2op || channel.chtype == _chDrum) {
        _envelopeKeyOn(channel.slotz[0], _egkNorm);
        _envelopeKeyOn(channel.slotz[1], _egkNorm);
      }
    } else {
      _envelopeKeyOn(channel.slotz[0], _egkNorm);
      _envelopeKeyOn(channel.slotz[1], _egkNorm);
    }
  }

  void _channelKeyOff(_Channel channel) {
    if (newm != 0) {
      if (channel.chtype == _ch4op) {
        _envelopeKeyOff(channel.slotz[0], _egkNorm);
        _envelopeKeyOff(channel.slotz[1], _egkNorm);
        _envelopeKeyOff(channel.pair.slotz[0], _egkNorm);
        _envelopeKeyOff(channel.pair.slotz[1], _egkNorm);
      } else if (channel.chtype == _ch2op || channel.chtype == _chDrum) {
        _envelopeKeyOff(channel.slotz[0], _egkNorm);
        _envelopeKeyOff(channel.slotz[1], _egkNorm);
      }
    } else {
      _envelopeKeyOff(channel.slotz[0], _egkNorm);
      _envelopeKeyOff(channel.slotz[1], _egkNorm);
    }
  }

  void _channelSet4Op(int data) {
    int bit;
    int chnum;
    for (bit = 0; bit < 6; bit++) {
      chnum = bit;
      if (bit >= 3) {
        chnum += 9 - 3;
      }
      if (((data >> bit) & 0x01) != 0) {
        _chan[chnum].chtype = _ch4op;
        _chan[chnum + 3].chtype = _ch4op2;
        _channelUpdateAlg(_chan[chnum]);
      } else {
        _chan[chnum].chtype = _ch2op;
        _chan[chnum + 3].chtype = _ch2op;
        _channelUpdateAlg(_chan[chnum]);
        _channelUpdateAlg(_chan[chnum + 3]);
      }
    }
  }

  static int _clipSample(int sample) {
    if (sample > 32767) {
      sample = 32767;
    } else if (sample < -32768) {
      sample = -32768;
    }
    return _i16(sample);
  }

  void _processSlot(_Slot slot) {
    _slotCalcFb(slot);
    _envelopeCalc(slot);
    _phaseGenerate(slot);
    _slotGenerate(slot);
  }

  // ===========================================================================
  // Generation
  // ===========================================================================

  void _generate4Ch(List<int> buf4) {
    _Channel channelLocal;
    _WriteBuf writebufLocal;
    List<_IntRef> out;
    final List<int> mix = <int>[0, 0];
    int ii;
    int accm;
    int shift = 0;

    buf4[1] = _clipSample(mixbuff[1]);
    buf4[3] = _clipSample(mixbuff[3]);

    final int firstLoopEnd = _quirkChannelSampleDelay ? 15 : 36;
    for (ii = 0; ii < firstLoopEnd; ii++) {
      _processSlot(_slotArr[ii]);
    }

    mix[0] = mix[1] = 0;
    for (ii = 0; ii < 18; ii++) {
      channelLocal = _chan[ii];
      out = channelLocal.out;
      accm = _i16(out[0]() + out[1]() + out[2]() + out[3]());
      // mix[0] += (int16_t)(accm & channel->cha)
      mix[0] += _i16(accm & channelLocal.cha);
      mix[1] += _i16(accm & channelLocal.chc);
    }
    mixbuff[0] = _i32(mix[0]);
    mixbuff[2] = _i32(mix[1]);

    if (_quirkChannelSampleDelay) {
      for (ii = 15; ii < 18; ii++) {
        _processSlot(_slotArr[ii]);
      }
    }

    buf4[0] = _clipSample(mixbuff[0]);
    buf4[2] = _clipSample(mixbuff[2]);

    if (_quirkChannelSampleDelay) {
      for (ii = 18; ii < 33; ii++) {
        _processSlot(_slotArr[ii]);
      }
    }

    mix[0] = mix[1] = 0;
    for (ii = 0; ii < 18; ii++) {
      channelLocal = _chan[ii];
      out = channelLocal.out;
      accm = _i16(out[0]() + out[1]() + out[2]() + out[3]());
      mix[0] += _i16(accm & channelLocal.chb);
      mix[1] += _i16(accm & channelLocal.chd);
    }
    mixbuff[1] = _i32(mix[0]);
    mixbuff[3] = _i32(mix[1]);

    if (_quirkChannelSampleDelay) {
      for (ii = 33; ii < 36; ii++) {
        _processSlot(_slotArr[ii]);
      }
    }

    if ((timer & 0x3f) == 0x3f) {
      tremolopos = (tremolopos + 1) % 210;
    }
    if (tremolopos < 105) {
      tremolo = tremolopos >> tremoloshift;
    } else {
      tremolo = (210 - tremolopos) >> tremoloshift;
    }

    if ((timer & 0x3ff) == 0x3ff) {
      vibpos = (vibpos + 1) & 7;
    }

    timer = _u16(timer + 1);

    if (egState != 0) {
      while (shift < 13 && ((egTimer >> shift) & 1) == 0) {
        shift++;
      }
      if (shift > 12) {
        egAdd = 0;
      } else {
        egAdd = shift + 1;
      }
      egTimerLo = egTimer & 0x3;
    }

    if (egTimerrem != 0 || egState != 0) {
      if (egTimer == 0xfffffffff) {
        egTimer = 0;
        egTimerrem = 1;
      } else {
        egTimer++;
        egTimerrem = 0;
      }
    }

    egState ^= 1;

    while (true) {
      writebufLocal = _writebufArr[writebufCur];
      if (!(writebufLocal.time <= writebufSamplecnt)) {
        break;
      }
      if ((writebufLocal.reg & 0x200) == 0) {
        break;
      }
      writebufLocal.reg &= 0x1ff;
      writeReg(writebufLocal.reg, writebufLocal.data);
      writebufCur = (writebufCur + 1) % _oplWritebufSize;
    }
    writebufSamplecnt++;
  }

  void _generate(List<int> buf) {
    final List<int> samples4 = <int>[0, 0, 0, 0];
    _generate4Ch(samples4);
    buf[0] = samples4[0];
    buf[1] = samples4[1];
  }

  void _generate4ChResampled(List<int> buf4) {
    while (samplecnt >= rateratio) {
      oldsamples[0] = samples[0];
      oldsamples[1] = samples[1];
      oldsamples[2] = samples[2];
      oldsamples[3] = samples[3];
      _generate4Ch(samples);
      samplecnt -= rateratio;
    }
    buf4[0] = _i16((oldsamples[0] * (rateratio - samplecnt) +
            samples[0] * samplecnt) ~/
        rateratio);
    buf4[1] = _i16((oldsamples[1] * (rateratio - samplecnt) +
            samples[1] * samplecnt) ~/
        rateratio);
    buf4[2] = _i16((oldsamples[2] * (rateratio - samplecnt) +
            samples[2] * samplecnt) ~/
        rateratio);
    buf4[3] = _i16((oldsamples[3] * (rateratio - samplecnt) +
            samples[3] * samplecnt) ~/
        rateratio);
    samplecnt += 1 << _rsmFrac;
  }

  void _generateResampled(List<int> buf) {
    final List<int> samples4 = <int>[0, 0, 0, 0];
    _generate4ChResampled(samples4);
    buf[0] = samples4[0];
    buf[1] = samples4[1];
  }

  // ===========================================================================
  // Public interface
  // ===========================================================================

  /// Initialize/reset the chip for the given output [sampleRate] (Hz).
  ///
  /// The chip natively runs at 49716 Hz; the OPL3L resampler (rateratio /
  /// samplecnt) converts to [sampleRate] exactly as Nuked does.
  void reset(int sampleRate) {
    // memset(chip, 0, sizeof(opl3_chip)) — rebuild all state from scratch.
    _chan.clear();
    _slotArr.clear();
    timer = 0;
    egTimer = 0;
    egTimerrem = 0;
    egState = 0;
    egAdd = 0;
    egTimerLo = 0;
    newm = 0;
    nts = 0;
    rhy = 0;
    vibpos = 0;
    vibshift = 0;
    tremolo = 0;
    tremolopos = 0;
    tremoloshift = 0;
    noise = 0;
    zeromod = 0;
    mixbuff[0] = mixbuff[1] = mixbuff[2] = mixbuff[3] = 0;
    rmHhBit2 = rmHhBit3 = rmHhBit7 = rmHhBit8 = 0;
    rmTcBit3 = rmTcBit5 = 0;
    rateratio = 0;
    samplecnt = 0;
    oldsamples[0] = oldsamples[1] = oldsamples[2] = oldsamples[3] = 0;
    samples[0] = samples[1] = samples[2] = samples[3] = 0;
    writebufSamplecnt = 0;
    writebufCur = 0;
    writebufLast = 0;
    writebufLasttime = 0;
    _writebufArr =
        List<_WriteBuf>.generate(_oplWritebufSize, (_) => _WriteBuf());

    for (int slotnum = 0; slotnum < 36; slotnum++) {
      _slotArr.add(_Slot(this, slotnum));
    }
    for (int channum = 0; channum < 18; channum++) {
      _chan.add(_Channel(this, channum));
    }

    for (int slotnum = 0; slotnum < 36; slotnum++) {
      final _Slot s = _slotArr[slotnum];
      s.mod = _refZeromod();
      s.egRout = 0x1ff;
      s.egOut = 0x1ff;
      s.egGen = _egNumRelease;
      s.trem = _refZeromodTrem();
      s.slotNum = slotnum;
    }
    for (int channum = 0; channum < 18; channum++) {
      final _Channel ch = _chan[channum];
      final int localChSlot = _chSlot[channum];
      ch.slotz[0] = _slotArr[localChSlot];
      ch.slotz[1] = _slotArr[localChSlot + 3];
      _slotArr[localChSlot].channel = ch;
      _slotArr[localChSlot + 3].channel = ch;
      if ((channum % 9) < 3) {
        ch.pair = _chan[channum + 3];
      } else if ((channum % 9) < 6) {
        ch.pair = _chan[channum - 3];
      }
      ch.out[0] = _refZeromod();
      ch.out[1] = _refZeromod();
      ch.out[2] = _refZeromod();
      ch.out[3] = _refZeromod();
      ch.chtype = _ch2op;
      ch.cha = 0xffff;
      ch.chb = 0xffff;
      // ch_num set by constructor.
      _channelSetupAlg(ch);
    }
    noise = 1;
    rateratio = ((sampleRate << _rsmFrac) ~/ 49716) & 0xffffffff;
    tremoloshift = 4;
    vibshift = 1;
  }

  /// Immediate register write. [reg] is the 9-bit register (bit 8 selects the
  /// high bank), [value] is the 8-bit data byte.
  void writeReg(int reg, int value) {
    reg &= 0x1ff;
    value &= 0xff;
    final int high = (reg >> 8) & 0x01;
    final int regm = reg & 0xff;
    switch (regm & 0xf0) {
      case 0x00:
        if (high != 0) {
          switch (regm & 0x0f) {
            case 0x04:
              _channelSet4Op(value);
              break;
            case 0x05:
              newm = value & 0x01;
              break;
          }
        } else {
          switch (regm & 0x0f) {
            case 0x08:
              nts = (value >> 6) & 0x01;
              break;
          }
        }
        break;
      case 0x20:
      case 0x30:
        if (_adSlot[regm & 0x1f] >= 0) {
          _slotWrite20(_slotArr[18 * high + _adSlot[regm & 0x1f]], value);
        }
        break;
      case 0x40:
      case 0x50:
        if (_adSlot[regm & 0x1f] >= 0) {
          _slotWrite40(_slotArr[18 * high + _adSlot[regm & 0x1f]], value);
        }
        break;
      case 0x60:
      case 0x70:
        if (_adSlot[regm & 0x1f] >= 0) {
          _slotWrite60(_slotArr[18 * high + _adSlot[regm & 0x1f]], value);
        }
        break;
      case 0x80:
      case 0x90:
        if (_adSlot[regm & 0x1f] >= 0) {
          _slotWrite80(_slotArr[18 * high + _adSlot[regm & 0x1f]], value);
        }
        break;
      case 0xe0:
      case 0xf0:
        if (_adSlot[regm & 0x1f] >= 0) {
          _slotWriteE0(_slotArr[18 * high + _adSlot[regm & 0x1f]], value);
        }
        break;
      case 0xa0:
        if ((regm & 0x0f) < 9) {
          _channelWriteA0(_chan[9 * high + (regm & 0x0f)], value);
        }
        break;
      case 0xb0:
        if (regm == 0xbd && high == 0) {
          tremoloshift = (((value >> 7) ^ 1) << 1) + 2;
          vibshift = ((value >> 6) & 0x01) ^ 1;
          _channelUpdateRhythm(value);
        } else if ((regm & 0x0f) < 9) {
          _channelWriteB0(_chan[9 * high + (regm & 0x0f)], value);
          if ((value & 0x20) != 0) {
            _channelKeyOn(_chan[9 * high + (regm & 0x0f)]);
          } else {
            _channelKeyOff(_chan[9 * high + (regm & 0x0f)]);
          }
        }
        break;
      case 0xc0:
        if ((regm & 0x0f) < 9) {
          _channelWriteC0(_chan[9 * high + (regm & 0x0f)], value);
        }
        break;
    }
  }

  /// Buffered (time-delayed) register write — matches OPL3_WriteRegBuffered.
  void writeRegBuffered(int reg, int value) {
    reg &= 0xffff;
    value &= 0xff;
    int time1, time2;
    final int writebufLastLocal = writebufLast;
    final _WriteBuf wb = _writebufArr[writebufLastLocal];

    if ((wb.reg & 0x200) != 0) {
      writeReg(wb.reg & 0x1ff, wb.data);

      writebufCur = (writebufLastLocal + 1) % _oplWritebufSize;
      writebufSamplecnt = wb.time;
    }

    wb.reg = reg | 0x200;
    wb.data = value;
    time1 = writebufLasttime + _oplWritebufDelay;
    time2 = writebufSamplecnt;

    if (time1 < time2) {
      time1 = time2;
    }

    wb.time = time1;
    writebufLasttime = time1;
    writebufLast = (writebufLastLocal + 1) % _oplWritebufSize;
  }

  /// Generate one stereo (L,R) resampled output frame into [out2] (length 2).
  /// Maps to OPL3_GenerateResampled.
  void generate(Int16List out2) {
    final List<int> buf = <int>[0, 0];
    _generateResampled(buf);
    out2[0] = buf[0];
    out2[1] = buf[1];
  }

  /// Generate one stereo frame at the native 49716 Hz (no resampling).
  /// Maps to OPL3_Generate.
  void generateNative(Int16List out2) {
    final List<int> buf = <int>[0, 0];
    _generate(buf);
    out2[0] = buf[0];
    out2[1] = buf[1];
  }

  /// Generate [numFrames] interleaved stereo frames into [interleavedStereo]
  /// (length >= numFrames*2). Maps to OPL3_GenerateStream.
  void generateStream(Int16List interleavedStereo, int numFrames) {
    final List<int> buf = <int>[0, 0];
    int p = 0;
    for (int i = 0; i < numFrames; i++) {
      _generateResampled(buf);
      interleavedStereo[p] = buf[0];
      interleavedStereo[p + 1] = buf[1];
      p += 2;
    }
  }
}

// Truncate to signed 32-bit (mixbuff is int32_t).
int _i32(int v) {
  v &= 0xffffffff;
  if (v >= 0x80000000) {
    v -= 0x100000000;
  }
  return v;
}
