// Injected interfaces for the GAME-STATE + UI subsystems.
//
// This subsystem (g_game / st_stuff / hu_stuff / am_map / m_menu / wi_stuff)
// must NOT depend on the concrete play-simulation or 3D renderer types. Per the
// project boundaries it uses *dependency inversion*: the integration layer
// supplies implementations of the interfaces below, wiring them to the real
// playsim (player state) and renderer (3D view).
//
// See lib/CONTRACTS_STATE.md for the full contract.

import '../../engine/video/framebuffer.dart';

/// Renders the 3D world view (R_RenderPlayerView equivalent) into the given
/// [Framebuffer]. The integration layer wires this to the real renderer; the
/// game-state machine calls it when [GameState.gamestate] is GS_LEVEL, before
/// it overlays the status bar / HUD / automap.
///
/// The whole 320x200 buffer may be written; the status bar drawer will overlay
/// the bottom 32 rows afterwards (when the bar is visible).
typedef WorldView = void Function(Framebuffer fb);

/// Player ammo types, vanilla `ammotype_t` order (am_clip, am_shell, am_cell,
/// am_misl). Used to index the [PlayerStatus] ammo/maxammo arrays.
enum AmmoType { clip, shell, cell, misl }

/// Power-up indices the status bar / automap care about (vanilla powertype_t
/// subset). Only [strength] (berserk) and [invulnerability]/[infrared] affect
/// the face / palette; we expose the ones st_stuff reads.
enum PowerType { invulnerability, strength, infrared }

/// Read-only view of the player's HUD-relevant state.
///
/// This is the seam between the status bar / HUD / automap (which only DISPLAY
/// values) and the play-simulation (which OWNS them). The integration layer
/// implements this by reading the real `player_t`; tests use [DummyPlayerStatus].
///
/// All accessors are pure reads, called once per tic by ST_Ticker / HU_Ticker
/// and during drawing. Indices: weapons/keys are small fixed arrays.
abstract interface class PlayerStatus {
  /// Health percentage shown on the bar (player.health), 0..199 typically.
  int get health;

  /// Armor percentage (player.armorpoints).
  int get armor;

  /// Armor type (0 = none, 1 = green/security, 2 = blue/mega). Drives the
  /// armor face/key colour in some HUDs; st_stuff itself just shows the count.
  int get armorType;

  /// Currently selected weapon slot (vanilla `readyweapon`, 0..8:
  /// fist, pistol, shotgun, chaingun, rocket, plasma, bfg, chainsaw, sshotgun).
  int get readyWeapon;

  /// Whether the player owns weapon [slot] (0..8). Drives the STARMS arsenal
  /// number highlighting.
  bool ownsWeapon(int slot);

  /// Ammo currently held of [type] (player.ammo[type]).
  int ammo(AmmoType type);

  /// Maximum ammo capacity of [type] (player.maxammo[type]).
  int maxAmmo(AmmoType type);

  /// The ammo type the ready weapon consumes, or null if the weapon uses no
  /// ammo (fist / chainsaw). Drives the big ammo number on the bar.
  AmmoType? get readyWeaponAmmo;

  /// Whether the player holds key card [index] (0=blue,1=yellow,2=red card;
  /// 3=blue,4=yellow,5=red skull), vanilla `cards[]`. Drives the key icons.
  bool ownsCard(int index);

  /// Frag count for deathmatch (shown in place of the arsenal on co-op/DM).
  /// Single-player returns 0.
  int get fragCount;

  /// Active tics remaining for [power] (player.powers[power]); 0 = inactive.
  /// Used by the face logic (god/invuln) and palette tinting hooks.
  int powerTics(PowerType power);

  /// Damage taken since last tic (player.damagecount) — drives the "ouch" /
  /// pain face direction. 0 if unhurt.
  int get damageCount;

  /// Bonus pickup flash counter (player.bonuscount). Returned for palette hooks.
  int get bonusCount;

