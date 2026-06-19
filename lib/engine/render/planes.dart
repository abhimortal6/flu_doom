// Visplanes (floors / ceilings) and sky, ported from Chocolate Doom r_plane.c
// + r_sky.c.
//
// A visplane is a horizontal flat region (one floor or ceiling) with a per-
// column [top]/[bottom] span. R_FindPlane finds or creates a visplane matching
// a (height, picnum, lightlevel); segs add to the current floor/ceiling plane
// as they are drawn; R_DrawPlanes rasterizes every plane as horizontal spans
// (R_MapPlane) or, for the sky flat, as vertical textured columns.
//
// We depend on RenderState (projection, light tables, view) and DrawContext
// (the span/column drawers). The owning Renderer wires those in.

import 'dart:typed_data';

import '../data/textures.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../math/tables.dart';
import 'draw.dart';
import 'render_state.dart';

/// Sentinel for "no value yet" in a visplane's per-column top array.
const int kPlaneTopUnset = 0xFFFF; // (short)-1 style sentinel; we use 0xFFFF

/// A single visplane. Vanilla `visplane_t`.
class VisPlane {
  VisPlane(int width)
      : top = Uint16List(width),
        bottom = Uint16List(width);

  fixed_t height = 0;
  int picNum = 0;
  int lightLevel = 0;
  int minX = 0;
  int maxX = -1;

  /// Per-column top (inclusive) and bottom (inclusive) screen rows.
  /// top[x] == kPlaneTopUnset means the column is not part of this plane.
  final Uint16List top;
  final Uint16List bottom;

  void reset(fixed_t h, int pic, int light, int width) {
    height = h;
    picNum = pic;
    lightLevel = light;
    minX = width;
    maxX = -1;
    for (int i = 0; i < width; i++) {
      top[i] = kPlaneTopUnset;
    }
  }
}

/// The visplane manager + plane/sky rasterizer.
class PlaneRenderer {
  PlaneRenderer({
    required this.state,
    required this.draw,
    required this.textures,
    required this.skyTexture,
    required this.skyFlatNum,
  }) {
    _yslope = Int32List(state.viewHeight);
    _distScale = Int32List(state.screenWidth);
  }

  final RenderState state;
  final DrawContext draw;
  final Textures textures;

  /// Composite texture number used for the sky.
  final int skyTexture;

  /// Flat number that means "sky" (F_SKY1). Sectors with this floor/ceiling pic
  /// render the sky instead of a flat.
  final int skyFlatNum;

  final List<VisPlane> _planes = <VisPlane>[];
  int _planeCount = 0;

  // R_MapPlane precomputed tables.
  late final Int32List _yslope; // per-row distance slope
  late final Int32List _distScale; // per-column distance scale

  // Sky scaling.
  late final int _skyTextureMid = 100 << kFracBits; // SKYTEXTUREMID-ish

  /// R_ClearPlanes: called once per frame.
  void clearPlanes() {
    _planeCount = 0;
    // Precompute yslope and distscale (R_InitPlanes / R_SetupFrame portion).
    final int centerY = state.centerY;
    for (int i = 0; i < state.viewHeight; i++) {
      // dy = abs(((i - centery) << FRACBITS) + FRACUNIT/2)
      int dy = ((i - centerY) << kFracBits) + (kFracUnit ~/ 2);
      dy = dy.abs();
      _yslope[i] = fixedDiv((state.viewWidth >> 1) << kFracBits, dy);
    }
    for (int i = 0; i < state.viewWidth; i++) {
      final int cosadj = (cosineOf(state.xToViewAngle[i])).abs();
      _distScale[i] = fixedDiv(kFracUnit, cosadj == 0 ? 1 : cosadj);
    }
  }

  VisPlane _alloc() {
    if (_planeCount < _planes.length) {
      return _planes[_planeCount++];
    }
    final VisPlane p = VisPlane(state.screenWidth);
    _planes.add(p);
    _planeCount++;
    return p;
  }

