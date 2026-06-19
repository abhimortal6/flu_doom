// Wall/seg rendering — faithful Dart port of Chocolate Doom
// (commit 353cf500) src/doom/r_segs.c (R_StoreWallRange, R_RenderSegLoop,
// R_RenderMaskedSegRange) plus R_ScaleFromGlobalAngle from r_main.c.
//
// CRITICAL FAITHFULNESS POINTS (prior paraphrases broke these):
//   * HEIGHTBITS = 12 (NOT FRACBITS=16). worldtop/worldbottom/worldhigh/worldlow
//     are shifted right by 4 before the seg loop; topfrac/bottomfrac use
//     (centeryfrac>>4); yl = (topfrac+HEIGHTUNIT-1)>>HEIGHTBITS. This is what
//     keeps wall tops/bottoms stable as the camera turns/moves.
//   * finetangent/finesine are indexed with `angle>>ANGLETOFINESHIFT` WITHOUT
//     a fine mask (vanilla relies on the oversized tables). See render_state.
//   * openings[] / lastopening hold the saved sprite-clip silhouettes; the
//     drawseg's sprtopclip/sprbottomclip are slices into openings, exactly as
//     vanilla. We own openings[] here (r_plane.c declares it, r_segs.c fills it).

import 'dart:typed_data';

import '../data/textures.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../math/tables.dart';
import '../../game/world/defs.dart';
import 'draw.dart';
import 'planes.dart';
import 'render_state.dart';

const int kHeightBits = 12;
const int kHeightUnit = 1 << kHeightBits;

// Silhouette flags (r_defs.h).
const int kSilNone = 0;
const int kSilBottom = 1;
const int kSilTop = 2;
const int kSilBoth = 3;

const int kIntMax = 0x7fffffff;
const int kIntMin = -0x80000000;
const int kShrtMax = 0x7fff;

/// drawseg_t. sprtopclip/sprbottomclip are slices into the openings[] buffer
/// (or the constant negonearray/screenheightarray); maskedtexturecol likewise.
class DrawSeg {
  Seg? curLine;
  int x1 = 0;
  int x2 = 0;
  fixed_t scale1 = 0;
  fixed_t scale2 = 0;
  fixed_t scaleStep = 0;

  int silhouette = 0;
  fixed_t bsilHeight = 0;
  fixed_t tsilHeight = 0;

  // Pointers (array + base index) into openings[] or the constant clip arrays.
  // We model a C `short*` as (array, offset) so `arr[offset + x]` == `ptr[x]`.
  Int16List? sprTopClip;
  int sprTopClipBase = 0;
  Int16List? sprBottomClip;
  int sprBottomClipBase = 0;

  // maskedtexturecol: short* into openings, biased so [base + x] is column x.
  Int16List? maskedTextureCol;
  int maskedTextureColBase = 0;

  int topClip(int x) => sprTopClip![sprTopClipBase + x];
  int bottomClip(int x) => sprBottomClip![sprBottomClipBase + x];
}

class SegRenderer {
  SegRenderer({
    required this.state,
    required this.draw,
    required this.planes,
    required this.textures,
    required this.skyFlatNum,
  }) {
    // MAXOPENINGS = SCREENWIDTH*64.
    _openings = Int16List(state.screenWidth * 64);
  }

  final RenderState state;
  final DrawContext draw;
  final PlaneRenderer planes;
  final Textures textures;
  final int skyFlatNum;

  // drawsegs[MAXDRAWSEGS] + ds_p.
  final List<DrawSeg> drawSegs = <DrawSeg>[];
  int dsP = 0; // ds_p as an index (one past the last valid drawseg).

  // openings[MAXOPENINGS] + lastopening.
  late final Int16List _openings;
  int _lastOpening = 0;
  Int16List get openings => _openings;

  // Per-subsector floor/ceiling plane (R_Subsector sets these via BSP).
  VisPlane? floorPlane;
  VisPlane? ceilingPlane;

