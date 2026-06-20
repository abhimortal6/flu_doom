// OPL MIDI player, ported 1:1 from Chocolate Doom src/i_oplmusic.c.
//
// This is the GENMIDI->OPL3 voice engine: it loads the DMX GENMIDI instrument
// bank (via [GenMidi]), allocates the 18 OPL3 voices, and programs the chip
// register-by-register from MIDI note-on/off, program-change, controller and
// pitch-bend events. The instrument/voice/frequency/volume math is a verbatim
// port of i_oplmusic.c — see the named functions (VoiceKeyOn,
// SetVoiceVolume, FrequencyForVoice, LoadOperatorData, ...).
//
// DIFFERENCE FROM VANILLA — scheduling only, not the synth: vanilla drives
// tracks with asynchronous OPL timer callbacks (OPL_SetCallback). Here the
// caller ([MusicEngine]) renders offline, so this class exposes a synchronous
// event-driven model: [playSong] loads the tracks, [stepUntilDone] /
// [advanceOneEvent] iterate events in tempo order (the moral equivalent of the
// TrackTimerCallback chain), and the OPL register writes go to a real [Opl3]
// instance. Everything between the OPL_WriteRegister boundaries is unchanged.

import 'genmidi.dart';
import 'midifile.dart';
import 'opl3.dart';

// --- opl.h register / voice constants (verbatim) ---

const int kOplNumVoices = 9; // OPL_NUM_VOICES

const int kOplRegWaveformEnable = 0x01;
const int kOplRegTimerCtrl = 0x04;
const int kOplRegFmMode = 0x08;
const int kOplRegNew = 0x105;

const int kOplRegsTremolo = 0x20;
const int kOplRegsLevel = 0x40;
const int kOplRegsAttack = 0x60;
const int kOplRegsSustain = 0x80;
const int kOplRegsWaveform = 0xE0;

const int kOplRegsFreq1 = 0xA0;
const int kOplRegsFreq2 = 0xB0;
const int kOplRegsFeedback = 0xC0;

const int kOplNumOperators = 21; // OPL_NUM_OPERATORS

// --- i_oplmusic.c #defines ---

const int kGenmidiNumInstrs = 128; // GENMIDI_NUM_INSTRS
const int kGenmidiFlagFixed = 0x0001; // GENMIDI_FLAG_FIXED
const int kGenmidiFlag2Voice = 0x0004; // GENMIDI_FLAG_2VOICE
const int kPercussionLogLen = 16;

/// opl_driver_ver_t. doom1.wad shareware is Doom 1.9 (the default the port uses
/// for the full game); we match vanilla's I_SetOPLDriverVer default of
/// opl_doom_1_9. The 1.666 branches are ported for fidelity but unused.
enum OplDriverVer { doom1_1666, doom2_1666, doom1_9 }

// Operators used by the different voices (voice_operators[2][OPL_NUM_VOICES]).
const List<List<int>> _voiceOperators = <List<int>>[
  <int>[0x00, 0x01, 0x02, 0x08, 0x09, 0x0a, 0x10, 0x11, 0x12],
  <int>[0x03, 0x04, 0x05, 0x0b, 0x0c, 0x0d, 0x13, 0x14, 0x15],
];

