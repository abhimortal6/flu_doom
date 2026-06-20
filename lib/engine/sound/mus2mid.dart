// MUS -> MIDI converter, ported 1:1 from Chocolate Doom src/mus2mid.c
// (Ben Ryves 2006). Converts a DMX MUS lump into a single-track, type-0
// Standard MIDI File (MThd + one MTrk).
//
// The MUS format is a compact, Doom-specific MIDI-like stream:
//   - a header (id "MUS\x1a", score length/start, channel/instrument counts),
//   - a sequence of events, each a one-byte descriptor (channel + event code +
//     "last" flag) optionally followed by payload bytes, with variable-length
//     delay (time) codes interspersed between event groups.
//
// This is a faithful port: the same controller map, the same
// channel allocation (MUS percussion channel 15 -> MIDI channel 9), the same
// 8-bit controller-value clamp quirk, and the same variable-length delta
// encoding as vanilla. Output bytes are identical to mus2mid.c's.

import 'dart:typed_data';

const int _numChannels = 16;

const int _midiPercussionChan = 9;
const int _musPercussionChan = 15;

// MUS event codes (musevent).
const int _musReleaseKey = 0x00;
const int _musPressKey = 0x10;
const int _musPitchWheel = 0x20;
const int _musSystemEvent = 0x30;
const int _musChangeController = 0x40;
const int _musScoreEnd = 0x60;

// MIDI event codes (midievent).
const int _midiReleaseKey = 0x80;
const int _midiPressKey = 0x90;
const int _midiChangeController = 0xB0;
const int _midiChangePatch = 0xC0;
const int _midiPitchWheel = 0xE0;

// Standard MIDI type-0 header + track header. The final 4 bytes are a
// placeholder for the track length, patched in at the end (offset 18).
const List<int> _midiHeader = <int>[
  0x4D, 0x54, 0x68, 0x64, // 'M','T','h','d'  Main header
  0x00, 0x00, 0x00, 0x06, // Header size
  0x00, 0x00, //             MIDI type (0)
  0x00, 0x01, //             Number of tracks
  0x00, 0x46, //             Resolution
  0x4D, 0x54, 0x72, 0x6B, // 'M','T','r','k'  Start of track
  0x00, 0x00, 0x00, 0x00, // Placeholder for track length
];

// Controller number map: MUS controller index -> MIDI controller number.
const List<int> _controllerMap = <int>[
  0x00, 0x20, 0x01, 0x07, 0x0A, 0x0B, 0x5B, 0x5D, //
  0x40, 0x43, 0x78, 0x7B, 0x7E, 0x7F, 0x79,
];

/// Thrown when a MUS lump cannot be converted (mirrors mus2mid.c returning
/// `true` for failure).
class Mus2MidException implements Exception {
  Mus2MidException(this.message);
  final String message;
  @override
  String toString() => 'Mus2MidException: $message';
}

// Growable output buffer behaving like the vanilla MEMFILE: supports append
// writes and a seek-back to patch the track length.
class _MemFile {
  final List<int> _bytes = <int>[];

  int get length => _bytes.length;

  void writeByte(int b) => _bytes.add(b & 0xFF);

  void writeBytes(List<int> bs) {
    for (final int b in bs) {
      _bytes.add(b & 0xFF);
    }
  }

  // Overwrite 4 bytes at [offset] (used to patch the MTrk length field).
  void patch4(int offset, int b0, int b1, int b2, int b3) {
    _bytes[offset] = b0 & 0xFF;
    _bytes[offset + 1] = b1 & 0xFF;
    _bytes[offset + 2] = b2 & 0xFF;
    _bytes[offset + 3] = b3 & 0xFF;
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}

// Sequential reader over the MUS input, mirroring mem_fread/mem_fseek usage.
class _MusReader {
  _MusReader(this._data);
  final Uint8List _data;
  int _pos = 0;

  void seek(int pos) => _pos = pos;

  // Returns the next byte, or null at EOF (mirrors mem_fread != 1).
  int? readByte() {
    if (_pos >= _data.length) return null;
    return _data[_pos++];
  }

