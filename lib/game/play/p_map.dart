// Movement & collision, ported from Chocolate Doom src/p_map.c (+ the thing
// position linking from p_maputl.c P_SetThingPosition/P_UnsetThingPosition).
//
// P_CheckPosition does the actual clip test (against lines and other things in
// the touched blockmap cells); P_TryMove applies a move if valid, handling
// step-up / drop-off and updating floor/ceiling refs; P_SlideMove implements
// wall sliding for the player. Iterators walk the world blockmap.
//
// The blockmap origin/links use the shared world Level. We keep a per-MapMove
// context object instead of vanilla file-scope globals so the simulation can
// hold one cleanly.

import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import '../world/level.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_maputl.dart';

/// MAXRADIUS: largest mobj radius, used to widen blockmap scans. Vanilla 32.
const fixed_t kMaxRadius = 32 * kFracUnit;

/// Pikup/clip callback: invoked when [thing] touches a pickup [special] mobj.
/// Pickups are deferred this slice — the hook lets a later wave plug in
/// P_TouchSpecialThing without touching collision code.
typedef SpecialTouch = void Function(Mobj special, Mobj toucher);

/// Movement engine. One instance per [Level]; rebuild on level change.
class MapMove {
  MapMove(this.level);

  Level level;

  // --- P_CheckPosition outputs (vanilla globals tmfloorz etc.) ---
  fixed_t tmFloorZ = 0;
  fixed_t tmCeilingZ = 0;
  fixed_t tmDropoffZ = 0;

  // The thing being moved and its trial bounding box (vanilla tmthing/tmbbox).
  Mobj? _tmThing;
  fixed_t _tmX = 0;
  fixed_t _tmY = 0;
  final List<fixed_t> _tmBBox = <fixed_t>[0, 0, 0, 0];
  int _tmFlags = 0;

  /// The first line that blocked the last move (for use/special hooks).
  Line? ceilingLine;

  /// Lines crossed during the move whose specials should be triggered when the
  /// move succeeds. Vanilla `spechit[]`.
  final List<Line> specHit = <Line>[];

  /// Optional pickup hook (deferred behaviour).
  SpecialTouch? onTouchSpecial;

  /// Global traversal stamp; bump before each blockmap scan. (We keep a local
  /// counter mirroring world.validCount usage.)
  int validCount = 0;

  // -----------------------------------------------------------------------
  // Thing <-> sector / blockmap linking (P_SetThingPosition / Unset).
  // -----------------------------------------------------------------------

  /// P_UnsetThingPosition: remove [thing] from sector thinglist + blockmap.
  void unsetThingPosition(Mobj thing) {
    if ((thing.flags & mfNoSector) == 0) {
      final Sector? sec = thing.subsectorSector;
      if (sec != null) {
        if (thing.sNext != null) thing.sNext!.sPrev = thing.sPrev;
        if (thing.sPrev != null) {
          thing.sPrev!.sNext = thing.sNext;
        } else {
          sec.thingList = thing.sNext;
        }
      }
      thing.sNext = null;
      thing.sPrev = null;
    }
    if ((thing.flags & mfNoBlockmap) == 0 && thing.blockIndex >= 0) {
      if (thing.bNext != null) thing.bNext!.bPrev = thing.bPrev;
      if (thing.bPrev != null) {
        thing.bPrev!.bNext = thing.bNext;
      } else {
        _blockLinks[thing.blockIndex] = thing.bNext;
      }
      thing.bNext = null;
      thing.bPrev = null;
      thing.blockIndex = -1;
    }
  }

  /// Per-cell blockmap thing list heads (vanilla `blocklinks`). Lazily sized
  /// to the blockmap grid.
  late final List<Mobj?> _blockLinks =
      List<Mobj?>.filled(level.blockmap.width * level.blockmap.height, null);

