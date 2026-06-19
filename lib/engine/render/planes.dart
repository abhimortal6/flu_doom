// Visplanes (floors / ceilings) and sky — faithful Dart port of
// Chocolate Doom (commit 353cf500) src/doom/r_plane.c + src/doom/r_sky.c.
//
// R_ClearPlanes, R_FindPlane, R_CheckPlane, R_MapPlane, R_MakeSpans,
// R_DrawPlanes are transcribed faithfully, preserving the exact order of
// operations and the per-frame state (lastvisplane, lastopening, floorclip,
// ceilingclip, basexscale/baseyscale, cachedheight[]).
//
// visplane_t.top/bottom are `byte[SCREENWIDTH]` in vanilla with 0xff meaning
// "no value"; SCREENHEIGHT (200) fits in a byte, so we keep Uint8List and the
// 0xff sentinel exactly as the C code does (including the minx-1 / maxx+1
// sentinel writes R_DrawPlanes relies on).

import 'dart:typed_data';

import '../data/textures.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../math/tables.dart';
import 'draw.dart';
import 'render_state.dart';

/// MAXVISPLANES.
const int kMaxVisPlanes = 128;

/// visplane_t. top/bottom are byte arrays; 0xff = unset.
class VisPlane {
  VisPlane(int width)
      : top = Uint8List(width + 2),
        bottom = Uint8List(width + 2);

  fixed_t height = 0;
  int picNum = 0;
  int lightLevel = 0;
  int minX = 0;
  int maxX = -1;

  // top/bottom are indexed [x] but vanilla writes top[minx-1] and top[maxx+1]
  // as sentinels; we offset by 1 so index -1 .. width are valid. Access via
  // [topAt]/[setTop] which add the +1 bias.
  final Uint8List top;
  final Uint8List bottom;

  int topAt(int x) => top[x + 1];
  int bottomAt(int x) => bottom[x + 1];
  void setTop(int x, int v) => top[x + 1] = v;
  void setBottom(int x, int v) => bottom[x + 1] = v;

