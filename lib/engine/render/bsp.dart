// BSP traversal — faithful Dart port of Chocolate Doom (commit
// 353cf500) src/doom/r_bsp.c: R_ClearClipSegs, R_ClipSolidWallSegment,
// R_ClipPassWallSegment, R_AddLine, R_CheckBBox (with the exact checkcoord
// table), R_Subsector, R_RenderBSPNode, plus R_PointOnSide from r_main.c.
//
// solidsegs[] is modelled as a contiguous list of cliprange_t; `newend` is the
// index one past the last valid range, exactly as the C pointer. The
// pointer-walk merges/crunches are transcribed step for step.

import '../math/angle.dart';
import '../math/fixed.dart';
import '../../game/world/defs.dart';
import 'planes.dart';
import 'render_state.dart';
import 'segs.dart';
import 'things.dart';

/// cliprange_t.
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
    required this.things,
  });

  final RenderState state;
  final SegRenderer segs;
  final PlaneRenderer planes;
  final ThingRenderer things;

  late List<Seg> _segsList;
  late List<Subsector> _subsectors;
  late List<Node> _nodes;

  // solidsegs[MAXSEGS] + newend. MAXSEGS = SCREENWIDTH/2 + 1.
  final List<_ClipRange> _solidSegs = <_ClipRange>[];
  int _newEnd = 0; // index one past the last valid solidseg.

  _ClipRange _seg(int i) {
    while (_solidSegs.length <= i) {
      _solidSegs.add(_ClipRange(0, 0));
    }
    return _solidSegs[i];
  }

  /// R_ClearClipSegs.
  void clearClipSegs() {
    _seg(0).first = -0x7fffffff;
    _seg(0).last = -1;
    _seg(1).first = state.viewWidth;
    _seg(1).last = 0x7fffffff;
    _newEnd = 2;
  }

  /// Render the whole BSP. Caller has already done the per-frame clears.
  void render({
    required List<Seg> segsList,
    required List<Subsector> subsectors,
    required List<Node> nodes,
    required int rootNode,
  }) {
    _segsList = segsList;
    _subsectors = subsectors;
    _nodes = nodes;
    _renderBSPNode(rootNode);
  }

  // R_RenderBSPNode.
  void _renderBSPNode(int bspnum) {
    if ((bspnum & nfSubsector) != 0) {
      if (bspnum == -1) {
        _subsector(0);
      } else {
        _subsector(bspnum & ~nfSubsector);
      }
      return;
    }
    final Node bsp = _nodes[bspnum];
    final int side = _pointOnSide(state.viewX, state.viewY, bsp);
    _renderBSPNode(bsp.children[side]);
    if (_checkBBox(bsp.bbox[side ^ 1])) {
      _renderBSPNode(bsp.children[side ^ 1]);
    }
  }

  // R_PointOnSide (r_main.c).
  int _pointOnSide(fixed_t x, fixed_t y, Node node) {
    if (node.dx == 0) {
      if (x <= node.x) return node.dy > 0 ? 1 : 0;
      return node.dy < 0 ? 1 : 0;
    }
    if (node.dy == 0) {
      if (y <= node.y) return node.dx < 0 ? 1 : 0;
      return node.dx > 0 ? 1 : 0;
    }
    final fixed_t dx = toInt32(x - node.x);
    final fixed_t dy = toInt32(y - node.y);
    if (((node.dy ^ node.dx ^ dx ^ dy) & 0x80000000) != 0) {
      if (((node.dy ^ dx) & 0x80000000) != 0) {
        return 1; // left is negative
      }
      return 0;
    }
    final int left = fixedMul(node.dy >> kFracBits, dx);
    final int right = fixedMul(dy, node.dx >> kFracBits);
    if (right < left) return 0; // front side
    return 1; // back side
  }

  // R_Subsector.
  void _subsector(int num) {
    final Subsector sub = _subsectors[num];
    final Sector frontSector = sub.sector;
    final int count = sub.numLines;
    int lineIdx = sub.firstLine;

    if (frontSector.floorHeight < state.viewZ) {
      segs.floorPlane = planes.findPlane(
          frontSector.floorHeight, frontSector.floorPic, frontSector.lightLevel);
    } else {
      segs.floorPlane = null;
    }

    if (frontSector.ceilingHeight > state.viewZ ||
        frontSector.ceilingPic == planes.skyFlatNum) {
      segs.ceilingPlane = planes.findPlane(frontSector.ceilingHeight,
          frontSector.ceilingPic, frontSector.lightLevel);
    } else {
      segs.ceilingPlane = null;
    }

    things.addSprites(frontSector);

    for (int i = 0; i < count; i++) {
      _addLine(_segsList[lineIdx]);
      lineIdx++;
    }
  }

  // R_AddLine.
  void _addLine(Seg line) {
    segs.setCurLine(line);

    angle_t angle1 = state.pointToAngle(line.v1.x, line.v1.y);
    angle_t angle2 = state.pointToAngle(line.v2.x, line.v2.y);

    final angle_t span = normAngle(angle1 - angle2);
    if (span >= kAng180) return; // back side

    segs.rwAngle1 = angle1;
    angle1 = normAngle(angle1 - state.viewAngle);
    angle2 = normAngle(angle2 - state.viewAngle);

    final angle_t clipAngle = state.clipAngle;
    final angle_t twoClip = normAngle(clipAngle * 2);

    angle_t tspan = normAngle(angle1 + clipAngle);
    if (tspan > twoClip) {
      tspan = normAngle(tspan - twoClip);
      if (tspan >= span) return; // totally off the left edge
      angle1 = clipAngle;
    }
    tspan = normAngle(clipAngle - angle2);
    if (tspan > twoClip) {
      tspan = normAngle(tspan - twoClip);
      if (tspan >= span) return;
      angle2 = normAngle(-clipAngle);
    }

    // The seg is in the view range, but not necessarily visible.
    final int fa1 = fineShift(normAngle(angle1 + kAng90));
    final int fa2 = fineShift(normAngle(angle2 + kAng90));
    final int x1 = state.viewAngleToX[fa1];
    final int x2 = state.viewAngleToX[fa2];

    if (x1 == x2) return; // does not cross a pixel

    final Sector? back = line.backSector;
    final Sector front = line.frontSector;

    // Single sided line?
    if (back == null) {
      _clipSolidWallSegment(x1, x2 - 1);
      return;
    }
    // Closed door.
    if (back.ceilingHeight <= front.floorHeight ||
        back.floorHeight >= front.ceilingHeight) {
      _clipSolidWallSegment(x1, x2 - 1);
      return;
    }
    // Window.
    if (back.ceilingHeight != front.ceilingHeight ||
        back.floorHeight != front.floorHeight) {
      _clipPassWallSegment(x1, x2 - 1);
      return;
    }
    // Reject empty lines used for triggers and special events.
    if (back.ceilingPic == front.ceilingPic &&
        back.floorPic == front.floorPic &&
        back.lightLevel == front.lightLevel &&
        line.sidedef.midTexture == 0) {
      return;
    }
    _clipPassWallSegment(x1, x2 - 1);
  }

  // R_ClipSolidWallSegment.
  void _clipSolidWallSegment(int first, int last) {
    // Find the first range that touches the range.
    int start = 0;
    while (_seg(start).last < first - 1) {
      start++;
    }

    if (first < _seg(start).first) {
      if (last < _seg(start).first - 1) {
        // Post is entirely visible (above start), insert a new clippost.
        segs.storeWallRange(first, last);
        int next = _newEnd;
        _newEnd++;
        while (next != start) {
          _seg(next).first = _seg(next - 1).first;
          _seg(next).last = _seg(next - 1).last;
          next--;
        }
        _seg(next).first = first;
        _seg(next).last = last;
        return;
      }
      // There is a fragment above *start.
      segs.storeWallRange(first, _seg(start).first - 1);
      _seg(start).first = first;
    }

    // Bottom contained in start?
    if (last <= _seg(start).last) return;

    int next = start;
    while (last >= _seg(next + 1).first - 1) {
      // There is a fragment between two posts.
      segs.storeWallRange(_seg(next).last + 1, _seg(next + 1).first - 1);
      next++;
      if (last <= _seg(next).last) {
        // Bottom is contained in next.
        _seg(start).last = _seg(next).last;
        _crunch(start, next);
        return;
      }
    }

    // There is a fragment after *next.
    segs.storeWallRange(_seg(next).last + 1, last);
    _seg(start).last = last;
    _crunch(start, next);
  }

  // The `crunch:` label in R_ClipSolidWallSegment:
  //   if (next == start) return;
  //   while (next++ != newend) { *++start = *next; }
  //   newend = start+1;
  // (newend is one-past-last; _newEnd matches.)
  void _crunch(int start, int next) {
    if (next == start) {
      return; // post just extended past the bottom of one post
    }
    while (next != _newEnd) {
      next++; // post-increment in the condition
      start++; // pre-increment in *++start
      _seg(start).first = _seg(next).first;
      _seg(start).last = _seg(next).last;
    }
    _newEnd = start + 1;
  }

  // R_ClipPassWallSegment.
  void _clipPassWallSegment(int first, int last) {
    int start = 0;
    while (_seg(start).last < first - 1) {
      start++;
    }

    if (first < _seg(start).first) {
      if (last < _seg(start).first - 1) {
        segs.storeWallRange(first, last);
        return;
      }
      segs.storeWallRange(first, _seg(start).first - 1);
    }

    if (last <= _seg(start).last) return;

    while (last >= _seg(start + 1).first - 1) {
      segs.storeWallRange(_seg(start).last + 1, _seg(start + 1).first - 1);
      start++;
      if (last <= _seg(start).last) return;
    }

    segs.storeWallRange(_seg(start).last + 1, last);
  }

  // checkcoord[12][4] (r_bsp.c).
  static const List<List<int>> _checkCoord = <List<int>>[
    <int>[3, 0, 2, 1],
    <int>[3, 0, 2, 0],
    <int>[3, 1, 2, 0],
    <int>[0, 0, 0, 0],
    <int>[2, 0, 2, 1],
    <int>[0, 0, 0, 0],
    <int>[3, 1, 3, 0],
    <int>[0, 0, 0, 0],
    <int>[2, 0, 3, 1],
    <int>[2, 1, 3, 1],
    <int>[2, 1, 3, 0],
    <int>[0, 0, 0, 0],
  ];

  // R_CheckBBox. bspcoord is indexed [BOXTOP,BOXBOTTOM,BOXLEFT,BOXRIGHT].
  bool _checkBBox(List<fixed_t> bspcoord) {
    int boxx;
    int boxy;
    if (state.viewX <= bspcoord[Box.left]) {
      boxx = 0;
    } else if (state.viewX < bspcoord[Box.right]) {
      boxx = 1;
    } else {
      boxx = 2;
    }
    if (state.viewY >= bspcoord[Box.top]) {
      boxy = 0;
    } else if (state.viewY > bspcoord[Box.bottom]) {
      boxy = 1;
    } else {
      boxy = 2;
    }

    final int boxpos = (boxy << 2) + boxx;
    if (boxpos == 5) return true;

    final fixed_t x1 = bspcoord[_checkCoord[boxpos][0]];
    final fixed_t y1 = bspcoord[_checkCoord[boxpos][1]];
    final fixed_t x2 = bspcoord[_checkCoord[boxpos][2]];
    final fixed_t y2 = bspcoord[_checkCoord[boxpos][3]];

    angle_t angle1 = normAngle(state.pointToAngle(x1, y1) - state.viewAngle);
    angle_t angle2 = normAngle(state.pointToAngle(x2, y2) - state.viewAngle);

    final angle_t span = normAngle(angle1 - angle2);
    if (span >= kAng180) return true; // sitting on a line

    final angle_t clipAngle = state.clipAngle;
    final angle_t twoClip = normAngle(clipAngle * 2);

    angle_t tspan = normAngle(angle1 + clipAngle);
    if (tspan > twoClip) {
      tspan = normAngle(tspan - twoClip);
      if (tspan >= span) return false;
      angle1 = clipAngle;
    }
    tspan = normAngle(clipAngle - angle2);
    if (tspan > twoClip) {
      tspan = normAngle(tspan - twoClip);
      if (tspan >= span) return false;
      angle2 = normAngle(-clipAngle);
    }

    final int fa1 = fineShift(normAngle(angle1 + kAng90));
    final int fa2 = fineShift(normAngle(angle2 + kAng90));
    int sx1 = state.viewAngleToX[fa1];
    int sx2 = state.viewAngleToX[fa2];

    if (sx1 == sx2) return false; // does not cross a pixel
    sx2--;

    int start = 0;
    while (_seg(start).last < sx2) {
      start++;
    }
    if (sx1 >= _seg(start).first && sx2 <= _seg(start).last) {
      return false; // the clippost contains the new span
    }
    return true;
  }
}
