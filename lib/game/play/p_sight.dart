// Line-of-sight / visibility, ported 1:1 from Chocolate Doom src/doom/p_sight.c.
//
// [Sight.checkSight] is P_CheckSight: a REJECT-matrix fast reject (using the
// world [Reject] lump) followed by a recursive BSP cross (P_CrossBSPNode /
// P_CrossSubsector) along the `strace` divline. The file-scope statics of
// p_sight.c (sightzstart/topslope/bottomslope/strace/t2x/t2y/validcount) are
// instance fields here.
//
// This is the modern Doom path (gameversion > exe_doom_1_2); the 1.2
// PTR_SightTraverse path is not modelled (we always run the BSP cross), which
// matches the released Doom/Doom II behaviour the port targets.
//
// Faithfulness is mandatory: this is a port, not a paraphrase.

import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import '../world/level.dart';
import 'mobj.dart';

/// divline_t (p_sight.c local). Kept private so p_sight.dart needs no
/// dependency on p_shoot.dart's intercept machinery.
class _DivLine {
  fixed_t x = 0;
  fixed_t y = 0;
  fixed_t dx = 0;
  fixed_t dy = 0;
}

/// P_CheckSight and its BSP cross. One instance per [Level].
class Sight {
  Sight(this.level) {
    // Build a sector -> index map so the REJECT lookup is O(1) (vanilla uses
    // pointer arithmetic `sector - sectors`).
    for (int i = 0; i < level.sectors.length; i++) {
      _sectorIndex[level.sectors[i]] = i;
    }
  }

  final Level level;

  final Map<Sector, int> _sectorIndex = <Sector, int>{};

  // --- p_sight.c file-scope statics (now instance fields) ---
  /// validcount: traversal stamp bumped each P_CheckSight (line dedupe).
  int validCount = 0;

  fixed_t _sightZStart = 0; // eye z of looker
  fixed_t _topSlope = 0;
  fixed_t _bottomSlope = 0; // slopes to top and bottom of target

  final _DivLine _strace = _DivLine(); // from t1 to t2
  fixed_t _t2x = 0;
  fixed_t _t2y = 0;

  /// sightcounts[2]: [0] = reject-rejected, [1] = bsp-traversed (diagnostics).
  final List<int> sightCounts = <int>[0, 0];

  // =======================================================================
  // P_DivlineSide (p_sight.c). Returns 0 (front), 1 (back), or 2 (on).
  // =======================================================================
  int _divlineSide(fixed_t x, fixed_t y, _DivLine node) {
    if (node.dx == 0) {
      if (x == node.x) {
        return 2;
      }
      if (x <= node.x) {
        return node.dy > 0 ? 1 : 0;
      }
      return node.dy < 0 ? 1 : 0;
    }

    if (node.dy == 0) {
      // NB: vanilla compares x against node->y / y against node->y here. This
      // is the verbatim (quirky) original code.
      if (x == node.y) {
        return 2;
      }
      if (y <= node.y) {
        return node.dx < 0 ? 1 : 0;
      }
      return node.dx > 0 ? 1 : 0;
    }

    final fixed_t dx = toInt32(x - node.x);
    final fixed_t dy = toInt32(y - node.y);

    final fixed_t left = toInt32((node.dy >> kFracBits) * (dx >> kFracBits));
    final fixed_t right = toInt32((dy >> kFracBits) * (node.dx >> kFracBits));

    if (right < left) {
      return 0; // front side
    }
    if (left == right) {
      return 2;
    }
    return 1; // back side
  }

