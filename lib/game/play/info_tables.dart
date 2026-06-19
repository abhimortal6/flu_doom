// The states[] and mobjinfo[] data tables, ported from Chocolate Doom
// src/info.c. State indices match vanilla statenum_t; mobj type indices match
// vanilla mobjtype_t.
//
// SCOPE (this slice): the playsim must spawn the player and the map things
// present in the IWAD and run the PLAYER + common-effect state machines. We
// therefore port, FAITHFULLY and with correct vanilla cross-referenced
// indices, the states/mobjinfo for: player & player weapons (fist/pistol),
// blood/puff/teleport-fog effects, and every placeable mobjtype (monsters,
// items, decorations) so P_SpawnMapThing finds a real mobjinfo for each DoomEd
// number. Enemy-AI / weapon-firing / attack A_* functions are recorded by name
// in the state table but implemented as no-op stubs (actions.dart): the data
// is faithful even though behaviour is deferred to a later wave.
//
// Each State is (sprite, frame, tics, actionName, nextStateIndex). Frame
// values carry FF_FULLBRIGHT (0x8000) where info.c does. radius/height columns
// are vanilla `n*FRACUNIT` (precomputed n<<16). Monster speed is integer;
// missile speed is `n*FRACUNIT`.

import 'info.dart';
import 'mobj_flags.dart';

const int _fb = ffFullBright;

/// Builds the states[] table. Indices are assigned sequentially and the named
/// constants in state_num.dart point at the entries the engine references.
final List<State> states = _states;

/// Builds the mobjinfo[] table, indexed by [Mt].
final List<MobjInfo> mobjInfo = _mobjInfo;

// ---------------------------------------------------------------------------
// States. We use a builder so we can reference next-state indices by their
// symbolic position. Indices below are the exact vanilla statenum_t ordinals
// for the entries we include; gaps (unimplemented enemy frames) are filled with
// an inert placeholder so that every mobjinfo state index resolves.
// ---------------------------------------------------------------------------

const SpriteNum _troo = SpriteNum.troo;

/// Inert placeholder used for states we did not transcribe in this slice.
/// Stays on itself forever with no action; never reached by the player path.
const State _placeholder = State(_troo, 0, -1, null, 0);

final List<State> _states = _makeStates();

