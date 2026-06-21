// Shooting / aiming / missiles, ported from Chocolate Doom:
//   - P_PathTraverse + the intercept routines (p_maputl.c),
//   - P_AimLineAttack / P_LineAttack / PTR_AimTraverse / PTR_ShootTraverse /
//     P_RadiusAttack / PIT_RadiusAttack (p_map.c),
//   - P_SpawnMissile / P_SpawnPlayerMissile / P_ExplodeMissile / P_SpawnPuff /
//     P_SpawnBlood / P_CheckMissileSpawn (p_mobj.c),
//   - P_BulletSlope (p_pspr.c).
//
// These live in p_shoot.dart (not appended to p_maputl.dart / p_mobj.dart) so
// those world/collision files stay single-reader; missile spawning calls
// mobjSim.spawnMobj (CONTRACTS_COMBAT §2/§10). The intercept buffer + the
// `trace` divline are instance fields here (no C file-scope statics).
//
// Faithfulness is mandatory: this is a faithful port, not a paraphrase.

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../../engine/math/tables.dart';
import '../world/defs.dart';
import 'info_tables.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_inter.dart';
import 'p_map.dart';
import 'p_maputl.dart';
import 'p_mobj.dart';
import 'p_random.dart';
import 'sound_hook.dart';
import 'state_num.dart';

/// MELEERANGE (p_local.h).
const fixed_t kMeleeRange = 64 * kFracUnit;

/// MISSILERANGE (p_local.h).
const fixed_t kMissileRange = 32 * 64 * kFracUnit;

/// MAXINTERCEPTS (p_local.h).
const int kMaxIntercepts = 128;

// Path-traverse flags (PT_*).
const int ptAddLines = 1;
const int ptAddThings = 2;
const int ptEarlyOut = 4;

// MAPBLOCK macros (p_local.h).
const int _mapBlockSize = kMapBlockUnits * kFracUnit; // 128<<FRACBITS
const int _mapBMask = _mapBlockSize - 1;
const int _mapBlockShift = kFracBits + 7;
const int _mapBToFrac = _mapBlockShift - kFracBits;

/// SCREENWIDTH / SCREENHEIGHT, used by the aim-slope clamp (vanilla 320x200).
const int _screenWidth = 320;
const int _screenHeight = 200;

/// divline_t.
class DivLine {
  fixed_t x = 0;
  fixed_t y = 0;
  fixed_t dx = 0;
  fixed_t dy = 0;
}

/// intercept_t.
class Intercept {
  fixed_t frac = 0; // along the trace line (0..FRACUNIT)
  bool isALine = false;
  Mobj? thing; // d.thing (isALine == false)
  Line? line; // d.line (isALine == true)
}

/// A traverser callback. Returns false to stop early. (traverser_t.)
typedef Traverser = bool Function(Intercept it);

/// P_CheckSight, injected by COMBAT-D once COMBAT-A's Sight lands. Used only by
/// PIT_RadiusAttack. Defaults to "visible" so radius attacks still apply
/// falloff before sight wiring (documented faithful degradation).
typedef CheckSight = bool Function(Mobj t1, Mobj t2);

/// Hitscan, aiming and missile spawning. Builds on the existing [MapMove] (for
/// the blockmap + sector queries) and [MobjSim] (for spawning), and calls back
/// into [Interactions] for damage. Sound through the injected [SoundHook].
class Shoot {
  Shoot(this.move, this.mobjSim, this.inter, this.sound);

  final MapMove move;
  final MobjSim mobjSim;
  final Interactions inter;
  final SoundHook sound;

  /// Optional LOS predicate for radius attacks (wired by COMBAT-D).
  CheckSight? checkSight;

  /// Optional sky-flat number (ceilingPic value) so PTR_ShootTraverse can do
  /// the sky-hack guard. -1 = unknown (never matches a real ceilingPic).
  int skyFlatNum = -1;