  /// P_SetThingPosition: link [thing] into the sector it sits in (by point)
  /// and the blockmap cell it occupies. Resolves the containing sector via the
  /// BSP, matching vanilla R_PointInSubsector.
  void setThingPosition(Mobj thing) {
    final Sector sec = pointInSector(thing.x, thing.y);
    thing.subsectorSector = sec;
    if ((thing.flags & mfNoSector) == 0) {
      thing.sPrev = null;
      thing.sNext = sec.thingList as Mobj?;
      if (sec.thingList != null) (sec.thingList as Mobj).sPrev = thing;
      sec.thingList = thing;
    }
    if ((thing.flags & mfNoBlockmap) == 0) {
      final int bx = blockX(level.blockmap, thing.x);
      final int by = blockY(level.blockmap, thing.y);
      if (bx >= 0 &&
          by >= 0 &&
          bx < level.blockmap.width &&
          by < level.blockmap.height) {
        final int idx = by * level.blockmap.width + bx;
        thing.blockIndex = idx;
        thing.bPrev = null;
        thing.bNext = _blockLinks[idx];
        if (_blockLinks[idx] != null) _blockLinks[idx]!.bPrev = thing;
        _blockLinks[idx] = thing;
      } else {
        thing.blockIndex = -1;
        thing.bNext = null;
        thing.bPrev = null;
      }
    }
  }

  /// R_PointInSubsector -> sector, via BSP descent. Faithful classification.
  Sector pointInSector(fixed_t x, fixed_t y) {
    if (level.nodes.isEmpty) {
      return level.subsectors.first.sector;
    }
    int nodeNum = level.rootNode;
    while ((nodeNum & nfSubsector) == 0) {
      final Node node = level.nodes[nodeNum];
      final int side = pointOnDivlineSide(x, y, node.x, node.y, node.dx, node.dy);
      nodeNum = node.children[side];
    }
    return level.subsectors[nodeNum & ~nfSubsector].sector;
  }

  // -----------------------------------------------------------------------
  // Blockmap iterators (P_BlockLinesIterator / P_BlockThingsIterator).
  // -----------------------------------------------------------------------

  /// P_BlockLinesIterator: call [fn] for each line in cell (bx,by). Stops and
  /// returns false if [fn] returns false; uses [validCount] to dedupe.
  bool blockLinesIterator(int bx, int by, bool Function(Line) fn) {
    if (bx < 0 || by < 0 || bx >= level.blockmap.width || by >= level.blockmap.height) {
      return true;
    }
    for (final int lineNum in level.blockmap.linesInBlock(bx, by)) {
      final Line line = level.lines[lineNum];
      if (line.validCount == validCount) continue;
      line.validCount = validCount;
      if (!fn(line)) return false;
    }
    return true;
  }

  /// P_BlockThingsIterator: call [fn] for each mobj in cell (bx,by).
  bool blockThingsIterator(int bx, int by, bool Function(Mobj) fn) {
    if (bx < 0 || by < 0 || bx >= level.blockmap.width || by >= level.blockmap.height) {
      return true;
    }
    Mobj? m = _blockLinks[by * level.blockmap.width + bx];
    while (m != null) {
      final Mobj? nextM = m.bNext;
      if (!fn(m)) return false;
      m = nextM;
    }
    return true;
  }

  // -----------------------------------------------------------------------
  // P_CheckPosition / clip tests.
  // -----------------------------------------------------------------------

  /// PIT_CheckLine: does the trial box cross [line] in a blocking way?
  bool _checkLine(Line line) {
    if (_tmBBox[Box.right] <= line.boundingBox[Box.left] ||
        _tmBBox[Box.left] >= line.boundingBox[Box.right] ||
        _tmBBox[Box.top] <= line.boundingBox[Box.bottom] ||
        _tmBBox[Box.bottom] >= line.boundingBox[Box.top]) {
      return true;
    }
    if (boxOnLineSide(_tmBBox, line) != -1) return true;

    // A one-sided line (no back side) always blocks.
    if (line.backSide == null) {
      return false;
    }
    // Explicitly blocking lines block everything not on noclip.
    if ((line.flags & mlBlocking) != 0) {
      return false;
    }
    if ((line.flags & mlBlockMonsters) != 0 &&
        (_tmThing!.player == null)) {
      return false;
    }

    lineOpening(line);
    if (opening.openTop < tmCeilingZ) {
      tmCeilingZ = opening.openTop;
      ceilingLine = line;
    }
    if (opening.openBottom > tmFloorZ) {
      tmFloorZ = opening.openBottom;
    }
    if (opening.lowFloor < tmDropoffZ) {
      tmDropoffZ = opening.lowFloor;
    }
    // Record specials to maybe trigger after the move.
    if (line.special != 0) {
      specHit.add(line);
    }
    return true;
  }