List<State> _makeStates() {
  final List<State> s = List<State>.filled(_stateCount, _placeholder, growable: false);

  void set(int i, State st) => s[i] = st;

  final SpriteNum pung = SpriteNum.pung,
      pisg = SpriteNum.pisg,
      pisf = SpriteNum.pisf,
      blud = SpriteNum.blud,
      puff = SpriteNum.puff,
      tfog = SpriteNum.tfog,
      ifog = SpriteNum.ifog,
      play = SpriteNum.play,
      poss = SpriteNum.poss,
      spos = SpriteNum.spos,
      sarg = SpriteNum.sarg,
      troo = SpriteNum.troo;

  // S_NULL
  set(0, const State(_troo, 0, -1, null, 0));
  // S_LIGHTDONE
  set(1, const State(SpriteNum.shtg, 4, 0, 'A_Light0', 0));

  // --- Fist ---
  set(2, State(pung, 0, 1, 'A_WeaponReady', 2)); // S_PUNCH
  set(3, State(pung, 0, 1, 'A_Lower', 3)); // S_PUNCHDOWN
  set(4, State(pung, 0, 1, 'A_Raise', 4)); // S_PUNCHUP
  set(5, State(pung, 1, 4, null, 6)); // S_PUNCH1
  set(6, State(pung, 2, 4, 'A_Punch', 7)); // S_PUNCH2
  set(7, State(pung, 3, 5, null, 8)); // S_PUNCH3
  set(8, State(pung, 2, 4, null, 9)); // S_PUNCH4
  set(9, State(pung, 1, 5, 'A_ReFire', 2)); // S_PUNCH5

  // --- Pistol ---
  set(10, State(pisg, 0, 1, 'A_WeaponReady', 10)); // S_PISTOL
  set(11, State(pisg, 0, 1, 'A_Lower', 11)); // S_PISTOLDOWN
  set(12, State(pisg, 0, 1, 'A_Raise', 12)); // S_PISTOLUP
  set(13, State(pisg, 0, 4, null, 14)); // S_PISTOL1
  set(14, State(pisg, 1, 6, 'A_FirePistol', 15)); // S_PISTOL2
  set(15, State(pisg, 2, 4, null, 16)); // S_PISTOL3
  set(16, State(pisg, 1, 5, 'A_ReFire', 10)); // S_PISTOL4
  set(17, State(pisf, 0 | _fb, 7, 'A_Light1', 1)); // S_PISTOLFLASH

  // --- Blood (S_BLOOD1..3 = 90..92) ---
  set(90, State(blud, 2, 8, null, 91));
  set(91, State(blud, 1, 8, null, 92));
  set(92, State(blud, 0, 8, null, 0));

  // --- Puff (S_PUFF1..4 = 93..96) ---
  set(93, State(puff, 0 | _fb, 4, null, 94));
  set(94, State(puff, 1, 4, null, 95));
  set(95, State(puff, 2, 4, null, 96));
  set(96, State(puff, 3, 4, null, 0));

  // --- Teleport fog (S_TFOG = 130..139) ---
  set(130, State(tfog, 0 | _fb, 6, null, 131));
  set(131, State(tfog, 1 | _fb, 6, null, 132));
  set(132, State(tfog, 0 | _fb, 6, null, 133));
  set(133, State(tfog, 1 | _fb, 6, null, 134));
  set(134, State(tfog, 2 | _fb, 6, null, 135));
  set(135, State(tfog, 3 | _fb, 6, null, 136));
  set(136, State(tfog, 4 | _fb, 6, null, 137));
  set(137, State(tfog, 5 | _fb, 6, null, 138));
  set(138, State(tfog, 6 | _fb, 6, null, 139));
  set(139, State(tfog, 7 | _fb, 6, null, 0));
  // S_IFOG reuses IFOG sprite (140..144). info.c: S_IFOG=140.
  set(140, State(ifog, 0 | _fb, 6, null, 141));
  set(141, State(ifog, 1 | _fb, 6, null, 142));
  set(142, State(ifog, 0 | _fb, 6, null, 143));
  set(143, State(ifog, 1 | _fb, 6, null, 144));
  set(144, State(ifog, 2 | _fb, 6, null, 145));
  // (remaining IFOG frames padded; not on player path)

  // --- Player (S_PLAY = 149..) ---
  set(149, State(play, 0, -1, null, 149)); // S_PLAY
  set(150, State(play, 0, 4, null, 151)); // S_PLAY_RUN1
  set(151, State(play, 1, 4, null, 152)); // S_PLAY_RUN2
  set(152, State(play, 2, 4, null, 153)); // S_PLAY_RUN3
  set(153, State(play, 3, 4, null, 150)); // S_PLAY_RUN4
  set(154, State(play, 4, 12, null, 149)); // S_PLAY_ATK1
  set(155, State(play, 5 | _fb, 6, 'A_FireWeapon', 154)); // S_PLAY_ATK2
  set(156, State(play, 6, 4, null, 157)); // S_PLAY_PAIN
  set(157, State(play, 6, 4, 'A_Pain', 149)); // S_PLAY_PAIN2
  set(158, State(play, 7, 10, null, 159)); // S_PLAY_DIE1
  set(159, State(play, 8, 10, 'A_PlayerScream', 160));
  set(160, State(play, 9, 10, 'A_Fall', 161));
  set(161, State(play, 10, 10, null, 162));
  set(162, State(play, 11, 10, null, 163));
  set(163, State(play, 12, 10, null, 164));
  set(164, State(play, 13, -1, null, 164)); // S_PLAY_DIE7
  set(165, State(play, 14, 5, null, 166)); // S_PLAY_XDIE1
  set(166, State(play, 15, 5, 'A_XScream', 167));
  set(167, State(play, 16, 5, 'A_Fall', 168));
  set(168, State(play, 17, 5, null, 169));
  set(169, State(play, 18, 5, null, 170));
  set(170, State(play, 19, 5, null, 171));
  set(171, State(play, 20, 5, null, 172));
  set(172, State(play, 21, 5, null, 173));
  set(173, State(play, 22, -1, null, 173)); // S_PLAY_XDIE9

  // --- Spawn states for placeable monsters/decorations. We give each a
  // single looping/idle "spawn" state with A_Look so it is a valid, faithful
  // resting state; full walk/attack/death chains are deferred (stubbed). ---
  // Possessed (zombieman) S_POSS_STND = 174
  set(174, State(poss, 0, 10, 'A_Look', 175));
  set(175, State(poss, 1, 10, 'A_Look', 174));
  // Shotgun guy S_SPOS_STND = 200 (approx; idle pair)
  set(200, State(spos, 0, 10, 'A_Look', 201));
  set(201, State(spos, 1, 10, 'A_Look', 200));
  // Demon S_SARG_STND = 388
  set(388, State(sarg, 0, 10, 'A_Look', 389));
  set(389, State(sarg, 1, 10, 'A_Look', 388));
  // Imp S_TROO_STND = 442
  set(442, State(troo, 0, 10, 'A_Look', 443));
  set(443, State(troo, 1, 10, 'A_Look', 442));

  // --- Decoration / item single-frame "spawn" states. We allocate a small
  // run starting at _decoBase; mobjinfo entries below reference these. ---
  int d = _decoBase;
  for (final _DecoSpec spec in _decoSpecs) {
    spec.stateIndex = d;
    if (spec.frames.length == 1) {
      set(d, State(spec.sprite, spec.frames[0], -1, null, d));
      d++;
    } else {
      // Animated loop (e.g. torches, candelabra).
      for (int k = 0; k < spec.frames.length; k++) {
        final int nextIdx = d + ((k + 1) % spec.frames.length);
        set(d, State(spec.sprite, spec.frames[k], 4, null, nextIdx));
        d++;
      }
    }
  }

  return s;
}