  // --- intercept buffer + trace (p_maputl.c file-scope, now instance) ---
  final List<Intercept> _intercepts =
      List<Intercept>.generate(kMaxIntercepts, (_) => Intercept());
  int _interceptP = 0;
  final DivLine trace = DivLine();
  bool _earlyOut = false;

  // --- P_LineAttack / P_AimLineAttack outputs (p_map.c file-scope) ---
  /// extern mobj_t* linetarget — who got aimed at / hit (or null).
  Mobj? linetarget;

  /// extern fixed_t attackrange.
  fixed_t attackRange = 0;

  /// extern fixed_t aimslope.
  fixed_t aimSlope = 0;

  /// Height if not aiming up or down (shootz).
  fixed_t _shootZ = 0;

  Mobj? _shootThing;
  int _laDamage = 0;
  fixed_t _topSlope = 0;
  fixed_t _bottomSlope = 0;

  /// bulletslope (p_pspr.c).
  fixed_t bulletSlopeValue = 0;

  // --- P_RadiusAttack (p_map.c file-scope) ---
  Mobj? _bombSource;
  late Mobj _bombSpot;
  int _bombDamage = 0;

  // =======================================================================
  // P_PointOnDivlineSide (p_maputl.c)
  // =======================================================================
  int _pointOnDivlineSide(fixed_t x, fixed_t y, DivLine line) {
    if (line.dx == 0) {
      if (x <= line.x) {
        return line.dy > 0 ? 1 : 0;
      }
      return line.dy < 0 ? 1 : 0;
    }
    if (line.dy == 0) {
      if (y <= line.y) {
        return line.dx < 0 ? 1 : 0;
      }
      return line.dx > 0 ? 1 : 0;
    }

    final fixed_t dx = toInt32(x - line.x);
    final fixed_t dy = toInt32(y - line.y);

    // try to quickly decide by looking at sign bits
    if (((line.dy ^ line.dx ^ dx ^ dy) & 0x80000000) != 0) {
      if (((line.dy ^ dx) & 0x80000000) != 0) {
        return 1; // (left is negative)
      }
      return 0;
    }

    final fixed_t left = fixedMul(line.dy >> 8, dx >> 8);
    final fixed_t right = fixedMul(dy >> 8, line.dx >> 8);

    if (right < left) {
      return 0; // front side
    }
    return 1; // back side
  }

  // =======================================================================
  // P_MakeDivline (p_maputl.c)
  // =======================================================================
  void _makeDivline(Line li, DivLine dl) {
    dl.x = li.v1.x;
    dl.y = li.v1.y;
    dl.dx = li.dx;
    dl.dy = li.dy;
  }

  // =======================================================================
  // P_InterceptVector (p_maputl.c). v2 is the trace, v1 the line divline.
  // =======================================================================
  fixed_t _interceptVector(DivLine v2, DivLine v1) {
    final fixed_t den =
        toInt32(fixedMul(v1.dy >> 8, v2.dx) - fixedMul(v1.dx >> 8, v2.dy));

    if (den == 0) {
      return 0;
    }

    final fixed_t num = toInt32(fixedMul(toInt32(v1.x - v2.x) >> 8, v1.dy) +
        fixedMul(toInt32(v2.y - v1.y) >> 8, v1.dx));

    return fixedDiv(num, den);
  }

  // =======================================================================
  // PIT_AddLineIntercepts (p_maputl.c)
  // =======================================================================
  bool _addLineIntercepts(Line ld) {
    int s1;
    int s2;

    // avoid precision problems with two routines
    if (trace.dx > kFracUnit * 16 ||
        trace.dy > kFracUnit * 16 ||
        trace.dx < -kFracUnit * 16 ||
        trace.dy < -kFracUnit * 16) {
      s1 = _pointOnDivlineSide(ld.v1.x, ld.v1.y, trace);
      s2 = _pointOnDivlineSide(ld.v2.x, ld.v2.y, trace);
    } else {
      s1 = pointOnLineSide(trace.x, trace.y, ld);
      s2 = pointOnLineSide(
          toInt32(trace.x + trace.dx), toInt32(trace.y + trace.dy), ld);
    }

    if (s1 == s2) {
      return true; // line isn't crossed
    }

    // hit the line
    final DivLine dl = DivLine();
    _makeDivline(ld, dl);
    final fixed_t frac = _interceptVector(trace, dl);

    if (frac < 0) {
      return true; // behind source
    }

    // try to early out the check
    if (_earlyOut && frac < kFracUnit && ld.backSector == null) {
      return false; // stop checking
    }

    if (_interceptP >= kMaxIntercepts) {
      return false; // overflow guard (InterceptsOverrun emulation omitted)
    }
    _intercepts[_interceptP]
      ..frac = frac
      ..isALine = true
      ..line = ld
      ..thing = null;
    _interceptP++;

    return true; // continue
  }