  /// PIT_CheckThing: blocking against another solid mobj.
  bool _checkThing(Mobj thing) {
    if ((thing.flags & (mfSolid | mfSpecial | mfShootable)) == 0) {
      return true;
    }
    final fixed_t blockDist = thing.radius + _tmThing!.radius;
    if ((thing.x - _tmX).abs() >= blockDist ||
        (thing.y - _tmY).abs() >= blockDist) {
      return true; // didn't hit it
    }
    if (identical(thing, _tmThing)) return true;

    // Pickup: if the trial thing wants pickups and target is a special.
    if ((thing.flags & mfSpecial) != 0) {
      final bool solid = (thing.flags & mfSolid) != 0;
      if ((_tmFlags & mfPickup) != 0) {
        onTouchSpecial?.call(thing, _tmThing!);
      }
      return !solid;
    }
    return (thing.flags & mfSolid) == 0;
  }

  /// P_CheckPosition: can [thing] occupy (x,y)? Fills tmFloorZ/tmCeilingZ.
  bool checkPosition(Mobj thing, fixed_t x, fixed_t y) {
    _tmThing = thing;
    _tmFlags = thing.flags;
    _tmX = x;
    _tmY = y;
    _tmBBox[Box.top] = toInt32(y + thing.radius);
    _tmBBox[Box.bottom] = toInt32(y - thing.radius);
    _tmBBox[Box.right] = toInt32(x + thing.radius);
    _tmBBox[Box.left] = toInt32(x - thing.radius);

    final Sector newSec = pointInSector(x, y);
    ceilingLine = null;
    // Start with the subsector's floor/ceiling, valid for any position.
    tmFloorZ = newSec.floorHeight;
    tmDropoffZ = newSec.floorHeight;
    tmCeilingZ = newSec.ceilingHeight;

    validCount++;
    specHit.clear();

    if ((thing.flags & mfNoClip) != 0) {
      return true;
    }

    // Things in the touched blockmap cells.
    final int xl = blockX(level.blockmap, _tmBBox[Box.left] - kMaxRadius);
    final int xh = blockX(level.blockmap, _tmBBox[Box.right] + kMaxRadius);
    final int yl = blockY(level.blockmap, _tmBBox[Box.bottom] - kMaxRadius);
    final int yh = blockY(level.blockmap, _tmBBox[Box.top] + kMaxRadius);
    for (int bx = xl; bx <= xh; bx++) {
      for (int by = yl; by <= yh; by++) {
        if (!blockThingsIterator(bx, by, _checkThing)) return false;
      }
    }

    // Lines in the touched cells.
    final int lxl = blockX(level.blockmap, _tmBBox[Box.left]);
    final int lxh = blockX(level.blockmap, _tmBBox[Box.right]);
    final int lyl = blockY(level.blockmap, _tmBBox[Box.bottom]);
    final int lyh = blockY(level.blockmap, _tmBBox[Box.top]);
    for (int bx = lxl; bx <= lxh; bx++) {
      for (int by = lyl; by <= lyh; by++) {
        if (!blockLinesIterator(bx, by, _checkLine)) return false;
      }
    }
    return true;
  }

  // -----------------------------------------------------------------------
  // P_TryMove.
  // -----------------------------------------------------------------------

  /// P_TryMove: attempt to move [thing] to (x,y). On success, relinks position
  /// and updates floorZ/ceilingZ. Honours step-up (24) and drop-off rules.
  bool tryMove(Mobj thing, fixed_t x, fixed_t y) {
    floatOk = false;
    if (!checkPosition(thing, x, y)) {
      return false;
    }
    if ((thing.flags & mfNoClip) == 0) {
      if (toInt32(tmCeilingZ - tmFloorZ) < thing.height) {
        return false; // doesn't fit
      }
      floatOk = true;
      if ((thing.flags & mfTeleport) == 0 &&
          toInt32(tmCeilingZ - thing.z) < thing.height) {
        return false; // mobj must lower itself to fit
      }
      if ((thing.flags & mfTeleport) == 0 &&
          toInt32(tmFloorZ - thing.z) > 24 * kFracUnit) {
        return false; // too big a step up
      }
      if ((thing.flags & (mfDropOff | mfFloat)) == 0 &&
          toInt32(tmFloorZ - tmDropoffZ) > 24 * kFracUnit) {
        return false; // don't stand over a drop off
      }
    }

    // The move is OK: relink and commit.
    unsetThingPosition(thing);
    final fixed_t oldX = thing.x;
    final fixed_t oldY = thing.y;
    thing.floorZ = tmFloorZ;
    thing.ceilingZ = tmCeilingZ;
    thing.x = x;
    thing.y = y;
    setThingPosition(thing);

    // Trigger crossed-line specials (use/teleport) — deferred; record only.
    crossedSpecials
      ..clear()
      ..addAll(specHit);
    crossedFromX = oldX;
    crossedFromY = oldY;
    return true;
  }

