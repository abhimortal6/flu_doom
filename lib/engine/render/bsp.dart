// BSP traversal, ported from Chocolate Doom r_bsp.c
// (R_RenderBSPNode, R_Subsector, R_AddLine, R_ClipSolidWallSegment,
// R_ClipPassWallSegment, R_CheckBBox) plus the solidsegs clip-range list.
//
// Walks the BSP front-to-back from the viewpoint. For each subsector it
// projects its segs into screen-column ranges, clips them against already-drawn
// solid walls (the cliprange list), draws visible walls (via SegRenderer), and
// registers the subsector's floor/ceiling visplanes (via PlaneRenderer).

import '../math/angle.dart';
import '../math/fixed.dart';
import '../../game/world/defs.dart';
import 'planes.dart';
import 'render_state.dart';
import 'segs.dart';

/// A solid-wall screen-column range, vanilla `cliprange_t`.
class _ClipRange {
  _ClipRange(this.first, this.last);
  int first;
  int last;
}

class BspRenderer {
  BspRenderer({
    required this.state,
    required this.segs,
    required this.planes,
  });

  final RenderState state;
  final SegRenderer segs;
  final PlaneRenderer planes;

  // The level we are rendering (set per frame).
  late List<Seg> _segsList;
  late List<Subsector> _subsectors;
  late List<Node> _nodes;
  late int _rootNode;

  // solidsegs cliprange list.
  final List<_ClipRange> _solidSegs = <_ClipRange>[];
  int _solidCount = 0;

  void clear() {
    _solidCount = 0;
    _addSolid(-0x7fffffff, -1);
    _addSolid(state.viewWidth, 0x7fffffff);
  }

  void _addSolid(int first, int last) {
    if (_solidCount < _solidSegs.length) {
      _solidSegs[_solidCount].first = first;
      _solidSegs[_solidCount].last = last;
    } else {
      _solidSegs.add(_ClipRange(first, last));
    }
    _solidCount++;
  }

  /// Render the whole BSP for the current frame into the wired-up sub-renderers.
  void render({
    required List<Seg> segsList,
    required List<Subsector> subsectors,
    required List<Node> nodes,
    required int rootNode,
  }) {
    _segsList = segsList;
    _subsectors = subsectors;
    _nodes = nodes;
    _rootNode = rootNode;
    clear();
    _renderNode(_rootNode);
  }

  void _renderNode(int nodeNum) {
    // If this is a subsector leaf.
    if ((nodeNum & nfSubsector) != 0) {
      final int idx = (nodeNum == -1) ? 0 : (nodeNum & ~nfSubsector);
      _subsector(idx);
      return;
    }
    final Node node = _nodes[nodeNum];
    final int side = _pointOnSide(state.viewX, state.viewY, node);
    // Render near side first.
    _renderNode(node.children[side]);
    // Then far side if visible (we skip the bbox visibility test for
    // simplicity/correctness — it is only an optimisation; faithful behaviour
    // is preserved because solidsegs still clips everything).
    if (_checkBBox(node.bbox[side ^ 1])) {
      _renderNode(node.children[side ^ 1]);
    }
  }

  // R_PointOnSide.
  int _pointOnSide(fixed_t x, fixed_t y, Node node) {
    if (node.dx == 0) {
      if (x <= node.x) {
        return node.dy > 0 ? 1 : 0;
      }
      return node.dy < 0 ? 1 : 0;
    }
    if (node.dy == 0) {
      if (y <= node.y) {
        return node.dx < 0 ? 1 : 0;
      }
      return node.dx > 0 ? 1 : 0;
    }
    final fixed_t dx = toInt32(x - node.x);
    final fixed_t dy = toInt32(y - node.y);
    // Try to quickly decide by looking at sign bits.
    if ((node.dy ^ node.dx ^ dx ^ dy) < 0) {
      return ((node.dy ^ dx) < 0) ? 1 : 0;
    }
    final int left = fixedMul(node.dy >> kFracBits, dx);
    final int right = fixedMul(dy, node.dx >> kFracBits);
    return right < left ? 0 : 1;
  }

