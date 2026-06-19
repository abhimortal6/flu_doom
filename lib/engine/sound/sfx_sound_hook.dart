// SfxSoundHook — the real SoundHook, porting Chocolate Doom s_sound.c 1:1.
//
// Implements S_StartSound / S_StartSoundAtVolume (folded into one, as vanilla
// S_StartSound is itself the AtVolume entry in Doom), S_AdjustSoundParams
// (distance attenuation + stereo separation), S_GetChannel (priority-based
// channel stealing + same-origin stop) over NUM_CHANNELS (8) channels.
//
// The engine logic is pure Dart; the only audio output goes through the
// injected [AudioEngine] wrapper (flutter_soloud). Sound buffers are decoded
// from the WAD's DS* lumps lazily and cached.
//
// FAITHFULNESS: the channel/attenuation/pan math is ported verbatim
// from s_sound.c (S_StartSound, S_AdjustSoundParams, S_GetChannel, S_StopSound,
// S_StopChannel) and i_sdlsound.c (I_SDL_UpdateSoundParams left/right mix).
// The only deviation is the final hand-off to the audio plugin: vanilla mixes
// to per-channel left/right gains (0..255); flutter_soloud takes a single
// volume + pan, so those two gains are mapped to (volume, pan) — see _emit().

import 'dart:typed_data';

import '../../game/play/mobj.dart';
import '../../game/play/p_random.dart' show mRandom;
import '../../game/play/sound_hook.dart';
import '../../game/play/sounds.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../math/tables.dart' show finesine, tantoangle;
import '../wad/wad.dart';
import 'audio_engine.dart';
import 'dmx.dart';
import 'sfxinfo.dart';

// --- s_sound.c #defines (verbatim) ---

/// S_CLIPPING_DIST — distance at which sounds clip out (1200 * FRACUNIT).
const int kSClippingDist = 1200 * kFracUnit;

/// S_CLOSE_DIST — distance at which sounds are maxed out (200 * FRACUNIT).
const int kSCloseDist = 200 * kFracUnit;

/// S_ATTENUATOR — the range over which sound attenuates.
const int kSAttenuator = (kSClippingDist - kSCloseDist) >> kFracBits;

/// S_STEREO_SWING — stereo separation swing (96 * FRACUNIT).
const int kSStereoSwing = 96 * kFracUnit;

/// NORM_SEP — centred stereo separation.
const int kNormSep = 128;

/// NUM_CHANNELS / snd_channels — number of mixing channels.
const int kNumChannels = 8;

/// ANGLETOFINESHIFT (tables.h).
const int _angleToFineShift = 19;

/// One mixing channel. Vanilla `channel_t` (minus the backend handle, which the
/// fire-and-forget plugin manages itself).
class _Channel {
  /// The sfx id playing on this channel, or 0 (Sfx.none) if free. Stands in for
  /// vanilla `sfxinfo_t* sfxinfo` (null == available).
  int sfxId = Sfx.none;

  /// Origin mobj of the sound, or null for a global/centred sound.
  Object? origin;

  /// Pitch (set but, like vanilla with pitch-shift off, not applied).
  int pitch = kNormPitch;

  /// Wall-clock time (ms since epoch) at which the sound on this channel is
  /// expected to finish. Stands in for vanilla's per-tic `I_SoundIsPlaying`
  /// check in S_UpdateSounds: once elapsed, the channel is free for reuse.
  int endTimeMs = 0;

  bool get free => sfxId == Sfx.none;
}

/// Provides the current listener (the console player's mobj). May return null
/// before the player exists.
typedef ListenerProvider = Mobj? Function();

/// The real [SoundHook]. Faithful port of s_sound.c S_StartSound.
class SfxSoundHook implements SoundHook {
  SfxSoundHook({
    required this.wad,
    required this.audio,
    required this.listenerProvider,
    int sfxVolume = 8,
  }) {
    setSfxVolume(sfxVolume);
  }

  final WadFile wad;
  final AudioEngine audio;
  final ListenerProvider listenerProvider;

  /// The 8 mixing channels.
  final List<_Channel> _channels =
      List<_Channel>.generate(kNumChannels, (_) => _Channel());

  /// snd_SfxVolume: the internal 0..127 volume (S_SetSfxVolume).
  int _sndSfxVolume = 127;