  /// P_TryMove output: whether the move would fit vertically. Vanilla floatok.
  bool floatOk = false;

  /// Lines whose specials were crossed by the last successful move (deferred
  /// triggering hook). Vanilla iterates spechit after the move.
  final List<Line> crossedSpecials = <Line>[];
  fixed_t crossedFromX = 0;
  fixed_t crossedFromY = 0;

  // -----------------------------------------------------------------------
  // P_SlideMove (wall sliding for the player).
  // -----------------------------------------------------------------------

  fixed_t _bestSlideFrac = 0;
  Line? _bestSlideLine;
  fixed_t _tmXMove = 0;
  fixed_t _tmYMove = 0;
  late Mobj _slideMo;

  /// P_SlideMove: move [mo] using its momentum, sliding along the first wall it
  /// hits instead of stopping dead. Faithful to vanilla's iterative approach.
  void slideMove(Mobj mo) {
    _slideMo = mo;
    int hitCount = 0;
    fixed_t leadX;
    fixed_t leadY;
    fixed_t trailX;
    fixed_t trailY;

    do {
      if (++hitCount == 3) {
        _stairStep(mo);
        return;
      }

      if (mo.momX > 0) {
        leadX = toInt32(mo.x + mo.radius);
        trailX = toInt32(mo.x - mo.radius);
      } else {
        leadX = toInt32(mo.x - mo.radius);
        trailX = toInt32(mo.x + mo.radius);
      }
      if (mo.momY > 0) {
        leadY = toInt32(mo.y + mo.radius);
        trailY = toInt32(mo.y - mo.radius);
      } else {
        leadY = toInt32(mo.y - mo.radius);
        trailY = toInt32(mo.y + mo.radius);
      }

      _bestSlideFrac = kFracUnit + 1;
      _pathTraverseSlide(leadX, leadY, mo.momX, mo.momY);
      _pathTraverseSlide(trailX, leadY, mo.momX, mo.momY);
      _pathTraverseSlide(leadX, trailY, mo.momX, mo.momY);

      if (_bestSlideFrac == kFracUnit + 1) {
        // The move must have hit the middle, so stairstep.
        _stairStep(mo);
        return;
      }

      // Fudge a bit to make sure it doesn't hit.
      _bestSlideFrac = toInt32(_bestSlideFrac - 0x800);
      if (_bestSlideFrac > 0) {
        final fixed_t newX = fixedMul(mo.momX, _bestSlideFrac);
        final fixed_t newY = fixedMul(mo.momY, _bestSlideFrac);
        if (!tryMove(mo, toInt32(mo.x + newX), toInt32(mo.y + newY))) {
          _stairStep(mo);
          return;
        }
      }

      _bestSlideFrac = toInt32(kFracUnit - (_bestSlideFrac + 0x800));
      if (_bestSlideFrac > kFracUnit) _bestSlideFrac = kFracUnit;
      if (_bestSlideFrac <= 0) return;

      _tmXMove = fixedMul(mo.momX, _bestSlideFrac);
      _tmYMove = fixedMul(mo.momY, _bestSlideFrac);

      _hitSlideLine(_bestSlideLine!); // clip the momentum to the wall

      mo.momX = _tmXMove;
      mo.momY = _tmYMove;
    } while (!tryMove(mo, toInt32(mo.x + _tmXMove), toInt32(mo.y + _tmYMove)));
  }

