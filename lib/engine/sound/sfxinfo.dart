// sfxinfo_t table — ported 1:1 from Chocolate Doom src/doom/sounds.c S_sfx[].
//
// Indexed by the `Sfx.*` ordinals (sounds.dart / sfxenum_t). Each entry carries
// the lump name suffix, priority, singularity group, link target and pitch/
// volume offsets used by S_StartSound.
//
// The vanilla `sfxinfo_t` (i_sound.h) fields used by the play-sim sound path:
//   - name        : lump name without the "ds" prefix ("pistol" -> "DSPISTOL")
//   - priority    : channel-stealing priority (higher wins)
//   - singularity : `int singularity` — group id; same group from the same
//                    origin stops the previous. In vanilla sounds.c this field
//                    is initialised to 0 for every entry (the SOUND/SOUND_LINK
//                    macros set it 0), so it is effectively unused in shareware
//                    Doom; ported for fidelity.
//   - link        : index into S_sfx[] of the sound this aliases (-1 = none).
//                    Only sfx_chgun links (to sfx_pistol). A linked sound plays
//                    the linked lump and applies the volume/pitch offsets.
//   - pitch       : pitch offset when linked (-1 = NORM_PITCH/unused).
//   - volume      : volume offset when linked.
//
// Generated from sounds.c: every entry is SOUND(name, priority) with
// singularity=0, link=-1, pitch=-1, volume=0, EXCEPT sfx_chgun which is
// SOUND_LINK("chgun", 64, sfx_pistol, 150, 0).

import '../../game/play/sounds.dart';

/// One vanilla `sfxinfo_t` row.
class SfxInfo {
  const SfxInfo(
    this.name,
    this.priority, {
    this.singularity = 0,
    this.link = -1,
    this.pitch = -1,
    this.volume = 0,
  });

  /// Lump-name suffix; the WAD lump is "ds" + [name] uppercased ("DSPISTOL").
  final String name;

  /// Channel-stealing priority. Higher = harder to evict (S_GetChannel).
  final int priority;

  /// Singularity group (0 = none). Vanilla `singularity`.
  final int singularity;

  /// Index into [sfxInfo] of the linked (aliased) sound, or -1 for none.
  final int link;

  /// Pitch offset when linked (NORM_PITCH=128 baseline; -1 = unused).
  final int pitch;

  /// Volume offset (0..) applied when linked. Vanilla `volume`.
  final int volume;
}

/// NORM_PITCH (s_sound.c) — the un-shifted pitch baseline.
const int kNormPitch = 128;

