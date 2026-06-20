// Music engine: the high-level glue that turns a WAD MUS lump into looping
// OPL3 audio, plus the per-game-state song selection tables.
//
// Pipeline (per song):
//   WAD D_<name> (MUS or MIDI) --header sniff (I_OPL_RegisterSong)--> standard
//     MIDI (mus2mid for MUS lumps, passthrough for MThd lumps like Freedoom's)
//     --MidiFile.parse--> tracks --OplPlayer (i_oplmusic.c)--> OPL3 register
//     writes --Opl3.generateStream--> interleaved-stereo PCM --> WAV
//     --> AudioEngine.playMusic(looping).
//
// SELECTION TABLES (ported from s_sound.c + sounds.c):
//   - S_music[] : the musicenum_t -> "d_"+name lump-name table (musicForId).
//   - S_Start   : doom1 level music selection
//                 mnum = mus_e1m1 + (gameepisode-1)*9 + gamemap-1 (musicForLevel).
//
// LOOPING / NO-JANK: the full track is rendered offline to a single PCM buffer
// (a finite render of the looping song — one pass through every track to the
// end-of-track restart), then handed to soloud which loops the buffer in its
// own mixer thread. To avoid stalling a UI frame, the render runs in a Dart
// isolate (compute()); a synchronous path is also exposed for tests/headless.
//
// FALLBACK: every public method is failure-tolerant. If audio is disabled, the
// WAD lacks GENMIDI / the song, or any stage throws, the engine becomes a
// silent no-op and the game never crashes.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../wad/wad.dart';
import 'audio_engine.dart';
import 'genmidi.dart';
import 'midifile.dart';
import 'mus2mid.dart';
import 'opl3.dart';
import 'opl_player.dart';

// =====================================================================
// musicenum_t (sounds.h) — the music ids, index = ordinal.
// =====================================================================

/// Music ids, vanilla `musicenum_t`. Index = ordinal (mus_None == 0).
abstract final class Mus {
  static const int none = 0;
  static const int e1m1 = 1;
  static const int e1m2 = 2;
  static const int e1m3 = 3;
  static const int e1m4 = 4;
  static const int e1m5 = 5;
  static const int e1m6 = 6;
  static const int e1m7 = 7;
  static const int e1m8 = 8;
  static const int e1m9 = 9;
  static const int e2m1 = 10;
  static const int e2m2 = 11;
  static const int e2m3 = 12;
  static const int e2m4 = 13;
  static const int e2m5 = 14;
  static const int e2m6 = 15;
  static const int e2m7 = 16;
  static const int e2m8 = 17;
  static const int e2m9 = 18;
  static const int e3m1 = 19;
  static const int e3m2 = 20;
  static const int e3m3 = 21;
  static const int e3m4 = 22;
  static const int e3m5 = 23;
  static const int e3m6 = 24;
  static const int e3m7 = 25;
  static const int e3m8 = 26;
  static const int e3m9 = 27;
  static const int inter = 28;
  static const int intro = 29;
  static const int bunny = 30;
  static const int victor = 31;
  static const int introa = 32;
  static const int runnin = 33;
  static const int stalks = 34;
  static const int countd = 35;
  static const int betwee = 36;
  static const int doom = 37;
  static const int theDa = 38;
  static const int shawn = 39;
  static const int ddtblu = 40;
  static const int inCit = 41;
  static const int dead = 42;
  static const int stlks2 = 43;
  static const int theda2 = 44;
  static const int doom2 = 45;
  static const int ddtbl2 = 46;
  static const int runni2 = 47;
  static const int dead2 = 48;
  static const int stlks3 = 49;
  static const int romero = 50;
  static const int shawn2 = 51;
  static const int messag = 52;
  static const int count2 = 53;
  static const int ddtbl3 = 54;
  static const int ampie = 55;
  static const int theda3 = 56;
  static const int adrian = 57;
  static const int messg2 = 58;
  static const int romer2 = 59;
  static const int tense = 60;
  static const int shawn3 = 61;
  static const int openin = 62;
  static const int evil = 63;
  static const int ultima = 64;
  static const int readM = 65;
  static const int dm2ttl = 66;
  static const int dm2int = 67;
}

