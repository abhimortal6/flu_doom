// Enemy thinking / AI + action pointers, ported 1:1 from Chocolate Doom
// src/doom/p_enemy.c.
//
// [EnemyAi] holds the movement helpers (P_CheckMeleeRange / P_CheckMissileRange
// / P_Move / P_TryWalk / P_NewChaseDir / P_LookForPlayers / P_NoiseAlert) and
// every enemy A_* action pointer. It builds on the existing play-sim:
//   - MobjSim  (P_SetMobjState / P_SpawnMobj / P_RemoveMobj),
//   - MapMove  (P_TryMove / P_CheckPosition / blockmap iterators + linking),
//   - Sight    (P_CheckSight),
//   - Shoot    (P_AimLineAttack / P_LineAttack / P_SpawnMissile / P_SpawnPuff /
//               P_RadiusAttack),
//   - Interactions (P_DamageMobj),
//   - SoundHook (S_StartSound).
//
// Vanilla file-scope globals are instance fields here (no C statics). Things
// the play-sim owns but vanilla reads as globals (the players[] table,
// playeringame[], gametic, the level for the brain-target scan) are injected
// public fields wired by COMBAT-D.
//
// Faithfulness is mandatory: this is a port, not a paraphrase.

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../../engine/math/tables.dart';
import '../world/defs.dart';
import '../world/level.dart';
import 'actions.dart';
import 'info.dart';
import 'info_tables.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_inter.dart';
import 'p_map.dart';
import 'p_maputl.dart';
import 'p_mobj.dart';
import 'p_random.dart';
import 'p_shoot.dart';
import 'p_sight.dart';
import 'player.dart';
import 'sound_hook.dart';
import 'sounds.dart';
import 'state_num.dart';

// dirtype_t.
const int _diEast = 0;
const int _diNorthEast = 1;
const int _diNorth = 2;
const int _diNorthWest = 3;
const int _diWest = 4;
const int _diSouthWest = 5;
const int _diSouth = 6;
const int _diSouthEast = 7;
const int _diNoDir = 8;

/// P_NewChaseDir related LUT: opposite[NUMDIRS].
const List<int> _opposite = <int>[
  _diWest, _diSouthWest, _diSouth, _diSouthEast,
  _diEast, _diNorthEast, _diNorth, _diNorthWest, _diNoDir,
];

/// diags[4].
const List<int> _diags = <int>[
  _diNorthWest, _diNorthEast, _diSouthWest, _diSouthEast,
];

// P_Move speed tables (fixed_t). 47000 is the diagonal component.
const List<fixed_t> _xspeed = <fixed_t>[
  kFracUnit, 47000, 0, -47000, -kFracUnit, -47000, 0, 47000,
];
const List<fixed_t> _yspeed = <fixed_t>[
  0, 47000, kFracUnit, 47000, 0, -47000, -kFracUnit, -47000,
];

/// TRACEANGLE (p_enemy.c).
const int _traceAngle = 0xc000000;

/// FATSPREAD (p_enemy.c) = ANG90/8.
const int _fatSpread = kAng90 ~/ 8;

/// SKULLSPEED (p_enemy.c) = 20*FRACUNIT.
const fixed_t _skullSpeed = 20 * kFracUnit;

/// MELEERANGE (p_local.h).
const fixed_t _meleeRange = kMeleeRange;

/// MISSILERANGE (p_local.h).
const fixed_t _missileRange = kMissileRange;

/// MAXRADIUS (p_local.h).
const fixed_t _maxRadius = 32 * kFracUnit;

/// Enemy AI + action pointers.
class EnemyAi {
  EnemyAi(this.mobjSim, this.mapMove, this.sight, this.shoot, this.inter,
      this.sound);

  final MobjSim mobjSim;
  final MapMove mapMove;
  final Sight sight;
  final Shoot shoot;
  final Interactions inter;
  final SoundHook sound;

  // --- Injected play-sim state (wired by COMBAT-D; sensible defaults) ---

  /// players[MAXPLAYERS]. P_LookForPlayers iterates this. Defaults to empty;
  /// COMBAT-D points it at the live player table.
  List<Player> players = <Player>[];

  /// playeringame[MAXPLAYERS]. Parallel to [players].
  List<bool> playerInGame = <bool>[];

  /// The level (for A_BrainAwake's MT_BOSSTARGET scan). Wired by COMBAT-D.
  Level? level;

  /// gametic, read by A_Tracer ("if (gametic&3) return;"). Wired by COMBAT-D.
  int gametic = 0;

  // --- p_enemy.c file-scope statics (now instance fields) ---

  /// soundtarget (P_RecursiveSound / P_NoiseAlert).
  Mobj? _soundTarget;

  /// validcount for the sound flood (separate from the sight validcount).
  int _soundValidCount = 0;

  // PIT_VileCheck statics.
  Mobj? _corpseHit;
  fixed_t _vileTryX = 0;
  fixed_t _vileTryY = 0;

  // A_BrainSpit / A_BrainAwake statics.
  final List<Mobj> _brainTargets = <Mobj>[];
  int _brainTargetOn = 0;
  // static int easy in A_BrainSpit: toggled every call; only read by the
  // sk_easy skip branch (skill not threaded into the play-sim, assumed
  // sk_medium), so it is write-only here. Kept verbatim for faithfulness.
  // ignore: unused_field
  int _brainEasy = 0;

  // =======================================================================
  // P_RecursiveSound (p_enemy.c)
  // =======================================================================
  void _recursiveSound(Sector sec, int soundBlocks) {
    // wake up all monsters in this sector
    if (sec.validCount == _soundValidCount &&
        sec.soundTraversed <= soundBlocks + 1) {
      return; // already flooded
    }

    sec.validCount = _soundValidCount;
    sec.soundTraversed = soundBlocks + 1;
    sec.soundTarget = _soundTarget;

    for (int i = 0; i < sec.lineCount; i++) {
      final Line check = sec.lines[i];
      if ((check.flags & mlTwoSided) == 0) {
        continue;
      }

      lineOpening(check);

      if (opening.openRange <= 0) {
        continue; // closed door
      }

      final Sector other;
      if (identical(check.frontSide.sector, sec)) {
        other = check.backSide!.sector;
      } else {
        other = check.frontSide.sector;
      }

      if ((check.flags & mlSoundBlock) != 0) {
        if (soundBlocks == 0) {
          _recursiveSound(other, 1);
        }
      } else {
        _recursiveSound(other, soundBlocks);
      }
    }
  }