// Frequency values to use for each note (frequency_curve[]). Verbatim.
const List<int> _frequencyCurve = <int>[
  0x133, 0x133, 0x134, 0x134, 0x135, 0x136, 0x136, 0x137, // -1
  0x137, 0x138, 0x138, 0x139, 0x139, 0x13a, 0x13b, 0x13b,
  0x13c, 0x13c, 0x13d, 0x13d, 0x13e, 0x13f, 0x13f, 0x140,
  0x140, 0x141, 0x142, 0x142, 0x143, 0x143, 0x144, 0x144,
  0x145, 0x146, 0x146, 0x147, 0x147, 0x148, 0x149, 0x149, // -2
  0x14a, 0x14a, 0x14b, 0x14c, 0x14c, 0x14d, 0x14d, 0x14e,
  0x14f, 0x14f, 0x150, 0x150, 0x151, 0x152, 0x152, 0x153,
  0x153, 0x154, 0x155, 0x155, 0x156, 0x157, 0x157, 0x158,
  0x158, 0x159, 0x15a, 0x15a, 0x15b, 0x15b, 0x15c, 0x15d, // 0
  0x15d, 0x15e, 0x15f, 0x15f, 0x160, 0x161, 0x161, 0x162,
  0x162, 0x163, 0x164, 0x164, 0x165, 0x166, 0x166, 0x167,
  0x168, 0x168, 0x169, 0x16a, 0x16a, 0x16b, 0x16c, 0x16c,
  0x16d, 0x16e, 0x16e, 0x16f, 0x170, 0x170, 0x171, 0x172, // 1
  0x172, 0x173, 0x174, 0x174, 0x175, 0x176, 0x176, 0x177,
  0x178, 0x178, 0x179, 0x17a, 0x17a, 0x17b, 0x17c, 0x17c,
  0x17d, 0x17e, 0x17e, 0x17f, 0x180, 0x181, 0x181, 0x182,
  0x183, 0x183, 0x184, 0x185, 0x185, 0x186, 0x187, 0x188, // 2
  0x188, 0x189, 0x18a, 0x18a, 0x18b, 0x18c, 0x18d, 0x18d,
  0x18e, 0x18f, 0x18f, 0x190, 0x191, 0x192, 0x192, 0x193,
  0x194, 0x194, 0x195, 0x196, 0x197, 0x197, 0x198, 0x199,
  0x19a, 0x19a, 0x19b, 0x19c, 0x19d, 0x19d, 0x19e, 0x19f, // 3
  0x1a0, 0x1a0, 0x1a1, 0x1a2, 0x1a3, 0x1a3, 0x1a4, 0x1a5,
  0x1a6, 0x1a6, 0x1a7, 0x1a8, 0x1a9, 0x1a9, 0x1aa, 0x1ab,
  0x1ac, 0x1ad, 0x1ad, 0x1ae, 0x1af, 0x1b0, 0x1b0, 0x1b1,
  0x1b2, 0x1b3, 0x1b4, 0x1b4, 0x1b5, 0x1b6, 0x1b7, 0x1b8, // 4
  0x1b8, 0x1b9, 0x1ba, 0x1bb, 0x1bc, 0x1bc, 0x1bd, 0x1be,
  0x1bf, 0x1c0, 0x1c0, 0x1c1, 0x1c2, 0x1c3, 0x1c4, 0x1c4,
  0x1c5, 0x1c6, 0x1c7, 0x1c8, 0x1c9, 0x1c9, 0x1ca, 0x1cb,
  0x1cc, 0x1cd, 0x1ce, 0x1ce, 0x1cf, 0x1d0, 0x1d1, 0x1d2, // 5
  0x1d3, 0x1d3, 0x1d4, 0x1d5, 0x1d6, 0x1d7, 0x1d8, 0x1d8,
  0x1d9, 0x1da, 0x1db, 0x1dc, 0x1dd, 0x1de, 0x1de, 0x1df,
  0x1e0, 0x1e1, 0x1e2, 0x1e3, 0x1e4, 0x1e5, 0x1e5, 0x1e6,
  0x1e7, 0x1e8, 0x1e9, 0x1ea, 0x1eb, 0x1ec, 0x1ed, 0x1ed, // 6
  0x1ee, 0x1ef, 0x1f0, 0x1f1, 0x1f2, 0x1f3, 0x1f4, 0x1f5,
  0x1f6, 0x1f6, 0x1f7, 0x1f8, 0x1f9, 0x1fa, 0x1fb, 0x1fc,
  0x1fd, 0x1fe, 0x1ff, 0x200, 0x201, 0x201, 0x202, 0x203,
  0x204, 0x205, 0x206, 0x207, 0x208, 0x209, 0x20a, 0x20b, // 7
  0x20c, 0x20d, 0x20e, 0x20f, 0x210, 0x210, 0x211, 0x212,
  0x213, 0x214, 0x215, 0x216, 0x217, 0x218, 0x219, 0x21a,
  0x21b, 0x21c, 0x21d, 0x21e, 0x21f, 0x220, 0x221, 0x222,
  0x223, 0x224, 0x225, 0x226, 0x227, 0x228, 0x229, 0x22a, // 8
  0x22b, 0x22c, 0x22d, 0x22e, 0x22f, 0x230, 0x231, 0x232,
  0x233, 0x234, 0x235, 0x236, 0x237, 0x238, 0x239, 0x23a,
  0x23b, 0x23c, 0x23d, 0x23e, 0x23f, 0x240, 0x241, 0x242,
  0x244, 0x245, 0x246, 0x247, 0x248, 0x249, 0x24a, 0x24b, // 9
  0x24c, 0x24d, 0x24e, 0x24f, 0x250, 0x251, 0x252, 0x253,
  0x254, 0x256, 0x257, 0x258, 0x259, 0x25a, 0x25b, 0x25c,
  0x25d, 0x25e, 0x25f, 0x260, 0x262, 0x263, 0x264, 0x265,
  0x266, 0x267, 0x268, 0x269, 0x26a, 0x26c, 0x26d, 0x26e, // 10
  0x26f, 0x270, 0x271, 0x272, 0x273, 0x275, 0x276, 0x277,
  0x278, 0x279, 0x27a, 0x27b, 0x27d, 0x27e, 0x27f, 0x280,
  0x281, 0x282, 0x284, 0x285, 0x286, 0x287, 0x288, 0x289,
  0x28b, 0x28c, 0x28d, 0x28e, 0x28f, 0x290, 0x292, 0x293, // 11
  0x294, 0x295, 0x296, 0x298, 0x299, 0x29a, 0x29b, 0x29c,
  0x29e, 0x29f, 0x2a0, 0x2a1, 0x2a2, 0x2a4, 0x2a5, 0x2a6,
  0x2a7, 0x2a9, 0x2aa, 0x2ab, 0x2ac, 0x2ae, 0x2af, 0x2b0,
  0x2b1, 0x2b2, 0x2b4, 0x2b5, 0x2b6, 0x2b7, 0x2b9, 0x2ba, // 12
  0x2bb, 0x2bd, 0x2be, 0x2bf, 0x2c0, 0x2c2, 0x2c3, 0x2c4,
  0x2c5, 0x2c7, 0x2c8, 0x2c9, 0x2cb, 0x2cc, 0x2cd, 0x2ce,
  0x2d0, 0x2d1, 0x2d2, 0x2d4, 0x2d5, 0x2d6, 0x2d8, 0x2d9,
  0x2da, 0x2dc, 0x2dd, 0x2de, 0x2e0, 0x2e1, 0x2e2, 0x2e4, // 13
  0x2e5, 0x2e6, 0x2e8, 0x2e9, 0x2ea, 0x2ec, 0x2ed, 0x2ee,
  0x2f0, 0x2f1, 0x2f2, 0x2f4, 0x2f5, 0x2f6, 0x2f8, 0x2f9,
  0x2fb, 0x2fc, 0x2fd, 0x2ff, 0x300, 0x302, 0x303, 0x304,
  0x306, 0x307, 0x309, 0x30a, 0x30b, 0x30d, 0x30e, 0x310, // 14
  0x311, 0x312, 0x314, 0x315, 0x317, 0x318, 0x31a, 0x31b,
  0x31c, 0x31e, 0x31f, 0x321, 0x322, 0x324, 0x325, 0x327,
  0x328, 0x329, 0x32b, 0x32c, 0x32e, 0x32f, 0x331, 0x332,
  0x334, 0x335, 0x337, 0x338, 0x33a, 0x33b, 0x33d, 0x33e, // 15
  0x340, 0x341, 0x343, 0x344, 0x346, 0x347, 0x349, 0x34a,
  0x34c, 0x34d, 0x34f, 0x350, 0x352, 0x353, 0x355, 0x357,
  0x358, 0x35a, 0x35b, 0x35d, 0x35e, 0x360, 0x361, 0x363,
  0x365, 0x366, 0x368, 0x369, 0x36b, 0x36c, 0x36e, 0x370, // 16
  0x371, 0x373, 0x374, 0x376, 0x378, 0x379, 0x37b, 0x37c,
  0x37e, 0x380, 0x381, 0x383, 0x384, 0x386, 0x388, 0x389,
  0x38b, 0x38d, 0x38e, 0x390, 0x392, 0x393, 0x395, 0x397,
  0x398, 0x39a, 0x39c, 0x39d, 0x39f, 0x3a1, 0x3a2, 0x3a4, // 17
  0x3a6, 0x3a7, 0x3a9, 0x3ab, 0x3ac, 0x3ae, 0x3b0, 0x3b1,
  0x3b3, 0x3b5, 0x3b7, 0x3b8, 0x3ba, 0x3bc, 0x3bd, 0x3bf,
  0x3c1, 0x3c3, 0x3c4, 0x3c6, 0x3c8, 0x3ca, 0x3cb, 0x3cd,
  0x3cf, 0x3d1, 0x3d2, 0x3d4, 0x3d6, 0x3d8, 0x3da, 0x3db, // 18
  0x3dd, 0x3df, 0x3e1, 0x3e3, 0x3e4, 0x3e6, 0x3e8, 0x3ea,
  0x3ec, 0x3ed, 0x3ef, 0x3f1, 0x3f3, 0x3f5, 0x3f6, 0x3f8,
  0x3fa, 0x3fc, 0x3fe, 0x36c,
];

