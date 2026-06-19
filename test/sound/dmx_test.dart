// DMX decoder + sfxinfo resolution unit tests, run against the REAL shareware
// doom1.wad (no audio device required — pure parsing).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart' show LoadMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/sound/audio_engine.dart';
import 'package:flu_doom/engine/sound/dmx.dart';
import 'package:flu_doom/engine/sound/sfx_sound_hook.dart';
import 'package:flu_doom/engine/sound/sfxinfo.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/sounds.dart';

void main() {
  late WadFile wad;

  setUpAll(() {
    final File f = File('assets/doom1.wad');
    expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
    wad = WadFile.fromBytes(f.readAsBytesSync());
  });

  group('decodeDmx', () {
    test('parses DSPISTOL header (format/rate/length)', () {
      final Lump lump = wad.getLump('DSPISTOL');
      final DmxSound dmx = decodeDmx(Uint8List.fromList(lump.bytes));

      // DMX format-3 sounds in the Doom IWAD are 11025 Hz.
      expect(dmx.sampleRate, 11025);

      // Re-derive the declared length from the raw header and check the
      // decoder stripped exactly the 32 pad bytes (16 lead + 16 trail).
      final Uint8List raw = Uint8List.fromList(lump.bytes);
      final int declared =
          (raw[7] << 24) | (raw[6] << 16) | (raw[5] << 8) | raw[4];
      expect(dmx.sampleCount, declared - 32);
      expect(dmx.samples.length, dmx.sampleCount);
      expect(dmx.sampleCount, greaterThan(0));
    });

    test('emits a valid little-endian 16-bit mono WAV header', () {
      final Lump lump = wad.getLump('DSPISTOL');
      final DmxSound dmx = decodeDmx(Uint8List.fromList(lump.bytes));
      final Uint8List wav = dmx.toWav();

      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      final ByteData bd = ByteData.sublistView(wav);
      expect(bd.getUint16(20, Endian.little), 1); // PCM
      expect(bd.getUint16(22, Endian.little), 1); // mono
      expect(bd.getUint32(24, Endian.little), 11025); // sample rate
      expect(bd.getUint16(34, Endian.little), 16); // bits/sample
      // data chunk = sampleCount * 2 bytes.
      expect(bd.getUint32(40, Endian.little), dmx.sampleCount * 2);
      expect(wav.length, 44 + dmx.sampleCount * 2);
    });

    test('rejects a non-DMX buffer', () {
      expect(() => decodeDmx(Uint8List.fromList(<int>[1, 2, 3, 4])),
          throwsA(isA<DmxException>()));
    });

    test('decodes several common SFX lumps without error', () {
      for (final String name in <String>[
        'DSSHOTGN',
        'DSDOROPN',
        'DSDORCLS',
        'DSSWTCHN',
        'DSITEMUP',
        'DSBAREXP',
      ]) {
        final Lump? lump = wad.lumpByName(name);
        expect(lump, isNotNull, reason: '$name should exist in doom1.wad');
        final DmxSound dmx = decodeDmx(Uint8List.fromList(lump!.bytes));
        expect(dmx.sampleCount, greaterThan(0));
      }
    });
  });

  group('sfxinfo table', () {
    test('has one entry per Sfx ordinal and matches vanilla priorities', () {
      expect(sfxInfo.length, 109); // NUMSFX (0..108).
      expect(sfxInfo[Sfx.pistol].priority, 64);
      expect(sfxInfo[Sfx.sawidl].priority, 118);
      expect(sfxInfo[Sfx.stnmov].priority, 119);
      expect(sfxInfo[Sfx.posact].priority, 120);
      expect(sfxInfo[Sfx.telept].priority, 32);
    });

    test('chgun links to pistol (vanilla SOUND_LINK)', () {
      expect(sfxInfo[Sfx.chgun].link, Sfx.pistol);
      expect(sfxInfo[Sfx.chgun].pitch, 150);
      // Linked lump name resolves to the linked sound's lump.
      expect(sfxLumpName(Sfx.chgun), 'DSPISTOL');
    });

    test('lump names resolve to real DS* lumps', () {
      for (final int id in <int>[
        Sfx.pistol,
        Sfx.shotgn,
        Sfx.doropn,
        Sfx.itemup,
        Sfx.barexp,
        Sfx.swtchn,
      ]) {
        final String name = sfxLumpName(id);
        expect(wad.hasLump(name), true, reason: '$name missing from doom1.wad');
      }
    });
  });

  group('SfxSoundHook (with a fake audio engine, no device)', () {
    test('startSound decodes + plays a centred sound for null origin', () async {
      final _FakeAudio fake = _FakeAudio();
      await fake.init();
      final SfxSoundHook hook = SfxSoundHook(
        wad: wad,
        audio: fake,
        listenerProvider: () => null,
        sfxVolume: 8,
      );

      hook.startSound(null, Sfx.pistol);
      // Lazy decode/load is async; let it complete.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.loaded, contains('DSPISTOL'));
      expect(fake.plays, isNotEmpty);
      // Centred: pan ~ 0.
      expect(fake.plays.first.pan.abs(), lessThan(0.01));
      expect(hook.playCount, greaterThan(0));
    });

    test('positioned sound off to one side pans non-centre', () async {
      final _FakeAudio fake = _FakeAudio();
      await fake.init();

      final Mobj listener = Mobj()
        ..x = 0
        ..y = 0
        ..angle = 0; // facing east (+x)
      final Mobj source = Mobj()
        ..x = 0
        ..y = 300 * 65536 // 300 units north (to the player's left)
        ..angle = 0;

      final SfxSoundHook hook = SfxSoundHook(
        wad: wad,
        audio: fake,
        listenerProvider: () => listener,
        sfxVolume: 8,
      );

      hook.startSound(source, Sfx.shotgn);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.plays, isNotEmpty);
      // Off-axis source must not be dead-centre.
      expect(fake.plays.first.pan.abs(), greaterThan(0.0));
    });

    test('distant sound beyond clipping distance is inaudible', () async {
      final _FakeAudio fake = _FakeAudio();
      await fake.init();

      final Mobj listener = Mobj()
        ..x = 0
        ..y = 0
        ..angle = 0;
      final Mobj source = Mobj()
        ..x = 5000 * 65536 // far beyond S_CLIPPING_DIST (1200 units)
        ..y = 0
        ..angle = 0;

      final SfxSoundHook hook = SfxSoundHook(
        wad: wad,
        audio: fake,
        listenerProvider: () => listener,
      );

      hook.startSound(source, Sfx.shotgn);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.plays, isEmpty);
      expect(hook.playCount, 0);
    });
  });
}

class _PlayCall {
  _PlayCall(this.volume, this.pan);
  final double volume;
  final double pan;
}

class _FakeLoaded implements LoadedSound {
  _FakeLoaded(this.name);
  final String name;
}

class _FakeAudio implements AudioEngine {
  bool _init = false;
  final List<String> loaded = <String>[];
  final List<_PlayCall> plays = <_PlayCall>[];

  @override
  bool get initialized => _init;

  @override
  Future<bool> init() async {
    _init = true;
    return true;
  }

  @override
  Future<LoadedSound> load(String name, Uint8List wavBytes) async {
    loaded.add(name);
    // Sanity: the buffer must be a WAV.
    expect(String.fromCharCodes(wavBytes.sublist(0, 4)), 'RIFF');
    return _FakeLoaded(name);
  }

  @override
  void play(LoadedSound sound, {required double volume, required double pan}) {
    plays.add(_PlayCall(volume, pan));
  }

  @override
  Future<void> dispose() async {}
}

// Reference LoadMode so the soloud import is exercised (and the test file
// documents that the WAV buffer is what loadMem(LoadMode.memory) consumes).
// ignore: unused_element
LoadMode get _wavLoadMode => LoadMode.memory;