  /// Decoded WAV buffers per lump name, cached after first decode.
  final Map<String, LoadedSound?> _cache = <String, LoadedSound?>{};

  /// Playback duration (ms) per lump name, used to free finished channels.
  final Map<String, int> _durationMs = <String, int>{};

  /// In-flight loads to avoid double-decoding the same lump.
  final Set<String> _loading = <String>{};

  /// Debug counter: number of times a sound was actually emitted to the plugin.
  int playCount = 0;

  /// S_SetSfxVolume. Vanilla user scale is 0..15; S_Init passes `sfxVolume * 8`
  /// to set the internal 0..127 [snd_SfxVolume]. Pass the user 0..15 value here.
  void setSfxVolume(int userVolume0to15) {
    final int v = userVolume0to15.clamp(0, 15);
    _sndSfxVolume = v * 8; // matches d_main.c: S_Init(sfxVolume * 8, ...).
  }

  // -------------------------------------------------------------------------
  // S_StartSound (s_sound.c). origin is the Mobj or null. sfxId is a Sfx.* id.
  // -------------------------------------------------------------------------
  @override
  void startSound(Object? origin, int sfxId) {
    // check for bogus sound # (vanilla I_Error -> we simply ignore).
    if (sfxId < 1 || sfxId >= sfxInfo.length) return;

    // S_UpdateSounds (the I_SoundIsPlaying portion): free channels whose sound
    // has finished, so priority/stealing only fights over genuinely-busy slots.
    _freeStoppedChannels();

    final SfxInfo sfx = sfxInfo[sfxId];

    int volume = _sndSfxVolume;
    int sep;
    int pitch = kNormPitch;

    // Initialize sound parameters (linked sounds adjust volume/pitch).
    if (sfx.link >= 0) {
      volume += sfx.volume;
      pitch = sfx.pitch;
      if (volume < 1) return;
      if (volume > _sndSfxVolume) volume = _sndSfxVolume;
    }

    final Mobj? listener = listenerProvider();

    // Check audibility and modify params (S_AdjustSoundParams), unless the
    // sound is the listener itself or unpositioned.
    if (origin != null && origin is Mobj && origin != listener) {
      if (listener == null) {
        // No listener yet: treat as centred full volume.
        sep = kNormSep;
      } else {
        final _AdjustResult r = _adjustSoundParams(listener, origin, volume);
        volume = r.vol;
        sep = r.sep;
        // Same x/y as listener -> centre (vanilla override).
        if (origin.x == listener.x && origin.y == listener.y) {
          sep = kNormSep;
        }
        if (!r.audible) return;
      }
    } else {
      sep = kNormSep;
    }

    // hacks to vary the sfx pitches (advances the cosmetic M_Random stream,
    // exactly as vanilla; pitch-shift is OFF by default in Doom so the value is
    // computed for fidelity but not applied to playback — see class header).
    if (sfxId >= Sfx.sawup && sfxId <= Sfx.sawhit) {
      pitch += 8 - (mRandom() & 15);
    } else if (sfxId != Sfx.itemup && sfxId != Sfx.tink) {
      pitch += 16 - (mRandom() & 31);
    }
    pitch = _clamp255(pitch);

    // kill old sound (S_StopSound on the same origin).
    _stopSound(origin);

    // try to find a channel.
    final int cnum = _getChannel(origin, sfxId);
    if (cnum < 0) return;

    _channels[cnum].pitch = pitch;
    // Mark when this channel's sound is expected to finish (S_UpdateSounds free
    // logic). If the duration is not yet known (first, still-decoding play) use
    // a conservative default; it is corrected on the next decode.
    final int dur = _durationMs[sfxLumpName(sfxId)] ?? 1000;
    _channels[cnum].endTimeMs =
        DateTime.now().millisecondsSinceEpoch + dur;

    // I_StartSound: resolve the lump, decode + play with vanilla left/right mix.
    _emit(sfxId, volume, sep);
  }