  // ---- file-scope r_segs.c state (rebuilt per R_StoreWallRange) ----
  late Seg _curLine;
  late Side _sideDef;
  late Line _lineDef;
  late Sector _frontSector;
  Sector? _backSector;

  bool _segTextured = false;
  bool _markFloor = false;
  bool _markCeiling = false;
  bool _maskedTexture = false;
  int _topTexture = 0;
  int _bottomTexture = 0;
  int _midTexture = 0;

  angle_t _rwNormalAngle = 0;
  angle_t rwAngle1 = 0; // set by BSP R_AddLine

  int _rwX = 0;
  int _rwStopX = 0;
  angle_t _rwCenterAngle = 0;
  fixed_t _rwOffset = 0;
  fixed_t _rwDistance = 0;
  fixed_t _rwScale = 0;
  fixed_t _rwScaleStep = 0;
  fixed_t _rwMidTextureMid = 0;
  fixed_t _rwTopTextureMid = 0;
  fixed_t _rwBottomTextureMid = 0;

  int _worldTop = 0;
  int _worldBottom = 0;
  int _worldHigh = 0;
  int _worldLow = 0;

  fixed_t _pixHigh = 0;
  fixed_t _pixLow = 0;
  fixed_t _pixHighStep = 0;
  fixed_t _pixLowStep = 0;

  fixed_t _topFrac = 0;
  fixed_t _topStep = 0;
  fixed_t _bottomFrac = 0;
  fixed_t _bottomStep = 0;

  late Int32List _wallLights;

  // masked midtexture column pointer for the current seg.
  int _maskedTextureColBase = 0;

  /// R_ClearDrawSegs.
  void clearDrawSegs() {
    dsP = 0;
  }

  /// lastopening = openings (called from R_ClearPlanes time in our pipeline).
  void clearOpenings() {
    _lastOpening = 0;
  }

  DrawSeg _curDrawSeg() {
    while (drawSegs.length <= dsP) {
      drawSegs.add(DrawSeg());
    }
    return drawSegs[dsP];
  }

  /// Set curline + front/back sectors for the current seg (R_AddLine does this
  /// in vanilla before calling the clip routines; BSP calls this).
  void setCurLine(Seg seg) {
    _curLine = seg;
    _frontSector = seg.frontSector;
    _backSector = seg.backSector;
  }

  /// R_ScaleFromGlobalAngle (r_main.c). detailshift == 0.
  fixed_t scaleFromGlobalAngle(angle_t visAngle) {
    final angle_t anglea = normAngle(kAng90 + toInt32(visAngle - state.viewAngle));
    final angle_t angleb = normAngle(kAng90 + toInt32(visAngle - _rwNormalAngle));
    final int sinea = finesine[fineShift(anglea)];
    final int sineb = finesine[fineShift(angleb)];
    final fixed_t num = fixedMul(state.projection, sineb);
    final int den = fixedMul(_rwDistance, sinea);

    fixed_t scale;
    if (den > num >> kFracBits) {
      scale = fixedDiv(num, den);
      if (scale > 64 * kFracUnit) {
        scale = 64 * kFracUnit;
      } else if (scale < 256) {
        scale = 256;
      }
    } else {
      scale = 64 * kFracUnit;
    }
    return scale;
  }

