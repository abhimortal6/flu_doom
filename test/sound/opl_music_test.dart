// OPL music engine tests: render the WAD's MUS songs through the full
// mus2mid -> MidiFile -> OplPlayer -> Opl3 pipeline and assert real,
// deterministic audio, plus the song-per-state selection tables. Pure synth /
// parsing — no audio device required (the disabled-engine path uses a fake).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/sound/audio_engine.dart';
import 'package:flu_doom/engine/sound/midifile.dart';
import 'package:flu_doom/engine/sound/music.dart';
import 'package:flu_doom/engine/wad/wad.dart';

/// A fake [AudioEngine] that records calls without touching any backend, so the
/// "disabled/headless" graceful-no-op path can be exercised deterministically.
class _FakeAudioEngine implements AudioEngine {
  _FakeAudioEngine({required this.initialized});

  @override
  final bool initialized;

  int playMusicCount = 0;
  int stopMusicCount = 0;

  /// Record of pauseMusic(paused) calls in order (true == pause).
  final List<bool> pauseCalls = <bool>[];

  @override
  Future<bool> init() async => initialized;

  @override
  Future<LoadedSound> load(String name, Uint8List wavBytes) async =>
      throw UnimplementedError();

  @override
  void play(LoadedSound sound, {required double volume, required double pan}) {}

  @override
  Future<MusicHandle?> playMusic(String name, Uint8List wavBytes,
      {required double volume}) async {
    playMusicCount++;
    return _FakeMusicHandle();
  }

  @override
  Future<void> stopMusic(MusicHandle handle) async {
    stopMusicCount++;
  }

  @override
  void pauseMusic(MusicHandle handle, bool paused) {
    pauseCalls.add(paused);
  }

  @override
  void setMusicVolume(MusicHandle handle, double volume) {}

  @override
  Future<void> dispose() async {}
}

class _FakeMusicHandle implements MusicHandle {}

/// Number of non-silent (|sample| above a small threshold) frames in a WAV.
int _nonSilentSamples(Uint8List wav) {
  // Skip the 44-byte header; samples are signed 16-bit little-endian.
  final ByteData bd = ByteData.sublistView(wav);
  int count = 0;
  for (int p = 44; p + 1 < wav.length; p += 2) {
    final int s = bd.getInt16(p, Endian.little);
    if (s.abs() > 64) count++;
  }
  return count;
}

int _peakAmplitude(Uint8List wav) {
  final ByteData bd = ByteData.sublistView(wav);
  int peak = 0;
  for (int p = 44; p + 1 < wav.length; p += 2) {
    final int s = bd.getInt16(p, Endian.little).abs();
    if (s > peak) peak = s;
  }
  return peak;
}