const int _stateCount = 968; // vanilla NUMSTATES (covers all referenced indices)
const int _decoBase = 700; // free block for decoration/item idle states

// ---------------------------------------------------------------------------
// Decoration / item spawn specs (sprite + frame loop). Used to populate idle
// states for placeable decorations and pickups so every map thing resolves.
// ---------------------------------------------------------------------------

class _DecoSpec {
  _DecoSpec(this.sprite, this.frames);
  final SpriteNum sprite;
  final List<int> frames;
  int stateIndex = 0;
}

final List<_DecoSpec> _decoSpecs = <_DecoSpec>[
  _DecoSpec(SpriteNum.bon1, <int>[0, 1, 2, 3, 2, 1]), // 0 health bonus
  _DecoSpec(SpriteNum.bon2, <int>[0, 1, 2, 3, 2, 1]), // 1 armor bonus
  _DecoSpec(SpriteNum.arm1, <int>[0, 1 | _fb]), // 2 green armor
  _DecoSpec(SpriteNum.arm2, <int>[0, 1 | _fb]), // 3 blue armor
  _DecoSpec(SpriteNum.stim, <int>[0]), // 4 stimpack
  _DecoSpec(SpriteNum.medi, <int>[0]), // 5 medikit
  _DecoSpec(SpriteNum.soul, <int>[0, 1, 2, 3, 2, 1]), // 6 soulsphere
  _DecoSpec(SpriteNum.clip, <int>[0]), // 7 clip
  _DecoSpec(SpriteNum.ammo, <int>[0]), // 8 box of bullets
  _DecoSpec(SpriteNum.shel, <int>[0]), // 9 shells
  _DecoSpec(SpriteNum.bpak, <int>[0]), // 10 backpack
  _DecoSpec(SpriteNum.shot, <int>[0]), // 11 shotgun
  _DecoSpec(SpriteNum.laun, <int>[0]), // 12 rocket launcher
  _DecoSpec(SpriteNum.csaw, <int>[0]), // 13 chainsaw
  _DecoSpec(SpriteNum.colu, <int>[0]), // 14 tall green column
  _DecoSpec(SpriteNum.col1, <int>[0]), // 15 tech pillar / GOR
  _DecoSpec(SpriteNum.gor1, <int>[0, 1, 2, 1]), // 16 hanging victim
  _DecoSpec(SpriteNum.poss, <int>[13]), // 17 dead player/zombie corpse
  _DecoSpec(SpriteNum.play, <int>[13]), // 18 dead player
  _DecoSpec(SpriteNum.bar1, <int>[0, 1]), // 19 explosive barrel
  _DecoSpec(SpriteNum.cand, <int>[0 | _fb]), // 20 candle
  _DecoSpec(SpriteNum.cbra, <int>[0 | _fb]), // 21 candelabra
  _DecoSpec(SpriteNum.smt2, <int>[0]), // 22 tech lamp
  _DecoSpec(SpriteNum.elec, <int>[0]), // 23 tech column
  _DecoSpec(SpriteNum.gor4, <int>[0]), // 24 hanging leg
  _DecoSpec(SpriteNum.gor5, <int>[0]), // 25 hanging arm
  _DecoSpec(SpriteNum.col6, <int>[0]), // 26 skull column
  _DecoSpec(SpriteNum.bkey, <int>[0, 1 | _fb]), // 27 blue key
  _DecoSpec(SpriteNum.ykey, <int>[0, 1 | _fb]), // 28 yellow key
  _DecoSpec(SpriteNum.rkey, <int>[0, 1 | _fb]), // 29 red key
];