  // =======================================================================
  // PIT_AddThingIntercepts (p_maputl.c)
  // =======================================================================
  bool _addThingIntercepts(Mobj thing) {
    final bool tracePositive = (trace.dx ^ trace.dy) > 0;

    fixed_t x1;
    fixed_t y1;
    fixed_t x2;
    fixed_t y2;

    // check a corner to corner crossection for hit
    if (tracePositive) {
      x1 = toInt32(thing.x - thing.radius);
      y1 = toInt32(thing.y + thing.radius);
      x2 = toInt32(thing.x + thing.radius);
      y2 = toInt32(thing.y - thing.radius);
    } else {
      x1 = toInt32(thing.x - thing.radius);
      y1 = toInt32(thing.y - thing.radius);
      x2 = toInt32(thing.x + thing.radius);
      y2 = toInt32(thing.y + thing.radius);
    }

    final int s1 = _pointOnDivlineSide(x1, y1, trace);
    final int s2 = _pointOnDivlineSide(x2, y2, trace);

    if (s1 == s2) {
      return true; // line isn't crossed
    }

    final DivLine dl = DivLine()
      ..x = x1
      ..y = y1
      ..dx = toInt32(x2 - x1)
      ..dy = toInt32(y2 - y1);

    final fixed_t frac = _interceptVector(trace, dl);

    if (frac < 0) {
      return true; // behind source
    }

    if (_interceptP >= kMaxIntercepts) {
      return false;
    }
    _intercepts[_interceptP]
      ..frac = frac
      ..isALine = false
      ..thing = thing
      ..line = null;
    _interceptP++;

    return true; // keep going
  }

  // =======================================================================
  // P_TraverseIntercepts (p_maputl.c)
  // =======================================================================
  bool _traverseIntercepts(Traverser func, fixed_t maxFrac) {
    int count = _interceptP;
    Intercept? inIc;

    while (count-- != 0) {
      fixed_t dist = kInt32Max;
      for (int i = 0; i < _interceptP; i++) {
        final Intercept scan = _intercepts[i];
        if (scan.frac < dist) {
          dist = scan.frac;
          inIc = scan;
        }
      }

      if (dist > maxFrac) {
        return true; // checked everything in range
      }

      if (!func(inIc!)) {
        return false; // don't bother going farther
      }

      inIc.frac = kInt32Max;
    }

    return true; // everything was traversed
  }

