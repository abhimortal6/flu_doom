// MIDI file parser, ported 1:1 from Chocolate Doom src/midifile.c +
// src/midifile.h.
//
// This reads the standard-MIDI output of [mus2mid] (an MThd header chunk
// followed by one or more MTrk track chunks) into timed events that the OPL
// player ([OplPlayer]) iterates with delta times. Only what the OPL player
// needs is consumed: note on/off, controller, program change, pitch bend, and
// meta tempo / end-of-track; SysEx and unhandled metas are read and skipped.
//
// FAITHFULNESS: the variable-length / running-status / chunk-size logic is a
// faithful port of midifile.c. The C reads from a FILE*; here we
// read from a byte buffer with an explicit cursor (the moral equivalent of
// fgetc / fseek(-1)). Big-endian field reads mirror SDL_SwapBE16/32.

import 'dart:typed_data';

// --- midifile.h enums (verbatim) ---

/// MIDI_CHANNELS_PER_TRACK.
const int kMidiChannelsPerTrack = 16;

/// midi_event_type_t.
class MidiEventType {
  static const int noteOff = 0x80;
  static const int noteOn = 0x90;
  static const int afterTouch = 0xA0;
  static const int controller = 0xB0;
  static const int programChange = 0xC0;
  static const int chanAfterTouch = 0xD0;
  static const int pitchBend = 0xE0;

  static const int sysEx = 0xF0;
  static const int sysExSplit = 0xF7;
  static const int meta = 0xFF;
}

/// midi_controller_t (subset used by the OPL player).
class MidiController {
  static const int volumeMsb = 0x07;
  static const int pan = 0x0A;
  static const int allNotesOff = 0x7B;
}

/// midi_meta_event_type_t.
class MidiMetaEventType {
  static const int sequenceNumber = 0x00;
  static const int text = 0x01;
  static const int copyright = 0x02;
  static const int trackName = 0x03;
  static const int instrName = 0x04;
  static const int lyrics = 0x05;
  static const int marker = 0x06;
  static const int cuePoint = 0x07;
  static const int channelPrefix = 0x20;
  static const int endOfTrack = 0x2F;
  static const int setTempo = 0x51;
  static const int smpteOffset = 0x54;
  static const int timeSignature = 0x58;
  static const int keySignature = 0x59;
  static const int sequencerSpecific = 0x7F;
}

/// Thrown when MIDI data is malformed. The player treats this as "no song".
class MidiException implements Exception {
  MidiException(this.message);
  final String message;
  @override
  String toString() => 'MidiException: $message';
}

/// midi_channel_event_data_t.
class MidiChannelEventData {
  MidiChannelEventData(this.channel, this.param1, this.param2);
  final int channel;
  final int param1;
  final int param2;
}

/// midi_meta_event_data_t / midi_sysex_event_data_t (data buffer).
class MidiMetaEventData {
  MidiMetaEventData(this.type, this.length, this.data);
  final int type;
  final int length;
  final Uint8List data;
}

/// midi_event_t. The C uses a union over channel/meta/sysex; we expose all
/// three as nullable fields (only one is set per [eventType]).
class MidiEvent {
  MidiEvent({
    required this.deltaTime,
    required this.eventType,
    this.channel,
    this.meta,
    this.sysex,
  });

  /// Time between the previous event and this event (ticks).
  final int deltaTime;

  /// Type of event (`event_type & 0xf0` for channel events, else the full
  /// 0xF0/0xF7/0xFF byte).
  final int eventType;

  final MidiChannelEventData? channel;
  final MidiMetaEventData? meta;
  final MidiMetaEventData? sysex;
}

/// One parsed track (midi_track_t): the flat list of events in order.
class MidiTrack {
  MidiTrack(this.events);
  final List<MidiEvent> events;
}

/// Cursor over a byte buffer that mirrors midifile.c's FILE* reads. Returns
/// false on EOF the way ReadByte does, and supports the single fseek(-1) used
/// for running status.
class _ByteReader {
  _ByteReader(this._data);
  final Uint8List _data;
  int _pos = 0;

  bool get eof => _pos >= _data.length;

  /// ReadByte: returns -1 on EOF.
  int readByte() {
    if (_pos >= _data.length) return -1;
    return _data[_pos++];
  }

  /// fseek(stream, -1, SEEK_CUR).
  void seekBack() {
    if (_pos > 0) _pos--;
  }

  int readBE16() {
    final int b0 = readByte();
    final int b1 = readByte();
    if (b0 < 0 || b1 < 0) throw MidiException('Unexpected EOF reading BE16');
    return (b0 << 8) | b1;
  }

