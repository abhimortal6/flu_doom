// GENERATED 1:1 from reference/chocolate-doom/src/doom/info.{c,h} by
// tool/gen_info.py. DO NOT EDIT BY HAND. State/sprite/mobjtype enums and
// the State / MobjInfo struct definitions, faithful to vanilla.
//
// Frame encoding (vanilla): low bits are the sprite subframe; FF_FULLBRIGHT
// (0x8000) is OR'd in for full-bright frames (kept in [State.frame] as info.c).

/// FF_FULLBRIGHT bit on a state frame (info.h). Bit 15.
const int ffFullBright = 0x8000;

/// Mask to recover the base subframe from a state frame (info.h FF_FRAMEMASK).
const int ffFrameMask = 0x7fff;

/// Sprite numbers, vanilla `spritenum_t` (info.h). Order matches sprnames[].
enum SpriteNum {
  troo, shtg, pung, pisg, pisf, shtf, sht2, chgg, chgf, misg,
  misf, sawg, plsg, plsf, bfgg, bfgf, blud, puff, bal1, bal2,
  plss, plse, misl, bfs1, bfe1, bfe2, tfog, ifog, play, poss,
  spos, vile, fire, fatb, fbxp, skel, manf, fatt, cpos, sarg,
  head, bal7, boss, bos2, skul, spid, bspi, apls, apbx, cybr,
  pain, sswv, keen, bbrn, bosf, arm1, arm2, bar1, bexp, fcan,
  bon1, bon2, bkey, rkey, ykey, bsku, rsku, ysku, stim, medi,
  soul, pinv, pstr, pins, mega, suit, pmap, pvis, clip, ammo,
  rock, brok, cell, celp, shel, sbox, bpak, bfug, mgun, csaw,
  laun, plas, shot, sgn2, colu, smt2, gor1, pol2, pol5, pol4,
  pol3, pol1, pol6, gor2, gor3, gor4, gor5, smit, col1, col2,
  col3, col4, cand, cbra, col6, tre1, tre2, elec, ceye, fsku,
  col5, tblu, tgrn, tred, smbt, smgt, smrt, hdb1, hdb2, hdb3,
  hdb4, hdb5, hdb6, pob1, pob2, brs1, tlmp, tlp2,
}

/// The 4-letter sprite name table, vanilla `sprnames[]` (info.c).
const List<String> spriteNames = <String>[
  'TROO', 'SHTG', 'PUNG', 'PISG', 'PISF', 'SHTF', 'SHT2', 'CHGG', 'CHGF', 'MISG',
  'MISF', 'SAWG', 'PLSG', 'PLSF', 'BFGG', 'BFGF', 'BLUD', 'PUFF', 'BAL1', 'BAL2',
  'PLSS', 'PLSE', 'MISL', 'BFS1', 'BFE1', 'BFE2', 'TFOG', 'IFOG', 'PLAY', 'POSS',
  'SPOS', 'VILE', 'FIRE', 'FATB', 'FBXP', 'SKEL', 'MANF', 'FATT', 'CPOS', 'SARG',
  'HEAD', 'BAL7', 'BOSS', 'BOS2', 'SKUL', 'SPID', 'BSPI', 'APLS', 'APBX', 'CYBR',
  'PAIN', 'SSWV', 'KEEN', 'BBRN', 'BOSF', 'ARM1', 'ARM2', 'BAR1', 'BEXP', 'FCAN',
  'BON1', 'BON2', 'BKEY', 'RKEY', 'YKEY', 'BSKU', 'RSKU', 'YSKU', 'STIM', 'MEDI',
  'SOUL', 'PINV', 'PSTR', 'PINS', 'MEGA', 'SUIT', 'PMAP', 'PVIS', 'CLIP', 'AMMO',
  'ROCK', 'BROK', 'CELL', 'CELP', 'SHEL', 'SBOX', 'BPAK', 'BFUG', 'MGUN', 'CSAW',
  'LAUN', 'PLAS', 'SHOT', 'SGN2', 'COLU', 'SMT2', 'GOR1', 'POL2', 'POL5', 'POL4',
  'POL3', 'POL1', 'POL6', 'GOR2', 'GOR3', 'GOR4', 'GOR5', 'SMIT', 'COL1', 'COL2',
  'COL3', 'COL4', 'CAND', 'CBRA', 'COL6', 'TRE1', 'TRE2', 'ELEC', 'CEYE', 'FSKU',
  'COL5', 'TBLU', 'TGRN', 'TRED', 'SMBT', 'SMGT', 'SMRT', 'HDB1', 'HDB2', 'HDB3',
  'HDB4', 'HDB5', 'HDB6', 'POB1', 'POB2', 'BRS1', 'TLMP', 'TLP2',
];

/// A single animation state, vanilla `state_t` (info.h). [action] is the name
/// of the A_* function to invoke on entry (null = no action). [nextState] is
/// an index into [states] (use [StateNum.sNull] = 0 = "remove me").
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

  final SpriteNum sprite;
  final int frame;
  final int tics;
  final String? action;
  final int nextState;
  final int misc1;
  final int misc2;
}

/// Static info for one kind of thing, vanilla `mobjinfo_t` (info.h). State
/// fields are indices into [states]; radius/height are fixed_t; monster speed
/// is integer, missile speed is fixed_t — verbatim as in info.c.
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

  final int doomedNum;
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
  final int speed;
  final int radius;
  final int height;
  final int mass;
  final int damage;
  final int activeSound;
  final int flags;
  final int raiseState;
}