  // =======================================================================
  // P_PathTraverse (p_maputl.c)
  // =======================================================================
  /// Walk the blockmap cells the segment (x1,y1)->(x2,y2) crosses, collecting
  /// line and/or thing intercepts, then call [trav] in increasing frac order.
  /// Returns true if it ran to the end (not stopped early).
  bool pathTraverse(fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2, int flags,
      Traverser trav) {
    final bm = move.level.blockmap;
    final int bMapOrgX = bm.originX << kFracBits;
    final int bMapOrgY = bm.originY << kFracBits;

    _earlyOut = (flags & ptEarlyOut) != 0;

    move.validCount++;
    _interceptP = 0;

    if (((x1 - bMapOrgX) & _mapBMask) == 0) {
      x1 += kFracUnit; // don't side exactly on a line
    }
    if (((y1 - bMapOrgY) & _mapBMask) == 0) {
      y1 += kFracUnit; // don't side exactly on a line
    }

    trace.x = x1;
    trace.y = y1;
    trace.dx = toInt32(x2 - x1);
    trace.dy = toInt32(y2 - y1);

    x1 = toInt32(x1 - bMapOrgX);
    y1 = toInt32(y1 - bMapOrgY);
    final int xt1 = x1 >> _mapBlockShift;
    final int yt1 = y1 >> _mapBlockShift;

    x2 = toInt32(x2 - bMapOrgX);
    y2 = toInt32(y2 - bMapOrgY);
    final int xt2 = x2 >> _mapBlockShift;
    final int yt2 = y2 >> _mapBlockShift;

    int mapXStep;
    int mapYStep;
    fixed_t partial;
    fixed_t xStep;
    fixed_t yStep;

    if (xt2 > xt1) {
      mapXStep = 1;
      partial = kFracUnit - ((x1 >> _mapBToFrac) & (kFracUnit - 1));
      yStep = fixedDiv(toInt32(y2 - y1), (toInt32(x2 - x1)).abs());
    } else if (xt2 < xt1) {
      mapXStep = -1;
      partial = (x1 >> _mapBToFrac) & (kFracUnit - 1);
      yStep = fixedDiv(toInt32(y2 - y1), (toInt32(x2 - x1)).abs());
    } else {
      mapXStep = 0;
      partial = kFracUnit;
      yStep = 256 * kFracUnit;
    }

    fixed_t yIntercept = (y1 >> _mapBToFrac) + fixedMul(partial, yStep);

    if (yt2 > yt1) {
      mapYStep = 1;
      partial = kFracUnit - ((y1 >> _mapBToFrac) & (kFracUnit - 1));
      xStep = fixedDiv(toInt32(x2 - x1), (toInt32(y2 - y1)).abs());
    } else if (yt2 < yt1) {
      mapYStep = -1;
      partial = (y1 >> _mapBToFrac) & (kFracUnit - 1);
      xStep = fixedDiv(toInt32(x2 - x1), (toInt32(y2 - y1)).abs());
    } else {
      mapYStep = 0;
      partial = kFracUnit;
      xStep = 256 * kFracUnit;
    }
    fixed_t xIntercept = (x1 >> _mapBToFrac) + fixedMul(partial, xStep);

    // Step through map blocks.
    int mapX = xt1;
    int mapY = yt1;

    for (int count = 0; count < 64; count++) {
      if ((flags & ptAddLines) != 0) {
        if (!move.blockLinesIterator(mapX, mapY, _addLineIntercepts)) {
          return false; // early out
        }
      }

      if ((flags & ptAddThings) != 0) {
        if (!move.blockThingsIterator(mapX, mapY, _addThingIntercepts)) {
          return false; // early out
        }
      }

      if (mapX == xt2 && mapY == yt2) {
        break;
      }

      if ((yIntercept >> kFracBits) == mapY) {
        yIntercept = toInt32(yIntercept + yStep);
        mapX += mapXStep;
      } else if ((xIntercept >> kFracBits) == mapX) {
        xIntercept = toInt32(xIntercept + xStep);
        mapY += mapYStep;
      }
    }
    // go through the sorted list
    return _traverseIntercepts(trav, kFracUnit);
  }