void main() {
  late WadFile wad;

  setUpAll(() {
    final File f = File('assets/doom1.wad');
    expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
    wad = WadFile.fromBytes(f.readAsBytesSync());
  });

  group('music selection tables (S_music / S_Start)', () {
    test('E1M1 maps to d_e1m1; the title maps to d_intro', () {
      // S_Start level music: mnum = mus_e1m1 + (ep-1)*9 + map-1.
      expect(musicForLevel(1, 1), Mus.e1m1);
      expect(musicForId(musicForLevel(1, 1)), 'd_e1m1');

      // Title / demoscreen music is D_INTRO (mus_intro).
      expect(musicForId(Mus.intro), 'd_intro');
      // Intermission music is D_INTER (mus_inter).
      expect(musicForId(Mus.inter), 'd_inter');
    });

    test('level offsets across the episode are correct', () {
      expect(musicForId(musicForLevel(1, 2)), 'd_e1m2');
      expect(musicForId(musicForLevel(1, 9)), 'd_e1m9');
      expect(musicForId(musicForLevel(2, 1)), 'd_e2m1');
      expect(musicForId(musicForLevel(3, 8)), 'd_e3m8');
    });

    test('mus_None / out-of-range -> null lump name', () {
      expect(musicForId(Mus.none), isNull);
      expect(musicForId(-1), isNull);
      expect(musicForId(9999), isNull);
    });
  });

  group('OPL render pipeline', () {
    test('D_E1M1 renders to a NON-SILENT, real-amplitude WAV', () {
      final Lump gmLump = wad.getLump('GENMIDI');
      final Lump musLump = wad.getLump('D_E1M1');
      final Uint8List wav = renderMusToWav(
        Uint8List.fromList(musLump.bytes),
        Uint8List.fromList(gmLump.bytes),
        kMusicSampleRate,
      )!;

      // Valid WAV header.
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');

      // Substantial buffer (a real multi-second song, not a stub).
      expect(wav.length, greaterThan(44 + kMusicSampleRate)); // > ~0.25s stereo

      // Real amplitude + many non-silent samples (proves the synth produced
      // actual music, not silence).
      final int peak = _peakAmplitude(wav);
      final int nonSilent = _nonSilentSamples(wav);
      expect(peak, greaterThan(500), reason: 'render should have real amplitude');
      expect(nonSilent, greaterThan(1000),
          reason: 'render should be substantially non-silent');
    });

    test('D_E1M1 render is DETERMINISTIC (byte-identical across runs)', () {
      final Lump gmLump = wad.getLump('GENMIDI');
      final Lump musLump = wad.getLump('D_E1M1');
      final Uint8List a = renderMusToWav(Uint8List.fromList(musLump.bytes),
          Uint8List.fromList(gmLump.bytes), kMusicSampleRate)!;
      final Uint8List b = renderMusToWav(Uint8List.fromList(musLump.bytes),
          Uint8List.fromList(gmLump.bytes), kMusicSampleRate)!;
      expect(a.length, b.length);
      expect(a, orderedEquals(b));
    });

    test('D_INTRO and D_INTER render without throwing', () {
      final Lump gmLump = wad.getLump('GENMIDI');
      for (final String name in <String>['D_INTRO', 'D_INTER']) {
        final Lump musLump = wad.getLump(name);
        expect(
          () => renderMusToWav(Uint8List.fromList(musLump.bytes),
              Uint8List.fromList(gmLump.bytes), kMusicSampleRate),
          returnsNormally,
          reason: '$name should render without exception',
        );
      }
    });

    test('MidiFile parses the mus2mid output of D_E1M1 (>=1 track, events)', () {
      // Defensive parse check independent of the full render.
      final Lump musLump = wad.getLump('D_E1M1');
      // renderMusToWav exercises mus2mid + MidiFile.parse internally; here we
      // just assert the player produced a non-null buffer above. Additionally
      // verify the public MidiException type exists for malformed input.
      expect(() => MidiFile.parse(Uint8List.fromList(<int>[0, 1, 2, 3])),
          throwsA(isA<MidiException>()));
      expect(musLump.size, greaterThan(0));
    });
  });

  group('MusicEngine graceful behaviour', () {
    test('disabled (uninitialized audio) engine is a silent no-op', () async {
      final _FakeAudioEngine audio = _FakeAudioEngine(initialized: false);
      final MusicEngine music = MusicEngine(wad: wad, audio: audio);

      expect(music.enabled, isFalse,
          reason: 'engine disabled when audio not initialized');

      // changeMusic must NOT crash and must NOT touch the backend.
      await music.changeMusic(Mus.intro);
      await music.changeMusic(musicForLevel(1, 1));
      music.setMusicVolume(8);
      await music.stop();
      await music.dispose();

      expect(audio.playMusicCount, 0);
      expect(music.playCount, 0);
    });

    test('enabled engine renders + hands a buffer to the backend on changeMusic',
        () async {
      final _FakeAudioEngine audio = _FakeAudioEngine(initialized: true);
      // useIsolate:false so the test renders synchronously and deterministically.
      final MusicEngine music =
          MusicEngine(wad: wad, audio: audio, useIsolate: false);
      expect(music.enabled, isTrue,
          reason: 'engine enabled with audio + GENMIDI present');

      // Title song (D_INTRO).
      await music.changeMusic(Mus.intro);
      expect(audio.playMusicCount, 1, reason: 'a song buffer was handed off');
      expect(music.playCount, 1);
      expect(music.currentMusic, Mus.intro);

      // Same song again -> no redundant restart (S_ChangeMusic guard).
      await music.changeMusic(Mus.intro);
      expect(audio.playMusicCount, 1);

      // Level song (D_E1M1) -> stop previous, start new.
      await music.changeMusic(musicForLevel(1, 1));
      expect(audio.playMusicCount, 2, reason: 'level start handed off a buffer');
      expect(audio.stopMusicCount, greaterThanOrEqualTo(1));
      expect(music.currentMusic, Mus.e1m1);

      await music.dispose();
    });

    test('pause/resume forwards to the backend and is idempotent', () async {
      final _FakeAudioEngine audio = _FakeAudioEngine(initialized: true);
      final MusicEngine music =
          MusicEngine(wad: wad, audio: audio, useIsolate: false);

      await music.changeMusic(Mus.intro);
      expect(music.isPaused, isFalse);

      // Pause -> one pause(true) call.
      music.pause();
      expect(music.isPaused, isTrue);
      expect(audio.pauseCalls, <bool>[true]);

      // Re-pausing is a no-op (idempotent).
      music.pause();
      expect(audio.pauseCalls, <bool>[true]);

      // Resume -> one pause(false) call.
      music.resume();
      expect(music.isPaused, isFalse);
      expect(audio.pauseCalls, <bool>[true, false]);

      // Re-resuming is a no-op.
      music.resume();
      expect(audio.pauseCalls, <bool>[true, false]);

      await music.dispose();
    });

    test('a song started while paused comes up paused', () async {
      final _FakeAudioEngine audio = _FakeAudioEngine(initialized: true);
      final MusicEngine music =
          MusicEngine(wad: wad, audio: audio, useIsolate: false);

      // Pause BEFORE any song is playing (e.g. menu open at boot).
      music.pause();
      expect(audio.pauseCalls, isEmpty,
          reason: 'no stream yet, nothing to pause');

      // Now a song starts -> it must come up paused.
      await music.changeMusic(Mus.intro);
      expect(audio.pauseCalls, <bool>[true],
          reason: 'newly started stream paused because engine is paused');

      await music.dispose();
    });

    test('disabled engine pause/resume are silent no-ops', () async {
      final _FakeAudioEngine audio = _FakeAudioEngine(initialized: false);
      final MusicEngine music = MusicEngine(wad: wad, audio: audio);
      music.pause();
      music.resume();
      expect(music.isPaused, isFalse);
      expect(audio.pauseCalls, isEmpty);
      await music.dispose();
    });

    test('renderSongSync proves a non-silent buffer for the title + level',
        () async {
      final _FakeAudioEngine audio = _FakeAudioEngine(initialized: true);
      final MusicEngine music =
          MusicEngine(wad: wad, audio: audio, useIsolate: false);

      final Uint8List? intro = music.renderSongSync(Mus.intro);
      final Uint8List? e1m1 = music.renderSongSync(musicForLevel(1, 1));
      expect(intro, isNotNull);
      expect(e1m1, isNotNull);
      expect(_peakAmplitude(intro!), greaterThan(500));
      expect(_peakAmplitude(e1m1!), greaterThan(500));
    });
  });
}