  void reset(fixed_t h, int pic, int light) {
    height = h;
    picNum = pic;
    lightLevel = light;
    minX = 0x7fffffff; // SCREENWIDTH placeholder, set by caller
    maxX = -1;
    // memset(top, 0xff, ...)
    for (int i = 0; i < top.length; i++) {
      top[i] = 0xff;
    }
  }
}

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
    // spanstart[SCREENHEIGHT]; sized to 256 so the sentinel (0xff) row index
    // that R_MakeSpans can transiently touch via an uninitialised sentinel
    // column never goes out of bounds (vanilla relies on undefined leftover
    // here; we make it safe without changing any observable span).
    _spanStart = Int32List(256);
    _cachedHeight = Int32List(state.viewHeight);
    _cachedDistance = Int32List(state.viewHeight);
    _cachedXStep = Int32List(state.viewHeight);
    _cachedYStep = Int32List(state.viewHeight);
    // R_ExecuteSetViewSize: yslope / distscale are view-size dependent and
    // computed once.
    for (int i = 0; i < state.viewHeight; i++) {
      int dy = ((i - state.viewHeight ~/ 2) << kFracBits) + kFracUnit ~/ 2;
      dy = dy.abs();
      _yslope[i] = fixedDiv((state.viewWidth ~/ 2) * kFracUnit, dy);
    }
    for (int i = 0; i < state.viewWidth; i++) {
      final int cosadj = finecosine[fineShift(state.xToViewAngle[i])].abs();
      _distScale[i] = fixedDiv(kFracUnit, cosadj);
    }
  }

  final RenderState state;
  final DrawContext draw;
  final Textures textures;
  final int skyTexture;
  final int skyFlatNum;

  // visplanes[MAXVISPLANES] + lastvisplane.
  final List<VisPlane> _planes = <VisPlane>[];
  int _lastVisPlane = 0; // index one past the last valid visplane

  // R_MapPlane tables.
  late final Int32List _yslope;
  late final Int32List _distScale;
  late final Int32List _spanStart;
  late final Int32List _cachedHeight;
  late final Int32List _cachedDistance;
  late final Int32List _cachedXStep;
  late final Int32List _cachedYStep;

  fixed_t _planeHeight = 0;
  late Int32List _planeZLight;

  fixed_t _baseXScale = 0;
  fixed_t _baseYScale = 0;

  // skytexturemid (r_sky.c): SKYFLATNUM hack; vanilla skytexturemid = 100<<FRACBITS.
  static const fixed_t _skyTextureMid = 100 << kFracBits;
  // ANGLETOSKYSHIFT.
  static const int _angleToSkyShift = 22;

  /// R_ClearPlanes: at beginning of frame.
  void clearPlanes() {
    // opening / clipping determination
    for (int i = 0; i < state.viewWidth; i++) {
      state.floorClip[i] = state.viewHeight;
      state.ceilingClip[i] = -1;
    }

    _lastVisPlane = 0;
    // lastopening = openings  -> handled by SegRenderer (it owns openings[]).

    // texture calculation: memset(cachedheight, 0, ...)
    for (int i = 0; i < _cachedHeight.length; i++) {
      _cachedHeight[i] = 0;
    }

    // left to right mapping
    final int angle = fineShift(normAngle(state.viewAngle - kAng90));
    _baseXScale = fixedDiv(finecosine[angle], state.centerXFrac);
    _baseYScale = -fixedDiv(finesine[angle], state.centerXFrac);
  }

  VisPlane _visPlaneAt(int i) {
    while (_planes.length <= i) {
      _planes.add(VisPlane(state.screenWidth));
    }
    return _planes[i];
  }

  /// R_FindPlane.
  VisPlane findPlane(fixed_t height, int picNum, int lightLevel) {
    if (picNum == skyFlatNum) {
      height = 0; // all skys map together
      lightLevel = 0;
    }

    int checkIdx = 0;
    for (; checkIdx < _lastVisPlane; checkIdx++) {
      final VisPlane c = _planes[checkIdx];
      if (height == c.height &&
          picNum == c.picNum &&
          lightLevel == c.lightLevel) {
        break;
      }
    }

    if (checkIdx < _lastVisPlane) {
      return _planes[checkIdx];
    }

    // new visplane
    final VisPlane check = _visPlaneAt(_lastVisPlane);
    _lastVisPlane++;
    check.height = height;
    check.picNum = picNum;
    check.lightLevel = lightLevel;
    check.minX = state.screenWidth;
    check.maxX = -1;
    for (int i = 0; i < check.top.length; i++) {
      check.top[i] = 0xff;
      check.bottom[i] = 0; // deterministic sentinel bottom (see clearPlanes note)
    }
    return check;
  }

  /// R_CheckPlane.
  VisPlane checkPlane(VisPlane pl, int start, int stop) {
    int intrl;
    int intrh;
    int unionl;
    int unionh;

    if (start < pl.minX) {
      intrl = pl.minX;
      unionl = start;
    } else {
      unionl = pl.minX;
      intrl = start;
    }

    if (stop > pl.maxX) {
      intrh = pl.maxX;
      unionh = stop;
    } else {
      unionh = pl.maxX;
      intrh = stop;
    }

    int x = intrl;
    for (; x <= intrh; x++) {
      if (pl.topAt(x) != 0xff) break;
    }

    if (x > intrh) {
      pl.minX = unionl;
      pl.maxX = unionh;
      return pl; // use the same one
    }

    // make a new visplane
    final VisPlane np = _visPlaneAt(_lastVisPlane);
    np.height = pl.height;
    np.picNum = pl.picNum;
    np.lightLevel = pl.lightLevel;
    _lastVisPlane++;
    np.minX = start;
    np.maxX = stop;
    for (int i = 0; i < np.top.length; i++) {
      np.top[i] = 0xff;
      np.bottom[i] = 0;
    }
    return np;
  }

  /// R_MapPlane.
  void mapPlane(int y, int x1, int x2) {
    fixed_t distance;
    if (_planeHeight != _cachedHeight[y]) {
      _cachedHeight[y] = _planeHeight;
      distance = _cachedDistance[y] = fixedMul(_planeHeight, _yslope[y]);
      draw.dsXstep = _cachedXStep[y] = fixedMul(distance, _baseXScale);
      draw.dsYstep = _cachedYStep[y] = fixedMul(distance, _baseYScale);
    } else {
      distance = _cachedDistance[y];
      draw.dsXstep = _cachedXStep[y];
      draw.dsYstep = _cachedYStep[y];
    }

    final fixed_t length = fixedMul(distance, _distScale[x1]);
    final int angle = fineShift(normAngle(state.viewAngle + state.xToViewAngle[x1]));
    draw.dsXfrac = toInt32(state.viewX + fixedMul(finecosine[angle], length));
    draw.dsYfrac = toInt32(-state.viewY - fixedMul(finesine[angle], length));

    int index = distance >> kLightZShift;
    if (index >= kMaxLightZ) index = kMaxLightZ - 1;
    draw.dsColormap = state.colormap.mapAt(_planeZLight[index]);

    draw.dsY = y;
    draw.dsX1 = x1;
    draw.dsX2 = x2;
    draw.drawSpan();
  }

  /// R_MakeSpans.
  void _makeSpans(int x, int t1, int b1, int t2, int b2) {
    while (t1 < t2 && t1 <= b1) {
      mapPlane(t1, _spanStart[t1], x - 1);
      t1++;
    }
    while (b1 > b2 && b1 >= t1) {
      mapPlane(b1, _spanStart[b1], x - 1);
      b1--;
    }
    while (t2 < t1 && t2 <= b2) {
      _spanStart[t2] = x;
      t2++;
    }
    while (b2 > b1 && b2 >= t2) {
      _spanStart[b2] = x;
      b2--;
    }
  }

  /// Called by R_DrawPlanes for the sky flat.
  void _drawSky(VisPlane pl) {
    // dc_iscale = pspriteiscale>>detailshift; detailshift==0.
    draw.dcIScale = state.pspriteIScale;
    draw.dcColormap = state.colormap.mapAt(0); // always full bright
    draw.dcTextureMid = _skyTextureMid;
    final Texture tex = textures.texture(skyTexture);
    final int texHeight = tex.height;
    final Uint8List composite = textures.textureColumns(skyTexture);
    for (int x = pl.minX; x <= pl.maxX; x++) {
      final int dcYl = pl.topAt(x);
      final int dcYh = pl.bottomAt(x);
      if (dcYl <= dcYh) {
        final int angle =
            fineShiftSky(normAngle(state.viewAngle + state.xToViewAngle[x]));
        final int col = angle % tex.width;
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

  /// (viewangle + xtoviewangle[x]) >> ANGLETOSKYSHIFT, vanilla R_GetColumn arg.
  int fineShiftSky(int angle) => (angle & 0xFFFFFFFF) >> _angleToSkyShift;

  /// R_DrawPlanes: at the end of each frame.
  void drawPlanes() {
    for (int p = 0; p < _lastVisPlane; p++) {
      final VisPlane pl = _planes[p];
      if (pl.minX > pl.maxX) continue;

      // sky flat
      if (pl.picNum == skyFlatNum) {
        _drawSky(pl);
        continue;
      }

      // regular flat
      draw.dsSource = textures.flatPixels(pl.picNum);

      _planeHeight = (pl.height - state.viewZ).abs();
      int light = (pl.lightLevel >> kLightSegShift) + state.extraLight;
      if (light >= kLightLevels) light = kLightLevels - 1;
      if (light < 0) light = 0;
      _planeZLight = state.zLight[light];

      pl.setTop(pl.maxX + 1, 0xff);
      pl.setTop(pl.minX - 1, 0xff);

      final int stop = pl.maxX + 1;
      for (int x = pl.minX; x <= stop; x++) {
        _makeSpans(
          x,
          pl.topAt(x - 1),
          pl.bottomAt(x - 1),
          pl.topAt(x),
          pl.bottomAt(x),
        );
      }
    }
  }
}