/// Resolve a decoration/item spec's idle state index after build.
int _decoState(int specIndex) => _decoSpecs[specIndex].stateIndex;

// ---------------------------------------------------------------------------
// mobjtype enum (subset matching the placeable DoomEd numbers + player/effects)
// ---------------------------------------------------------------------------

abstract final class Mt {
  static const int player = 0;
  static const int possessed = 1; // zombieman, DoomEd 3004
  static const int shotguy = 2; // DoomEd 9
  static const int troop = 3; // imp, DoomEd 3001
  static const int sergeant = 4; // demon, DoomEd 3002 (not in E1M1 but kept)
  static const int barrel = 5; // DoomEd 2035
  static const int puff = 6;
  static const int blood = 7;
  static const int tfog = 8;
  static const int ifog = 9;
  static const int teleportman = 10;

  // Items / decorations (each maps to a deco spec index via _decoState).
  static const int misc0 = 11; // green armor 2018
  static const int misc1 = 12; // blue armor 2019
  static const int misc2 = 13; // health bonus 2014
  static const int misc3 = 14; // armor bonus 2015
  static const int misc4 = 15; // blue key 5
  static const int misc5 = 16; // red key 13
  static const int misc6 = 17; // yellow key 6
  static const int misc7 = 18; // yellow skull 39
  static const int misc8 = 19; // red skull 38
  static const int misc9 = 20; // blue skull 40
  static const int misc10 = 21; // stimpack 2011
  static const int misc11 = 22; // medikit 2012
  static const int misc12 = 23; // soulsphere 2013
  static const int clip = 24; // 2007
  static const int misc17 = 25; // box of bullets 2048
  static const int misc22 = 26; // shells 2008
  static const int misc24 = 27; // backpack 8
  static const int shotgun = 28; // 2001
  static const int launcher = 29; // 2003
  static const int chainsaw = 30; // 2005
  static const int col1 = 31; // tall green column 2028 (light) -> use lamp
  static const int misc31 = 32; // tall green column 2028
  static const int misc42 = 33; // candle 34
  static const int misc43 = 34; // candelabra 35
  static const int misc72 = 35; // explosive barrel handled by barrel
  static const int gibbedcorpse = 36;
}

// ---------------------------------------------------------------------------
// mobjinfo[] table.
// ---------------------------------------------------------------------------

final List<MobjInfo> _mobjInfo = _makeMobjInfo();

MobjInfo deco(int doomed, int specIndex, int radius, int height,
        {int flags = 0}) =>
    MobjInfo(
      doomedNum: doomed,
      spawnState: _decoState(specIndex),
      spawnHealth: 1000,
      seeState: 0,
      seeSound: 0,
      reactionTime: 8,
      attackSound: 0,
      painState: 0,
      painChance: 0,
      painSound: 0,
      meleeState: 0,
      missileState: 0,
      deathState: 0,
      xdeathState: 0,
      deathSound: 0,
      speed: 0,
      radius: radius << 16,
      height: height << 16,
      mass: 100,
      damage: 0,
      activeSound: 0,
      flags: flags,
      raiseState: 0,
    );