  // =======================================================================
  // P_InterceptVector2 (p_sight.c). v2 = strace, v1 = the line divline.
  // =======================================================================
  fixed_t _interceptVector2(_DivLine v2, _DivLine v1) {
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
  // P_CrossSubsector (p_sight.c). Returns true if strace crosses subsector
  // [num] successfully (no occluder blocks LOS).
  // =======================================================================
  bool _crossSubsector(int num) {
    final Subsector sub = level.subsectors[num];

    int count = sub.numLines;
    int segIdx = sub.firstLine;

    for (; count != 0; segIdx++, count--) {
      final Seg seg = level.segs[segIdx];
      final Line line = seg.linedef;

      // already checked other side?
      if (line.validCount == validCount) {
        continue;
      }
      line.validCount = validCount;

      final Vertex v1 = line.v1;
      final Vertex v2 = line.v2;
      int s1 = _divlineSide(v1.x, v1.y, _strace);
      int s2 = _divlineSide(v2.x, v2.y, _strace);

      // line isn't crossed?
      if (s1 == s2) {
        continue;
      }

      final _DivLine divl = _DivLine()
        ..x = v1.x
        ..y = v1.y
        ..dx = toInt32(v2.x - v1.x)
        ..dy = toInt32(v2.y - v1.y);
      s1 = _divlineSide(_strace.x, _strace.y, divl);
      s2 = _divlineSide(_t2x, _t2y, divl);

      // line isn't crossed?
      if (s1 == s2) {
        continue;
      }

      // Backsector may be NULL if this is an "impassible glass" hack line.
      if (line.backSector == null) {
        return false;
      }

      // stop because it is not two sided anyway
      if ((line.flags & mlTwoSided) == 0) {
        return false;
      }

      // crosses a two sided line
      final Sector front = seg.frontSector;
      final Sector back = seg.backSector!;

      // no wall to block sight with?
      if (front.floorHeight == back.floorHeight &&
          front.ceilingHeight == back.ceilingHeight) {
        continue;
      }

      // possible occluder because of ceiling height differences
      final fixed_t openTop;
      if (front.ceilingHeight < back.ceilingHeight) {
        openTop = front.ceilingHeight;
      } else {
        openTop = back.ceilingHeight;
      }

      // because of floor height differences
      final fixed_t openBottom;
      if (front.floorHeight > back.floorHeight) {
        openBottom = front.floorHeight;
      } else {
        openBottom = back.floorHeight;
      }

      // quick test for totally closed doors
      if (openBottom >= openTop) {
        return false; // stop
      }

      final fixed_t frac = _interceptVector2(_strace, divl);

      if (front.floorHeight != back.floorHeight) {
        final fixed_t slope =
            fixedDiv(toInt32(openBottom - _sightZStart), frac);
        if (slope > _bottomSlope) {
          _bottomSlope = slope;
        }
      }

      if (front.ceilingHeight != back.ceilingHeight) {
        final fixed_t slope = fixedDiv(toInt32(openTop - _sightZStart), frac);
        if (slope < _topSlope) {
          _topSlope = slope;
        }
      }

      if (_topSlope <= _bottomSlope) {
        return false; // stop
      }
    }

    // passed the subsector ok
    return true;
  }

  // =======================================================================
  // P_CrossBSPNode (p_sight.c). Returns true if strace crosses node [bspnum].
  // =======================================================================
  bool _crossBSPNode(int bspnum) {
    if ((bspnum & nfSubsector) != 0) {
      if (bspnum == -1) {
        return _crossSubsector(0);
      }
      return _crossSubsector(bspnum & ~nfSubsector);
    }

    final Node bsp = level.nodes[bspnum];

    // decide which side the start point is on
    final _DivLine bspLine = _DivLine()
      ..x = bsp.x
      ..y = bsp.y
      ..dx = bsp.dx
      ..dy = bsp.dy;
    int side = _divlineSide(_strace.x, _strace.y, bspLine);
    if (side == 2) {
      side = 0; // an "on" should cross both sides
    }

    // cross the starting side
    if (!_crossBSPNode(bsp.children[side])) {
      return false;
    }

    // the partition plane is crossed here
    if (side == _divlineSide(_t2x, _t2y, bspLine)) {
      // the line doesn't touch the other side
      return true;
    }

    // cross the ending side
    return _crossBSPNode(bsp.children[side ^ 1]);
  }

  // =======================================================================
  // P_CheckSight (p_sight.c). Returns true if a straight line between t1 and
  // t2 is unobstructed. Uses REJECT.
  // =======================================================================
  bool checkSight(Mobj t1, Mobj t2) {
    // First check for trivial rejection (REJECT table).
    final int? s1 = _sectorIndex[t1.subsectorSector];
    final int? s2 = _sectorIndex[t2.subsectorSector];
    if (s1 != null && s2 != null) {
      if (level.reject.rejected(s1, s2)) {
        sightCounts[0]++;
        // can't possibly be connected
        return false;
      }
    }

    // An unobstructed LOS is possible. Now look from eyes of t1 to any part
    // of t2.
    sightCounts[1]++;

    validCount++;

    _sightZStart = toInt32(t1.z + t1.height - (t1.height >> 2));
    _topSlope = toInt32((t2.z + t2.height) - _sightZStart);
    _bottomSlope = toInt32(t2.z - _sightZStart);

    _strace.x = t1.x;
    _strace.y = t1.y;
    _t2x = t2.x;
    _t2y = t2.y;
    _strace.dx = toInt32(t2.x - t1.x);
    _strace.dy = toInt32(t2.y - t1.y);

    // the head node is the last node output
    return _crossBSPNode(level.nodes.length - 1);
  }
}