  // R_CheckBBox: is any of this bbox potentially visible (not fully behind
  // solidsegs)? We compute the screen span of the box and test the cliprange.
  bool _checkBBox(List<fixed_t> bspcoord) {
    // Determine the box corners to use based on view position (vanilla
    // checkcoord table). We approximate with the two extreme corners.
    final fixed_t bx1 = bspcoord[Box.left];
    final fixed_t bx2 = bspcoord[Box.right];
    final fixed_t by1 = bspcoord[Box.top];
    final fixed_t by2 = bspcoord[Box.bottom];

    // Pick the two corners that bound the angular extent (vanilla checkcoord).
    int boxx = state.viewX <= bx1 ? 0 : (state.viewX < bx2 ? 1 : 2);
    int boxy = state.viewY >= by1 ? 0 : (state.viewY > by2 ? 1 : 2);
    final int boxpos = (boxy << 2) + boxx;
    if (boxpos == 5) return true; // inside the box

    final List<List<fixed_t>> corners = _checkCoord(
        boxpos, bx1, bx2, by1, by2);
    final angle_t angle1 = state.pointToAngle(corners[0][0], corners[0][1]);
    final angle_t angle2 = state.pointToAngle(corners[1][0], corners[1][1]);

    // Reuse the same clip span logic as a wall but only to test coverage.
    final _Span? span = _angleToScreenSpan(angle1, angle2);
    if (span == null) return false;
    // Is [span.x1..span.x2] fully covered by a single solid seg?
    int sx1 = span.x1;
    int sx2 = span.x2;
    int i = 0;
    while (i < _solidCount && _solidSegs[i].last < sx2) {
      i++;
    }
    if (i < _solidCount &&
        sx1 >= _solidSegs[i].first &&
        sx2 <= _solidSegs[i].last) {
      return false; // fully behind a solid wall
    }
    return true;
  }

  List<List<fixed_t>> _checkCoord(
      int boxpos, fixed_t bx1, fixed_t bx2, fixed_t by1, fixed_t by2) {
    // checkcoord[boxpos] selects which corners form the angular extent.
    // Order: x1,y1, x2,y2 (left edge to right edge of the box as seen).
    switch (boxpos) {
      case 0:
        return [
          [bx2, by1],
          [bx1, by2]
        ];
      case 1:
        return [
          [bx1, by1],
          [bx1, by2]
        ];
      case 2:
        return [
          [bx1, by1],
          [bx2, by2]
        ];
      case 4:
        return [
          [bx2, by2],
          [bx1, by2]
        ];
      case 6:
        return [
          [bx1, by1],
          [bx2, by1]
        ];
      case 8:
        return [
          [bx2, by2],
          [bx1, by1]
        ];
      case 9:
        return [
          [bx1, by2],
          [bx1, by1]
        ];
      case 10:
        return [
          [bx1, by2],
          [bx2, by1]
        ];
      default:
        return [
          [bx2, by1],
          [bx1, by2]
        ];
    }
  }

  void _subsector(int num) {
    final Subsector sub = _subsectors[num];
    final Sector sector = sub.sector;

    // Register floor/ceiling visplanes for this subsector.
    segs.floorPlane = sector.floorHeight < state.viewZ
        ? planes.findPlane(sector.floorHeight, sector.floorPic,
            sector.lightLevel)
        : null;
    segs.ceilingPlane = (sector.ceilingHeight > state.viewZ ||
            sector.ceilingPic == planes.skyFlatNum)
        ? planes.findPlane(sector.ceilingHeight, sector.ceilingPic,
            sector.lightLevel)
        : null;

    final int first = sub.firstLine;
    for (int i = 0; i < sub.numLines; i++) {
      _addLine(_segsList[first + i]);
    }
  }

  // R_AddLine.
  void _addLine(Seg seg) {
    final angle_t angle1 = state.pointToAngle(seg.v1.x, seg.v1.y);
    final angle_t angle2 = state.pointToAngle(seg.v2.x, seg.v2.y);

    // Back-face cull: seg must span clockwise (angle1 -> angle2).
    final angle_t span = toInt32(angle1 - angle2) & 0xFFFFFFFF;
    if (span >= kAng180) return;

    final _Span? scr = _angleToScreenSpan(angle1, angle2);
    if (scr == null) return;
    final int x1 = scr.x1;
    final int x2 = scr.x2;
    if (x1 > x2) return;

    final Sector? back = seg.backSector;
    final bool solid = _isSolid(seg, back);

    if (solid) {
      _clipSolidWallSegment(seg, x1, x2, angle1);
    } else {
      _clipPassWallSegment(seg, x1, x2, angle1);
    }
  }

  bool _isSolid(Seg seg, Sector? back) {
    if (back == null) return true;
    final Sector front = seg.frontSector;
    // Closed door.
    if (back.ceilingHeight <= front.floorHeight ||
        back.floorHeight >= front.ceilingHeight) {
      return true;
    }
    // Otherwise it is a passable (window / step) two-sided wall.
    return false;
  }