// Mapping from MIDI volume level to OPL level value (volume_mapping_table[]).
const List<int> _volumeMappingTable = <int>[
  0, 1, 3, 5, 6, 8, 10, 11,
  13, 14, 16, 17, 19, 20, 22, 23,
  25, 26, 27, 29, 30, 32, 33, 34,
  36, 37, 39, 41, 43, 45, 47, 49,
  50, 52, 54, 55, 57, 59, 60, 61,
  63, 64, 66, 67, 68, 69, 71, 72,
  73, 74, 75, 76, 77, 79, 80, 81,
  82, 83, 84, 84, 85, 86, 87, 88,
  89, 90, 91, 92, 92, 93, 94, 95,
  96, 96, 97, 98, 99, 99, 100, 101,
  101, 102, 103, 103, 104, 105, 105, 106,
  107, 107, 108, 109, 109, 110, 110, 111,
  112, 112, 113, 113, 114, 114, 115, 115,
  116, 117, 117, 118, 118, 119, 119, 120,
  120, 121, 121, 122, 122, 123, 123, 123,
  124, 124, 125, 125, 126, 126, 127, 127,
];

/// opl_channel_data_t.
class _OplChannelData {
  GenMidiInstr? instrument;
  int volume = 0;
  int volumeBase = 0;
  int pan = 0;
  int bend = 0;
}

/// opl_voice_s.
class _OplVoice {
  int index = 0;
  int op1 = 0;
  int op2 = 0;
  int array = 0;
  GenMidiInstr? currentInstr;

  /// Whether [currentInstr] is a percussion (>= percussion bank) entry. The C
  /// uses pointer comparison `voice->current_instr < percussion_instrs`; we
  /// track the boolean explicitly for the pause logic.
  bool currentInstrIsPercussion = false;

  int currentInstrVoice = 0;
  _OplChannelData? channel;
  int key = 0;
  int note = 0;
  int freq = 0;
  int noteVolume = 0;
  int carVolume = 0;
  int modVolume = 0;
  int regPan = 0;
  int priority = 0;
}

/// One scheduled track playing (opl_track_data_t).
class _OplTrackData {
  _OplTrackData(this.iter);
  MidiTrackIterator iter;

  /// Absolute tick position of the next event in this track (our scheduling
  /// replacement for OPL_SetCallback). Computed from cumulative delta times.
  int nextTick = 0;

  /// Whether this track has reached end-of-track.
  bool finished = false;
}

/// The OPL MIDI player. Faithful port of i_oplmusic.c, with synchronous
/// (offline) event stepping instead of async OPL timer callbacks.
class OplPlayer {
  OplPlayer({
    required this.opl,
    required GenMidi genmidi,
    bool opl3Mode = true,
    this.driverVer = OplDriverVer.doom1_9,
    bool stereoCorrect = false,
  })  : _genmidi = genmidi,
        _oplOpl3Mode = opl3Mode,
        _oplStereoCorrect = stereoCorrect {
    _numOplVoices = _oplOpl3Mode ? kOplNumVoices * 2 : kOplNumVoices;
  }

  final Opl3 opl;
  final GenMidi _genmidi;
  final OplDriverVer driverVer;
  final bool _oplOpl3Mode;
  final bool _oplStereoCorrect;

  late int _numOplVoices;

  int _currentMusicVolume = 127;
  int _startMusicVolume = 127;

  // Voices (voices[], voice_free_list[], voice_alloced_list[]).
  final List<_OplVoice> _voices =
      List<_OplVoice>.generate(kOplNumVoices * 2, (_) => _OplVoice());
  final List<_OplVoice?> _voiceFreeList =
      List<_OplVoice?>.filled(kOplNumVoices * 2, null);
  final List<_OplVoice?> _voiceAllocedList =
      List<_OplVoice?>.filled(kOplNumVoices * 2, null);
  int _voiceFreeNum = 0;
  int _voiceAllocedNum = 0;

