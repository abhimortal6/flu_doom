// SoundHook — injectable S_StartSound facade (audio is a later wave).
//
// Audio is not implemented in the combat wave, but every combat call site that
// vanilla Doom sounds at MUST call this hook so wiring real audio later is a
// one-line swap. Sound ids are the `Sfx.*` ordinals from sounds.dart.
//
// See lib/CONTRACTS_COMBAT.md §7.

/// S_StartSound(origin, sfx). `origin` is the Mobj (or null for ui/global);
/// kept as Object? so the play-sim need not depend on an audio type.
abstract interface class SoundHook {
  void startSound(Object? origin, int sfxId);
}

/// A no-op [SoundHook]. Constructed by PlaySim until a real audio backend is
/// wired in a later wave.
class NullSoundHook implements SoundHook {
  const NullSoundHook();

  @override
  void startSound(Object? origin, int sfxId) {}
}