  /// R_RenderSegLoop.
  void _renderSegLoop() {
    for (; _rwX < _rwStopX; _rwX++) {
      // mark floor / ceiling areas
      int yl = (_topFrac + kHeightUnit - 1) >> kHeightBits;
      if (yl < state.ceilingClip[_rwX] + 1) {
        yl = state.ceilingClip[_rwX] + 1;
      }

      if (_markCeiling) {
        final int top = state.ceilingClip[_rwX] + 1;
        int bottom = yl - 1;
        if (bottom >= state.floorClip[_rwX]) {
          bottom = state.floorClip[_rwX] - 1;
        }
        if (top <= bottom) {
          ceilingPlane!.setTop(_rwX, top);
          ceilingPlane!.setBottom(_rwX, bottom);
        }
      }

      int yh = _bottomFrac >> kHeightBits;
      if (yh >= state.floorClip[_rwX]) {
        yh = state.floorClip[_rwX] - 1;
      }

      if (_markFloor) {
        int top = yh + 1;
        final int bottom = state.floorClip[_rwX] - 1;
        if (top <= state.ceilingClip[_rwX]) {
          top = state.ceilingClip[_rwX] + 1;
        }
        if (top <= bottom) {
          floorPlane!.setTop(_rwX, top);
          floorPlane!.setBottom(_rwX, bottom);
        }
      }

      // texturecolumn and lighting are independent of wall tiers
      int textureColumn = 0;
      if (_segTextured) {
        final int angle =
            fineShift(normAngle(_rwCenterAngle + state.xToViewAngle[_rwX]));
        textureColumn =
            toInt32(_rwOffset - fixedMul(finetangent[angle], _rwDistance));
        textureColumn >>= kFracBits;
        int index = _rwScale >> kLightScaleShift;
        if (index >= kMaxLightScale) index = kMaxLightScale - 1;
        draw.dcColormap = state.colormap.mapAt(_wallLights[index]);
        draw.dcX = _rwX;
        draw.dcIScale = _rwScale != 0 ? fixedDiv(kFracUnit, _rwScale) : 0;
      }

      // draw the wall tiers
      if (_midTexture != 0) {
        // single sided line
        draw.dcYl = yl;
        draw.dcYh = yh;
        draw.dcTextureMid = _rwMidTextureMid;
        _setColumnSource(_midTexture, textureColumn);
        draw.drawColumn();
        state.ceilingClip[_rwX] = state.viewHeight;
        state.floorClip[_rwX] = -1;
      } else {
        // two sided line
        if (_topTexture != 0) {
          final int mid0 = _pixHigh >> kHeightBits;
          _pixHigh = toInt32(_pixHigh + _pixHighStep);
          int mid = mid0;
          if (mid >= state.floorClip[_rwX]) {
            mid = state.floorClip[_rwX] - 1;
          }
          if (mid >= yl) {
            draw.dcYl = yl;
            draw.dcYh = mid;
            draw.dcTextureMid = _rwTopTextureMid;
            _setColumnSource(_topTexture, textureColumn);
            draw.drawColumn();
            state.ceilingClip[_rwX] = mid;
          } else {
            state.ceilingClip[_rwX] = yl - 1;
          }
        } else {
          if (_markCeiling) state.ceilingClip[_rwX] = yl - 1;
        }

        if (_bottomTexture != 0) {
          int mid = (_pixLow + kHeightUnit - 1) >> kHeightBits;
          _pixLow = toInt32(_pixLow + _pixLowStep);
          if (mid <= state.ceilingClip[_rwX]) {
            mid = state.ceilingClip[_rwX] + 1;
          }
          if (mid <= yh) {
            draw.dcYl = mid;
            draw.dcYh = yh;
            draw.dcTextureMid = _rwBottomTextureMid;
            _setColumnSource(_bottomTexture, textureColumn);
            draw.drawColumn();
            state.floorClip[_rwX] = mid;
          } else {
            state.floorClip[_rwX] = yh + 1;
          }
        } else {
          if (_markFloor) state.floorClip[_rwX] = yh + 1;
        }

        if (_maskedTexture) {
          _openings[_maskedTextureColBase + _rwX] = textureColumn;
        }
      }

      _rwScale = toInt32(_rwScale + _rwScaleStep);
      _topFrac = toInt32(_topFrac + _topStep);
      _bottomFrac = toInt32(_bottomFrac + _bottomStep);
    }
  }