  // =======================================================================
  // PTR_AimTraverse (p_map.c). Sets linetarget + aimslope when aimed at.
  // =======================================================================
  bool _aimTraverse(Intercept inIc) {
    if (inIc.isALine) {
      final Line li = inIc.line!;

      if ((li.flags & mlTwoSided) == 0) {
        return false; // stop
      }

      // Crosses a two sided line. Restricts the possible target ranges.
      lineOpening(li);

      if (opening.openBottom >= opening.openTop) {
        return false; // stop
      }

      final fixed_t dist = fixedMul(attackRange, inIc.frac);

      if (li.backSector == null ||
          li.frontSector.floorHeight != li.backSector!.floorHeight) {
        final fixed_t slope =
            fixedDiv(toInt32(opening.openBottom - _shootZ), dist);
        if (slope > _bottomSlope) {
          _bottomSlope = slope;
        }
      }

      if (li.backSector == null ||
          li.frontSector.ceilingHeight != li.backSector!.ceilingHeight) {
        final fixed_t slope =
            fixedDiv(toInt32(opening.openTop - _shootZ), dist);
        if (slope < _topSlope) {
          _topSlope = slope;
        }
      }

      if (_topSlope <= _bottomSlope) {
        return false; // stop
      }

      return true; // shot continues
    }

    // shoot a thing
    final Mobj th = inIc.thing!;
    if (identical(th, _shootThing)) {
      return true; // can't shoot self
    }

    if ((th.flags & mfShootable) == 0) {
      return true; // corpse or something
    }

    // check angles to see if the thing can be aimed at
    final fixed_t dist = fixedMul(attackRange, inIc.frac);
    fixed_t thingTopSlope =
        fixedDiv(toInt32(th.z + th.height - _shootZ), dist);

    if (thingTopSlope < _bottomSlope) {
      return true; // shot over the thing
    }

    fixed_t thingBottomSlope = fixedDiv(toInt32(th.z - _shootZ), dist);

    if (thingBottomSlope > _topSlope) {
      return true; // shot under the thing
    }

    // this thing can be hit!
    if (thingTopSlope > _topSlope) {
      thingTopSlope = _topSlope;
    }

    if (thingBottomSlope < _bottomSlope) {
      thingBottomSlope = _bottomSlope;
    }

    aimSlope = (thingTopSlope + thingBottomSlope) ~/ 2;
    linetarget = th;

    return false; // don't go any farther
  }

  // =======================================================================
  // PTR_ShootTraverse (p_map.c)
  // =======================================================================
  bool _shootTraverse(Intercept inIc) {
    if (inIc.isALine) {
      final Line li = inIc.line!;

      // P_ShootSpecialLine omitted (special line activation lives elsewhere);
      // its absence does not affect the puff/damage path.

      bool hitLine = false;

      if ((li.flags & mlTwoSided) == 0) {
        hitLine = true;
      } else {
        // crosses a two sided line
        lineOpening(li);

        final fixed_t dist = fixedMul(attackRange, inIc.frac);

        if (li.backSector == null) {
          fixed_t slope = fixedDiv(toInt32(opening.openBottom - _shootZ), dist);
          if (slope > aimSlope) {
            hitLine = true;
          } else {
            slope = fixedDiv(toInt32(opening.openTop - _shootZ), dist);
            if (slope < aimSlope) {
              hitLine = true;
            }
          }
        } else {
          if (li.frontSector.floorHeight != li.backSector!.floorHeight) {
            final fixed_t slope =
                fixedDiv(toInt32(opening.openBottom - _shootZ), dist);
            if (slope > aimSlope) {
              hitLine = true;
            }
          }

          if (!hitLine &&
              li.frontSector.ceilingHeight != li.backSector!.ceilingHeight) {
            final fixed_t slope =
                fixedDiv(toInt32(opening.openTop - _shootZ), dist);
            if (slope < aimSlope) {
              hitLine = true;
            }
          }
        }

        if (!hitLine) {
          return true; // shot continues
        }
      }

      // hit line
      // position a bit closer
      final fixed_t frac =
          toInt32(inIc.frac - fixedDiv(4 * kFracUnit, attackRange));
      final fixed_t x = toInt32(trace.x + fixedMul(trace.dx, frac));
      final fixed_t y = toInt32(trace.y + fixedMul(trace.dy, frac));
      final fixed_t z = toInt32(
          _shootZ + fixedMul(aimSlope, fixedMul(frac, attackRange)));

      if (li.frontSector.ceilingPic == skyFlatNum) {
        // don't shoot the sky!
        if (z > li.frontSector.ceilingHeight) {
          return false;
        }
        // it's a sky hack wall
        if (li.backSector != null &&
            li.backSector!.ceilingPic == skyFlatNum) {
          return false;
        }
      }

      // Spawn bullet puffs.
      spawnPuff(x, y, z);

      // don't go any farther
      return false;
    }

    // shoot a thing
    final Mobj th = inIc.thing!;
    if (identical(th, _shootThing)) {
      return true; // can't shoot self
    }

    if ((th.flags & mfShootable) == 0) {
      return true; // corpse or something
    }

    // check angles to see if the thing can be aimed at
    final fixed_t dist = fixedMul(attackRange, inIc.frac);
    final fixed_t thingTopSlope =
        fixedDiv(toInt32(th.z + th.height - _shootZ), dist);

    if (thingTopSlope < aimSlope) {
      return true; // shot over the thing
    }

    final fixed_t thingBottomSlope = fixedDiv(toInt32(th.z - _shootZ), dist);

    if (thingBottomSlope > aimSlope) {
      return true; // shot under the thing
    }

    // hit thing
    // position a bit closer
    final fixed_t frac =
        toInt32(inIc.frac - fixedDiv(10 * kFracUnit, attackRange));

    final fixed_t x = toInt32(trace.x + fixedMul(trace.dx, frac));
    final fixed_t y = toInt32(trace.y + fixedMul(trace.dy, frac));
    final fixed_t z =
        toInt32(_shootZ + fixedMul(aimSlope, fixedMul(frac, attackRange)));

    // Spawn bullet puffs or blood spots, depending on target type.
    if ((th.flags & mfNoBlood) != 0) {
      spawnPuff(x, y, z);
    } else {
      spawnBlood(x, y, z, _laDamage);
    }

    if (_laDamage != 0) {
      inter.damageMobj(th, _shootThing, _shootThing, _laDamage);
    }

    // don't go any farther
    return false;
  }