  // Per-channel data (channels[MIDI_CHANNELS_PER_TRACK]).
  final List<_OplChannelData> _channels =
      List<_OplChannelData>.generate(kMidiChannelsPerTrack, (_) => _OplChannelData());

  // Track data.
  List<_OplTrackData> _tracks = <_OplTrackData>[];
  int _numTracks = 0;
  int _runningTracks = 0;
  bool _songLooping = false;

  // Tempo control.
  int _ticksPerBeat = 1;
  int _usPerBeat = 500 * 1000;

  // Percussion mini-log.
  final List<int> _lastPerc = List<int>.filled(kPercussionLogLen, 0);
  int _lastPercCount = 0;

  /// Current absolute tick position of the song (max over tracks consumed).
  int _songTick = 0;

  // -------------------------------------------------------------------------
  // OPL register write helpers (OPL_WriteRegister). Use the buffered path for
  // the bulk register programming and the immediate path for frequency / key
  // writes, matching the I_OPL register flow (chip writes go to the same Opl3).
  // -------------------------------------------------------------------------
  void _writeReg(int reg, int value) => opl.writeRegBuffered(reg, value & 0xff);

  // -------------------------------------------------------------------------
  // OPL_InitRegisters (opl.c). Clears the chip and selects OPL2/OPL3 mode.
  // -------------------------------------------------------------------------
  void initRegisters(bool opl3) {
    // Initialize level registers.
    for (int r = kOplRegsLevel; r <= kOplRegsLevel + kOplNumOperators; r++) {
      _writeReg(r, 0x3f);
    }
    // Other registers (writes to non-existent regs, like Doom; <= intentional).
    for (int r = kOplRegsAttack; r <= kOplRegsWaveform + kOplNumOperators; r++) {
      _writeReg(r, 0x00);
    }
    for (int r = 1; r < kOplRegsLevel; r++) {
      _writeReg(r, 0x00);
    }

    // Reset both timers and enable interrupts.
    _writeReg(kOplRegTimerCtrl, 0x60);
    _writeReg(kOplRegTimerCtrl, 0x80);
    // Allow FM chips to control the waveform of each operator.
    _writeReg(kOplRegWaveformEnable, 0x20);

    if (opl3) {
      _writeReg(kOplRegNew, 0x01);
      for (int r = kOplRegsLevel; r <= kOplRegsLevel + kOplNumOperators; r++) {
        _writeReg(r | 0x100, 0x3f);
      }
      for (int r = kOplRegsAttack;
          r <= kOplRegsWaveform + kOplNumOperators;
          r++) {
        _writeReg(r | 0x100, 0x00);
      }
      for (int r = 1; r < kOplRegsLevel; r++) {
        _writeReg(r | 0x100, 0x00);
      }
    }

    // Keyboard split point on (?)
    _writeReg(kOplRegFmMode, 0x40);
    if (opl3) {
      _writeReg(kOplRegNew, 0x01);
    }
  }

  // -------------------------------------------------------------------------
  // GetFreeVoice / ReleaseVoice (voice allocation).
  // -------------------------------------------------------------------------
  _OplVoice? _getFreeVoice() {
    if (_voiceFreeNum == 0) {
      return null;
    }
    final _OplVoice result = _voiceFreeList[0]!;
    _voiceFreeNum--;
    for (int i = 0; i < _voiceFreeNum; i++) {
      _voiceFreeList[i] = _voiceFreeList[i + 1];
    }
    _voiceAllocedList[_voiceAllocedNum++] = result;
    return result;
  }

  void _releaseVoice(int index) {
    // Doom 2 1.666 OPL crash emulation.
    if (index >= _voiceAllocedNum) {
      _voiceAllocedNum = 0;
      _voiceFreeNum = 0;
      return;
    }

    final _OplVoice voice = _voiceAllocedList[index]!;
    _voiceKeyOff(voice);
    voice.channel = null;
    voice.note = 0;

    final bool doubleVoice = voice.currentInstrVoice != 0;

    _voiceAllocedNum--;
    for (int i = index; i < _voiceAllocedNum; i++) {
      _voiceAllocedList[i] = _voiceAllocedList[i + 1];
    }

    _voiceFreeList[_voiceFreeNum++] = voice;

    if (doubleVoice && driverVer.index < OplDriverVer.doom1_9.index) {
      _releaseVoice(index);
    }
  }

  // -------------------------------------------------------------------------
  // LoadOperatorData.
  // -------------------------------------------------------------------------
  // Returns the level value written (the C writes through *volume).
  int _loadOperatorData(int operator, GenMidiOp data, bool maxLevel) {
    int level = data.scale;
    if (maxLevel) {
      level |= 0x3f;
    } else {
      level |= data.level;
    }

    _writeReg(kOplRegsLevel + operator, level);
    _writeReg(kOplRegsTremolo + operator, data.tremolo);
    _writeReg(kOplRegsAttack + operator, data.attack);
    _writeReg(kOplRegsSustain + operator, data.sustain);
    _writeReg(kOplRegsWaveform + operator, data.waveform);
    return level;
  }