  // R_GetColumn(tex, col) -> a height-tall column; col masked to texture width.
  void _setColumnSource(int texNum, int col) {
    final Texture tex = textures.texture(texNum);
    int c = col % tex.width;
    if (c < 0) c += tex.width;
    draw.dcSource = textures.textureColumn(texNum, c);
    draw.dcSourceLen = tex.height;
  }

  /// R_StoreWallRange.
  void storeWallRange(int start, int stop) {
    // don't overflow and crash (MAXDRAWSEGS guard is implicit: we grow).
    final DrawSeg dsp = _curDrawSeg();

    _sideDef = _curLine.sidedef;
    _lineDef = _curLine.linedef;

    // mark the segment as visible for auto map
    _lineDef.flags |= mlMapped;

    // calculate rw_distance for scale calculation
    _rwNormalAngle = normAngle(_curLine.angle + kAng90);
    int offsetAngle = toInt32(_rwNormalAngle - rwAngle1).abs();
    if (offsetAngle > kAng90) offsetAngle = kAng90;

    final angle_t distAngle = normAngle(kAng90 - offsetAngle);
    final fixed_t hyp = state.pointToDist(_curLine.v1.x, _curLine.v1.y);
    final int sineVal = finesine[fineShift(distAngle)];
    _rwDistance = fixedMul(hyp, sineVal);

    dsp.x1 = _rwX = start;
    dsp.x2 = stop;
    dsp.curLine = _curLine;
    _rwStopX = stop + 1;

    // calculate scale at both ends and step
    dsp.scale1 = _rwScale =
        scaleFromGlobalAngle(normAngle(state.viewAngle + state.xToViewAngle[start]));

    if (stop > start) {
      dsp.scale2 =
          scaleFromGlobalAngle(normAngle(state.viewAngle + state.xToViewAngle[stop]));
      dsp.scaleStep = _rwScaleStep = (dsp.scale2 - _rwScale) ~/ (stop - start);
    } else {
      dsp.scale2 = dsp.scale1;
      _rwScaleStep = 0;
    }

    // calculate texture boundaries and decide if floor/ceiling marks needed
    _worldTop = toInt32(_frontSector.ceilingHeight - state.viewZ);
    _worldBottom = toInt32(_frontSector.floorHeight - state.viewZ);

    _midTexture = _topTexture = _bottomTexture = 0;
    _maskedTexture = false;
    dsp.maskedTextureCol = null;

    final Sector? back = _backSector;
    if (back == null) {
      // single sided line
      _midTexture = _sideDef.midTexture;
      _markFloor = _markCeiling = true;
      if ((_lineDef.flags & mlDontPegBottom) != 0) {
        final fixed_t vtop = _frontSector.floorHeight +
            (textures.texture(_sideDef.midTexture).height << kFracBits);
        _rwMidTextureMid = toInt32(vtop - state.viewZ);
      } else {
        _rwMidTextureMid = _worldTop;
      }
      _rwMidTextureMid = toInt32(_rwMidTextureMid + _sideDef.rowOffset);

      dsp.silhouette = kSilBoth;
      dsp.sprTopClip = state.screenHeightArray;
      dsp.sprTopClipBase = 0;
      dsp.sprBottomClip = state.negOneArray;
      dsp.sprBottomClipBase = 0;
      dsp.bsilHeight = kIntMax;
      dsp.tsilHeight = kIntMin;
    } else {
      // two sided line
      dsp.sprTopClip = null;
      dsp.sprBottomClip = null;
      dsp.silhouette = 0;

      if (_frontSector.floorHeight > back.floorHeight) {
        dsp.silhouette = kSilBottom;
        dsp.bsilHeight = _frontSector.floorHeight;
      } else if (back.floorHeight > state.viewZ) {
        dsp.silhouette = kSilBottom;
        dsp.bsilHeight = kIntMax;
      }

      if (_frontSector.ceilingHeight < back.ceilingHeight) {
        dsp.silhouette |= kSilTop;
        dsp.tsilHeight = _frontSector.ceilingHeight;
      } else if (back.ceilingHeight < state.viewZ) {
        dsp.silhouette |= kSilTop;
        dsp.tsilHeight = kIntMin;
      }

      if (back.ceilingHeight <= _frontSector.floorHeight) {
        dsp.sprBottomClip = state.negOneArray;
        dsp.sprBottomClipBase = 0;
        dsp.bsilHeight = kIntMax;
        dsp.silhouette |= kSilBottom;
      }
      if (back.floorHeight >= _frontSector.ceilingHeight) {
        dsp.sprTopClip = state.screenHeightArray;
        dsp.sprTopClipBase = 0;
        dsp.tsilHeight = kIntMin;
        dsp.silhouette |= kSilTop;
      }

      _worldHigh = toInt32(back.ceilingHeight - state.viewZ);
      _worldLow = toInt32(back.floorHeight - state.viewZ);

      // hack to allow height changes in outdoor areas
      if (_frontSector.ceilingPic == skyFlatNum &&
          back.ceilingPic == skyFlatNum) {
        _worldTop = _worldHigh;
      }

      if (_worldLow != _worldBottom ||
          back.floorPic != _frontSector.floorPic ||
          back.lightLevel != _frontSector.lightLevel) {
        _markFloor = true;
      } else {
        _markFloor = false;
      }

      if (_worldHigh != _worldTop ||
          back.ceilingPic != _frontSector.ceilingPic ||
          back.lightLevel != _frontSector.lightLevel) {
        _markCeiling = true;
      } else {
        _markCeiling = false;
      }

      if (back.ceilingHeight <= _frontSector.floorHeight ||
          back.floorHeight >= _frontSector.ceilingHeight) {
        // closed door
        _markCeiling = _markFloor = true;
      }

      if (_worldHigh < _worldTop) {
        // top texture
        _topTexture = _sideDef.topTexture;
        if ((_lineDef.flags & mlDontPegTop) != 0) {
          _rwTopTextureMid = _worldTop;
        } else {
          final fixed_t vtop = back.ceilingHeight +
              (textures.texture(_sideDef.topTexture).height << kFracBits);
          _rwTopTextureMid = toInt32(vtop - state.viewZ);
        }
      }
      if (_worldLow > _worldBottom) {
        // bottom texture
        _bottomTexture = _sideDef.bottomTexture;
        if ((_lineDef.flags & mlDontPegBottom) != 0) {
          _rwBottomTextureMid = _worldTop;
        } else {
          _rwBottomTextureMid = _worldLow;
        }
      }
      _rwTopTextureMid = toInt32(_rwTopTextureMid + _sideDef.rowOffset);
      _rwBottomTextureMid = toInt32(_rwBottomTextureMid + _sideDef.rowOffset);

      // allocate space for masked texture tables
      if (_sideDef.midTexture != 0) {
        _maskedTexture = true;
        // ds_p->maskedtexturecol = lastopening - rw_x; lastopening += stopx-rwx
        _maskedTextureColBase = _lastOpening - _rwX;
        dsp.maskedTextureCol = _openings;
        dsp.maskedTextureColBase = _maskedTextureColBase;
        _lastOpening += _rwStopX - _rwX;
      }
    }

    // calculate rw_offset (only needed for textured lines)
    _segTextured =
        (_midTexture | _topTexture | _bottomTexture) != 0 || _maskedTexture;

    if (_segTextured) {
      // offsetangle = rw_normalangle - rw_angle1 (unsigned)
      angle_t offAngle = normAngle(_rwNormalAngle - rwAngle1);
      if (offAngle > kAng180) offAngle = normAngle(-offAngle);
      if (offAngle > kAng90) offAngle = kAng90;

      final int sineVal2 = finesine[fineShift(offAngle)];
      _rwOffset = fixedMul(hyp, sineVal2);

      if (normAngle(_rwNormalAngle - rwAngle1) < kAng180) {
        _rwOffset = -_rwOffset;
      }
      _rwOffset = toInt32(_rwOffset + _sideDef.textureOffset + _curLine.offset);
      _rwCenterAngle = normAngle(kAng90 + state.viewAngle - _rwNormalAngle);

      // light table
      int lightnum = (_frontSector.lightLevel >> kLightSegShift) + state.extraLight;
      if (_curLine.v1.y == _curLine.v2.y) {
        lightnum--;
      } else if (_curLine.v1.x == _curLine.v2.x) {
        lightnum++;
      }
      if (lightnum < 0) {
        _wallLights = state.scaleLight[0];
      } else if (lightnum >= kLightLevels) {
        _wallLights = state.scaleLight[kLightLevels - 1];
      } else {
        _wallLights = state.scaleLight[lightnum];
      }
    }

    // if a floor / ceiling plane is on the wrong side of the view plane, it is
    // definitely invisible and doesn't need to be marked.
    if (_frontSector.floorHeight >= state.viewZ) {
      _markFloor = false;
    }
    if (_frontSector.ceilingHeight <= state.viewZ &&
        _frontSector.ceilingPic != skyFlatNum) {
      _markCeiling = false;
    }

    // calculate incremental stepping values for texture edges
    _worldTop >>= 4;
    _worldBottom >>= 4;

    _topStep = -fixedMul(_rwScaleStep, _worldTop);
    _topFrac = toInt32((state.centerYFrac >> 4) - fixedMul(_worldTop, _rwScale));

    _bottomStep = -fixedMul(_rwScaleStep, _worldBottom);
    _bottomFrac =
        toInt32((state.centerYFrac >> 4) - fixedMul(_worldBottom, _rwScale));

    if (back != null) {
      _worldHigh >>= 4;
      _worldLow >>= 4;

      if (_worldHigh < _worldTop) {
        _pixHigh =
            toInt32((state.centerYFrac >> 4) - fixedMul(_worldHigh, _rwScale));
        _pixHighStep = -fixedMul(_rwScaleStep, _worldHigh);
      }
      if (_worldLow > _worldBottom) {
        _pixLow =
            toInt32((state.centerYFrac >> 4) - fixedMul(_worldLow, _rwScale));
        _pixLowStep = -fixedMul(_rwScaleStep, _worldLow);
      }
    }

    // render it
    if (_markCeiling) {
      ceilingPlane = planes.checkPlane(ceilingPlane!, _rwX, _rwStopX - 1);
    }
    if (_markFloor) {
      floorPlane = planes.checkPlane(floorPlane!, _rwX, _rwStopX - 1);
    }

    _renderSegLoop();

    // save sprite clipping info
    if (((dsp.silhouette & kSilTop) != 0 || _maskedTexture) &&
        dsp.sprTopClip == null) {
      // memcpy(lastopening, ceilingclip+start, (rw_stopx-start)*sizeof short)
      for (int i = 0; i < _rwStopX - start; i++) {
        _openings[_lastOpening + i] = state.ceilingClip[start + i];
      }
      dsp.sprTopClip = _openings;
      dsp.sprTopClipBase = _lastOpening - start;
      _lastOpening += _rwStopX - start;
    }
    if (((dsp.silhouette & kSilBottom) != 0 || _maskedTexture) &&
        dsp.sprBottomClip == null) {
      for (int i = 0; i < _rwStopX - start; i++) {
        _openings[_lastOpening + i] = state.floorClip[start + i];
      }
      dsp.sprBottomClip = _openings;
      dsp.sprBottomClipBase = _lastOpening - start;
      _lastOpening += _rwStopX - start;
    }

    if (_maskedTexture && (dsp.silhouette & kSilTop) == 0) {
      dsp.silhouette |= kSilTop;
      dsp.tsilHeight = kIntMin;
    }
    if (_maskedTexture && (dsp.silhouette & kSilBottom) == 0) {
      dsp.silhouette |= kSilBottom;
      dsp.bsilHeight = kIntMax;
    }

    dsP++;
  }
}