  // =======================================================================
  // P_AimLineAttack (p_map.c)
  // =======================================================================
  /// Aim from [t1] along [angle] for [distance]; sets [linetarget] and returns
  /// the vertical aim slope.
  fixed_t aimLineAttack(Mobj t1, angle_t angle, fixed_t distance) {
    final int an = angleToFineIndex(angle);
    _shootThing = t1;

    final fixed_t x2 =
        toInt32(t1.x + (distance >> kFracBits) * finecosine[an]);
    final fixed_t y2 =
        toInt32(t1.y + (distance >> kFracBits) * finesine[an]);
    _shootZ = toInt32(t1.z + (t1.height >> 1) + 8 * kFracUnit);

    // can't shoot outside view angles
    _topSlope = (_screenHeight ~/ 2) * kFracUnit ~/ (_screenWidth ~/ 2);
    _bottomSlope = -(_screenHeight ~/ 2) * kFracUnit ~/ (_screenWidth ~/ 2);

    attackRange = distance;
    linetarget = null;

    pathTraverse(
        t1.x, t1.y, x2, y2, ptAddLines | ptAddThings, _aimTraverse);

    if (linetarget != null) {
      return aimSlope;
    }

    return 0;
  }

  // =======================================================================
  // P_LineAttack (p_map.c). If damage == 0, just a test trace leaving
  // linetarget set.
  // =======================================================================
  void lineAttack(
      Mobj t1, angle_t angle, fixed_t distance, fixed_t slope, int damage) {
    final int an = angleToFineIndex(angle);
    _shootThing = t1;
    _laDamage = damage;
    final fixed_t x2 =
        toInt32(t1.x + (distance >> kFracBits) * finecosine[an]);
    final fixed_t y2 =
        toInt32(t1.y + (distance >> kFracBits) * finesine[an]);
    _shootZ = toInt32(t1.z + (t1.height >> 1) + 8 * kFracUnit);
    attackRange = distance;
    aimSlope = slope;

    pathTraverse(
        t1.x, t1.y, x2, y2, ptAddLines | ptAddThings, _shootTraverse);
  }