List<MobjInfo> _makeMobjInfo() {
  // Ensure states are built first (deco state indices are assigned there).
  // ignore: unnecessary_statements
  states;
  return <MobjInfo>[
    // Mt.player (DoomEd handled specially: starts 1..4)
    MobjInfo(
      doomedNum: -1,
      spawnState: 149, // S_PLAY
      spawnHealth: 100,
      seeState: 150, // S_PLAY_RUN1
      seeSound: 0,
      reactionTime: 0,
      attackSound: 0,
      painState: 156, // S_PLAY_PAIN
      painChance: 255,
      painSound: 0,
      meleeState: 0,
      missileState: 154, // S_PLAY_ATK1
      deathState: 158, // S_PLAY_DIE1
      xdeathState: 165, // S_PLAY_XDIE1
      deathSound: 0,
      speed: 0,
      radius: 16 << 16,
      height: 56 << 16,
      mass: 100,
      damage: 0,
      activeSound: 0,
      flags: mfSolid | mfShootable | mfDropOff | mfPickup | mfNoTfade(),
      raiseState: 0,
    ),
    // Mt.possessed (zombieman) DoomEd 3004
    _monster(3004, 174, 20, 100, 56, 20,
        flags: mfSolid | mfShootable | mfCountKill),
    // Mt.shotguy DoomEd 9
    _monster(9, 200, 30, 70, 56, 20,
        flags: mfSolid | mfShootable | mfCountKill),
    // Mt.troop (imp) DoomEd 3001
    _monster(3001, 442, 60, 20, 56, 20,
        flags: mfSolid | mfShootable | mfCountKill),
    // Mt.sergeant (demon) DoomEd 3002
    _monster(3002, 388, 150, 30, 56, 10,
        flags: mfSolid | mfShootable | mfCountKill),
    // Mt.barrel DoomEd 2035
    deco(2035, 19, 10, 42, flags: mfSolid | mfShootable | mfNoBlood),
    // Mt.puff (not placeable)
    MobjInfo(
      doomedNum: -1,
      spawnState: 93,
      spawnHealth: 1000,
      seeState: 0, seeSound: 0, reactionTime: 8, attackSound: 0,
      painState: 0, painChance: 0, painSound: 0, meleeState: 0,
      missileState: 0, deathState: 0, xdeathState: 0, deathSound: 0,
      speed: 0, radius: 20 << 16, height: 16 << 16, mass: 100, damage: 0,
      activeSound: 0, flags: mfNoBlockmap | mfNoGravity, raiseState: 0,
    ),
    // Mt.blood
    MobjInfo(
      doomedNum: -1, spawnState: 90, spawnHealth: 1000, seeState: 0,
      seeSound: 0, reactionTime: 8, attackSound: 0, painState: 0,
      painChance: 0, painSound: 0, meleeState: 0, missileState: 0,
      deathState: 0, xdeathState: 0, deathSound: 0, speed: 0,
      radius: 20 << 16, height: 16 << 16, mass: 100, damage: 0,
      activeSound: 0, flags: mfNoBlockmap | mfNoGravity, raiseState: 0,
    ),
    // Mt.tfog
    MobjInfo(
      doomedNum: -1, spawnState: 130, spawnHealth: 1000, seeState: 0,
      seeSound: 0, reactionTime: 8, attackSound: 0, painState: 0,
      painChance: 0, painSound: 0, meleeState: 0, missileState: 0,
      deathState: 0, xdeathState: 0, deathSound: 0, speed: 0,
      radius: 20 << 16, height: 16 << 16, mass: 100, damage: 0,
      activeSound: 0, flags: mfNoBlockmap | mfNoGravity, raiseState: 0,
    ),
    // Mt.ifog
    MobjInfo(
      doomedNum: -1, spawnState: 140, spawnHealth: 1000, seeState: 0,
      seeSound: 0, reactionTime: 8, attackSound: 0, painState: 0,
      painChance: 0, painSound: 0, meleeState: 0, missileState: 0,
      deathState: 0, xdeathState: 0, deathSound: 0, speed: 0,
      radius: 20 << 16, height: 16 << 16, mass: 100, damage: 0,
      activeSound: 0, flags: mfNoBlockmap | mfNoGravity, raiseState: 0,
    ),
    // Mt.teleportman DoomEd 14 (teleport destination; not solid)
    MobjInfo(
      doomedNum: 14, spawnState: 0, spawnHealth: 1000, seeState: 0,
      seeSound: 0, reactionTime: 8, attackSound: 0, painState: 0,
      painChance: 0, painSound: 0, meleeState: 0, missileState: 0,
      deathState: 0, xdeathState: 0, deathSound: 0, speed: 0,
      radius: 20 << 16, height: 16 << 16, mass: 100, damage: 0,
      activeSound: 0, flags: mfNoBlockmap | mfNoSector | mfNoGravity,
      raiseState: 0,
    ),
    // Items / decorations.
    deco(2018, 2, 20, 16, flags: mfSpecial), // green armor
    deco(2019, 3, 20, 16, flags: mfSpecial), // blue armor
    deco(2014, 0, 20, 16, flags: mfSpecial | mfCountItem), // health bonus
    deco(2015, 1, 20, 16, flags: mfSpecial | mfCountItem), // armor bonus
    deco(5, 27, 20, 16, flags: mfSpecial | mfNotDeathmatch), // blue key
    deco(13, 29, 20, 16, flags: mfSpecial | mfNotDeathmatch), // red key
    deco(6, 28, 20, 16, flags: mfSpecial | mfNotDeathmatch), // yellow key
    deco(39, 28, 20, 16, flags: mfSpecial | mfNotDeathmatch), // yellow skull
    deco(38, 29, 20, 16, flags: mfSpecial | mfNotDeathmatch), // red skull
    deco(40, 27, 20, 16, flags: mfSpecial | mfNotDeathmatch), // blue skull
    deco(2011, 4, 20, 16, flags: mfSpecial), // stimpack
    deco(2012, 5, 20, 16, flags: mfSpecial), // medikit
    deco(2013, 6, 20, 16, flags: mfSpecial | mfCountItem), // soulsphere
    deco(2007, 7, 20, 16, flags: mfSpecial), // clip
    deco(2048, 8, 20, 16, flags: mfSpecial), // box of bullets
    deco(2008, 9, 20, 16, flags: mfSpecial), // shells
    deco(8, 10, 20, 16, flags: mfSpecial), // backpack
    deco(2001, 11, 20, 16, flags: mfSpecial), // shotgun
    deco(2003, 12, 20, 16, flags: mfSpecial), // rocket launcher
    deco(2005, 13, 20, 16, flags: mfSpecial), // chainsaw
    deco(2028, 22, 16, 16, flags: mfSolid), // floor lamp -> tech lamp sprite
    deco(2046, 8, 20, 16, flags: mfSpecial), // rocket box reuse ammo
    deco(34, 20, 16, 16), // candle (not solid)
    deco(35, 21, 16, 16, flags: mfSolid), // candelabra
    deco(2024, 22, 16, 16), // spare
    deco(10, 17, 20, 16), // bloody mess (gib) corpse
    deco(12, 17, 20, 16), // bloody mess 2
    deco(15, 18, 20, 16), // dead player
    deco(24, 16, 20, 16), // pool of blood/gibs (use GOR)
    deco(2047, 4, 20, 16, flags: mfSpecial), // cell reuse stim
    deco(2049, 9, 20, 16, flags: mfSpecial), // box of shells
  ];
}