  int? readUint16Le() {
    if (_pos + 2 > _data.length) return null;
    final int v = _data[_pos] | (_data[_pos + 1] << 8);
    _pos += 2;
    return v;
  }
}

/// Convert a MUS lump to a Standard MIDI (type-0) file. Returns the MIDI bytes.
///
/// 1:1 port of `mus2mid()` from mus2mid.c. Throws [Mus2MidException] on any
/// condition where the C returns failure (truncated input, bad event, etc.).
Uint8List mus2mid(Uint8List mus) {
  final _MusReader musinput = _MusReader(mus);
  final _MemFile midioutput = _MemFile();

  // Cached channel velocities (channelvelocities[]): all 127 initially.
  final List<int> channelvelocities = List<int>.filled(_numChannels, 127);

  // Timestamps between sequences of MUS events.
  int queuedtime = 0;

  // Counter for the length of the track.
  int tracksize = 0;

  // Channel map: MUS channel -> MIDI channel (-1 = unallocated).
  final List<int> channelMap = List<int>.filled(_numChannels, -1);

  // --- Helpers (translated from the static Write* functions) ---

  // Write a variable-length timestamp; returns true on (write) failure.
  // Updates queuedtime/tracksize like the C does.
  bool writeTime(int time) {
    int buffer = time & 0x7F;
    while ((time >>= 7) != 0) {
      buffer <<= 8;
      buffer |= ((time & 0x7F) | 0x80);
    }
    for (;;) {
      final int writeval = buffer & 0xFF;
      midioutput.writeByte(writeval);
      ++tracksize;
      if ((buffer & 0x80) != 0) {
        buffer >>= 8;
      } else {
        queuedtime = 0;
        return false;
      }
    }
  }

  bool writeEndTrack() {
    if (writeTime(queuedtime)) return true;
    midioutput.writeBytes(const <int>[0xFF, 0x2F, 0x00]);
    tracksize += 3;
    return false;
  }

  bool writePressKey(int channel, int key, int velocity) {
    if (writeTime(queuedtime)) return true;
    midioutput.writeByte(_midiPressKey | channel);
    midioutput.writeByte(key & 0x7F);
    midioutput.writeByte(velocity & 0x7F);
    tracksize += 3;
    return false;
  }

  bool writeReleaseKey(int channel, int key) {
    if (writeTime(queuedtime)) return true;
    midioutput.writeByte(_midiReleaseKey | channel);
    midioutput.writeByte(key & 0x7F);
    midioutput.writeByte(0);
    tracksize += 3;
    return false;
  }

  bool writePitchWheel(int channel, int wheel) {
    if (writeTime(queuedtime)) return true;
    midioutput.writeByte(_midiPitchWheel | channel);
    midioutput.writeByte(wheel & 0x7F);
    midioutput.writeByte((wheel >> 7) & 0x7F);
    tracksize += 3;
    return false;
  }

  bool writeChangePatch(int channel, int patch) {
    if (writeTime(queuedtime)) return true;
    midioutput.writeByte(_midiChangePatch | channel);
    midioutput.writeByte(patch & 0x7F);
    tracksize += 2;
    return false;
  }

  bool writeChangeControllerValued(int channel, int control, int value) {
    if (writeTime(queuedtime)) return true;
    midioutput.writeByte(_midiChangeController | channel);
    midioutput.writeByte(control & 0x7F);
    // Quirk in vanilla DOOM? MUS controller values should be 7-bit, not 8-bit.
    // Fix on said quirk to stop MIDI players complaining about out-of-range:
    int working = value & 0xFF;
    if ((working & 0x80) != 0) {
      working = 0x7F;
    }
    midioutput.writeByte(working);
    tracksize += 3;
    return false;
  }

  bool writeChangeControllerValueless(int channel, int control) {
    return writeChangeControllerValued(channel, control, 0);
  }

  // Allocate a free MIDI channel (AllocateMIDIChannel).
  int allocateMidiChannel() {
    int max = -1;
    for (int i = 0; i < _numChannels; ++i) {
      if (channelMap[i] > max) {
        max = channelMap[i];
      }
    }
    int result = max + 1;
    // Don't allocate the MIDI percussion channel!
    if (result == _midiPercussionChan) {
      ++result;
    }
    return result;
  }

  // Given a MUS channel number, get the MIDI channel to use (GetMIDIChannel).
  int getMidiChannel(int musChannel) {
    if (musChannel == _musPercussionChan) {
      return _midiPercussionChan;
    } else {
      if (channelMap[musChannel] == -1) {
        channelMap[musChannel] = allocateMidiChannel();
        // First time using the channel, send an "all notes off" event. This
        // fixes "The D_DDTBLU disease".
        writeChangeControllerValueless(channelMap[musChannel], 0x7B);
      }
      return channelMap[musChannel];
    }
  }

  // --- Read the MUS header (ReadMusHeader) ---
  final int? id0 = musinput.readByte();
  final int? id1 = musinput.readByte();
  final int? id2 = musinput.readByte();
  final int? id3 = musinput.readByte();
  final int? scorelength = musinput.readUint16Le();
  final int? scorestart = musinput.readUint16Le();
  final int? primarychannels = musinput.readUint16Le();
  final int? secondarychannels = musinput.readUint16Le();
  final int? instrumentcount = musinput.readUint16Le();
  if (id0 == null ||
      id1 == null ||
      id2 == null ||
      id3 == null ||
      scorelength == null ||
      scorestart == null ||
      primarychannels == null ||
      secondarychannels == null ||
      instrumentcount == null) {
    throw Mus2MidException('Truncated MUS header');
  }

  // Seek to where the data is held.
  musinput.seek(scorestart);

  // So, we can assume the MUS file is faintly legit. Start writing MIDI data.
  midioutput.writeBytes(_midiHeader);
  tracksize = 0;

  bool hitscoreend = false;

  // Now, process the MUS file:
  while (!hitscoreend) {
    // Handle a block of events:
    while (!hitscoreend) {
      // Fetch channel number and event code:
      final int? eventdescriptor = musinput.readByte();
      if (eventdescriptor == null) {
        throw Mus2MidException('Unexpected EOF reading event descriptor');
      }

      final int channel = getMidiChannel(eventdescriptor & 0x0F);
      final int event = eventdescriptor & 0x70;

      switch (event) {
        case _musReleaseKey:
          {
            final int? key = musinput.readByte();
            if (key == null) {
              throw Mus2MidException('EOF reading release key');
            }
            if (writeReleaseKey(channel, key)) {
              throw Mus2MidException('Write failure (release key)');
            }
            break;
          }

        case _musPressKey:
          {
            int? key = musinput.readByte();
            if (key == null) {
              throw Mus2MidException('EOF reading press key');
            }
            if ((key & 0x80) != 0) {
              final int? vel = musinput.readByte();
              if (vel == null) {
                throw Mus2MidException('EOF reading velocity');
              }
              channelvelocities[channel] = vel & 0x7F;
            }
            if (writePressKey(channel, key, channelvelocities[channel])) {
              throw Mus2MidException('Write failure (press key)');
            }
            break;
          }

        case _musPitchWheel:
          {
            final int? key = musinput.readByte();
            if (key == null) {
              // C: `break;` out of the switch (no failure).
              break;
            }
            if (writePitchWheel(channel, key * 64)) {
              throw Mus2MidException('Write failure (pitch wheel)');
            }
            break;
          }

        case _musSystemEvent:
          {
            final int? controllernumber = musinput.readByte();
            if (controllernumber == null) {
              throw Mus2MidException('EOF reading system event');
            }
            if (controllernumber < 10 || controllernumber > 14) {
              throw Mus2MidException('System controller out of range');
            }
            if (writeChangeControllerValueless(
                channel, _controllerMap[controllernumber])) {
              throw Mus2MidException('Write failure (system event)');
            }
            break;
          }

        case _musChangeController:
          {
            final int? controllernumber = musinput.readByte();
            if (controllernumber == null) {
              throw Mus2MidException('EOF reading controller number');
            }
            final int? controllervalue = musinput.readByte();
            if (controllervalue == null) {
              throw Mus2MidException('EOF reading controller value');
            }
            if (controllernumber == 0) {
              if (writeChangePatch(channel, controllervalue)) {
                throw Mus2MidException('Write failure (change patch)');
              }
            } else {
              if (controllernumber < 1 || controllernumber > 9) {
                throw Mus2MidException('Controller number out of range');
              }
              if (writeChangeControllerValued(
                  channel, _controllerMap[controllernumber], controllervalue)) {
                throw Mus2MidException('Write failure (change controller)');
              }
            }
            break;
          }

        case _musScoreEnd:
          hitscoreend = true;
          break;

        default:
          throw Mus2MidException(
              'Unknown MUS event 0x${event.toRadixString(16)}');
      }

      if ((eventdescriptor & 0x80) != 0) {
        break;
      }
    }

    // Now we need to read the time code:
    if (!hitscoreend) {
      int timedelay = 0;
      for (;;) {
        final int? working = musinput.readByte();
        if (working == null) {
          throw Mus2MidException('EOF reading time code');
        }
        timedelay = timedelay * 128 + (working & 0x7F);
        if ((working & 0x80) == 0) {
          break;
        }
      }
      queuedtime += timedelay;
    }
  }

  // End of track.
  if (writeEndTrack()) {
    throw Mus2MidException('Write failure (end track)');
  }

  // Write the track size into the stream (seek to offset 18).
  midioutput.patch4(
    18,
    (tracksize >> 24) & 0xFF,
    (tracksize >> 16) & 0xFF,
    (tracksize >> 8) & 0xFF,
    tracksize & 0xFF,
  );

  return midioutput.toBytes();
}