  int readBE32() {
    final int b0 = readByte();
    final int b1 = readByte();
    final int b2 = readByte();
    final int b3 = readByte();
    if (b0 < 0 || b1 < 0 || b2 < 0 || b3 < 0) {
      throw MidiException('Unexpected EOF reading BE32');
    }
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  }

  /// ReadVariableLength: up to four 7-bit groups, MSB-continuation.
  int readVariableLength() {
    int result = 0;
    for (int i = 0; i < 4; i++) {
      final int b = readByte();
      if (b < 0) {
        throw MidiException('EOF reading variable-length value');
      }
      result <<= 7;
      result |= b & 0x7f;
      if ((b & 0x80) == 0) {
        return result;
      }
    }
    throw MidiException('Variable-length value too long (max four bytes)');
  }

  /// ReadByteSequence.
  Uint8List readByteSequence(int numBytes) {
    if (_pos + numBytes > _data.length) {
      throw MidiException('EOF reading byte sequence ($numBytes bytes)');
    }
    final Uint8List out = Uint8List.sublistView(_data, _pos, _pos + numBytes);
    _pos += numBytes;
    // Copy so the event owns its bytes independent of the source buffer.
    return Uint8List.fromList(out);
  }
}

/// A loaded MIDI file (midi_file_t): header time division + parsed tracks.
class MidiFile {
  MidiFile._(this.timeDivision, this._tracks);

  /// time_division from MThd (already de-SMPTE'd: negative SMPTE values are
  /// converted as in MIDI_GetFileTimeDivision).
  final int timeDivision;

  final List<MidiTrack> _tracks;

  /// MIDI_NumTracks.
  int get numTracks => _tracks.length;

  /// MIDI_GetFileTimeDivision.
  int get fileTimeDivision => timeDivision;

  MidiTrack track(int i) => _tracks[i];

  /// MIDI_IterateTrack.
  MidiTrackIterator iterateTrack(int i) => MidiTrackIterator(_tracks[i]);

  // ReadChannelEvent.
  static MidiEvent _readChannelEvent(
      _ByteReader r, int eventType, bool twoParam) {
    final int param1 = r.readByte();
    if (param1 < 0) throw MidiException('EOF reading channel event param1');
    int param2 = 0;
    if (twoParam) {
      param2 = r.readByte();
      if (param2 < 0) throw MidiException('EOF reading channel event param2');
    }
    return MidiEvent(
      deltaTime: 0, // set by caller after delta is read.
      eventType: eventType & 0xf0,
      channel: MidiChannelEventData(eventType & 0x0f, param1, param2),
    );
  }

  // ReadSysExEvent.
  static MidiEvent _readSysExEvent(_ByteReader r, int eventType) {
    final int length = r.readVariableLength();
    final Uint8List data = r.readByteSequence(length);
    return MidiEvent(
      deltaTime: 0,
      eventType: eventType,
      sysex: MidiMetaEventData(0, length, data),
    );
  }

  // ReadMetaEvent.
  static MidiEvent _readMetaEvent(_ByteReader r) {
    final int type = r.readByte();
    if (type < 0) throw MidiException('EOF reading meta event type');
    final int length = r.readVariableLength();
    final Uint8List data = r.readByteSequence(length);
    return MidiEvent(
      deltaTime: 0,
      eventType: MidiEventType.meta,
      meta: MidiMetaEventData(type, length, data),
    );
  }

  // ReadEvent: returns the event (with delta_time filled) and updates the
  // running last-event-type via the [_RunningStatus] holder.
  static MidiEvent _readEvent(_ByteReader r, _RunningStatus status) {
    final int deltaTime = r.readVariableLength();

    int eventType = r.readByte();
    if (eventType < 0) throw MidiException('EOF reading event type');

    // Running status: top bit clear -> reuse previous event type, rewind one.
    if ((eventType & 0x80) == 0) {
      eventType = status.lastEventType;
      r.seekBack();
    } else {
      status.lastEventType = eventType;
    }

    MidiEvent event;
    switch (eventType & 0xf0) {
      case MidiEventType.noteOff:
      case MidiEventType.noteOn:
      case MidiEventType.afterTouch:
      case MidiEventType.controller:
      case MidiEventType.pitchBend:
        event = _readChannelEvent(r, eventType, true);
        return _withDelta(event, deltaTime);
      case MidiEventType.programChange:
      case MidiEventType.chanAfterTouch:
        event = _readChannelEvent(r, eventType, false);
        return _withDelta(event, deltaTime);
      default:
        break;
    }

    switch (eventType) {
      case MidiEventType.sysEx:
      case MidiEventType.sysExSplit:
        return _withDelta(_readSysExEvent(r, eventType), deltaTime);
      case MidiEventType.meta:
        return _withDelta(_readMetaEvent(r), deltaTime);
      default:
        break;
    }

    throw MidiException(
        'Unknown MIDI event type: 0x${eventType.toRadixString(16)}');
  }