  // =======================================================================
  // P_BulletSlope (p_pspr.c)
  // =======================================================================
  /// Sets a slope so a near miss is at approximately the height of the intended
  /// target. Leaves [linetarget] set and returns the slope (also in
  /// [bulletSlopeValue]).
  fixed_t bulletSlope(Mobj mo) {
    // see which target is to be aimed at
    angle_t an = mo.angle;
    bulletSlopeValue = aimLineAttack(mo, an, 16 * 64 * kFracUnit);

    if (linetarget == null) {
      an = normAngle(an + (1 << 26));
      bulletSlopeValue = aimLineAttack(mo, an, 16 * 64 * kFracUnit);
      if (linetarget == null) {
        an = normAngle(an - (2 << 26));
        bulletSlopeValue = aimLineAttack(mo, an, 16 * 64 * kFracUnit);
      }
    }
    return bulletSlopeValue;
  }

  // =======================================================================
  // P_RadiusAttack + PIT_RadiusAttack (p_map.c)
  // =======================================================================
  bool _radiusAttackPit(Mobj thing) {
    if ((thing.flags & mfShootable) == 0) {
      return true;
    }

    // Boss spider and cyborg take no damage from concussion.
    if (thing.type == Mt.cyborg || thing.type == Mt.spider) {
      return true;
    }

    final fixed_t dx = (toInt32(thing.x - _bombSpot.x)).abs();
    final fixed_t dy = (toInt32(thing.y - _bombSpot.y)).abs();

    fixed_t dist = dx > dy ? dx : dy;
    dist = toInt32(dist - thing.radius) >> kFracBits;

    if (dist < 0) {
      dist = 0;
    }

    if (dist >= _bombDamage) {
      return true; // out of range
    }

    final bool sighted = checkSight?.call(thing, _bombSpot) ?? true;
    if (sighted) {
      // must be in direct path
      inter.damageMobj(thing, _bombSpot, _bombSource, _bombDamage - dist);
    }

    return true;
  }

  /// P_RadiusAttack. [source] is the creature that caused the explosion at
  /// [spot].
  void radiusAttack(Mobj spot, Mobj? source, int damage) {
    final bm = move.level.blockmap;
    final int bMapOrgX = bm.originX << kFracBits;
    final int bMapOrgY = bm.originY << kFracBits;

    final fixed_t dist = (damage + 32) << kFracBits; // damage + MAXRADIUS(32)
    final int yh = toInt32(spot.y + dist - bMapOrgY) >> _mapBlockShift;
    final int yl = toInt32(spot.y - dist - bMapOrgY) >> _mapBlockShift;
    final int xh = toInt32(spot.x + dist - bMapOrgX) >> _mapBlockShift;
    final int xl = toInt32(spot.x - dist - bMapOrgX) >> _mapBlockShift;
    _bombSpot = spot;
    _bombSource = source;
    _bombDamage = damage;

    for (int y = yl; y <= yh; y++) {
      for (int x = xl; x <= xh; x++) {
        move.blockThingsIterator(x, y, _radiusAttackPit);
      }
    }
  }

  // =======================================================================
  // P_ExplodeMissile (p_mobj.c)
  // =======================================================================
  void explodeMissile(Mobj mo) {
    mo.momX = mo.momY = mo.momZ = 0;

    mobjSim.setMobjState(mo, mobjInfo[mo.type].deathState);

    mo.tics -= pRandom() & 3;

    if (mo.tics < 1) {
      mo.tics = 1;
    }

    mo.flags &= ~mfMissile;

    if (mo.info.deathSound != 0) {
      sound.startSound(mo, mo.info.deathSound);
    }
  }

  // =======================================================================
  // P_SpawnPuff (p_mobj.c)
  // =======================================================================
  void spawnPuff(fixed_t x, fixed_t y, fixed_t z) {
    z = toInt32(z + (pSubRandom() << 10));

    final Mobj th = mobjSim.spawnMobj(x, y, z, Mt.puff);
    th.momZ = kFracUnit;
    th.tics -= pRandom() & 3;

    if (th.tics < 1) {
      th.tics = 1;
    }

    // don't make punches spark on the wall
    if (attackRange == kMeleeRange) {
      mobjSim.setMobjState(th, St.sPuff3);
    }
  }