/// S_music[] base names (sounds.c). Index = [Mus] ordinal. Index 0 is the
/// NULL dummy. The played lump name is "d_" + base (see [musicForId]).
const List<String?> kMusicNames = <String?>[
  null, // mus_None
  'e1m1', 'e1m2', 'e1m3', 'e1m4', 'e1m5', 'e1m6', 'e1m7', 'e1m8', 'e1m9',
  'e2m1', 'e2m2', 'e2m3', 'e2m4', 'e2m5', 'e2m6', 'e2m7', 'e2m8', 'e2m9',
  'e3m1', 'e3m2', 'e3m3', 'e3m4', 'e3m5', 'e3m6', 'e3m7', 'e3m8', 'e3m9',
  'inter', 'intro', 'bunny', 'victor', 'introa', 'runnin', 'stalks', 'countd',
  'betwee', 'doom', 'the_da', 'shawn', 'ddtblu', 'in_cit', 'dead', 'stlks2',
  'theda2', 'doom2', 'ddtbl2', 'runni2', 'dead2', 'stlks3', 'romero', 'shawn2',
  'messag', 'count2', 'ddtbl3', 'ampie', 'theda3', 'adrian', 'messg2', 'romer2',
  'tense', 'shawn3', 'openin', 'evil', 'ultima', 'read_m', 'dm2ttl', 'dm2int',
];

/// The WAD lump name for music id [musicnum] ("d_" + base name), or null for
/// the NULL entry / out-of-range. Mirrors S_ChangeMusic's `"d_%s"` formatting.
String? musicForId(int musicnum) {
  if (musicnum <= 0 || musicnum >= kMusicNames.length) return null;
  final String? base = kMusicNames[musicnum];
  if (base == null) return null;
  return 'd_$base';
}

/// S_Start level-music selection for Doom 1 (registered/shareware, episodes
/// 1..3): mnum = mus_e1m1 + (gameepisode-1)*9 + gamemap-1. Returns the music id.
int musicForLevel(int gameepisode, int gamemap) {
  return Mus.e1m1 + (gameepisode - 1) * 9 + (gamemap - 1);
}

// =====================================================================
// Offline OPL render.
// =====================================================================

/// Sample rate for OPL rendering / soloud (matches the SFX path / soloud
/// default).
const int kMusicSampleRate = 44100;

/// Hard safety cap on render length (seconds) so a malformed/looping song can't
/// render forever. Real Doom tracks are well under this.
const int _kMaxRenderSeconds = 120;

/// Default cap used by the live game ([MusicEngine.maxRenderSeconds]). Bounding
/// the rendered audio window bounds the FIRST-SOUND LATENCY: the synchronous
/// OPL3 synth costs ~0.13s of CPU per second of audio at 44.1kHz, so a 96s song
/// (E1M1) would take ~15s to fully pre-render before playback could start. We
/// instead render up to this many seconds and let soloud loop that window. Most
/// Doom songs are shorter than this and still loop seamlessly; longer songs loop
/// at the cap with a minor seam — an acceptable trade for fast, jank-free start.
/// Rendering still runs in an isolate, so the UI never stalls regardless.
const int kDefaultMaxRenderSeconds = 35;

/// Sniff a music lump header and return standard MIDI bytes, faithfully to
/// I_OPL_RegisterSong (i_oplmusic.c). DMX MUS lumps ('M','U','S',0x1a) are
/// converted via mus2mid; standard MIDI lumps ('M','T','h','d', e.g. Freedoom's
/// D_* music) are passed through unchanged. Anything else is unsupported and
/// returns null (no throw). Mirrors IsMid()/MUS_HEADER_MAGIC in vanilla.
Uint8List? _toMidiBytes(Uint8List data) {
  if (data.length < 4) return null;
  // MUS magic: 'M','U','S',0x1a -> convert to MIDI (the shareware Doom path).
  if (data[0] == 0x4D && data[1] == 0x55 && data[2] == 0x53 && data[3] == 0x1A) {
    return mus2mid(data);
  }
  // MIDI magic: 'M','T','h','d' -> already standard MIDI; use the bytes directly
  // (this is the Freedoom path — vanilla's IsMid() does exactly this).
  if (data[0] == 0x4D && data[1] == 0x54 && data[2] == 0x68 && data[3] == 0x64) {
    return data;
  }
  // Unknown header: unsupported. Return null so the caller stays silent.
  return null;
}