  static MidiEvent _withDelta(MidiEvent e, int deltaTime) => MidiEvent(
        deltaTime: deltaTime,
        eventType: e.eventType,
        channel: e.channel,
        meta: e.meta,
        sysex: e.sysex,
      );

  // ReadTrack: read the MTrk header, then events until end-of-track.
  static MidiTrack _readTrack(_ByteReader r) {
    // ReadTrackHeader.
    final int b0 = r.readByte();
    final int b1 = r.readByte();
    final int b2 = r.readByte();
    final int b3 = r.readByte();
    if (b0 < 0 || b1 < 0 || b2 < 0 || b3 < 0) {
      throw MidiException('EOF reading track chunk header');
    }
    if (b0 != 0x4D || b1 != 0x54 || b2 != 0x72 || b3 != 0x6B) {
      throw MidiException("Expected 'MTrk' chunk header");
    }
    r.readBE32(); // track->data_len (unused; we read until end-of-track).

    final List<MidiEvent> events = <MidiEvent>[];
    final _RunningStatus status = _RunningStatus();

    for (;;) {
      final MidiEvent event = _readEvent(r, status);
      events.add(event);
      if (event.eventType == MidiEventType.meta &&
          event.meta != null &&
          event.meta!.type == MidiMetaEventType.endOfTrack) {
        break;
      }
    }

    return MidiTrack(events);
  }

  /// MIDI_LoadFile + ReadFileHeader (from a byte buffer rather than a path).
  static MidiFile parse(Uint8List bytes) {
    final _ByteReader r = _ByteReader(bytes);

    // Header: 'MThd' + size(6) + format(2) + numTracks(2) + timeDivision(2).
    final int b0 = r.readByte();
    final int b1 = r.readByte();
    final int b2 = r.readByte();
    final int b3 = r.readByte();
    if (b0 != 0x4D || b1 != 0x54 || b2 != 0x68 || b3 != 0x64) {
      throw MidiException("Expected 'MThd' chunk header");
    }
    final int chunkSize = r.readBE32();
    if (chunkSize != 6) {
      throw MidiException('Invalid MIDI chunk header! chunk_size=$chunkSize');
    }
    final int formatType = r.readBE16();
    final int numTracks = r.readBE16();
    final int rawTimeDivision = r.readBE16();
    if ((formatType != 0 && formatType != 1) || numTracks < 1) {
      throw MidiException('Only type 0/1 MIDI files supported!');
    }

    // MIDI_GetFileTimeDivision: handle SMPTE (negative) time division.
    final int signed =
        rawTimeDivision >= 0x8000 ? rawTimeDivision - 0x10000 : rawTimeDivision;
    final int timeDivision;
    if (signed < 0) {
      timeDivision = (-(signed ~/ 256)) * (signed & 0xFF);
    } else {
      timeDivision = signed;
    }

    final List<MidiTrack> tracks = <MidiTrack>[];
    for (int i = 0; i < numTracks; i++) {
      tracks.add(_readTrack(r));
    }

    return MidiFile._(timeDivision, tracks);
  }
}

/// Holder for the running last-event-type (the C passes `&last_event_type`).
class _RunningStatus {
  int lastEventType = 0;
}

/// midi_track_iter_t: position over a track's events.
class MidiTrackIterator {
  MidiTrackIterator(this.track);
  final MidiTrack track;
  int position = 0;
  int loopPoint = 0;

  /// MIDI_GetDeltaTime: time until the next event (0 at end).
  int getDeltaTime() {
    if (position < track.events.length) {
      return track.events[position].deltaTime;
    }
    return 0;
  }

  /// MIDI_GetNextEvent: returns the next event or null at end.
  MidiEvent? getNextEvent() {
    if (position < track.events.length) {
      final MidiEvent e = track.events[position];
      position++;
      return e;
    }
    return null;
  }

  /// MIDI_RestartIterator.
  void restart() {
    position = 0;
    loopPoint = 0;
  }

  /// MIDI_SetLoopPoint.
  void setLoopPoint() => loopPoint = position;

  /// MIDI_RestartAtLoopPoint.
  void restartAtLoopPoint() => position = loopPoint;
}