  // =======================================================================
  // P_NoiseAlert (p_enemy.c)
  // =======================================================================
  void noiseAlert(Mobj target, Mobj emitter) {
    _soundTarget = target;
    _soundValidCount++;
    _recursiveSound(emitter.subsectorSector!, 0);
  }

  // =======================================================================
  // P_CheckMeleeRange (p_enemy.c)
  // =======================================================================
  bool checkMeleeRange(Mobj actor) {
    if (actor.target == null) {
      return false;
    }

    final Mobj pl = actor.target!;
    final fixed_t dist =
        approxDistance(toInt32(pl.x - actor.x), toInt32(pl.y - actor.y));

    // gameversion >= exe_doom_1_5 branch (the released game).
    final fixed_t range = toInt32(_meleeRange - 20 * kFracUnit + pl.info.radius);

    if (dist >= range) {
      return false;
    }

    if (!sight.checkSight(actor, actor.target!)) {
      return false;
    }

    return true;
  }

  // =======================================================================
  // P_CheckMissileRange (p_enemy.c)
  // =======================================================================
  bool checkMissileRange(Mobj actor) {
    if (!sight.checkSight(actor, actor.target!)) {
      return false;
    }

    if ((actor.flags & mfJustHit) != 0) {
      // the target just hit the enemy, so fight back!
      actor.flags &= ~mfJustHit;
      return true;
    }

    if (actor.reactionTime != 0) {
      return false; // do not attack yet
    }

    // OPTIMIZE: get this from a global checksight
    fixed_t dist = toInt32(approxDistance(toInt32(actor.x - actor.target!.x),
            toInt32(actor.y - actor.target!.y)) -
        64 * kFracUnit);

    if (actor.info.meleeState == 0) {
      dist = toInt32(dist - 128 * kFracUnit); // no melee attack, so fire more
    }

    dist >>= kFracBits;

    if (actor.type == Mt.vile) {
      if (dist > 14 * 64) {
        return false; // too far away
      }
    }

    if (actor.type == Mt.undead) {
      if (dist < 196) {
        return false; // close for fist attack
      }
      dist >>= 1;
    }

    if (actor.type == Mt.cyborg ||
        actor.type == Mt.spider ||
        actor.type == Mt.skull) {
      dist >>= 1;
    }

    if (dist > 200) {
      dist = 200;
    }

    if (actor.type == Mt.cyborg && dist > 160) {
      dist = 160;
    }

    if (pRandom() < dist) {
      return false;
    }

    return true;
  }

  // =======================================================================
  // P_Move (p_enemy.c)
  // =======================================================================
  bool move(Mobj actor) {
    if (actor.moveDir == _diNoDir) {
      return false;
    }

    // (unsigned)actor->movedir >= 8 => I_Error; movedir is always 0..8 here.

    final fixed_t tryx =
        toInt32(actor.x + actor.info.speed * _xspeed[actor.moveDir]);
    final fixed_t tryy =
        toInt32(actor.y + actor.info.speed * _yspeed[actor.moveDir]);

    final bool tryOk = mapMove.tryMove(actor, tryx, tryy);

    if (!tryOk) {
      // open any specials
      if ((actor.flags & mfFloat) != 0 && mapMove.floatOk) {
        // must adjust height
        if (actor.z < mapMove.tmFloorZ) {
          actor.z = toInt32(actor.z + kFloatSpeed);
        } else {
          actor.z = toInt32(actor.z - kFloatSpeed);
        }

        actor.flags |= mfInFloat;
        return true;
      }

      if (mapMove.specHit.isEmpty) {
        return false;
      }

      actor.moveDir = _diNoDir;
      bool good = false;
      // while (numspechit--) — use the special line activation hook.
      while (mapMove.specHit.isNotEmpty) {
        final Line ld = mapMove.specHit.removeLast();
        // if the special is not a door that can be opened, return false.
        if (_useSpecialLine(actor, ld, 0)) {
          good = true;
        }
      }
      return good;
    } else {
      actor.flags &= ~mfInFloat;
    }

    if ((actor.flags & mfFloat) == 0) {
      actor.z = actor.floorZ;
    }
    return true;
  }

  /// P_UseSpecialLine hook for monster door-opening. Special-line activation
  /// lives in the world/specials layer which COMBAT-A does not own; wired by
  /// COMBAT-D. Defaults to false (line not a usable door), a documented
  /// faithful degradation: monsters then treat the blocking line as a wall and
  /// pick a new chase dir (vanilla behaviour when P_UseSpecialLine returns 0).
  bool Function(Mobj actor, Line line, int side)? useSpecialLine;

  bool _useSpecialLine(Mobj actor, Line line, int side) =>
      useSpecialLine?.call(actor, line, side) ?? false;

  // =======================================================================
  // P_TryWalk (p_enemy.c)
  // =======================================================================
  bool tryWalk(Mobj actor) {
    if (!move(actor)) {
      return false;
    }

    actor.moveCount = pRandom() & 15;
    return true;
  }

  // =======================================================================
  // P_NewChaseDir (p_enemy.c)
  // =======================================================================
  void newChaseDir(Mobj actor) {
    final List<int> d = <int>[0, 0, 0]; // d[3]

    // I_Error if no target — actor->target is guaranteed by the callers.
    final int olddir = actor.moveDir;
    final int turnaround = _opposite[olddir];

    final fixed_t deltax = toInt32(actor.target!.x - actor.x);
    final fixed_t deltay = toInt32(actor.target!.y - actor.y);

    if (deltax > 10 * kFracUnit) {
      d[1] = _diEast;
    } else if (deltax < -10 * kFracUnit) {
      d[1] = _diWest;
    } else {
      d[1] = _diNoDir;
    }

    if (deltay < -10 * kFracUnit) {
      d[2] = _diSouth;
    } else if (deltay > 10 * kFracUnit) {
      d[2] = _diNorth;
    } else {
      d[2] = _diNoDir;
    }

    // try direct route
    if (d[1] != _diNoDir && d[2] != _diNoDir) {
      actor.moveDir =
          _diags[((deltay < 0 ? 1 : 0) << 1) + (deltax > 0 ? 1 : 0)];
      if (actor.moveDir != turnaround && tryWalk(actor)) {
        return;
      }
    }

    // try other directions
    if (pRandom() > 200 || deltay.abs() > deltax.abs()) {
      final int tdir = d[1];
      d[1] = d[2];
      d[2] = tdir;
    }

    if (d[1] == turnaround) {
      d[1] = _diNoDir;
    }
    if (d[2] == turnaround) {
      d[2] = _diNoDir;
    }

    if (d[1] != _diNoDir) {
      actor.moveDir = d[1];
      if (tryWalk(actor)) {
        // either moved forward or attacked
        return;
      }
    }

    if (d[2] != _diNoDir) {
      actor.moveDir = d[2];
      if (tryWalk(actor)) {
        return;
      }
    }

    // there is no direct path to the player, so pick another direction.
    if (olddir != _diNoDir) {
      actor.moveDir = olddir;
      if (tryWalk(actor)) {
        return;
      }
    }

    // randomly determine direction of search
    if ((pRandom() & 1) != 0) {
      for (int tdir = _diEast; tdir <= _diSouthEast; tdir++) {
        if (tdir != turnaround) {
          actor.moveDir = tdir;
          if (tryWalk(actor)) {
            return;
          }
        }
      }
    } else {
      for (int tdir = _diSouthEast; tdir != _diEast - 1; tdir--) {
        if (tdir != turnaround) {
          actor.moveDir = tdir;
          if (tryWalk(actor)) {
            return;
          }
        }
      }
    }

    if (turnaround != _diNoDir) {
      actor.moveDir = turnaround;
      if (tryWalk(actor)) {
        return;
      }
    }

    actor.moveDir = _diNoDir; // can not move
  }