  // -------------------------------------------------------------------------
  // SetVoiceInstrument.
  // -------------------------------------------------------------------------
  void _setVoiceInstrument(
      _OplVoice voice, GenMidiInstr instr, bool instrIsPercussion, int instrVoice) {
    if (identical(voice.currentInstr, instr) &&
        voice.currentInstrVoice == instrVoice) {
      return;
    }

    voice.currentInstr = instr;
    voice.currentInstrIsPercussion = instrIsPercussion;
    voice.currentInstrVoice = instrVoice;

    final GenMidiVoice data = instr.voices[instrVoice];

    // Are we using modulated feedback mode?
    final bool modulating = (data.feedback & 0x01) == 0;

    // Doom loads the second operator (carrier) first, then the first.
    voice.carVolume =
        _loadOperatorData(voice.op2 | voice.array, data.carrier, true);
    voice.modVolume = _loadOperatorData(
        voice.op1 | voice.array, data.modulator, !modulating);

    // Feedback register (connection + OPL3 channel A/B bits via reg_pan).
    _writeReg((kOplRegsFeedback + voice.index) | voice.array,
        data.feedback | voice.regPan);

    // Calculate voice priority.
    voice.priority = 0x0f -
        (data.carrier.attack >> 4) +
        0x0f -
        (data.carrier.sustain & 0x0f);
  }

