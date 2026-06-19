// State / mobjinfo tables, ported from Chocolate Doom src/info.c + info.h.
//
// This is a faithful port of the vanilla Doom state machine data:
//   - the sprite enum (spritenum_t) and the sprnames[] string table,
//   - the state enum (statenum_t),
//   - the states[] table (sprite, frame, tics, action-name, nextstate),
//   - the mobjtype enum (mobjtype_t),
//   - the mobjinfo[] table (spawn/see/... states, health, radius, height,
//     speed, mass, flags, ...).
//
// State actions are referenced by NAME (see actions.dart). Enemy AI / weapon /
// attack A_* functions are NOT implemented this slice; the names are still
// recorded so the tables stay faithful and later waves fill them in.
//
// Frame encoding (vanilla): the low 7 bits ('frame' here) are the sprite
// subframe (A..). FF_FULLBRIGHT (0x8000) is OR'd in for full-bright frames; we
// keep it in [State.frame] exactly as info.c does.

/// FF_FULLBRIGHT bit on a state frame (info.h). Bit 15.
const int ffFullBright = 0x8000;

/// Mask to recover the base subframe from a state frame (info.h FF_FRAMEMASK).
const int ffFrameMask = 0x7fff;

/// Sprite numbers, vanilla `spritenum_t` (info.h). Order is load-bearing: it
/// matches the sprnames[] table below 1:1.
enum SpriteNum {
  troo, shtg, pung, pisg, pisf, shtf, shtg2, chgg, chgf, misg, misf, sawg,
  plsg, plsf, bfgg, bfgf, blud, puff, bal1, bal2, plss, plse, misl, bfs1,
  bfe1, bfe2, tfog, ifog, play, poss, spos, vile, fire, fatb, fbxp, skel,
  manf, fatt, cpos, sarg, head, bal7, boss, bos2, skul, spid, bspi, apls,
  apbx, cybr, pain, sswv, keen, bbrn, bosf, arm1, arm2, bar1, bexp, fcan,
  bon1, bon2, bkey, rkey, ykey, bsku, rsku, ysku, stim, medi, soul, pinv,
  pstr, pins, mega, suit, pmap, pvis, clip, ammo, rock, brok, cell, cell2,
  shel, sbox, bpak, bfug, mgun, csaw, laun, plas, shot, sgn2, colu, smt2,
  gor1, gor2, gor3, gor4, gor5, smit, col1, col2, col3, col4, cand,
  cbra, col6, tre1, tre2, elec, ceye, fsku, col5, tblu, tgrn, tred, smbt,
  smgt, smrt, hdb1, hdb2, hdb3, hdb4, hdb5, hdb6, pob1, pob2, brs1, tlmp,
  tlp2,
}

/// The 4-letter sprite name table, vanilla `sprnames[]` (info.c). Indexed by
/// [SpriteNum.index].
const List<String> spriteNames = <String>[
  'TROO', 'SHTG', 'PUNG', 'PISG', 'PISF', 'SHTF', 'SHT2', 'CHGG', 'CHGF',
  'MISG', 'MISF', 'SAWG', 'PLSG', 'PLSF', 'BFGG', 'BFGF', 'BLUD', 'PUFF',
  'BAL1', 'BAL2', 'PLSS', 'PLSE', 'MISL', 'BFS1', 'BFE1', 'BFE2', 'TFOG',
  'IFOG', 'PLAY', 'POSS', 'SPOS', 'VILE', 'FIRE', 'FATB', 'FBXP', 'SKEL',
  'MANF', 'FATT', 'CPOS', 'SARG', 'HEAD', 'BAL7', 'BOSS', 'BOS2', 'SKUL',
  'SPID', 'BSPI', 'APLS', 'APBX', 'CYBR', 'PAIN', 'SSWV', 'KEEN', 'BBRN',
  'BOSF', 'ARM1', 'ARM2', 'BAR1', 'BEXP', 'FCAN', 'BON1', 'BON2', 'BKEY',
  'RKEY', 'YKEY', 'BSKU', 'RSKU', 'YSKU', 'STIM', 'MEDI', 'SOUL', 'PINV',
  'PSTR', 'PINS', 'MEGA', 'SUIT', 'PMAP', 'PVIS', 'CLIP', 'AMMO', 'ROCK',
  'BROK', 'CELL', 'CELP', 'SHEL', 'SBOX', 'BPAK', 'BFUG', 'MGUN', 'CSAW',
  'LAUN', 'PLAS', 'SHOT', 'SGN2', 'COLU', 'SMT2', 'GOR1', 'GOR2', 'GOR3',
  'GOR4', 'GOR5', 'SMIT', 'COL1', 'COL2', 'COL3', 'COL4', 'CAND', 'CBRA',
  'COL6', 'TRE1', 'TRE2', 'ELEC', 'CEYE', 'FSKU', 'COL5', 'TBLU', 'TGRN',
  'TRED', 'SMBT', 'SMGT', 'SMRT', 'HDB1', 'HDB2', 'HDB3', 'HDB4', 'HDB5',
  'HDB6', 'POB1', 'POB2', 'BRS1', 'TLMP', 'TLP2',
];

/// A single animation state, vanilla `state_t` (info.h). [action] is the name
/// of the A_* function to invoke on entry (null = no action). [nextState] is
/// an index into [states] (use [StateNum.sNull] = 0 to mean "remove me").
class State {
  const State(
    this.sprite,
    this.frame,
    this.tics,
    this.action,
    this.nextState, {
    this.misc1 = 0,
    this.misc2 = 0,
  });

  /// Sprite to draw. Vanilla `sprite`.
  final SpriteNum sprite;

  /// Sub-frame index plus FF_FULLBRIGHT bit. Vanilla `frame`.
  final int frame;

  /// Duration in tics, or -1 for "stay forever". Vanilla `tics`.
  final int tics;

  /// Name of the action function fired on entry, or null. See actions.dart.
  final String? action;

  /// Index into [states] of the next state. Vanilla `nextstate`.
  final int nextState;

  /// Misc parameters (used by a few weapon/jump states). Vanilla misc1/misc2.
  final int misc1;
  final int misc2;
}

/// Static info for one kind of thing, vanilla `mobjinfo_t` (info.h). State
/// fields are indices into [states]; speed/radius/height are vanilla raw
/// values (radius/height are fixed_t; speed is integer for monsters, fixed_t
/// for missiles — kept verbatim as in info.c).
class MobjInfo {
  const MobjInfo({
    required this.doomedNum,
    required this.spawnState,
    required this.spawnHealth,
    required this.seeState,
    required this.seeSound,
    required this.reactionTime,
    required this.attackSound,
    required this.painState,
    required this.painChance,
    required this.painSound,
    required this.meleeState,
    required this.missileState,
    required this.deathState,
    required this.xdeathState,
    required this.deathSound,
    required this.speed,
    required this.radius,
    required this.height,
    required this.mass,
    required this.damage,
    required this.activeSound,
    required this.flags,
    required this.raiseState,
  });

  final int doomedNum;       // -1 if not placeable by DoomEd number
  final int spawnState;
  final int spawnHealth;
  final int seeState;
  final int seeSound;
  final int reactionTime;
  final int attackSound;
  final int painState;
  final int painChance;
  final int painSound;
  final int meleeState;
  final int missileState;
  final int deathState;
  final int xdeathState;
  final int deathSound;
  final int speed;           // monsters: int units; missiles: fixed_t
  final int radius;          // fixed_t
  final int height;          // fixed_t
  final int mass;
  final int damage;
  final int activeSound;
  final int flags;           // MF_* bits (see mobj_flags.dart)
  final int raiseState;
}