/// Render a music lump (DMX MUS or standard MIDI) to an interleaved-stereo
/// 16-bit WAV buffer through the full sniff -> [mus2mid] (MUS only) -> MIDI ->
/// OplPlayer -> Opl3 pipeline. The header is sniffed exactly like vanilla
/// I_OPL_RegisterSong: MUS lumps are converted, MIDI lumps pass straight
/// through. Pure/synchronous; safe to run in an isolate. Returns null on any
/// failure or unsupported header (never throws).
Uint8List? renderMusToWav(Uint8List mus, Uint8List genmidiLump, int sampleRate,
    {int maxSeconds = _kMaxRenderSeconds}) {
  try {
    final Uint8List? midiBytes = _toMidiBytes(mus);
    if (midiBytes == null) return null; // unsupported header -> silent.
    final MidiFile file = MidiFile.parse(midiBytes);
    final GenMidi genmidi = GenMidi.parse(genmidiLump);

    final Opl3 opl = Opl3();
    opl.reset(sampleRate);

    final OplPlayer player = OplPlayer(opl: opl, genmidi: genmidi);
    player.initMusic();
    // looping:false for the render — we render up to maxSeconds of one pass and
    // let soloud loop the resulting buffer.
    player.playSong(file, looping: false);

    final int cap = maxSeconds < _kMaxRenderSeconds ? maxSeconds : _kMaxRenderSeconds;
    final int maxFrames = sampleRate * cap;
    final List<Int16List> chunks = <Int16List>[];
    int totalFrames = 0;
    int currentTick = 0;

    // Step event-by-event; render the audio between consecutive events.
    while (player.hasRunningTracks && totalFrames < maxFrames) {
      final int? next = player.nextEventTick;
      if (next == null) break;

      if (next > currentTick) {
        // Render (next - currentTick) ticks of audio at the current tempo.
        final double usPerTick = player.microsecondsPerTick;
        final int deltaTicks = next - currentTick;
        final double durationUs = deltaTicks * usPerTick;
        int frames = (durationUs * sampleRate / 1000000.0).round();
        if (frames > 0) {
          if (totalFrames + frames > maxFrames) {
            frames = maxFrames - totalFrames;
          }
          final Int16List buf = Int16List(frames * 2);
          opl.generateStream(buf, frames);
          chunks.add(buf);
          totalFrames += frames;
        }
        currentTick = next;
      }

      // Process all events due at currentTick (key-on/off etc.).
      player.processEventsUntil(currentTick);
    }

    if (totalFrames == 0) {
      // Nothing rendered (empty song). Still produce a short silent buffer so
      // the caller has a valid source; but report null so we don't loop silence.
      return null;
    }

    return _framesToWav(chunks, totalFrames, sampleRate);
  } catch (_) {
    return null;
  }
}

/// Arguments for the isolate render entry point.
class _RenderArgs {
  _RenderArgs(this.mus, this.genmidiLump, this.sampleRate, this.maxSeconds);
  final Uint8List mus;
  final Uint8List genmidiLump;
  final int sampleRate;
  final int maxSeconds;
}

/// Isolate entry point.
Uint8List? _renderEntry(_RenderArgs args) => renderMusToWav(
    args.mus, args.genmidiLump, args.sampleRate,
    maxSeconds: args.maxSeconds);