  void _stairStep(Mobj mo) {
    if (!tryMove(mo, mo.x, toInt32(mo.y + mo.momY))) {
      tryMove(mo, toInt32(mo.x + mo.momX), mo.y);
    }
  }

  /// Walk the blockmap along the slide vector, recording the closest blocking
  /// line into [_bestSlideLine]/[_bestSlideFrac]. Simplified but faithful: we
  /// test each line the path's bounding box could cross.
  void _pathTraverseSlide(fixed_t x1, fixed_t y1, fixed_t dx, fixed_t dy) {
    final fixed_t x2 = toInt32(x1 + dx);
    final fixed_t y2 = toInt32(y1 + dy);
    validCount++;
    final int bxl = blockX(level.blockmap, x1 < x2 ? x1 : x2);
    final int bxh = blockX(level.blockmap, x1 < x2 ? x2 : x1);
    final int byl = blockY(level.blockmap, y1 < y2 ? y1 : y2);
    final int byh = blockY(level.blockmap, y1 < y2 ? y2 : y1);
    for (int bx = bxl; bx <= bxh; bx++) {
      for (int by = byl; by <= byh; by++) {
        blockLinesIterator(bx, by, (Line line) {
          _slideTraverse(line, x1, y1, dx, dy);
          return true;
        });
      }
    }
  }

  void _slideTraverse(Line line, fixed_t x1, fixed_t y1, fixed_t dx, fixed_t dy) {
    // Only block on lines the slide thing would collide with.
    bool isBlocking;
    if (line.backSide == null) {
      // One-sided line.
      isBlocking = pointOnLineSide(_slideMo.x, _slideMo.y, line) == 0;
      if (!isBlocking) return;
    } else {
      lineOpening(line);
      if (opening.openRange < _slideMo.height) {
        isBlocking = true;
      } else if (toInt32(opening.openBottom - _slideMo.z) > 24 * kFracUnit) {
        isBlocking = true;
      } else if (toInt32(opening.openTop - _slideMo.z) < _slideMo.height) {
        isBlocking = true;
      } else {
        return; // not blocking
      }
    }

    // Compute intercept fraction of the slide vector against the line.
    final fixed_t frac = _interceptFrac(x1, y1, dx, dy, line);
    if (frac >= 0 && frac < _bestSlideFrac) {
      _bestSlideFrac = frac;
      _bestSlideLine = line;
    }
  }

  /// P_InterceptVector restricted to a line: fraction along (x1,y1)+(dx,dy)
  /// where it crosses [line], or -1 if parallel.
  fixed_t _interceptFrac(
      fixed_t x1, fixed_t y1, fixed_t dx, fixed_t dy, Line line) {
    final fixed_t den = toInt32(
        fixedMul(line.dy >> 8, dx >> 8) - fixedMul(line.dx >> 8, dy >> 8));
    if (den == 0) return -1;
    final fixed_t num = toInt32(
        fixedMul(toInt32(line.v1.x - x1) >> 8, line.dy >> 8) +
            fixedMul(toInt32(y1 - line.v1.y) >> 8, line.dx >> 8));
    return fixedDiv(num, den);
  }

  /// P_HitSlideLine: clip [_tmXMove]/[_tmYMove] so the thing slides along the
  /// line rather than into it. Faithful to vanilla (axis-aligned fast paths +
  /// angle projection).
  void _hitSlideLine(Line line) {
    if (line.slopeType == SlopeType.horizontal) {
      _tmYMove = 0;
      return;
    }
    if (line.slopeType == SlopeType.vertical) {
      _tmXMove = 0;
      return;
    }
    // General case: project momentum onto the line direction.
    final fixed_t lineDx = line.dx;
    final fixed_t lineDy = line.dy;
    // Use a double for the projection to stay faithful to magnitude; vanilla
    // uses angle tables. The result is the momentum component parallel to the
    // line, which is sufficient for the player's slide behaviour.
    final double lx = lineDx.toDouble();
    final double ly = lineDy.toDouble();
    final double len2 = lx * lx + ly * ly;
    if (len2 == 0) return;
    final double mx = _tmXMove.toDouble();
    final double my = _tmYMove.toDouble();
    final double dot = (mx * lx + my * ly) / len2;
    _tmXMove = toInt32((dot * lx).round());
    _tmYMove = toInt32((dot * ly).round());
  }
}