  // -------------------------------------------------------------------------
  // SetVoiceVolume.
  // -------------------------------------------------------------------------
  void _setVoiceVolume(_OplVoice voice, int volume) {
    voice.noteVolume = volume;

    final GenMidiVoice oplVoice =
        voice.currentInstr!.voices[voice.currentInstrVoice];

    // Multiply note volume and channel volume to get the actual volume.
    final int midiVolume =
        2 * (_volumeMappingTable[voice.channel!.volume] + 1);

    final int fullVolume =
        (_volumeMappingTable[voice.noteVolume] * midiVolume) >> 9;

    // The volume value to use in the register.
    final int carVolume = 0x3f - fullVolume;

    if (carVolume != (voice.carVolume & 0x3f)) {
      voice.carVolume = carVolume | (voice.carVolume & 0xc0);

      _writeReg((kOplRegsLevel + voice.op2) | voice.array, voice.carVolume);

      // Non-modulated feedback mode: set the modulator volume too.
      if ((oplVoice.feedback & 0x01) != 0 &&
          oplVoice.modulator.level != 0x3f) {
        int modVolume = oplVoice.modulator.level;
        if (modVolume < carVolume) {
          modVolume = carVolume;
        }

        modVolume |= voice.modVolume & 0xc0;

        if (modVolume != voice.modVolume) {
          voice.modVolume = modVolume;
          _writeReg((kOplRegsLevel + voice.op1) | voice.array,
              modVolume | (oplVoice.modulator.scale & 0xc0));
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // SetVoicePan.
  // -------------------------------------------------------------------------
  void _setVoicePan(_OplVoice voice, int pan) {
    voice.regPan = pan;
    final GenMidiVoice oplVoice =
        voice.currentInstr!.voices[voice.currentInstrVoice];
    _writeReg((kOplRegsFeedback + voice.index) | voice.array,
        oplVoice.feedback | pan);
  }

  // -------------------------------------------------------------------------
  // InitVoices.
  // -------------------------------------------------------------------------
  void _initVoices() {
    _voiceFreeNum = _numOplVoices;
    _voiceAllocedNum = 0;

    for (int i = 0; i < _numOplVoices; i++) {
      _voices[i].index = i % kOplNumVoices;
      _voices[i].op1 = _voiceOperators[0][i % kOplNumVoices];
      _voices[i].op2 = _voiceOperators[1][i % kOplNumVoices];
      _voices[i].array = (i ~/ kOplNumVoices) << 8;
      _voices[i].currentInstr = null;
      _voices[i].currentInstrIsPercussion = false;
      _voiceFreeList[i] = _voices[i];
    }
  }

  // -------------------------------------------------------------------------
  // I_OPL_SetMusicVolume.
  // -------------------------------------------------------------------------
  void setMusicVolume(int volume) {
    if (_currentMusicVolume == volume) {
      return;
    }
    _currentMusicVolume = volume;

    for (int i = 0; i < kMidiChannelsPerTrack; i++) {
      if (i == 15) {
        _setChannelVolume(_channels[i], volume, false);
      } else {
        _setChannelVolume(_channels[i], _channels[i].volumeBase, false);
      }
    }
  }

  // -------------------------------------------------------------------------
  // VoiceKeyOff.
  // -------------------------------------------------------------------------
  void _voiceKeyOff(_OplVoice voice) {
    _writeReg((kOplRegsFreq2 + voice.index) | voice.array, voice.freq >> 8);
  }

  // -------------------------------------------------------------------------
  // TrackChannelForEvent: MUS<->MIDI percussion channel swap (9 <-> 15).
  // -------------------------------------------------------------------------
  _OplChannelData _trackChannelForEvent(MidiEvent event) {
    int channelNum = event.channel!.channel;
    if (channelNum == 9) {
      channelNum = 15;
    } else if (channelNum == 15) {
      channelNum = 9;
    }
    return _channels[channelNum];
  }

  // -------------------------------------------------------------------------
  // KeyOffEvent.
  // -------------------------------------------------------------------------
  void _keyOffEvent(MidiEvent event) {
    final _OplChannelData channel = _trackChannelForEvent(event);
    final int key = event.channel!.param1;

    for (int i = 0; i < _voiceAllocedNum; i++) {
      if (identical(_voiceAllocedList[i]!.channel, channel) &&
          _voiceAllocedList[i]!.key == key) {
        _releaseVoice(i);
        i--;
      }
    }
  }

  // -------------------------------------------------------------------------
  // ReplaceExistingVoice (+ Doom1/Doom2 variants).
  // -------------------------------------------------------------------------
  // Compares two channels by their index in the channels[] array (the C
  // compares opl_channel_data_t pointers, which are ordered by channel number).
  int _channelOrder(_OplChannelData? c) =>
      c == null ? -1 : _channels.indexOf(c);

  void _replaceExistingVoice() {
    int result = 0;
    for (int i = 0; i < _voiceAllocedNum; i++) {
      if (_voiceAllocedList[i]!.currentInstrVoice != 0 ||
          _channelOrder(_voiceAllocedList[i]!.channel) >=
              _channelOrder(_voiceAllocedList[result]!.channel)) {
        result = i;
      }
    }
    _releaseVoice(result);
  }

  void _replaceExistingVoiceDoom1() {
    int result = 0;
    for (int i = 0; i < _voiceAllocedNum; i++) {
      if (_channelOrder(_voiceAllocedList[i]!.channel) >
          _channelOrder(_voiceAllocedList[result]!.channel)) {
        result = i;
      }
    }
    _releaseVoice(result);
  }

  void _replaceExistingVoiceDoom2(_OplChannelData channel) {
    int result = 0;
    int priority = 0x8000;
    for (int i = 0; i < _voiceAllocedNum - 3; i++) {
      if (_voiceAllocedList[i]!.priority < priority &&
          _channelOrder(_voiceAllocedList[i]!.channel) >=
              _channelOrder(channel)) {
        priority = _voiceAllocedList[i]!.priority;
        result = i;
      }
    }
    _releaseVoice(result);
  }

  // -------------------------------------------------------------------------
  // FrequencyForVoice.
  // -------------------------------------------------------------------------
  int _frequencyForVoice(_OplVoice voice) {
    int note = voice.note;

    final GenMidiVoice gmVoice =
        voice.currentInstr!.voices[voice.currentInstrVoice];

    if ((voice.currentInstr!.flags & kGenmidiFlagFixed) == 0) {
      note += gmVoice.baseNoteOffset; // already signed (SHORT()).
    }

    while (note < 0) {
      note += 12;
    }
    while (note > 95) {
      note -= 12;
    }

    int freqIndex = 64 + 32 * note + voice.channel!.bend;

    if (voice.currentInstrVoice != 0) {
      freqIndex += (voice.currentInstr!.fineTuning ~/ 2) - 64;
    }

    if (freqIndex < 0) {
      freqIndex = 0;
    }

    if (freqIndex < 284) {
      return _frequencyCurve[freqIndex];
    }

    final int subIndex = (freqIndex - 284) % (12 * 32);
    int octave = (freqIndex - 284) ~/ (12 * 32);

    if (octave >= 7) {
      octave = 7;
    }

    return _frequencyCurve[subIndex + 284] | (octave << 10);
  }

  // -------------------------------------------------------------------------
  // UpdateVoiceFrequency.
  // -------------------------------------------------------------------------
  void _updateVoiceFrequency(_OplVoice voice) {
    final int freq = _frequencyForVoice(voice);

    if (voice.freq != freq) {
      _writeReg((kOplRegsFreq1 + voice.index) | voice.array, freq & 0xff);
      _writeReg((kOplRegsFreq2 + voice.index) | voice.array,
          (freq >> 8) | 0x20);
      voice.freq = freq;
    }
  }

  // -------------------------------------------------------------------------
  // VoiceKeyOn.
  // -------------------------------------------------------------------------
  void _voiceKeyOn(_OplChannelData channel, GenMidiInstr instrument,
      bool instrIsPercussion, int instrumentVoice, int note, int key, int volume) {
    if (!_oplOpl3Mode && driverVer == OplDriverVer.doom1_1666) {
      instrumentVoice = 0;
    }

    final _OplVoice? voice = _getFreeVoice();
    if (voice == null) {
      return;
    }

    voice.channel = channel;
    voice.key = key;

    if ((instrument.flags & kGenmidiFlagFixed) != 0) {
      voice.note = instrument.fixedNote;
    } else {
      voice.note = note;
    }

    voice.regPan = channel.pan;

    _setVoiceInstrument(voice, instrument, instrIsPercussion, instrumentVoice);
    _setVoiceVolume(voice, volume);

    voice.freq = 0;
    _updateVoiceFrequency(voice);
  }

  // -------------------------------------------------------------------------
  // KeyOnEvent.
  // -------------------------------------------------------------------------
  void _keyOnEvent(MidiEvent event) {
    int note = event.channel!.param1;
    final int key = event.channel!.param1;
    final int volume = event.channel!.param2;

    // Volume of zero means key off.
    if (volume <= 0) {
      _keyOffEvent(event);
      return;
    }

    final _OplChannelData channel = _trackChannelForEvent(event);

    GenMidiInstr instrument;
    bool instrIsPercussion;
    if (event.channel!.channel == 9) {
      if (key < 35 || key > 81) {
        return;
      }
      instrument = _genmidi.percussion(key);
      instrIsPercussion = true;

      _lastPerc[_lastPercCount] = key;
      _lastPercCount = (_lastPercCount + 1) % kPercussionLogLen;
      note = 60;
    } else {
      // channel->instrument was assigned a melodic instrument; never percussion.
      instrument = channel.instrument!;
      instrIsPercussion = false;
    }

    final bool doubleVoice = (instrument.flags & kGenmidiFlag2Voice) != 0;

    switch (driverVer) {
      case OplDriverVer.doom1_1666:
        int voicenum = (doubleVoice ? 1 : 0) + 1;
        if (!_oplOpl3Mode) {
          voicenum = 1;
        }
        while (_voiceAllocedNum > _numOplVoices - voicenum) {
          _replaceExistingVoiceDoom1();
        }
        if (doubleVoice) {
          _voiceKeyOn(channel, instrument, instrIsPercussion, 1, note, key, volume);
        }
        _voiceKeyOn(channel, instrument, instrIsPercussion, 0, note, key, volume);
        break;
      case OplDriverVer.doom2_1666:
        if (_voiceAllocedNum == _numOplVoices) {
          _replaceExistingVoiceDoom2(channel);
        }
        if (_voiceAllocedNum == _numOplVoices - 1 && doubleVoice) {
          _replaceExistingVoiceDoom2(channel);
        }
        if (doubleVoice) {
          _voiceKeyOn(channel, instrument, instrIsPercussion, 1, note, key, volume);
        }
        _voiceKeyOn(channel, instrument, instrIsPercussion, 0, note, key, volume);
        break;
      case OplDriverVer.doom1_9:
        if (_voiceFreeNum == 0) {
          _replaceExistingVoice();
        }
        _voiceKeyOn(channel, instrument, instrIsPercussion, 0, note, key, volume);
        if (doubleVoice) {
          _voiceKeyOn(channel, instrument, instrIsPercussion, 1, note, key, volume);
        }
        break;
    }
  }

  // -------------------------------------------------------------------------
  // ProgramChangeEvent.
  // -------------------------------------------------------------------------
  void _programChangeEvent(MidiEvent event) {
    final _OplChannelData channel = _trackChannelForEvent(event);
    final int instrument = event.channel!.param1;
    channel.instrument = _genmidi.melodic(instrument);
  }

  // -------------------------------------------------------------------------
  // SetChannelVolume.
  // -------------------------------------------------------------------------
  void _setChannelVolume(_OplChannelData channel, int volume, bool clipStart) {
    channel.volumeBase = volume;

    if (volume > _currentMusicVolume) {
      volume = _currentMusicVolume;
    }
    if (clipStart && volume > _startMusicVolume) {
      volume = _startMusicVolume;
    }

    channel.volume = volume;

    for (int i = 0; i < _numOplVoices; i++) {
      if (identical(_voices[i].channel, channel)) {
        _setVoiceVolume(_voices[i], _voices[i].noteVolume);
      }
    }
  }

  // -------------------------------------------------------------------------
  // SetChannelPan.
  // -------------------------------------------------------------------------
  void _setChannelPan(_OplChannelData channel, int pan) {
    if (_oplStereoCorrect) {
      pan = 144 - pan;
    }

    if (_oplOpl3Mode) {
      int regPan;
      if (pan >= 96) {
        regPan = 0x10;
      } else if (pan <= 48) {
        regPan = 0x20;
      } else {
        regPan = 0x30;
      }
      if (channel.pan != regPan) {
        channel.pan = regPan;
        for (int i = 0; i < _numOplVoices; i++) {
          if (identical(_voices[i].channel, channel)) {
            _setVoicePan(_voices[i], regPan);
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // AllNotesOff.
  // -------------------------------------------------------------------------
  void _allNotesOff(_OplChannelData channel, int param) {
    for (int i = 0; i < _voiceAllocedNum; i++) {
      if (identical(_voiceAllocedList[i]!.channel, channel)) {
        _releaseVoice(i);
        i--;
      }
    }
  }

  // -------------------------------------------------------------------------
  // ControllerEvent.
  // -------------------------------------------------------------------------
  void _controllerEvent(MidiEvent event) {
    final _OplChannelData channel = _trackChannelForEvent(event);
    final int controller = event.channel!.param1;
    final int param = event.channel!.param2;

    switch (controller) {
      case MidiController.volumeMsb:
        _setChannelVolume(channel, param, true);
        break;
      case MidiController.pan:
        _setChannelPan(channel, param);
        break;
      case MidiController.allNotesOff:
        _allNotesOff(channel, param);
        break;
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // PitchBendEvent. (Only the MSB is considered, as Doom does.) The voice-list
  // reordering at the end is preserved verbatim.
  // -------------------------------------------------------------------------
  void _pitchBendEvent(MidiEvent event) {
    final List<_OplVoice> voiceUpdatedList = <_OplVoice>[];
    final List<_OplVoice> voiceNotUpdatedList = <_OplVoice>[];

    final _OplChannelData channel = _trackChannelForEvent(event);
    channel.bend = event.channel!.param2 - 64;

    for (int i = 0; i < _voiceAllocedNum; i++) {
      if (identical(_voiceAllocedList[i]!.channel, channel)) {
        _updateVoiceFrequency(_voiceAllocedList[i]!);
        voiceUpdatedList.add(_voiceAllocedList[i]!);
      } else {
        voiceNotUpdatedList.add(_voiceAllocedList[i]!);
      }
    }

    for (int i = 0; i < voiceNotUpdatedList.length; i++) {
      _voiceAllocedList[i] = voiceNotUpdatedList[i];
    }
    for (int i = 0; i < voiceUpdatedList.length; i++) {
      _voiceAllocedList[i + voiceNotUpdatedList.length] = voiceUpdatedList[i];
    }
  }

  // -------------------------------------------------------------------------
  // MetaSetTempo / MetaEvent.
  // -------------------------------------------------------------------------
  void _metaSetTempo(int tempo) {
    // OPL_AdjustCallbacks scales pending timers by us_per_beat/tempo; in our
    // offline model the new us_per_beat is simply used for subsequent
    // tick->microsecond conversions, which the renderer reads.
    _usPerBeat = tempo;
  }

  void _metaEvent(MidiEvent event) {
    final MidiMetaEventData meta = event.meta!;
    switch (meta.type) {
      case MidiMetaEventType.sequenceNumber:
      case MidiMetaEventType.text:
      case MidiMetaEventType.copyright:
      case MidiMetaEventType.trackName:
      case MidiMetaEventType.instrName:
      case MidiMetaEventType.lyrics:
      case MidiMetaEventType.marker:
      case MidiMetaEventType.cuePoint:
      case MidiMetaEventType.sequencerSpecific:
        break;
      case MidiMetaEventType.setTempo:
        if (meta.length == 3) {
          _metaSetTempo(
              (meta.data[0] << 16) | (meta.data[1] << 8) | meta.data[2]);
        }
        break;
      case MidiMetaEventType.endOfTrack:
        break;
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // ProcessEvent.
  // -------------------------------------------------------------------------
  void _processEvent(MidiEvent event) {
    switch (event.eventType) {
      case MidiEventType.noteOff:
        _keyOffEvent(event);
        break;
      case MidiEventType.noteOn:
        _keyOnEvent(event);
        break;
      case MidiEventType.controller:
        _controllerEvent(event);
        break;
      case MidiEventType.programChange:
        _programChangeEvent(event);
        break;
      case MidiEventType.pitchBend:
        _pitchBendEvent(event);
        break;
      case MidiEventType.meta:
        _metaEvent(event);
        break;
      case MidiEventType.sysEx:
      case MidiEventType.sysExSplit:
        break;
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // InitChannel.
  // -------------------------------------------------------------------------
  void _initChannel(_OplChannelData channel) {
    channel.instrument = _genmidi.melodic(0); // main_instrs[0]
    channel.volume = _currentMusicVolume;
    channel.volumeBase = 100;
    if (channel.volume > channel.volumeBase) {
      channel.volume = channel.volumeBase;
    }
    channel.pan = 0x30;
    channel.bend = 0;
  }

  // =========================================================================
  // Public driver: load + step the song (the I_OPL_PlaySong + TrackTimerCallback
  // chain, restructured for synchronous offline rendering).
  // =========================================================================

  /// I_OPL_InitMusic (the OPL chip init half): clear registers and set up the
  /// voice table. Call once before [playSong].
  void initMusic() {
    initRegisters(_oplOpl3Mode);
    _initVoices();
  }

  /// I_OPL_PlaySong: load the MIDI tracks and prepare them for stepping.
  void playSong(MidiFile file, {required bool looping}) {
    _numTracks = file.numTracks;
    _runningTracks = _numTracks;
    _songLooping = looping;
    _ticksPerBeat = file.fileTimeDivision;
    if (_ticksPerBeat <= 0) _ticksPerBeat = 1;
    _usPerBeat = 500 * 1000; // default 120 bpm
    _startMusicVolume = _currentMusicVolume;
    _songTick = 0;

    _tracks = <_OplTrackData>[];
    for (int i = 0; i < _numTracks; i++) {
      final MidiTrackIterator iter = file.iterateTrack(i);
      final _OplTrackData td = _OplTrackData(iter);
      td.nextTick = iter.getDeltaTime();
      _tracks.add(td);
    }

    for (int i = 0; i < kMidiChannelsPerTrack; i++) {
      _initChannel(_channels[i]);
    }
  }

  /// RestartSong: rewind every track to the beginning (for looping).
  void _restartSong() {
    _runningTracks = _numTracks;
    _startMusicVolume = _currentMusicVolume;
    _songTick = 0;
    for (final _OplTrackData td in _tracks) {
      td.iter.restart();
      td.finished = false;
      td.nextTick = td.iter.getDeltaTime();
    }
    for (int i = 0; i < kMidiChannelsPerTrack; i++) {
      _initChannel(_channels[i]);
    }
  }

  /// True while at least one track still has events to play.
  bool get hasRunningTracks => _runningTracks > 0;

  /// Microseconds per MIDI tick at the current tempo (us_per_beat/ticks_per_beat).
  double get microsecondsPerTick => _usPerBeat / _ticksPerBeat;

  /// Process all events scheduled at-or-before the absolute tick [untilTick],
  /// in tempo order across tracks, and return the number of microseconds of
  /// audio that should be rendered up to [untilTick] from the previous call's
  /// end. Caller advances [untilTick] in small steps and renders OPL PCM for
  /// the returned duration between calls. Returns the new song tick reached.
  ///
  /// This is the offline equivalent of the TrackTimerCallback/ScheduleTrack
  /// loop: it pops the earliest-scheduled track event, processes it, advances
  /// that track's nextTick by its next delta, and repeats until no track has an
  /// event at-or-before [untilTick].
  void processEventsUntil(int untilTick) {
    for (;;) {
      // Find the track with the earliest next event (smallest nextTick) that is
      // not finished and is due at-or-before untilTick.
      int best = -1;
      int bestTick = 0;
      for (int i = 0; i < _tracks.length; i++) {
        final _OplTrackData td = _tracks[i];
        if (td.finished) continue;
        if (td.nextTick <= untilTick) {
          if (best < 0 || td.nextTick < bestTick) {
            best = i;
            bestTick = td.nextTick;
          }
        }
      }
      if (best < 0) {
        return;
      }

      final _OplTrackData td = _tracks[best];
      _songTick = td.nextTick;

      final MidiEvent? event = td.iter.getNextEvent();
      if (event == null) {
        td.finished = true;
        continue;
      }

      _processEvent(event);

      if (event.eventType == MidiEventType.meta &&
          event.meta != null &&
          event.meta!.type == MidiMetaEventType.endOfTrack) {
        td.finished = true;
        _runningTracks--;
        if (_runningTracks <= 0 && _songLooping) {
          // Vanilla waits 5ms then RestartSong; here we restart immediately at
          // the loop boundary (the offline renderer accounts for elapsed time).
          _restartSong();
          return;
        }
        continue;
      }

      // Advance this track to its next event.
      final int delta = td.iter.getDeltaTime();
      td.nextTick = _songTick + delta;
    }
  }

  /// The smallest nextTick across all unfinished tracks, or null if none remain
  /// (used by the renderer to know how far to render before the next event).
  int? get nextEventTick {
    int? best;
    for (final _OplTrackData td in _tracks) {
      if (td.finished) continue;
      if (best == null || td.nextTick < best) {
        best = td.nextTick;
      }
    }
    return best;
  }

  /// I_OPL_StopSong: free all voices.
  void stopSong() {
    for (int i = 0; i < kMidiChannelsPerTrack; i++) {
      _allNotesOff(_channels[i], 0);
    }
    _tracks = <_OplTrackData>[];
    _numTracks = 0;
    _runningTracks = 0;
  }
}