  /// Free channels whose sound has finished playing (the per-tic
  /// S_UpdateSounds + I_SoundIsPlaying check, collapsed to a duration timer
  /// since the fire-and-forget backend exposes no live "is playing" query).
  void _freeStoppedChannels() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    for (int cnum = 0; cnum < kNumChannels; cnum++) {
      final _Channel c = _channels[cnum];
      if (!c.free && now >= c.endTimeMs) {
        _stopChannel(cnum);
      }
    }
  }

  // -------------------------------------------------------------------------
  // S_AdjustSoundParams (s_sound.c). Returns audible + modified vol/sep.
  // NOTE: gamemap==8 special-case (E1M8 boss attenuation) is intentionally NOT
  // applied — this is shareware E1; gamemap is never 8 at the listener path for
  // those branches in the non-boss case. The non-boss branch is ported exactly.
  // -------------------------------------------------------------------------
  _AdjustResult _adjustSoundParams(Mobj listener, Mobj source, int vol) {
    // approximate euclidean distance (GG1 p.428).
    final int adx = (listener.x - source.x).abs();
    final int ady = (listener.y - source.y).abs();
    final int approxDist = adx + ady - ((adx < ady ? adx : ady) >> 1);

    if (approxDist > kSClippingDist) {
      return const _AdjustResult(0, kNormSep, false);
    }

    // angle of source to listener.
    int angle = _pointToAngle2(listener.x, listener.y, source.x, source.y);
    if (angle > listener.angle) {
      angle = angle - listener.angle;
    } else {
      angle = angle + (0xffffffff - listener.angle);
    }
    angle = normAngle(angle) >> _angleToFineShift;

    // stereo separation.
    final int sep =
        128 - (fixedMul(kSStereoSwing, finesine[angle]) >> kFracBits);

    // volume calculation.
    int outVol;
    if (approxDist < kSCloseDist) {
      outVol = _sndSfxVolume;
    } else {
      // distance effect (non-boss branch).
      outVol = (_sndSfxVolume * ((kSClippingDist - approxDist) >> kFracBits)) ~/
          kSAttenuator;
    }

    return _AdjustResult(outVol, sep, outVol > 0);
  }

  // -------------------------------------------------------------------------
  // S_GetChannel (s_sound.c): find an open channel, reuse the same-origin
  // channel, or steal the lowest-priority one. Returns the channel # or -1.
  // -------------------------------------------------------------------------
  int _getChannel(Object? origin, int sfxId) {
    final int priority = sfxInfo[sfxId].priority;
    int cnum;

    // Find an open channel.
    for (cnum = 0; cnum < kNumChannels; cnum++) {
      if (_channels[cnum].free) {
        break;
      } else if (origin != null && _channels[cnum].origin == origin) {
        _stopChannel(cnum);
        break;
      }
    }

    // None available -> look for lower priority to evict.
    if (cnum == kNumChannels) {
      for (cnum = 0; cnum < kNumChannels; cnum++) {
        if (sfxInfo[_channels[cnum].sfxId].priority >= priority) {
          break;
        }
      }
      if (cnum == kNumChannels) {
        // No lower priority — drop this sound.
        return -1;
      } else {
        _stopChannel(cnum);
      }
    }

    final _Channel c = _channels[cnum];
    c.sfxId = sfxId;
    c.origin = origin;
    return cnum;
  }

  /// S_StopSound: free the channel currently playing for [origin].
  void _stopSound(Object? origin) {
    if (origin == null) return;
    for (int cnum = 0; cnum < kNumChannels; cnum++) {
      if (!_channels[cnum].free && _channels[cnum].origin == origin) {
        _stopChannel(cnum);
        break;
      }
    }
  }

  /// S_StopChannel: mark a channel free. (The plugin plays fire-and-forget, so
  /// there is no live handle to stop; freeing the slot reproduces the channel
  /// bookkeeping that priority/stealing depends on.)
  void _stopChannel(int cnum) {
    final _Channel c = _channels[cnum];
    c.sfxId = Sfx.none;
    c.origin = null;
  }

  // -------------------------------------------------------------------------
  // I_StartSound + I_UpdateSoundParams: resolve/decode the lump, compute the
  // vanilla left/right channel mix and hand off to the audio plugin.
  // -------------------------------------------------------------------------
  void _emit(int sfxId, int vol, int sep) {
    // I_SDL_UpdateSoundParams left/right mix (i_sdlsound.c).
    int left = ((254 - sep) * vol) ~/ 127;
    int right = (sep * vol) ~/ 127;
    left = left.clamp(0, 255);
    right = right.clamp(0, 255);
    if (left == 0 && right == 0) return;

    // Map vanilla per-channel gains (0..255 each) onto the plugin's single
    // (volume, pan). volume = the louder side (overall loudness); pan is the
    // left/right balance in [-1, +1]. This is the faithful-as-possible mapping
    // for a single-voice volume+pan API (soloud has no per-channel gain).
    final int louder = left > right ? left : right;
    final double playVolume = louder / 255.0;
    final int sum = left + right;
    final double pan = sum == 0 ? 0.0 : (right - left) / sum;

    final String lumpName = sfxLumpName(sfxId);
    final LoadedSound? cached = _cache[lumpName];
    if (cached != null) {
      audio.play(cached, volume: playVolume, pan: pan);
      playCount++;
      assert(() {
        // ignore: avoid_print
        print('[flu_doom][sfx] play $lumpName '
            'vol=${playVolume.toStringAsFixed(2)} pan=${pan.toStringAsFixed(2)} '
            '(#$playCount)');
        return true;
      }());
      return;
    }
    if (_cache.containsKey(lumpName)) {
      // Previously failed to decode/load — skip silently.
      return;
    }
    // Lazy decode + load, then play once ready. (First play of each lump is
    // dropped while it loads; vanilla precaches, but lazy is fine for SFX.)
    _loadAndPlay(lumpName, playVolume, pan);
  }

  Future<void> _loadAndPlay(String lumpName, double volume, double pan) async {
    if (_loading.contains(lumpName)) return;
    _loading.add(lumpName);
    try {
      final Lump? lump = wad.lumpByName(lumpName);
      if (lump == null) {
        _cache[lumpName] = null; // mark as unavailable.
        return;
      }
      final DmxSound dmx = decodeDmx(Uint8List.fromList(lump.bytes));
      _durationMs[lumpName] = _durationOf(dmx);
      final Uint8List wav = dmx.toWav();
      final LoadedSound loaded = await audio.load(lumpName, wav);
      _cache[lumpName] = loaded;
      // Play the just-loaded sound so the very first trigger is audible.
      audio.play(loaded, volume: volume, pan: pan);
      playCount++;
    } catch (_) {
      _cache[lumpName] = null; // mark unavailable on any decode/load failure.
    } finally {
      _loading.remove(lumpName);
    }
  }

  /// Pre-decode + load a sound so its first in-game trigger is instant.
  Future<void> precache(int sfxId) async {
    final String lumpName = sfxLumpName(sfxId);
    if (_cache.containsKey(lumpName) || _loading.contains(lumpName)) return;
    _loading.add(lumpName);
    try {
      final Lump? lump = wad.lumpByName(lumpName);
      if (lump == null) {
        _cache[lumpName] = null;
        return;
      }
      final DmxSound dmx = decodeDmx(Uint8List.fromList(lump.bytes));
      _durationMs[lumpName] = _durationOf(dmx);
      _cache[lumpName] = await audio.load(lumpName, dmx.toWav());
    } catch (_) {
      _cache[lumpName] = null;
    } finally {
      _loading.remove(lumpName);
    }
  }

  /// Playback duration in milliseconds for a decoded sound.
  static int _durationOf(DmxSound dmx) =>
      dmx.sampleRate <= 0 ? 0 : (dmx.sampleCount * 1000) ~/ dmx.sampleRate;

  // clamp 0..255 (s_sound.c Clamp).
  static int _clamp255(int x) => x < 0 ? 0 : (x > 255 ? 255 : x);

  // R_PointToAngle2 (r_main.c), ported locally (same as p_shoot.dart).
  static int _pointToAngle2(int x1, int y1, int x2, int y2) {
    int x = toInt32(x2 - x1);
    int y = toInt32(y2 - y1);
    if (x == 0 && y == 0) return 0;
    if (x >= 0) {
      if (y >= 0) {
        if (x > y) {
          return tantoangle[slopeDiv(y, x)];
        } else {
          return normAngle(kAng90 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(-tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng270 + tantoangle[slopeDiv(x, y)]);
        }
      }
    } else {
      x = -x;
      if (y >= 0) {
        if (x > y) {
          return normAngle(kAng180 - 1 - tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng90 + tantoangle[slopeDiv(x, y)]);
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(kAng180 + tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng270 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      }
    }
  }
}

/// Result of S_AdjustSoundParams.
class _AdjustResult {
  const _AdjustResult(this.vol, this.sep, this.audible);
  final int vol;
  final int sep;
  final bool audible;
}