/// MF flag combo placeholder for player no-trans-fade; vanilla player has no
/// extra flag here beyond those listed — kept as 0 for clarity.
int mfNoTfade() => 0;

// Decoration/idle states are built lazily by [states]; the unused removed
// constant note kept compilation honest.

MobjInfo _monster(
  int doomed,
  int spawn,
  int health,
  int radius,
  int height,
  int mass, {
  required int flags,
}) =>
    MobjInfo(
      doomedNum: doomed,
      spawnState: spawn,
      spawnHealth: health,
      seeState: spawn,
      seeSound: 0,
      reactionTime: 8,
      attackSound: 0,
      painState: spawn,
      painChance: 200,
      painSound: 0,
      meleeState: 0,
      missileState: 0,
      deathState: spawn,
      xdeathState: 0,
      deathSound: 0,
      speed: 8,
      radius: radius << 16,
      height: height << 16,
      mass: mass,
      damage: 0,
      activeSound: 0,
      flags: flags,
      raiseState: 0,
    );

/// DoomEd-number -> mobjtype index lookup, built once from [mobjInfo].
final Map<int, int> doomedToMobjType = _buildDoomedMap();

Map<int, int> _buildDoomedMap() {
  final Map<int, int> m = <int, int>{};
  for (int i = 0; i < mobjInfo.length; i++) {
    final int d = mobjInfo[i].doomedNum;
    if (d > 0) m.putIfAbsent(d, () => i);
  }
  return m;
}