  // Convert a clockwise angle pair to a screen column span, clipping to the
  // view frustum (vanilla R_AddLine span clip via xtoviewangle/viewangletox).
  _Span? _angleToScreenSpan(angle_t angle1, angle_t angle2) {
    // Rotate by -viewangle so the view faces angle 0.
    angle_t a1 = toInt32(angle1 - state.viewAngle) & 0xFFFFFFFF;
    angle_t a2 = toInt32(angle2 - state.viewAngle) & 0xFFFFFFFF;

    final angle_t clipAngle = state.xToViewAngle[0]; // == FOV/2 as an angle
    // tspan = a1 + clipangle; if > 2*clipangle then clip.
    final angle_t doubleClip = normAngle(clipAngle * 2);

    angle_t tspan = normAngle(a1 + clipAngle);
    if (tspan > doubleClip) {
      tspan = toInt32(tspan - doubleClip) & 0xFFFFFFFF;
      if (tspan >= doubleClip) return null; // entirely off the left? (vanilla)
      a1 = clipAngle;
    }
    tspan = normAngle(clipAngle - a2);
    if (tspan > doubleClip) {
      tspan = toInt32(tspan - doubleClip) & 0xFFFFFFFF;
      if (tspan >= doubleClip) return null;
      a2 = normAngle(-clipAngle) & 0xFFFFFFFF; // 0 - clipangle
    }

    // Now a1, a2 are within [-clip, +clip] expressed around 0..2^32.
    final int x1 = _viewAngleToScreenX(a1);
    final int x2 = _viewAngleToScreenX(a2);
    if (x1 >= x2) {
      // Span collapsed to nothing.
      if (x1 == x2) return null;
      return null;
    }
    return _Span(x1, x2 - 1);
  }

  int _viewAngleToScreenX(angle_t a) {
    // viewangletox index = (a + ANG90) >> ANGLETOFINESHIFT, masked.
    final int idx =
        (normAngle(a + kAng90) >> kAngleToFineShift) & (kFineAngles ~/ 2 - 1);
    return state.viewAngleToX[idx];
  }

  // R_ClipSolidWallSegment.
  void _clipSolidWallSegment(
      Seg seg, int first, int last, angle_t angle1) {
    // Find the first cliprange that touches or follows 'first'.
    int start = 0;
    while (start < _solidCount && _solidSegs[start].last < first - 1) {
      start++;
    }

    if (first < _solidSegs[start].first) {
      if (last < _solidSegs[start].first - 1) {
        // Entirely visible; draw and insert a new clip range.
        segs.storeWallRange(seg, first, last, angle1);
        _insertSolid(start, first, last);
        return;
      }
      // Draw up to the existing range's start.
      segs.storeWallRange(seg, first, _solidSegs[start].first - 1, angle1);
      _solidSegs[start].first = first;
    }

    if (last <= _solidSegs[start].last) {
      return; // fully behind already
    }

    // Walk and merge following ranges that this seg bridges.
    int next = start;
    while (last >= _solidSegs[next + 1].first - 1) {
      segs.storeWallRange(
          seg, _solidSegs[next].last + 1, _solidSegs[next + 1].first - 1,
          angle1);
      next++;
      if (last <= _solidSegs[next].last) {
        _solidSegs[start].last = _solidSegs[next].last;
        _removeRange(start + 1, next);
        return;
      }
    }
    // Draw remaining and extend.
    segs.storeWallRange(seg, _solidSegs[next].last + 1, last, angle1);
    _solidSegs[start].last = last;
    if (next != start) {
      _removeRange(start + 1, next);
    }
  }

  void _insertSolid(int at, int first, int last) {
    // Shift ranges up to make room at index 'at'.
    if (_solidCount >= _solidSegs.length) {
      _solidSegs.add(_ClipRange(0, 0));
    }
    for (int i = _solidCount; i > at; i--) {
      _solidSegs[i].first = _solidSegs[i - 1].first;
      _solidSegs[i].last = _solidSegs[i - 1].last;
    }
    _solidSegs[at].first = first;
    _solidSegs[at].last = last;
    _solidCount++;
  }

  void _removeRange(int from, int to) {
    // Remove ranges [from..to] inclusive by shifting down.
    final int n = to - from + 1;
    if (n <= 0) return;
    for (int i = from; i + n < _solidCount; i++) {
      _solidSegs[i].first = _solidSegs[i + n].first;
      _solidSegs[i].last = _solidSegs[i + n].last;
    }
    _solidCount -= n;
  }

  // R_ClipPassWallSegment: draw the visible portions of a passable (2-sided)
  // wall without adding to solidsegs.
  void _clipPassWallSegment(
      Seg seg, int first, int last, angle_t angle1) {
    int start = 0;
    while (start < _solidCount && _solidSegs[start].last < first - 1) {
      start++;
    }
    if (first < _solidSegs[start].first) {
      if (last < _solidSegs[start].first - 1) {
        segs.storeWallRange(seg, first, last, angle1);
        return;
      }
      segs.storeWallRange(seg, first, _solidSegs[start].first - 1, angle1);
    }
    if (last <= _solidSegs[start].last) return;
    while (last >= _solidSegs[start + 1].first - 1) {
      segs.storeWallRange(
          seg, _solidSegs[start].last + 1, _solidSegs[start + 1].first - 1,
          angle1);
      start++;
      if (last <= _solidSegs[start].last) return;
    }
    segs.storeWallRange(seg, _solidSegs[start].last + 1, last, angle1);
  }
}

class _Span {
  _Span(this.x1, this.x2);
  final int x1;
  final int x2;
}