  // =======================================================================
  // P_SpawnBlood (p_mobj.c)
  // =======================================================================
  void spawnBlood(fixed_t x, fixed_t y, fixed_t z, int damage) {
    z = toInt32(z + (pSubRandom() << 10));
    final Mobj th = mobjSim.spawnMobj(x, y, z, Mt.blood);
    th.momZ = kFracUnit * 2;
    th.tics -= pRandom() & 3;

    if (th.tics < 1) {
      th.tics = 1;
    }

    if (damage <= 12 && damage >= 9) {
      mobjSim.setMobjState(th, St.sBlood2);
    } else if (damage < 9) {
      mobjSim.setMobjState(th, St.sBlood3);
    }
  }

  // =======================================================================
  // P_CheckMissileSpawn (p_mobj.c)
  // =======================================================================
  void _checkMissileSpawn(Mobj th) {
    th.tics -= pRandom() & 3;
    if (th.tics < 1) {
      th.tics = 1;
    }

    // move a little forward so an angle can be computed if it immediately
    // explodes
    th.x = toInt32(th.x + (th.momX >> 1));
    th.y = toInt32(th.y + (th.momY >> 1));
    th.z = toInt32(th.z + (th.momZ >> 1));

    if (!move.tryMove(th, th.x, th.y)) {
      explodeMissile(th);
    }
  }

  // =======================================================================
  // P_SpawnMissile (p_mobj.c)
  // =======================================================================
  Mobj spawnMissile(Mobj source, Mobj dest, int type) {
    final Mobj th = mobjSim.spawnMobj(
        source.x, source.y, toInt32(source.z + 4 * 8 * kFracUnit), type);

    if (th.info.seeSound != 0) {
      sound.startSound(th, th.info.seeSound);
    }

    th.target = source; // where it came from
    angle_t an = _pointToAngle2(source.x, source.y, dest.x, dest.y);

    // fuzzy player
    if ((dest.flags & mfShadow) != 0) {
      an = normAngle(an + (pSubRandom() << 20));
    }

    th.angle = an;
    final int ani = angleToFineIndex(an);
    th.momX = fixedMul(th.info.speed, finecosine[ani]);
    th.momY = fixedMul(th.info.speed, finesine[ani]);

    int dist = approxDistance(
        toInt32(dest.x - source.x), toInt32(dest.y - source.y));
    dist = dist ~/ th.info.speed;

    if (dist < 1) {
      dist = 1;
    }

    th.momZ = toInt32(dest.z - source.z) ~/ dist;
    _checkMissileSpawn(th);

    return th;
  }

  // =======================================================================
  // P_SpawnPlayerMissile (p_mobj.c). Tries to aim at a nearby monster.
  // =======================================================================
  void spawnPlayerMissile(Mobj source, int type) {
    // see which target is to be aimed at
    angle_t an = source.angle;
    fixed_t slope = aimLineAttack(source, an, 16 * 64 * kFracUnit);

    if (linetarget == null) {
      an = normAngle(an + (1 << 26));
      slope = aimLineAttack(source, an, 16 * 64 * kFracUnit);

      if (linetarget == null) {
        an = normAngle(an - (2 << 26));
        slope = aimLineAttack(source, an, 16 * 64 * kFracUnit);
      }

      if (linetarget == null) {
        an = source.angle;
        slope = 0;
      }
    }

    final fixed_t x = source.x;
    final fixed_t y = source.y;
    final fixed_t z = toInt32(source.z + 4 * 8 * kFracUnit);

    final Mobj th = mobjSim.spawnMobj(x, y, z, type);

    if (th.info.seeSound != 0) {
      sound.startSound(th, th.info.seeSound);
    }

    th.target = source;
    th.angle = an;
    final int ani = angleToFineIndex(an);
    th.momX = fixedMul(th.info.speed, finecosine[ani]);
    th.momY = fixedMul(th.info.speed, finesine[ani]);
    th.momZ = fixedMul(th.info.speed, slope);

    _checkMissileSpawn(th);
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