/// Pack interleaved-stereo Int16 chunks into a 16-bit PCM WAV.
Uint8List _framesToWav(List<Int16List> chunks, int totalFrames, int sampleRate) {
  const int channels = 2;
  const int bitsPerSample = 16;
  final int dataBytes = totalFrames * channels * (bitsPerSample ~/ 8);
  final int totalBytes = 44 + dataBytes;

  final Uint8List out = Uint8List(totalBytes);
  final ByteData bd = ByteData.sublistView(out);
  int p = 0;
  void putAscii(String s) {
    for (int i = 0; i < s.length; i++) {
      out[p++] = s.codeUnitAt(i);
    }
  }

  final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final int blockAlign = channels * (bitsPerSample ~/ 8);

  putAscii('RIFF');
  bd.setUint32(p, totalBytes - 8, Endian.little);
  p += 4;
  putAscii('WAVE');
  putAscii('fmt ');
  bd.setUint32(p, 16, Endian.little);
  p += 4;
  bd.setUint16(p, 1, Endian.little); // PCM
  p += 2;
  bd.setUint16(p, channels, Endian.little);
  p += 2;
  bd.setUint32(p, sampleRate, Endian.little);
  p += 4;
  bd.setUint32(p, byteRate, Endian.little);
  p += 4;
  bd.setUint16(p, blockAlign, Endian.little);
  p += 2;
  bd.setUint16(p, bitsPerSample, Endian.little);
  p += 2;
  putAscii('data');
  bd.setUint32(p, dataBytes, Endian.little);
  p += 4;

  // Copy the PCM samples.
  for (final Int16List chunk in chunks) {
    for (int i = 0; i < chunk.length; i++) {
      bd.setInt16(p, chunk[i], Endian.little);
      p += 2;
    }
  }

  return out;
}

// =====================================================================
// MusicEngine.
// =====================================================================

/// The high-level music engine wired to the game-state machine. Holds the WAD,
/// the GENMIDI lump, and the [AudioEngine]; renders + plays the current song
/// LOOPED, and swaps it on state changes. Silent no-op when audio is disabled.
class MusicEngine {
  MusicEngine({
    required this.wad,
    required this.audio,
    this.sampleRate = kMusicSampleRate,
    bool enabled = true,
    this.useIsolate = true,
    this.maxRenderSeconds = kDefaultMaxRenderSeconds,
    int musicVolume = 8,
  })  : _enabled = enabled && audio.initialized {
    setMusicVolume(musicVolume);
    if (_enabled) {
      // Cache the GENMIDI lump up-front; if it is missing, music is disabled.
      final Lump? gm = wad.lumpByName('GENMIDI');
      if (gm == null) {
        _enabled = false;
      } else {
        _genmidiLump = Uint8List.fromList(gm.bytes);
      }
    }
  }

  final WadFile wad;
  final AudioEngine audio;
  final int sampleRate;
  final bool useIsolate;

  /// Max seconds of audio to render per song (bounds first-sound latency; see
  /// [kDefaultMaxRenderSeconds]).
  final int maxRenderSeconds;

  bool _enabled;
  Uint8List? _genmidiLump;

  /// snd_MusicVolume mapped to 0..1 for the backend (user 0..15 -> 0..1).
  double _volume01 = 1.0;

  /// The currently-playing music id (0 == none). Used to avoid redundant
  /// restarts (S_ChangeMusic's `musicnum == mus_playing` guard).
  int _currentMusic = Mus.none;

  /// Handle of the playing stream, if any.
  MusicHandle? _handle;

  /// Whether playback is currently paused (I_OPL_PauseSong state). Tracked so a
  /// stream started AFTER pause() (e.g. a slow render that completes while the
  /// menu is open) comes up paused too.
  bool _paused = false;

  /// Monotonic token to discard stale async renders if the song changes mid-load.
  int _playToken = 0;

  /// Render cache so repeated visits to a song don't re-render (e.g. demo loop).
  final Map<String, Uint8List?> _wavCache = <String, Uint8List?>{};

  /// Debug counter: number of music buffers handed to the backend.
  int playCount = 0;

  /// True if the engine will actually produce audio.
  bool get enabled => _enabled;

  /// The currently-selected music id (for tests / debug).
  int get currentMusic => _currentMusic;

  /// S_SetMusicVolume: user 0..15 -> backend 0..1, applied live.
  void setMusicVolume(int userVolume0to15) {
    final int v = userVolume0to15.clamp(0, 15);
    _volume01 = v / 15.0;
    final MusicHandle? h = _handle;
    if (h != null) {
      audio.setMusicVolume(h, _volume01);
    }
  }

