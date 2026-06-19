// Map utility geometry, ported from Chocolate Doom src/p_maputl.c.
//
// Pure helpers used by collision and traversal: point-vs-line side tests, box
// approximations, line "opening" (the vertical gap a two-sided line exposes),
// and blockmap coordinate conversions. No mutation of world state.

import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import '../world/level.dart';

/// P_PointOnLineSide: which side of [line] the point (x,y) is on. Returns
/// 0 (front/right) or 1 (back/left). Faithful to vanilla.
int pointOnLineSide(fixed_t x, fixed_t y, Line line) {
  if (line.dx == 0) {
    if (x <= line.v1.x) {
      return line.dy > 0 ? 1 : 0;
    }
    return line.dy < 0 ? 1 : 0;
  }
  if (line.dy == 0) {
    if (y <= line.v1.y) {
      return line.dx < 0 ? 1 : 0;
    }
    return line.dx > 0 ? 1 : 0;
  }
  final fixed_t dx = toInt32(x - line.v1.x);
  final fixed_t dy = toInt32(y - line.v1.y);
  final fixed_t left = fixedMul(line.dy >> kFracBits, dx);
  final fixed_t right = fixedMul(dy, line.dx >> kFracBits);
  return right < left ? 0 : 1;
}

/// P_PointOnDivlineSide for a partition (x,y,dx,dy). Used by node traversal.
int pointOnDivlineSide(
    fixed_t x, fixed_t y, fixed_t lx, fixed_t ly, fixed_t ldx, fixed_t ldy) {
  if (ldx == 0) {
    if (x <= lx) {
      return ldy > 0 ? 1 : 0;
    }
    return ldy < 0 ? 1 : 0;
  }
  if (ldy == 0) {
    if (y <= ly) {
      return ldx < 0 ? 1 : 0;
    }
    return ldx > 0 ? 1 : 0;
  }
  final fixed_t dx = toInt32(x - lx);
  final fixed_t dy = toInt32(y - ly);
  if ((ldy ^ ldx ^ dx ^ dy) & 0x80000000 != 0) {
    if ((ldy ^ dx) & 0x80000000 != 0) {
      return 1;
    }
    return 0;
  }
  final fixed_t left = fixedMul(ldy >> 8, dx >> 8);
  final fixed_t right = fixedMul(dy >> 8, ldx >> 8);
  return right < left ? 0 : 1;
}

/// P_BoxOnLineSide: -1 if box is wholly on one side, 0 if it straddles, 1 on
/// the other. [box] is [top, bottom, left, right] in fixed_t.
int boxOnLineSide(List<fixed_t> box, Line line) {
  int p1;
  int p2;
  switch (line.slopeType) {
    case SlopeType.horizontal:
      p1 = box[Box.top] > line.v1.y ? 1 : 0;
      p2 = box[Box.bottom] > line.v1.y ? 1 : 0;
      if (line.dx < 0) {
        p1 ^= 1;
        p2 ^= 1;
      }
      break;
    case SlopeType.vertical:
      p1 = box[Box.right] < line.v1.x ? 1 : 0;
      p2 = box[Box.left] < line.v1.x ? 1 : 0;
      if (line.dy < 0) {
        p1 ^= 1;
        p2 ^= 1;
      }
      break;
    case SlopeType.positive:
      p1 = pointOnLineSide(box[Box.left], box[Box.top], line);
      p2 = pointOnLineSide(box[Box.right], box[Box.bottom], line);
      break;
    case SlopeType.negative:
      p1 = pointOnLineSide(box[Box.right], box[Box.top], line);
      p2 = pointOnLineSide(box[Box.left], box[Box.bottom], line);
      break;
  }
  if (p1 == p2) return p1;
  return -1;
}

/// Result of P_LineOpening: the vertical gap a (two-sided) line exposes.
class LineOpening {
  fixed_t openTop = 0;
  fixed_t openBottom = 0;
  fixed_t openRange = 0;
  fixed_t lowFloor = 0;
}

/// Shared scratch opening (vanilla uses globals opentop/openbottom/...).
final LineOpening opening = LineOpening();

/// P_LineOpening: compute [opening] for [line]. One-sided lines have a zero
/// range (solid). Faithful to vanilla.
void lineOpening(Line line) {
  if (line.backSide == null) {
    opening.openRange = 0;
    return;
  }
  final Sector front = line.frontSector;
  final Sector back = line.backSector!;

  if (front.ceilingHeight < back.ceilingHeight) {
    opening.openTop = front.ceilingHeight;
  } else {
    opening.openTop = back.ceilingHeight;
  }
  if (front.floorHeight > back.floorHeight) {
    opening.openBottom = front.floorHeight;
    opening.lowFloor = back.floorHeight;
  } else {
    opening.openBottom = back.floorHeight;
    opening.lowFloor = front.floorHeight;
  }
  opening.openRange = toInt32(opening.openTop - opening.openBottom);
}

/// MAPBLOCKUNITS / blockmap helpers. Blocks are 128 map units; origin is in
/// whole units (multiply by FRACUNIT for fixed_t comparisons).
const int kMapBlockUnits = 128;
const int kMapBlockShift = kFracBits + 7; // FRACBITS + 7
const int kMapBToFrac = kMapBlockShift - kFracBits; // 7

/// Convert a fixed_t X to a blockmap column index for [blockmap].
int blockX(Blockmap blockmap, fixed_t x) =>
    (toInt32(x - (blockmap.originX << kFracBits)) >> kMapBlockShift);

/// Convert a fixed_t Y to a blockmap row index.
int blockY(Blockmap blockmap, fixed_t y) =>
    (toInt32(y - (blockmap.originY << kFracBits)) >> kMapBlockShift);

/// P_AproxDistance: cheap distance approximation. Vanilla.
fixed_t approxDistance(fixed_t dx, fixed_t dy) {
  dx = dx.abs();
  dy = dy.abs();
  if (dx < dy) {
    return toInt32(dx + dy - (dx >> 1));
  }
  return toInt32(dx + dy - (dy >> 1));
}