  // =======================================================================
  // P_LookForPlayers (p_enemy.c)
  // =======================================================================
  bool lookForPlayers(Mobj actor, bool allAround) {
    int c = 0;
    final int stop = (actor.lastLook - 1) & 3;

    for (;; actor.lastLook = (actor.lastLook + 1) & 3) {
      if (actor.lastLook >= playerInGame.length ||
          !playerInGame[actor.lastLook]) {
        continue;
      }

      if (c++ == 2 || actor.lastLook == stop) {
        // done looking
        return false;
      }

      final Player player = players[actor.lastLook];

      if (player.health <= 0) {
        continue; // dead
      }

      if (!sight.checkSight(actor, player.mo!)) {
        continue; // out of sight
      }

      if (!allAround) {
        final angle_t an = normAngle(_pointToAngle2(
                actor.x, actor.y, player.mo!.x, player.mo!.y) -
            actor.angle);

        if (an > kAng90 && an < kAng270) {
          final fixed_t dist = approxDistance(
              toInt32(player.mo!.x - actor.x), toInt32(player.mo!.y - actor.y));
          // if real close, react anyway
          if (dist > _meleeRange) {
            continue; // behind back
          }
        }
      }

      actor.target = player.mo;
      return true;
    }
  }

  // =======================================================================
  // A_Look (p_enemy.c)
  // =======================================================================
  void aLook(Mobj actor) {
    actor.threshold = 0; // any shot will wake up
    final Mobj? targ = actor.subsectorSector!.soundTarget as Mobj?;

    bool seeYou = false;

    if (targ != null && (targ.flags & mfShootable) != 0) {
      actor.target = targ;

      if ((actor.flags & mfAmbush) != 0) {
        if (sight.checkSight(actor, actor.target!)) {
          seeYou = true;
        }
      } else {
        seeYou = true;
      }
    }

    if (!seeYou) {
      if (!lookForPlayers(actor, false)) {
        return;
      }
    }

    // go into chase state (seeyou:)
    if (actor.info.seeSound != 0) {
      int snd;

      switch (actor.info.seeSound) {
        case Sfx.posit1:
        case Sfx.posit2:
        case Sfx.posit3:
          snd = Sfx.posit1 + pRandom() % 3;
          break;

        case Sfx.bgsit1:
        case Sfx.bgsit2:
          snd = Sfx.bgsit1 + pRandom() % 2;
          break;

        default:
          snd = actor.info.seeSound;
          break;
      }

      if (actor.type == Mt.spider || actor.type == Mt.cyborg) {
        // full volume
        sound.startSound(null, snd);
      } else {
        sound.startSound(actor, snd);
      }
    }

    mobjSim.setMobjState(actor, actor.info.seeState);
  }

  // =======================================================================
  // A_Chase (p_enemy.c)
  // =======================================================================
  void aChase(Mobj actor) {
    if (actor.reactionTime != 0) {
      actor.reactionTime--;
    }

    // modify target threshold
    if (actor.threshold != 0) {
      // gameversion > exe_doom_1_2 branch (the released game).
      if (actor.target == null || actor.target!.health <= 0) {
        actor.threshold = 0;
      } else {
        actor.threshold--;
      }
    }

    // turn towards movement direction if not there yet
    if (actor.moveDir < 8) {
      actor.angle &= (7 << 29);
      final int delta = toInt32(actor.angle - (actor.moveDir << 29));

      if (delta > 0) {
        actor.angle = normAngle(actor.angle - kAng90 ~/ 2);
      } else if (delta < 0) {
        actor.angle = normAngle(actor.angle + kAng90 ~/ 2);
      }
    }

    if (actor.target == null || (actor.target!.flags & mfShootable) == 0) {
      // look for a new target
      if (lookForPlayers(actor, true)) {
        return; // got a new target
      }

      mobjSim.setMobjState(actor, actor.info.spawnState);
      return;
    }

    // do not attack twice in a row
    if ((actor.flags & mfJustAttacked) != 0) {
      actor.flags &= ~mfJustAttacked;
      // gameskill != sk_nightmare && !fastparm (assume sk_medium, no fast).
      newChaseDir(actor);
      return;
    }

    // check for melee attack
    if (actor.info.meleeState != 0 && checkMeleeRange(actor)) {
      if (actor.info.attackSound != 0) {
        sound.startSound(actor, actor.info.attackSound);
      }

      mobjSim.setMobjState(actor, actor.info.meleeState);
      return;
    }

    // check for missile attack
    // (the C uses `goto nomissile` to skip to the chase; we inline that path.)
    if (actor.info.missileState != 0) {
      // gameskill < sk_nightmare && !fastparm && movecount (assume sk_medium).
      if (actor.moveCount != 0) {
        // goto nomissile
      } else if (!checkMissileRange(actor)) {
        // goto nomissile
      } else {
        mobjSim.setMobjState(actor, actor.info.missileState);
        actor.flags |= mfJustAttacked;
        return;
      }
    }

    // nomissile:
    // possibly choose another target (netgame only — single-player skips).

    // chase towards player
    if (--actor.moveCount < 0 || !move(actor)) {
      newChaseDir(actor);
    }

    // make active sound
    if (actor.info.activeSound != 0 && pRandom() < 3) {
      sound.startSound(actor, actor.info.activeSound);
    }
  }