  /// S_ChangeMusic: start playing music id [musicnum] LOOPED. If it is already
  /// playing, this is a no-op. Failure-tolerant.
  Future<void> changeMusic(int musicnum, {bool looping = true}) async {
    if (!_enabled) return;
    if (musicnum == _currentMusic && _handle != null) return;

    final String? lumpName = musicForId(musicnum);
    if (lumpName == null) {
      await stop();
      _currentMusic = Mus.none;
      return;
    }

    _currentMusic = musicnum;
    final int token = ++_playToken;

    // Stop the previous stream first (S_StopMusic before S_StartMusic).
    await stop();
    if (token != _playToken) return; // superseded while awaiting.

    try {
      final Uint8List? wav = await _renderSong(lumpName);
      if (token != _playToken) return; // superseded.
      if (wav == null) return; // missing lump / empty render -> silent.

      final MusicHandle? handle =
          await audio.playMusic(lumpName, wav, volume: _volume01);
      if (token != _playToken) {
        // A newer request won; stop this one if it started.
        if (handle != null) await audio.stopMusic(handle);
        return;
      }
      _handle = handle;
      if (handle != null) {
        // If a pause was requested while this song was still rendering, bring
        // it up paused so opening the menu before the first render finishes
        // doesn't leak audio.
        if (_paused) {
          audio.pauseMusic(handle, true);
        }
        playCount++;
        assert(() {
          // ignore: avoid_print
          print('[flu_doom][music] play $lumpName '
              'vol=${_volume01.toStringAsFixed(2)} (#$playCount)');
          return true;
        }());
      }
    } catch (_) {
      // Any failure -> silent; never crash.
    }
  }

  /// I_OPL_PauseSong: pause the currently-playing music (idempotent). New songs
  /// started while paused come up paused too. Safe when disabled / no stream.
  void pause() {
    if (!_enabled || _paused) return;
    _paused = true;
    final MusicHandle? h = _handle;
    if (h != null) {
      audio.pauseMusic(h, true);
    }
  }

  /// I_OPL_ResumeSong: resume paused music (idempotent). Safe when disabled.
  void resume() {
    if (!_enabled || !_paused) return;
    _paused = false;
    final MusicHandle? h = _handle;
    if (h != null) {
      audio.pauseMusic(h, false);
    }
  }

  /// Whether music playback is currently paused.
  bool get isPaused => _paused;

  /// Render (or fetch from cache) the WAV for lump [lumpName]. Runs the synth in
  /// an isolate when [useIsolate] is set, else synchronously.
  Future<Uint8List?> _renderSong(String lumpName) async {
    if (_wavCache.containsKey(lumpName)) {
      return _wavCache[lumpName];
    }
    final Lump? lump = wad.lumpByName(lumpName);
    final Uint8List? gm = _genmidiLump;
    if (lump == null || gm == null) {
      _wavCache[lumpName] = null;
      return null;
    }
    final Uint8List mus = Uint8List.fromList(lump.bytes);

    Uint8List? wav;
    if (useIsolate) {
      try {
        wav = await compute(
            _renderEntry, _RenderArgs(mus, gm, sampleRate, maxRenderSeconds));
      } catch (_) {
        // Fall back to synchronous render if isolate spawn fails.
        wav = renderMusToWav(mus, gm, sampleRate, maxSeconds: maxRenderSeconds);
      }
    } else {
      wav = renderMusToWav(mus, gm, sampleRate, maxSeconds: maxRenderSeconds);
    }

    _wavCache[lumpName] = wav;
    return wav;
  }

  /// Render a song to a WAV buffer WITHOUT playing it (for tests / proof of a
  /// non-silent render). Returns null on failure.
  Uint8List? renderSongSync(int musicnum) {
    final String? lumpName = musicForId(musicnum);
    final Uint8List? gm = _genmidiLump ?? _loadGenmidi();
    if (lumpName == null || gm == null) return null;
    final Lump? lump = wad.lumpByName(lumpName);
    if (lump == null) return null;
    return renderMusToWav(Uint8List.fromList(lump.bytes), gm, sampleRate,
        maxSeconds: maxRenderSeconds);
  }

  Uint8List? _loadGenmidi() {
    final Lump? gm = wad.lumpByName('GENMIDI');
    if (gm == null) return null;
    return Uint8List.fromList(gm.bytes);
  }

  /// S_StopMusic: stop and release the current stream.
  Future<void> stop() async {
    final MusicHandle? h = _handle;
    _handle = null;
    if (h != null) {
      await audio.stopMusic(h);
    }
  }

  /// Stop and forget the current selection.
  Future<void> dispose() async {
    _playToken++;
    await stop();
    _currentMusic = Mus.none;
  }
}