  /// True while the player just attacked (player.attackdown) — face looks
  /// forward / grits when firing. Optional cue for the face state machine.
  bool get attackDown;

  /// True if the player is dead (health <= 0); selects STFDEAD0.
  bool get isDead;

  /// Active tics remaining for pw_ironfeet (the radiation suit). Drives the
  /// green RADIATIONPAL screen tint (ST_doPaletteStuff). 0 = inactive.
  int get ironfeetTics;

  /// PLAYPAL palette index for this frame, computed exactly as vanilla
  /// ST_doPaletteStuff (st_stuff.c):
  ///   - damagecount (and the fading berserk pw_strength flash) -> red 1..8
  ///   - else bonuscount -> yellow 9..12
  ///   - else pw_ironfeet (radsuit, >4*32 or the low-bit blink) -> green 13
  ///   - else 0 (base palette)
  int get paletteIndex;
}

// --- ST_doPaletteStuff palette-band constants (st_stuff.c). ---

/// STARTREDPALS: first red damage palette index.
const int kStartRedPals = 1;

/// NUMREDPALS: count of red damage palettes (1..8).
const int kNumRedPals = 8;

/// STARTBONUSPALS: first yellow pickup palette index.
const int kStartBonusPals = 9;

/// NUMBONUSPALS: count of yellow pickup palettes (9..12).
const int kNumBonusPals = 4;

/// RADIATIONPAL: the green radiation-suit palette index.
const int kRadiationPal = 13;

/// ST_doPaletteStuff palette selection (st_stuff.c), as a pure function so both
/// the live adapter and tests share one implementation. [damageCount],
/// [bonusCount], [strengthTics] (pw_strength) and [ironfeetTics] (pw_ironfeet)
/// are the raw player_t values. Returns the PLAYPAL index 0..13.
int stPaletteIndex({
  required int damageCount,
  required int bonusCount,
  required int strengthTics,
  required int ironfeetTics,
}) {
  int cnt = damageCount;

  if (strengthTics != 0) {
    // slowly fade the berserk out
    final int bzc = 12 - (strengthTics >> 6);
    if (bzc > cnt) cnt = bzc;
  }

  int palette;
  if (cnt != 0) {
    palette = (cnt + 7) >> 3;
    if (palette >= kNumRedPals) palette = kNumRedPals - 1;
    palette += kStartRedPals;
  } else if (bonusCount != 0) {
    palette = (bonusCount + 7) >> 3;
    if (palette >= kNumBonusPals) palette = kNumBonusPals - 1;
    palette += kStartBonusPals;
  } else if (ironfeetTics > 4 * 32 || (ironfeetTics & 8) != 0) {
    palette = kRadiationPal;
  } else {
    palette = 0;
  }

  return palette;
}

/// Per-player end-of-level stats for the intermission (wi_stuff). The
/// integration layer fills these from the playsim's `wbstartstruct_t`; tests
/// use a literal instance.
class IntermissionStats {
  IntermissionStats({
    required this.episode,
    required this.lastMap,
    required this.nextMap,
    required this.killCount,
    required this.totalKills,
    required this.itemCount,
    required this.totalItems,
    required this.secretCount,
    required this.totalSecrets,
    required this.levelTimeSeconds,
    required this.parTimeSeconds,
  });

  /// Episode index (0-based). Shareware Doom = 0 (episode 1).
  final int episode;

  /// The map just finished (0-based map index within the episode).
  final int lastMap;

  /// The map about to start (0-based).
  final int nextMap;

  /// Monsters killed / total on the level.
  final int killCount;
  final int totalKills;

  /// Items picked up / total.
  final int itemCount;
  final int totalItems;

  /// Secrets found / total.
  final int secretCount;
  final int totalSecrets;

  /// Elapsed level time and par time, both in seconds.
  final int levelTimeSeconds;
  final int parTimeSeconds;
}