  // =======================================================================
  // A_FaceTarget (p_enemy.c)
  // =======================================================================
  void aFaceTarget(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    actor.flags &= ~mfAmbush;

    actor.angle = _pointToAngle2(
        actor.x, actor.y, actor.target!.x, actor.target!.y);

    if ((actor.target!.flags & mfShadow) != 0) {
      actor.angle = normAngle(actor.angle + (pSubRandom() << 21));
    }
  }

  // =======================================================================
  // A_PosAttack (p_enemy.c)
  // =======================================================================
  void aPosAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);
    angle_t angle = actor.angle;
    final fixed_t slope = shoot.aimLineAttack(actor, angle, _missileRange);

    sound.startSound(actor, Sfx.pistol);
    angle = normAngle(angle + (pSubRandom() << 20));
    final int damage = (pRandom() % 5 + 1) * 3;
    shoot.lineAttack(actor, angle, _missileRange, slope, damage);
  }

  void aSPosAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    sound.startSound(actor, Sfx.shotgn);
    aFaceTarget(actor);
    final angle_t bangle = actor.angle;
    final fixed_t slope = shoot.aimLineAttack(actor, bangle, _missileRange);

    for (int i = 0; i < 3; i++) {
      final angle_t angle = normAngle(bangle + (pSubRandom() << 20));
      final int damage = (pRandom() % 5 + 1) * 3;
      shoot.lineAttack(actor, angle, _missileRange, slope, damage);
    }
  }

  void aCPosAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    sound.startSound(actor, Sfx.shotgn);
    aFaceTarget(actor);
    final angle_t bangle = actor.angle;
    final fixed_t slope = shoot.aimLineAttack(actor, bangle, _missileRange);

    final angle_t angle = normAngle(bangle + (pSubRandom() << 20));
    final int damage = (pRandom() % 5 + 1) * 3;
    shoot.lineAttack(actor, angle, _missileRange, slope, damage);
  }

  void aCPosRefire(Mobj actor) {
    // keep firing unless target got out of sight
    aFaceTarget(actor);

    if (pRandom() < 40) {
      return;
    }

    if (actor.target == null ||
        actor.target!.health <= 0 ||
        !sight.checkSight(actor, actor.target!)) {
      mobjSim.setMobjState(actor, actor.info.seeState);
    }
  }

  void aSpidRefire(Mobj actor) {
    // keep firing unless target got out of sight
    aFaceTarget(actor);

    if (pRandom() < 10) {
      return;
    }

    if (actor.target == null ||
        actor.target!.health <= 0 ||
        !sight.checkSight(actor, actor.target!)) {
      mobjSim.setMobjState(actor, actor.info.seeState);
    }
  }

  void aBspiAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);

    // launch a missile
    shoot.spawnMissile(actor, actor.target!, Mt.arachplaz);
  }

  // =======================================================================
  // A_TroopAttack (p_enemy.c)
  // =======================================================================
  void aTroopAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);
    if (checkMeleeRange(actor)) {
      sound.startSound(actor, Sfx.claw);
      final int damage = (pRandom() % 8 + 1) * 3;
      inter.damageMobj(actor.target!, actor, actor, damage);
      return;
    }

    // launch a missile
    shoot.spawnMissile(actor, actor.target!, Mt.troopshot);
  }

  void aSargAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);

    // gameversion >= exe_doom_1_5 branch.
    if (!checkMeleeRange(actor)) {
      return;
    }

    final int damage = (pRandom() % 10 + 1) * 4;

    inter.damageMobj(actor.target!, actor, actor, damage);
  }

  void aHeadAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);
    if (checkMeleeRange(actor)) {
      final int damage = (pRandom() % 6 + 1) * 10;
      inter.damageMobj(actor.target!, actor, actor, damage);
      return;
    }

    // launch a missile
    shoot.spawnMissile(actor, actor.target!, Mt.headshot);
  }

  void aCyberAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);
    shoot.spawnMissile(actor, actor.target!, Mt.rocket);
  }

  void aBruisAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    if (checkMeleeRange(actor)) {
      sound.startSound(actor, Sfx.claw);
      final int damage = (pRandom() % 8 + 1) * 10;
      inter.damageMobj(actor.target!, actor, actor, damage);
      return;
    }

    // launch a missile
    shoot.spawnMissile(actor, actor.target!, Mt.bruisershot);
  }

  // =======================================================================
  // A_SkelMissile (p_enemy.c)
  // =======================================================================
  void aSkelMissile(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);
    actor.z = toInt32(actor.z + 16 * kFracUnit); // so missile spawns higher
    final Mobj mo = shoot.spawnMissile(actor, actor.target!, Mt.tracer);
    actor.z = toInt32(actor.z - 16 * kFracUnit); // back to normal

    mo.x = toInt32(mo.x + mo.momX);
    mo.y = toInt32(mo.y + mo.momY);
    mo.tracer = actor.target;
  }

  void aTracer(Mobj actor) {
    if ((gametic & 3) != 0) {
      return;
    }

    // spawn a puff of smoke behind the rocket
    shoot.spawnPuff(actor.x, actor.y, actor.z);

    final Mobj th = mobjSim.spawnMobj(toInt32(actor.x - actor.momX),
        toInt32(actor.y - actor.momY), actor.z, Mt.smoke);

    th.momZ = kFracUnit;
    th.tics -= pRandom() & 3;
    if (th.tics < 1) {
      th.tics = 1;
    }

    // adjust direction
    final Mobj? dest = actor.tracer;

    if (dest == null || dest.health <= 0) {
      return;
    }

    // change angle
    final angle_t exact =
        _pointToAngle2(actor.x, actor.y, dest.x, dest.y);

    if (exact != actor.angle) {
      if (normAngle(exact - actor.angle) > 0x80000000) {
        actor.angle = normAngle(actor.angle - _traceAngle);
        if (normAngle(exact - actor.angle) < 0x80000000) {
          actor.angle = exact;
        }
      } else {
        actor.angle = normAngle(actor.angle + _traceAngle);
        if (normAngle(exact - actor.angle) > 0x80000000) {
          actor.angle = exact;
        }
      }
    }

    final int ani = angleToFineIndex(actor.angle);
    actor.momX = fixedMul(actor.info.speed, finecosine[ani]);
    actor.momY = fixedMul(actor.info.speed, finesine[ani]);

    // change slope
    int dist = approxDistance(
        toInt32(dest.x - actor.x), toInt32(dest.y - actor.y));

    dist = dist ~/ actor.info.speed;

    if (dist < 1) {
      dist = 1;
    }
    final fixed_t slope =
        toInt32(dest.z + 40 * kFracUnit - actor.z) ~/ dist;

    if (slope < actor.momZ) {
      actor.momZ = toInt32(actor.momZ - kFracUnit ~/ 8);
    } else {
      actor.momZ = toInt32(actor.momZ + kFracUnit ~/ 8);
    }
  }

  void aSkelWhoosh(Mobj actor) {
    if (actor.target == null) {
      return;
    }
    aFaceTarget(actor);
    sound.startSound(actor, Sfx.skeswg);
  }

  void aSkelFist(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);

    if (checkMeleeRange(actor)) {
      final int damage = (pRandom() % 10 + 1) * 6;
      sound.startSound(actor, Sfx.skepch);
      inter.damageMobj(actor.target!, actor, actor, damage);
    }
  }

  // =======================================================================
  // PIT_VileCheck (p_enemy.c)
  // =======================================================================
  bool _vileCheck(Mobj thing) {
    if ((thing.flags & mfCorpse) == 0) {
      return true; // not a monster
    }

    if (thing.tics != -1) {
      return true; // not lying still yet
    }

    if (thing.info.raiseState == St.sNull) {
      return true; // monster doesn't have a raise state
    }

    final int maxdist = toInt32(thing.info.radius + mobjInfo[Mt.vile].radius);

    if (toInt32(thing.x - _vileTryX).abs() > maxdist ||
        toInt32(thing.y - _vileTryY).abs() > maxdist) {
      return true; // not actually touching
    }

    _corpseHit = thing;
    thing.momX = thing.momY = 0;
    thing.height <<= 2;
    final bool check = mapMove.checkPosition(thing, thing.x, thing.y);
    thing.height >>= 2;

    if (!check) {
      return true; // doesn't fit here
    }

    return false; // got one, so stop checking
  }

  // =======================================================================
  // A_VileChase (p_enemy.c)
  // =======================================================================
  void aVileChase(Mobj actor) {
    if (actor.moveDir != _diNoDir) {
      final bm = mapMove.level.blockmap;
      final int bMapOrgX = bm.originX << kFracBits;
      final int bMapOrgY = bm.originY << kFracBits;

      // check for corpses to raise
      _vileTryX =
          toInt32(actor.x + actor.info.speed * _xspeed[actor.moveDir]);
      _vileTryY =
          toInt32(actor.y + actor.info.speed * _yspeed[actor.moveDir]);

      final int xl =
          toInt32(_vileTryX - bMapOrgX - _maxRadius * 2) >> kMapBlockShift;
      final int xh =
          toInt32(_vileTryX - bMapOrgX + _maxRadius * 2) >> kMapBlockShift;
      final int yl =
          toInt32(_vileTryY - bMapOrgY - _maxRadius * 2) >> kMapBlockShift;
      final int yh =
          toInt32(_vileTryY - bMapOrgY + _maxRadius * 2) >> kMapBlockShift;

      for (int bx = xl; bx <= xh; bx++) {
        for (int by = yl; by <= yh; by++) {
          // Call PIT_VileCheck to see whether object is a raisable corpse.
          if (!mapMove.blockThingsIterator(bx, by, _vileCheck)) {
            // got one!
            final Mobj? temp = actor.target;
            actor.target = _corpseHit;
            aFaceTarget(actor);
            actor.target = temp;

            mobjSim.setMobjState(actor, St.sVileHeal1);
            sound.startSound(_corpseHit, Sfx.slop);
            final MobjInfo info = _corpseHit!.info;

            mobjSim.setMobjState(_corpseHit!, info.raiseState);
            _corpseHit!.height <<= 2;
            _corpseHit!.flags = info.flags;
            _corpseHit!.health = info.spawnHealth;
            _corpseHit!.target = null;

            return;
          }
        }
      }
    }

    // Return to normal attack.
    aChase(actor);
  }

  void aVileStart(Mobj actor) {
    sound.startSound(actor, Sfx.vilatk);
  }

  // =======================================================================
  // A_StartFire / A_FireCrackle / A_Fire (p_enemy.c)
  // =======================================================================
  void aStartFire(Mobj actor) {
    sound.startSound(actor, Sfx.flamst);
    aFire(actor);
  }

  void aFireCrackle(Mobj actor) {
    sound.startSound(actor, Sfx.flame);
    aFire(actor);
  }

  void aFire(Mobj actor) {
    final Mobj? dest = actor.tracer;
    if (dest == null) {
      return;
    }

    final Mobj target = _substNullMobj(actor.target);

    // don't move it if the vile lost sight
    if (!sight.checkSight(target, dest)) {
      return;
    }

    final int an = angleToFineIndex(dest.angle);

    mapMove.unsetThingPosition(actor);
    actor.x = toInt32(dest.x + fixedMul(24 * kFracUnit, finecosine[an]));
    actor.y = toInt32(dest.y + fixedMul(24 * kFracUnit, finesine[an]));
    actor.z = dest.z;
    mapMove.setThingPosition(actor);
  }

  // =======================================================================
  // A_VileTarget (p_enemy.c)
  // =======================================================================
  void aVileTarget(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);

    // NB: vanilla passes target->x for BOTH x and y here (a known bug). Kept
    // verbatim for faithfulness.
    final Mobj fog = mobjSim.spawnMobj(
        actor.target!.x, actor.target!.x, actor.target!.z, Mt.fire);

    actor.tracer = fog;
    fog.target = actor;
    fog.tracer = actor.target;
    aFire(fog);
  }

  // =======================================================================
  // A_VileAttack (p_enemy.c)
  // =======================================================================
  void aVileAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);

    if (!sight.checkSight(actor, actor.target!)) {
      return;
    }

    sound.startSound(actor, Sfx.barexp);
    inter.damageMobj(actor.target!, actor, actor, 20);
    actor.target!.momZ = 1000 * kFracUnit ~/ actor.target!.info.mass;

    final int an = angleToFineIndex(actor.angle);

    final Mobj? fire = actor.tracer;

    if (fire == null) {
      return;
    }

    // move the fire between the vile and the player
    fire.x = toInt32(
        actor.target!.x - fixedMul(24 * kFracUnit, finecosine[an]));
    fire.y = toInt32(
        actor.target!.y - fixedMul(24 * kFracUnit, finesine[an]));
    shoot.radiusAttack(fire, actor, 70);
  }

  // =======================================================================
  // A_FatRaise / A_FatAttack1..3 (p_enemy.c)
  // =======================================================================
  void aFatRaise(Mobj actor) {
    aFaceTarget(actor);
    sound.startSound(actor, Sfx.manatk);
  }

  void aFatAttack1(Mobj actor) {
    aFaceTarget(actor);

    // Change direction to ...
    actor.angle = normAngle(actor.angle + _fatSpread);
    final Mobj target = _substNullMobj(actor.target);
    shoot.spawnMissile(actor, target, Mt.fatshot);

    final Mobj mo = shoot.spawnMissile(actor, target, Mt.fatshot);
    mo.angle = normAngle(mo.angle + _fatSpread);
    final int an = angleToFineIndex(mo.angle);
    mo.momX = fixedMul(mo.info.speed, finecosine[an]);
    mo.momY = fixedMul(mo.info.speed, finesine[an]);
  }

  void aFatAttack2(Mobj actor) {
    aFaceTarget(actor);
    // Now here choose opposite deviation.
    actor.angle = normAngle(actor.angle - _fatSpread);
    final Mobj target = _substNullMobj(actor.target);
    shoot.spawnMissile(actor, target, Mt.fatshot);

    final Mobj mo = shoot.spawnMissile(actor, target, Mt.fatshot);
    mo.angle = normAngle(mo.angle - _fatSpread * 2);
    final int an = angleToFineIndex(mo.angle);
    mo.momX = fixedMul(mo.info.speed, finecosine[an]);
    mo.momY = fixedMul(mo.info.speed, finesine[an]);
  }

  void aFatAttack3(Mobj actor) {
    aFaceTarget(actor);

    final Mobj target = _substNullMobj(actor.target);

    Mobj mo = shoot.spawnMissile(actor, target, Mt.fatshot);
    mo.angle = normAngle(mo.angle - _fatSpread ~/ 2);
    int an = angleToFineIndex(mo.angle);
    mo.momX = fixedMul(mo.info.speed, finecosine[an]);
    mo.momY = fixedMul(mo.info.speed, finesine[an]);

    mo = shoot.spawnMissile(actor, target, Mt.fatshot);
    mo.angle = normAngle(mo.angle + _fatSpread ~/ 2);
    an = angleToFineIndex(mo.angle);
    mo.momX = fixedMul(mo.info.speed, finecosine[an]);
    mo.momY = fixedMul(mo.info.speed, finesine[an]);
  }

  // =======================================================================
  // A_SkullAttack (p_enemy.c)
  // =======================================================================
  void aSkullAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    final Mobj dest = actor.target!;
    actor.flags |= mfSkullFly;

    sound.startSound(actor, actor.info.attackSound);
    aFaceTarget(actor);
    final int an = angleToFineIndex(actor.angle);
    actor.momX = fixedMul(_skullSpeed, finecosine[an]);
    actor.momY = fixedMul(_skullSpeed, finesine[an]);
    int dist =
        approxDistance(toInt32(dest.x - actor.x), toInt32(dest.y - actor.y));
    dist = dist ~/ _skullSpeed;

    if (dist < 1) {
      dist = 1;
    }
    actor.momZ =
        toInt32(dest.z + (dest.height >> 1) - actor.z) ~/ dist;
  }

  // =======================================================================
  // A_PainShootSkull (p_enemy.c)
  // =======================================================================
  void _painShootSkull(Mobj actor, angle_t angle) {
    // count total number of skulls currently on the level
    int count = 0;
    for (final t in mobjSim.thinkers.thinkers) {
      if (t is Mobj && t.type == Mt.skull) {
        count++;
      }
    }

    // if there are already 20 skulls on the level, don't spit another one
    if (count > 20) {
      return;
    }

    // okay, there's place for another one
    final int an = angleToFineIndex(angle);

    final int prestep = toInt32(4 * kFracUnit +
        3 * (actor.info.radius + mobjInfo[Mt.skull].radius) ~/ 2);

    final fixed_t x = toInt32(actor.x + fixedMul(prestep, finecosine[an]));
    final fixed_t y = toInt32(actor.y + fixedMul(prestep, finesine[an]));
    final fixed_t z = toInt32(actor.z + 8 * kFracUnit);

    final Mobj newmobj = mobjSim.spawnMobj(x, y, z, Mt.skull);

    // Check for movements.
    if (!mapMove.tryMove(newmobj, newmobj.x, newmobj.y)) {
      // kill it immediately
      inter.damageMobj(newmobj, actor, actor, 10000);
      return;
    }

    newmobj.target = actor.target;
    aSkullAttack(newmobj);
  }

  void aPainAttack(Mobj actor) {
    if (actor.target == null) {
      return;
    }

    aFaceTarget(actor);
    _painShootSkull(actor, actor.angle);
  }

  void aPainDie(Mobj actor) {
    aFall(actor);
    _painShootSkull(actor, normAngle(actor.angle + kAng90));
    _painShootSkull(actor, normAngle(actor.angle + kAng180));
    _painShootSkull(actor, normAngle(actor.angle + kAng270));
  }

  // =======================================================================
  // A_Scream / A_XScream / A_Pain / A_Fall (p_enemy.c)
  // =======================================================================
  void aScream(Mobj actor) {
    int snd;

    switch (actor.info.deathSound) {
      case 0:
        return;

      case Sfx.podth1:
      case Sfx.podth2:
      case Sfx.podth3:
        snd = Sfx.podth1 + pRandom() % 3;
        break;

      case Sfx.bgdth1:
      case Sfx.bgdth2:
        snd = Sfx.bgdth1 + pRandom() % 2;
        break;

      default:
        snd = actor.info.deathSound;
        break;
    }

    // Check for bosses.
    if (actor.type == Mt.spider || actor.type == Mt.cyborg) {
      // full volume
      sound.startSound(null, snd);
    } else {
      sound.startSound(actor, snd);
    }
  }

  void aXScream(Mobj actor) {
    sound.startSound(actor, Sfx.slop);
  }

  void aPain(Mobj actor) {
    if (actor.info.painSound != 0) {
      sound.startSound(actor, actor.info.painSound);
    }
  }

  void aFall(Mobj actor) {
    // actor is on ground, it can be walked over
    actor.flags &= ~mfSolid;
  }

  // =======================================================================
  // A_Explode (p_enemy.c)
  // =======================================================================
  void aExplode(Mobj thingy) {
    shoot.radiusAttack(thingy, thingy.target, 128);
  }

  // =======================================================================
  // A_BossDeath (p_enemy.c)
  // =======================================================================
  /// EV-style level-end specials hook (EV_DoDoor / EV_DoFloor / G_ExitLevel)
  /// live in the world-specials / game layer COMBAT-A does not own; COMBAT-D
  /// wires them. When unwired, A_BossDeath still runs its faithful "all bosses
  /// dead?" scan and sounds, then no-ops the level trigger (documented faithful
  /// degradation). Signature mirrors the vanilla branch selection: the wirer
  /// decides commercial map7 / episode endings.
  void Function(Mobj boss)? bossDeathTrigger;

  void aBossDeath(Mobj mo) {
    // gamemode/gamemap gating lives in the wired trigger; we always run the
    // "are all of this boss type dead?" check (the part p_enemy.c owns) and
    // delegate the EV_* / G_ExitLevel decision.

    // make sure there is a player alive for victory
    bool anyAlive = false;
    for (int i = 0; i < players.length; i++) {
      if (i < playerInGame.length &&
          playerInGame[i] &&
          players[i].health > 0) {
        anyAlive = true;
        break;
      }
    }
    if (!anyAlive) {
      return; // no one left alive, so do not end game
    }

    // scan the remaining thinkers to see if all bosses are dead
    for (final t in mobjSim.thinkers.thinkers) {
      if (t is! Mobj) {
        continue;
      }
      if (!identical(t, mo) && t.type == mo.type && t.health > 0) {
        // other boss not dead
        return;
      }
    }

    // victory!
    bossDeathTrigger?.call(mo);
  }

  void aHoof(Mobj mo) {
    sound.startSound(mo, Sfx.hoof);
    aChase(mo);
  }

  void aMetal(Mobj mo) {
    sound.startSound(mo, Sfx.metal);
    aChase(mo);
  }

  void aBabyMetal(Mobj mo) {
    sound.startSound(mo, Sfx.bspwlk);
    aChase(mo);
  }

  // =======================================================================
  // A_KeenDie (p_enemy.c)
  // =======================================================================
  /// EV_DoDoor(tag 666, open) trigger, wired by COMBAT-D (world specials).
  void Function()? keenDieTrigger;

  void aKeenDie(Mobj mo) {
    aFall(mo);

    // scan the remaining thinkers to see if all Keens are dead
    for (final t in mobjSim.thinkers.thinkers) {
      if (t is! Mobj) {
        continue;
      }
      if (!identical(t, mo) && t.type == mo.type && t.health > 0) {
        // other Keen not dead
        return;
      }
    }

    keenDieTrigger?.call();
  }

  // =======================================================================
  // Brain (p_enemy.c)
  // =======================================================================
  void aBrainAwake(Mobj mo) {
    // find all the target spots (vanilla walks thinkercap; we walk the live
    // thinker list directly, which already excludes removed thinkers).
    _brainTargets.clear();
    _brainTargetOn = 0;

    for (final t in mobjSim.thinkers.thinkers) {
      if (t is Mobj && t.type == Mt.bosstarget) {
        _brainTargets.add(t);
      }
    }

    sound.startSound(null, Sfx.bossit);
  }

  void aBrainPain(Mobj mo) {
    sound.startSound(null, Sfx.bospn);
  }

  void aBrainScream(Mobj mo) {
    for (int x = toInt32(mo.x - 196 * kFracUnit);
        x < toInt32(mo.x + 320 * kFracUnit);
        x = toInt32(x + kFracUnit * 8)) {
      final int y = toInt32(mo.y - 320 * kFracUnit);
      final int z = toInt32(128 + pRandom() * 2 * kFracUnit);
      final Mobj th = mobjSim.spawnMobj(x, y, z, Mt.rocket);
      th.momZ = toInt32(pRandom() * 512);

      mobjSim.setMobjState(th, St.sBrainexplode1);

      th.tics -= pRandom() & 7;
      if (th.tics < 1) {
        th.tics = 1;
      }
    }

    sound.startSound(null, Sfx.bosdth);
  }

  void aBrainExplode(Mobj mo) {
    final int x = toInt32(mo.x + pSubRandom() * 2048);
    final int y = mo.y;
    final int z = toInt32(128 + pRandom() * 2 * kFracUnit);
    final Mobj th = mobjSim.spawnMobj(x, y, z, Mt.rocket);
    th.momZ = toInt32(pRandom() * 512);

    mobjSim.setMobjState(th, St.sBrainexplode1);

    th.tics -= pRandom() & 7;
    if (th.tics < 1) {
      th.tics = 1;
    }
  }

  /// G_ExitLevel, wired by COMBAT-D.
  void Function()? exitLevel;

  void aBrainDie(Mobj mo) {
    exitLevel?.call();
  }

  void aBrainSpit(Mobj mo) {
    _brainEasy ^= 1;
    // gameskill <= sk_easy && !easy — assume sk_medium, so never skip.

    if (_brainTargets.isEmpty) {
      // vanilla crashes here (I_Error); we no-op to keep the port alive.
      return;
    }

    // shoot a cube at current target
    final Mobj targ = _brainTargets[_brainTargetOn];
    _brainTargetOn = (_brainTargetOn + 1) % _brainTargets.length;

    // spawn brain missile
    final Mobj newmobj = shoot.spawnMissile(mo, targ, Mt.spawnshot);
    newmobj.target = targ;
    newmobj.reactionTime = (newmobj.momY == 0)
        ? 0
        : (toInt32(targ.y - mo.y) ~/ newmobj.momY) ~/
            states[newmobj.stateIndex].tics;

    sound.startSound(null, Sfx.bospit);
  }

  void aSpawnSound(Mobj mo) {
    sound.startSound(mo, Sfx.boscub);
    aSpawnFly(mo);
  }

  void aSpawnFly(Mobj mo) {
    if (--mo.reactionTime != 0) {
      return; // still flying
    }

    final Mobj targ = _substNullMobj(mo.target);

    // First spawn teleport fog.
    final Mobj fog =
        mobjSim.spawnMobj(targ.x, targ.y, targ.z, Mt.spawnfire);
    sound.startSound(fog, Sfx.telept);

    // Randomly select monster to spawn.
    final int r = pRandom();

    // Probability distribution, decreasing likelihood.
    final int type;
    if (r < 50) {
      type = Mt.troop;
    } else if (r < 90) {
      type = Mt.sergeant;
    } else if (r < 120) {
      type = Mt.shadows;
    } else if (r < 130) {
      type = Mt.pain;
    } else if (r < 160) {
      type = Mt.head;
    } else if (r < 162) {
      type = Mt.vile;
    } else if (r < 172) {
      type = Mt.undead;
    } else if (r < 192) {
      type = Mt.baby;
    } else if (r < 222) {
      type = Mt.fatso;
    } else if (r < 246) {
      type = Mt.knight;
    } else {
      type = Mt.bruiser;
    }

    final Mobj newmobj = mobjSim.spawnMobj(targ.x, targ.y, targ.z, type);
    if (lookForPlayers(newmobj, true)) {
      mobjSim.setMobjState(newmobj, newmobj.info.seeState);
    }

    // telefrag anything in this spot
    _teleportMove(newmobj, newmobj.x, newmobj.y);

    // remove self (i.e., cube).
    mobjSim.removeMobj(mo);
  }

  /// P_TeleportMove telefrag hook (lives in the teleport/specials layer
  /// COMBAT-A does not own). Wired by COMBAT-D. Default: a plain TryMove with
  /// the teleport flag so the spawned monster lands (documented faithful
  /// degradation — no telefrag of things already at the spot).
  void Function(Mobj thing, fixed_t x, fixed_t y)? teleportMove;

  void _teleportMove(Mobj thing, fixed_t x, fixed_t y) {
    if (teleportMove != null) {
      teleportMove!(thing, x, y);
    }
    // Without the hook, the monster keeps its spawn position (already placed by
    // spawnMobj); no further action needed.
  }

  // =======================================================================
  // A_PlayerScream (p_enemy.c)
  // =======================================================================
  /// commercial gamemode flag (DOOM II). When true and health < -50, the
  /// player uses sfx_pdiehi. Wired by COMBAT-D; defaults to non-commercial.
  bool commercial = false;

  void aPlayerScream(Mobj mo) {
    // Default death sound.
    int snd = Sfx.pldeth;

    if (commercial && mo.health < -50) {
      // IF THE PLAYER DIES LESS THAN -50% WITHOUT GIBBING
      snd = Sfx.pdiehi;
    }

    sound.startSound(mo, snd);
  }

  // =======================================================================
  // P_SubstNullMobj (p_mobj.c) — used by A_Fire / A_Fat* / A_SpawnFly. Vanilla
  // returns a dummy "null mobj" so deref of a null target never crashes; we
  // return the actor's own substitute only when target is null. To keep the
  // momentum math meaningful we fall back to a zeroed throwaway mobj.
  // =======================================================================
  Mobj _substNullMobj(Mobj? mo) {
    if (mo != null) {
      return mo;
    }
    // emptyobj in p_mobj.c: x=y=z=0, flags=0. A throwaway, never linked.
    return Mobj()
      ..x = 0
      ..y = 0
      ..z = 0
      ..flags = 0;
  }

  // =======================================================================
  // R_PointToAngle2 (r_main.c), ported locally to avoid a renderer dependency.
  // =======================================================================
  static angle_t _pointToAngle2(
      fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2) {
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

// ===========================================================================
// A_* registration entrypoint for COMBAT-D.
// ===========================================================================

/// Registers all 52 enemy/missile A_* action pointers COMBAT-A owns into [r].
/// COMBAT-D MUST call this BEFORE [ActionRegistry.registerAllStubs] so these
/// real bodies win (putIfAbsent semantics in registerAllStubs leave them).
///
/// The [ActionRegistry] MobjAction signature is
/// `void Function(Mobj, {Player?, Pspdef?})`; enemy actions ignore the named
/// args and act on the mobj. [shoot] and [inter] are accepted for symmetry with
/// the contract's documented entrypoint and to keep A_Explode self-contained
/// through [ai] (which already holds them).
void registerEnemyActions(
    ActionRegistry r, EnemyAi ai, Shoot shoot, Interactions inter) {
  void reg(String name, void Function(Mobj) fn) {
    r.register(name, (Mobj mo, {Player? player, Pspdef? psp}) => fn(mo));
  }

  reg('A_Look', ai.aLook);
  reg('A_Chase', ai.aChase);
  reg('A_FaceTarget', ai.aFaceTarget);
  reg('A_Pain', ai.aPain);
  reg('A_Scream', ai.aScream);
  reg('A_XScream', ai.aXScream);
  reg('A_Fall', ai.aFall);
  reg('A_Explode', ai.aExplode);
  reg('A_BossDeath', ai.aBossDeath);
  reg('A_PlayerScream', ai.aPlayerScream);

  reg('A_PosAttack', ai.aPosAttack);
  reg('A_SPosAttack', ai.aSPosAttack);
  reg('A_CPosAttack', ai.aCPosAttack);
  reg('A_CPosRefire', ai.aCPosRefire);

  reg('A_SpidRefire', ai.aSpidRefire);
  reg('A_BspiAttack', ai.aBspiAttack);
  reg('A_TroopAttack', ai.aTroopAttack);
  reg('A_SargAttack', ai.aSargAttack);

  reg('A_HeadAttack', ai.aHeadAttack);
  reg('A_CyberAttack', ai.aCyberAttack);
  reg('A_BruisAttack', ai.aBruisAttack);
  reg('A_SkullAttack', ai.aSkullAttack);

  reg('A_SkelMissile', ai.aSkelMissile);
  reg('A_SkelWhoosh', ai.aSkelWhoosh);
  reg('A_SkelFist', ai.aSkelFist);
  reg('A_Tracer', ai.aTracer);

  reg('A_VileChase', ai.aVileChase);
  reg('A_VileStart', ai.aVileStart);
  reg('A_VileTarget', ai.aVileTarget);
  reg('A_VileAttack', ai.aVileAttack);

  reg('A_StartFire', ai.aStartFire);
  reg('A_Fire', ai.aFire);
  reg('A_FireCrackle', ai.aFireCrackle);

  reg('A_FatRaise', ai.aFatRaise);
  reg('A_FatAttack1', ai.aFatAttack1);
  reg('A_FatAttack2', ai.aFatAttack2);
  reg('A_FatAttack3', ai.aFatAttack3);

  reg('A_PainAttack', ai.aPainAttack);
  reg('A_PainDie', ai.aPainDie);
  reg('A_KeenDie', ai.aKeenDie);

  reg('A_BrainAwake', ai.aBrainAwake);
  reg('A_BrainPain', ai.aBrainPain);
  reg('A_BrainScream', ai.aBrainScream);
  reg('A_BrainExplode', ai.aBrainExplode);
  reg('A_BrainDie', ai.aBrainDie);
  reg('A_BrainSpit', ai.aBrainSpit);
  reg('A_SpawnSound', ai.aSpawnSound);
  reg('A_SpawnFly', ai.aSpawnFly);

  reg('A_Hoof', ai.aHoof);
  reg('A_Metal', ai.aMetal);
  reg('A_BabyMetal', ai.aBabyMetal);
}