/// The vanilla S_sfx[] table, indexed by `Sfx.*`. Entry 0 is the dummy "none".
const List<SfxInfo> sfxInfo = <SfxInfo>[
  SfxInfo('none', 0),
  SfxInfo('pistol', 64),
  SfxInfo('shotgn', 64),
  SfxInfo('sgcock', 64),
  SfxInfo('dshtgn', 64),
  SfxInfo('dbopn', 64),
  SfxInfo('dbcls', 64),
  SfxInfo('dbload', 64),
  SfxInfo('plasma', 64),
  SfxInfo('bfg', 64),
  SfxInfo('sawup', 64),
  SfxInfo('sawidl', 118),
  SfxInfo('sawful', 64),
  SfxInfo('sawhit', 64),
  SfxInfo('rlaunc', 64),
  SfxInfo('rxplod', 70),
  SfxInfo('firsht', 70),
  SfxInfo('firxpl', 70),
  SfxInfo('pstart', 100),
  SfxInfo('pstop', 100),
  SfxInfo('doropn', 100),
  SfxInfo('dorcls', 100),
  SfxInfo('stnmov', 119),
  SfxInfo('swtchn', 78),
  SfxInfo('swtchx', 78),
  SfxInfo('plpain', 96),
  SfxInfo('dmpain', 96),
  SfxInfo('popain', 96),
  SfxInfo('vipain', 96),
  SfxInfo('mnpain', 96),
  SfxInfo('pepain', 96),
  SfxInfo('slop', 78),
  SfxInfo('itemup', 78),
  SfxInfo('wpnup', 78),
  SfxInfo('oof', 96),
  SfxInfo('telept', 32),
  SfxInfo('posit1', 98),
  SfxInfo('posit2', 98),
  SfxInfo('posit3', 98),
  SfxInfo('bgsit1', 98),
  SfxInfo('bgsit2', 98),
  SfxInfo('sgtsit', 98),
  SfxInfo('cacsit', 98),
  SfxInfo('brssit', 94),
  SfxInfo('cybsit', 92),
  SfxInfo('spisit', 90),
  SfxInfo('bspsit', 90),
  SfxInfo('kntsit', 90),
  SfxInfo('vilsit', 90),
  SfxInfo('mansit', 90),
  SfxInfo('pesit', 90),
  SfxInfo('sklatk', 70),
  SfxInfo('sgtatk', 70),
  SfxInfo('skepch', 70),
  SfxInfo('vilatk', 70),
  SfxInfo('claw', 70),
  SfxInfo('skeswg', 70),
  SfxInfo('pldeth', 32),
  SfxInfo('pdiehi', 32),
  SfxInfo('podth1', 70),
  SfxInfo('podth2', 70),
  SfxInfo('podth3', 70),
  SfxInfo('bgdth1', 70),
  SfxInfo('bgdth2', 70),
  SfxInfo('sgtdth', 70),
  SfxInfo('cacdth', 70),
  SfxInfo('skldth', 70),
  SfxInfo('brsdth', 32),
  SfxInfo('cybdth', 32),
  SfxInfo('spidth', 32),
  SfxInfo('bspdth', 32),
  SfxInfo('vildth', 32),
  SfxInfo('kntdth', 32),
  SfxInfo('pedth', 32),
  SfxInfo('skedth', 32),
  SfxInfo('posact', 120),
  SfxInfo('bgact', 120),
  SfxInfo('dmact', 120),
  SfxInfo('bspact', 100),
  SfxInfo('bspwlk', 100),
  SfxInfo('vilact', 100),
  SfxInfo('noway', 78),
  SfxInfo('barexp', 60),
  SfxInfo('punch', 64),
  SfxInfo('hoof', 70),
  SfxInfo('metal', 70),
  // sfx_chgun: SOUND_LINK("chgun", 64, sfx_pistol, 150, 0).
  SfxInfo('chgun', 64, link: Sfx.pistol, pitch: 150, volume: 0),
  SfxInfo('tink', 60),
  SfxInfo('bdopn', 100),
  SfxInfo('bdcls', 100),
  SfxInfo('itmbk', 100),
  SfxInfo('flame', 32),
  SfxInfo('flamst', 32),
  SfxInfo('getpow', 60),
  SfxInfo('bospit', 70),
  SfxInfo('boscub', 70),
  SfxInfo('bossit', 70),
  SfxInfo('bospn', 70),
  SfxInfo('bosdth', 70),
  SfxInfo('manatk', 70),
  SfxInfo('mandth', 70),
  SfxInfo('sssit', 70),
  SfxInfo('ssdth', 70),
  SfxInfo('keenpn', 70),
  SfxInfo('keendt', 70),
  SfxInfo('skeact', 70),
  SfxInfo('skesit', 70),
  SfxInfo('skeatk', 70),
  SfxInfo('radio', 60),
];

/// Resolve the WAD lump name for a sfx id: "ds" + name (vanilla GetSfxLumpName
/// with use_sfx_prefix). A linked sound resolves to the linked sound's lump.
String sfxLumpName(int sfxId) {
  SfxInfo sfx = sfxInfo[sfxId];
  if (sfx.link >= 0) {
    sfx = sfxInfo[sfx.link];
  }
  return 'DS${sfx.name.toUpperCase()}';
}
