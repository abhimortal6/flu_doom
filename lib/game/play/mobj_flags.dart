// mobj flag bits (MF_*), ported verbatim from Chocolate Doom src/p_mobj.h.
//
// These are the per-mobj behaviour flags stored in Mobj.flags. The values are
// the exact vanilla bit positions (1 << n) so the info.c mobjinfo flag columns
// can be transcribed unchanged.

/// Call P_SpecialThing when touched (picked up).
const int mfSpecial = 1;
/// Blocks: solid, things bump into it.
const int mfSolid = 2;
/// Can be hit by attacks.
const int mfShootable = 4;
/// Don't use the sector links (invisible but touchable).
const int mfNoSector = 8;
/// Don't use the blocklinks (inert, but visible).
const int mfNoBlockmap = 16;
/// Not to be activated by sound, deaf monster.
const int mfAmbush = 32;
/// Will try to attack right back.
const int mfJustHit = 64;
/// Will take at least one step before attacking.
const int mfJustAttacked = 128;
/// On level spawn (initial position), hang from the ceiling.
const int mfSpawnCeiling = 256;
/// Don't apply gravity (every tic), e.g. flying monsters/missiles.
const int mfNoGravity = 512;

/// Movement flags. Slide along walls / off step edges.
const int mfDropOff = 0x400;
/// For players, picks up items.
const int mfPickup = 0x800;
/// Player cheat / no clipping.
const int mfNoClip = 0x1000;
/// Player: keep info about sliding along walls.
const int mfSlide = 0x2000;
/// Allow moves to any height; no gravity. For monsters' floating attacks.
const int mfFloat = 0x4000;
/// Don't cross lines / look at heights on teleport.
const int mfTeleport = 0x8000;
/// Don't hit same species, explode on block. Player missiles + most monsters.
const int mfMissile = 0x10000;
/// Dropped by a demon (not the same as if pickup'd by the player).
const int mfDropped = 0x20000;
/// Use fuzzy draw (shadow demons / spectres).
const int mfShadow = 0x40000;
/// Don't bleed when shot (use puff).
const int mfNoBlood = 0x80000;
/// Don't stop moving halfway off a step, i.e. have dead bodies slide down.
const int mfCorpse = 0x100000;
/// Floating to a height for a move; don't auto-float to target's height.
const int mfInFloat = 0x200000;
/// On kill, count this towards intermission "kill" total.
const int mfCountKill = 0x400000;
/// On pickup, count towards "item" total.
const int mfCountItem = 0x800000;
/// Special handling: skull in flight (Lost Soul charge).
const int mfSkullFly = 0x1000000;
/// Don't spawn this in death-match (e.g. key cards).
const int mfNotDeathmatch = 0x2000000;
/// Player sprites in multiplayer modes: use translation table for color.
const int mfTranslation = 0xc000000;
/// Hmm: shift to select translation. MF_TRANSSHIFT.
const int mfTransShift = 26;