  /// R_FindPlane: find an existing plane matching (height, pic, light) or make
  /// a new one. The sky flat always uses height 0 / light 0 in vanilla.
  VisPlane findPlane(fixed_t height, int picNum, int lightLevel) {
    if (picNum == skyFlatNum) {
      height = 0;
      lightLevel = 0;
    }
    for (int i = 0; i < _planeCount; i++) {
      final VisPlane p = _planes[i];
      if (p.height == height &&
          p.picNum == picNum &&
          p.lightLevel == lightLevel) {
        return p;
      }
    }
    final VisPlane p = _alloc();
    p.reset(height, picNum, lightLevel, state.screenWidth);
    return p;
  }

  /// R_CheckPlane: extend [pl] to cover [start..stop]; if it would overlap an
  /// already-filled column, split off a fresh copy. Returns the plane to use.
  VisPlane checkPlane(VisPlane pl, int start, int stop) {
    int intrl;
    int intrh;
    if (start < pl.minX) {
      intrl = pl.minX;
    } else {
      intrl = start;
    }
    if (stop > pl.maxX) {
      intrh = pl.maxX;
    } else {
      intrh = stop;
    }
    int x = intrl;
    for (; x <= intrh; x++) {
      if (pl.top[x] != kPlaneTopUnset) break;
    }
    if (x > intrh) {
      // No overlap: just extend.
      if (start < pl.minX) pl.minX = start;
      if (stop > pl.maxX) pl.maxX = stop;
      return pl;
    }
    // Overlap: make a new plane that shares attributes.
    final VisPlane np = _alloc();
    np.reset(pl.height, pl.picNum, pl.lightLevel, state.screenWidth);
    np.minX = start;
    np.maxX = stop;
    return np;
  }

  /// R_MapPlane: rasterize one horizontal span of a plane at screen row [y]
  /// from column [x1] to [x2].
  void mapPlane(VisPlane pl, int y, int x1, int x2) {
    if (x2 < x1) return;
    // planeheight = abs(height - viewz); distance = planeheight * yslope[y].
    final fixed_t planeHeight = (pl.height - state.viewZ).abs();
    final fixed_t dist = fixedMul(planeHeight, _yslope[y]);
    final fixed_t length = fixedMul(dist, _distScale[x1]);
    final angle_t ang =
        normAngle(state.viewAngle + state.xToViewAngle[x1]);
    final int fineIdx = angleToFineIndex(ang);
    // ds_xfrac = viewx + cos*length ; ds_yfrac = -viewy - sin*length
    draw.dsXfrac =
        toInt32(state.viewX + fixedMul(finecosine[fineIdx], length));
    draw.dsYfrac =
        toInt32(-state.viewY - fixedMul(finesine[fineIdx], length));
    draw.dsXstep = fixedMul(dist, _baseXScale);
    draw.dsYstep = fixedMul(dist, _baseYScale);

    // Light.
    int li = pl.lightLevel >> kLightSegShift;
    li += state.extraLight;
    if (li < 0) li = 0;
    if (li >= kLightLevels) li = kLightLevels - 1;
    int idx = dist >> kLightZShift;
    if (idx >= kMaxLightZ) idx = kMaxLightZ - 1;
    final int cmIndex = state.zLight[li][idx];

    draw.dsColormap = state.colormap.mapAt(cmIndex);
    draw.dsY = y;
    draw.dsX1 = x1;
    draw.dsX2 = x2;
    draw.dsSource = textures.flatPixels(pl.picNum);
    draw.drawSpan();
  }

  // Base step scales (R_SetupFrame): basexscale/baseyscale.
  late fixed_t _baseXScale = 0;
  late fixed_t _baseYScale = 0;

  /// Called from setupFrame to recompute the per-frame base scales.
  void setupFrame() {
    // basexscale = FixedDiv(viewsin, projection)? Vanilla:
    //   basexscale =  FixedDiv (finecosine[angle], centerxfrac) ... approximated
    // Faithful r_plane.c R_MapPlane uses ds_xstep = FixedMul(distance,basexscale)
    // where basexscale = FixedMul(viewsin?, ...). We use the standard derivation:
    final angle_t a = state.viewAngle;
    final int fi = angleToFineIndex(a);
    _baseXScale = fixedDiv(finesine[fi], state.centerXFrac);
    _baseYScale = -fixedDiv(finecosine[fi], state.centerXFrac);
  }

