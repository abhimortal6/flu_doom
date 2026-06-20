// Audio backend wrapper around the flutter_soloud plugin.
//
// flutter_soloud (https://pub.dev/packages/flutter_soloud) is the chosen
// low-latency game-audio backend: it is a maintained Flutter plugin (platform
// channels, NOT FFI-into-our-engine — the engine logic stays pure Dart), it
// supports loading in-memory PCM/WAV buffers (`loadMem`), MANY concurrent
// voices, and per-voice volume + stereo pan (`play(volume:, pan:)`), on
// macOS + iOS + Android (and desktop/web). This thin wrapper is the ONLY place
// that touches the plugin, so the sound-sim ([SfxSoundHook]) stays testable and
// the engine never depends on the audio package directly.

import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// An opaque handle to a loaded, decoded sound buffer in the audio backend.
abstract interface class LoadedSound {}

/// An opaque handle to a playing, looping music stream in the audio backend.
abstract interface class MusicHandle {}

/// Abstract audio backend so the sound-sim can be unit-tested with a fake.
abstract interface class AudioEngine {
  /// True once [init] has completed successfully.
  bool get initialized;

  /// Initialize the backend. Returns true on success, false on failure
  /// (headless / no audio device) — never throws.
  Future<bool> init();

  /// Load a WAV/PCM buffer and return a reusable handle (cached by the caller).
  Future<LoadedSound> load(String name, Uint8List wavBytes);

  /// Play [sound] once. [volume] is 0..1, [pan] is -1 (left)..+1 (right).
  void play(LoadedSound sound, {required double volume, required double pan});

  /// Load a music WAV buffer and start it playing LOOPED at [volume] (0..1).
  /// Returns a handle for [stopMusic] / [setMusicVolume], or null on failure
  /// (never throws). The returned future completes once playback has started.
  Future<MusicHandle?> playMusic(String name, Uint8List wavBytes,
      {required double volume});

  /// Stop and release a looping music stream started by [playMusic].
  Future<void> stopMusic(MusicHandle handle);

  /// Adjust the volume (0..1) of a playing music stream.
  void setMusicVolume(MusicHandle handle, double volume);

  /// Release backend resources.
  Future<void> dispose();
}

class _SoLoudSound implements LoadedSound {
  _SoLoudSound(this.source);
  final AudioSource source;
}

class _SoLoudMusic implements MusicHandle {
  _SoLoudMusic(this.source, this.handle);
  final AudioSource source;
  final SoundHandle handle;
}

/// The real [AudioEngine] backed by flutter_soloud.
class SoLoudAudioEngine implements AudioEngine {
  final SoLoud _soloud = SoLoud.instance;
  bool _initialized = false;

  @override
  bool get initialized => _initialized;

  @override
  Future<bool> init() async {
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init();
      }
      _initialized = _soloud.isInitialized;
      return _initialized;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  @override
  Future<LoadedSound> load(String name, Uint8List wavBytes) async {
    final AudioSource src =
        await _soloud.loadMem(name, wavBytes, mode: LoadMode.memory);
    return _SoLoudSound(src);
  }

  @override
  void play(LoadedSound sound, {required double volume, required double pan}) {
    if (!_initialized) return;
    final AudioSource src = (sound as _SoLoudSound).source;
    // Fire-and-forget: we don't need the returned SoundHandle (one-shot SFX).
    try {
      _soloud.play(src, volume: volume, pan: pan);
    } catch (_) {
      // Ignore transient playback errors (e.g. max-voice-count reached).
    }
  }

  @override
  Future<MusicHandle?> playMusic(String name, Uint8List wavBytes,
      {required double volume}) async {
    if (!_initialized) return null;
    try {
      final AudioSource src =
          await _soloud.loadMem(name, wavBytes, mode: LoadMode.memory);
      // Note: SoundHandle is an extension type over int; the analyzer rejects
      // `await`-ing it directly (await_of_incompatible_type), so we obtain the
      // handle without await — play() resolves synchronously here.
      final SoundHandle handle =
          _soloud.play(src, volume: volume, looping: true);
      return _SoLoudMusic(src, handle);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> stopMusic(MusicHandle handle) async {
    if (!_initialized) return;
    final _SoLoudMusic m = handle as _SoLoudMusic;
    try {
      await _soloud.stop(m.handle);
      await _soloud.disposeSource(m.source);
    } catch (_) {
      // Ignore teardown errors.
    }
  }

  @override
  void setMusicVolume(MusicHandle handle, double volume) {
    if (!_initialized) return;
    final _SoLoudMusic m = handle as _SoLoudMusic;
    try {
      _soloud.setVolume(m.handle, volume);
    } catch (_) {
      // Ignore.
    }
  }

  @override
  Future<void> dispose() async {
    if (_initialized) {
      _soloud.deinit();
      _initialized = false;
    }
  }
}