  /// R_DrawPlanes: rasterize every visplane built this frame.
  void drawPlanes() {
    for (int p = 0; p < _planeCount; p++) {
      final VisPlane pl = _planes[p];
      if (pl.minX > pl.maxX) continue;
      if (pl.picNum == skyFlatNum) {
        _drawSky(pl);
        continue;
      }
      // For each column pair, find vertical spans and emit horizontal runs.
      // We sentinel the columns just outside [minX..maxX] as "closed".
      final Uint16List top = pl.top;
      final Uint16List bottom = pl.bottom;
      // Iterate columns; for each, walk down comparing with previous column to
      // build spans. Faithful R_MakeSpans approach.
      final int stop = pl.maxX + 1;
      // spanstart per row.
      for (int x = pl.minX; x <= stop; x++) {
        final int t1 = (x <= pl.maxX && top[x] != kPlaneTopUnset)
            ? top[x]
            : 0xFFFF;
        final int b1 = (x <= pl.maxX && top[x] != kPlaneTopUnset)
            ? bottom[x]
            : 0;
        final int t2 = (x - 1 >= pl.minX && top[x - 1] != kPlaneTopUnset)
            ? top[x - 1]
            : 0xFFFF;
        final int b2 = (x - 1 >= pl.minX && top[x - 1] != kPlaneTopUnset)
            ? bottom[x - 1]
            : 0;
        _makeSpans(pl, x, t1, b1, t2, b2);
      }
    }
  }

  // R_MakeSpans bookkeeping.
  late final Int32List _spanStart = Int32List(state.viewHeight);

  void _makeSpans(VisPlane pl, int x, int t1, int b1, int t2, int b2) {
    // Close spans from the previous column (t2..b2) that end here.
    while (t2 < t1 && t2 <= b2) {
      mapPlane(pl, t2, _spanStart[t2], x - 1);
      t2++;
    }
    while (b2 > b1 && b2 >= t2) {
      mapPlane(pl, b2, _spanStart[b2], x - 1);
      b2--;
    }
    // Open new spans for this column (t1..b1) not covered by previous.
    while (t1 < t2 && t1 <= b1) {
      _spanStart[t1] = x;
      t1++;
    }
    while (b1 > b2 && b1 >= t1) {
      _spanStart[b1] = x;
      b1--;
    }
  }

  // ---- Sky (r_sky.c / R_DrawSky in r_bsp via R_DrawPlanes) ----
  void _drawSky(VisPlane pl) {
    // The sky is drawn as vertical textured columns; the texture wraps across
    // the screen by viewangle. dc_iscale fixed (no perspective on sky).
    final Texture tex = textures.texture(skyTexture);
    final int texHeight = tex.height;
    final fixed_t dcIScale = kFracUnit * 200 ~/ state.viewHeight; // ~ skyiscale
    draw.dcColormap = state.colormap.mapAt(0); // sky is full-bright
    draw.dcTextureMid = _skyTextureMid;
    draw.dcIScale = dcIScale;
    final Uint8List composite = textures.textureColumns(skyTexture);
    for (int x = pl.minX; x <= pl.maxX; x++) {
      if (pl.top[x] == kPlaneTopUnset) continue;
      final int dcYl = pl.top[x];
      final int dcYh = pl.bottom[x];
      if (dcYl > dcYh) continue;
      // ANGLETOSKYSHIFT = 22. angle = (viewangle + xtoviewangle[x]) >> 22
      final angle_t ang =
          normAngle(state.viewAngle + state.xToViewAngle[x]);
      final int col = (ang >> 22) & (tex.width - 1);
      draw.dcX = x;
      draw.dcYl = dcYl;
      draw.dcYh = dcYh;
      draw.dcSource = Uint8List.sublistView(
          composite, col * texHeight, (col + 1) * texHeight);
      draw.dcSourceLen = texHeight;
      draw.drawColumn();
    }
  }
}
