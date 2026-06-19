// Wall/seg rendering, ported from Chocolate Doom r_segs.c
// (R_StoreWallRange + R_RenderSegLoop) and the drawseg bookkeeping needed for
// the masked midtexture pass.
//
// Given a seg clipped to a screen column range [x1, x2] with known wall angles,
// this projects the wall, computes per-column scale, and draws the solid
// one-sided wall (or the upper/lower steps of a two-sided wall), feeding the
// floor/ceiling visplanes the columns above/below the wall. Masked midtextures
// on two-sided lines are recorded as DrawSegs for the later masked pass.

import 'dart:typed_data';

import '../data/textures.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../math/tables.dart';
import '../../game/world/defs.dart';
import 'draw.dart';
import 'planes.dart';
import 'render_state.dart';

/// Recorded per-seg clip info, vanilla `drawseg_t`. Used by the masked pass to
/// clip sprites and to draw masked midtextures.
class DrawSeg {
  DrawSeg(int width)
      : sprTopClip = Int16List(width),
        sprBottomClip = Int16List(width),
        maskedTextureCol = Int32List(width);

  Seg? curLine;
  int x1 = 0;
  int x2 = 0;
  fixed_t scale1 = 0;
  fixed_t scale2 = 0;
  fixed_t scaleStep = 0;

  /// Whether this drawseg has masked midtexture columns to draw.
  bool silhouetteMasked = false;

  /// Texture number of the masked midtexture (0 = none).
  int maskedTexture = 0;

  /// Clip arrays for sprites: top/bottom silhouette per column.
  final Int16List sprTopClip;
  final Int16List sprBottomClip;

  /// Per-column texture column index for the masked midtexture (-1 = skip).
  final Int32List maskedTextureCol;

  // Lighting + scale info needed to redraw the midtexture in the masked pass.
  int lightLevel = 0;
  fixed_t rwScaleStep = 0;
  fixed_t rwScale = 0;
  fixed_t midTexMid = 0;
  fixed_t bottomFrontHeight = 0;
  fixed_t topFrontHeight = 0;
  fixed_t bottomBackHeight = 0;
  fixed_t topBackHeight = 0;
}

class SegRenderer {
  SegRenderer({
    required this.state,
    required this.draw,
    required this.planes,
    required this.textures,
    required this.skyFlatNum,
  });

  final RenderState state;
  final DrawContext draw;
  final PlaneRenderer planes;
  final Textures textures;
  final int skyFlatNum;

  // Recorded drawsegs this frame (for masked pass).
  final List<DrawSeg> drawSegs = <DrawSeg>[];
  int drawSegCount = 0;

  // Per-frame floor/ceiling plane the current subsector contributes to.
  VisPlane? floorPlane;
  VisPlane? ceilingPlane;

  void clear() {
    drawSegCount = 0;
  }

  DrawSeg _allocDrawSeg() {
    if (drawSegCount < drawSegs.length) {
      return drawSegs[drawSegCount++];
    }
    final DrawSeg ds = DrawSeg(state.screenWidth);
    drawSegs.add(ds);
    drawSegCount++;
    return ds;
  }

  /// R_StoreWallRange: project and draw the seg over screen columns [start..stop].
  /// [rwAngle1] is R_PointToAngle(curLine.v1). Faithful to r_segs.c.
  void storeWallRange(Seg seg, int start, int stop, angle_t rwAngle1) {
    if (start > stop) return;
    final DrawSeg ds = _allocDrawSeg();
    ds.curLine = seg;
    ds.x1 = start;
    ds.x2 = stop;

    final Side side = seg.sidedef;
    final Sector frontSector = seg.frontSector;
    final Sector? backSector = seg.backSector;
    final Line line = seg.linedef;

    // --- scale at the two ends (R_ScaleFromGlobalAngle) ---
    // distance to the seg.
    final angle_t segAngle = seg.angle;
    // offsetangle = abs(rw_normalangle - rw_angle1)
    final angle_t rwNormal = normAngle(segAngle + kAng90);
    int offsetAngle = toInt32(rwNormal - rwAngle1).abs();
    if (offsetAngle > kAng90) offsetAngle = kAng90;
    final angle_t distAngle = normAngle(kAng90 - offsetAngle);
    final fixed_t hyp = state.pointToDist(seg.v1.x, seg.v1.y);
    final fixed_t rwDistance =
        fixedMul(hyp, finesine[angleToFineIndex(distAngle)]);

    final fixed_t scale1 = _scaleFromGlobalAngle(
        normAngle(state.viewAngle + state.xToViewAngle[start]),
        rwNormal,
        rwDistance);
    ds.scale1 = scale1;
    fixed_t scaleStep = 0;
    if (stop > start) {
      final fixed_t scale2 = _scaleFromGlobalAngle(
          normAngle(state.viewAngle + state.xToViewAngle[stop]),
          rwNormal,
          rwDistance);
      ds.scale2 = scale2;
      scaleStep = (scale2 - scale1) ~/ (stop - start);
    } else {
      ds.scale2 = scale1;
    }
    ds.scaleStep = scaleStep;

    // --- vertical world bounds ---
    final fixed_t worldTop = toInt32(frontSector.ceilingHeight - state.viewZ);
    final fixed_t worldBottom = toInt32(frontSector.floorHeight - state.viewZ);

    bool markCeiling = false;
    bool markFloor = false;
    bool midTexture = false;
    bool topTexture = false;
    bool bottomTexture = false;
    int midTexNum = 0;
    int topTexNum = 0;
    int botTexNum = 0;

    fixed_t worldHigh = 0;
    fixed_t worldLow = 0;

    if (backSector == null) {
      // Solid one-sided wall.
      midTexNum = side.midTexture;
      midTexture = midTexNum != 0;
      markFloor = true;
      markCeiling = true;
    } else {
      worldHigh = toInt32(backSector.ceilingHeight - state.viewZ);
      worldLow = toInt32(backSector.floorHeight - state.viewZ);

      // Sky hack: both ceilings sky -> don't mark.
      markCeiling = !(frontSector.ceilingPic == skyFlatNum &&
              backSector.ceilingPic == skyFlatNum) &&
          (backSector.ceilingHeight != frontSector.ceilingHeight ||
              backSector.ceilingPic != frontSector.ceilingPic ||
              backSector.lightLevel != frontSector.lightLevel);
      markFloor = backSector.floorHeight != frontSector.floorHeight ||
          backSector.floorPic != frontSector.floorPic ||
          backSector.lightLevel != frontSector.lightLevel;

      // Closed door: treat as solid.
      if (backSector.ceilingHeight <= frontSector.floorHeight ||
          backSector.floorHeight >= frontSector.ceilingHeight) {
        markCeiling = markFloor = true;
      }

      if (worldHigh < worldTop) {
        topTexNum = side.topTexture;
        topTexture = topTexNum != 0;
      }
      if (worldLow > worldBottom) {
        botTexNum = side.bottomTexture;
        bottomTexture = botTexNum != 0;
      }
      // masked midtexture
      if (side.midTexture != 0) {
        ds.maskedTexture = side.midTexture;
        ds.silhouetteMasked = true;
      }
    }

    // --- texture vertical positioning (dc_texturemid) ---
    fixed_t midTexMid = 0;
    fixed_t topTexMid = 0;
    fixed_t botTexMid = 0;
    if (midTexture) {
      final int th = textures.texture(midTexNum).height << kFracBits;
      if ((line.flags & mlDontPegBottom) != 0) {
        final fixed_t vtop = frontSector.floorHeight + th;
        midTexMid = toInt32(vtop - state.viewZ);
      } else {
        midTexMid = worldTop;
      }
      midTexMid = toInt32(midTexMid + side.rowOffset);
    }
    if (topTexture) {
      if ((line.flags & mlDontPegTop) != 0) {
        topTexMid = worldTop;
      } else {
        final int th = textures.texture(topTexNum).height << kFracBits;
        final fixed_t vtop = backSector!.ceilingHeight + th;
        topTexMid = toInt32(vtop - state.viewZ);
      }
      topTexMid = toInt32(topTexMid + side.rowOffset);
    }
    if (bottomTexture) {
      if ((line.flags & mlDontPegBottom) != 0) {
        botTexMid = worldTop;
      } else {
        botTexMid = worldLow;
      }
      botTexMid = toInt32(botTexMid + side.rowOffset);
    }

    // --- texture u (horizontal) offset ---
    // rw_offset = FixedMul(hyp?, sin(offset)) + seg.offset + side.textureoffset
    angle_t offAng = toInt32(rwNormal - rwAngle1);
    fixed_t rwOffset = fixedMul(hyp, finesine[angleToFineIndex(offAng)]);
    // sign per vanilla
    if (toInt32(rwNormal - rwAngle1) < kAng180) {
      rwOffset = -rwOffset;
    }
    rwOffset = toInt32(rwOffset + seg.offset + side.textureOffset);
    final angle_t rwCenterAngle =
        normAngle(kAng90 + state.viewAngle - rwNormal);

    // --- light level ---
    int lightnum = (frontSector.lightLevel >> kLightSegShift) + state.extraLight;
    // Fake contrast: vertical/horizontal walls get +/-1 (vanilla).
    if (seg.v1.y == seg.v2.y) {
      lightnum--;
    } else if (seg.v1.x == seg.v2.x) {
      lightnum++;
    }
    if (lightnum < 0) lightnum = 0;
    if (lightnum >= kLightLevels) lightnum = kLightLevels - 1;
    final Int32List wallLights = state.scaleLight[lightnum];
    ds.lightLevel = lightnum;
    ds.rwScale = scale1;
    ds.rwScaleStep = scaleStep;
    ds.midTexMid = midTexMid;

    // --- the seg loop ---
    fixed_t topfrac = toInt32(state.centerYFrac - fixedMul(worldTop, scale1));
    final fixed_t topstep = -fixedMul(scaleStep, worldTop);
    fixed_t bottomfrac =
        toInt32(state.centerYFrac - fixedMul(worldBottom, scale1));
    final fixed_t bottomstep = -fixedMul(scaleStep, worldBottom);

    fixed_t pixhigh = 0;
    fixed_t pixhighstep = 0;
    fixed_t pixlow = 0;
    fixed_t pixlowstep = 0;
    if (backSector != null) {
      if (worldHigh < worldTop) {
        pixhigh = toInt32(state.centerYFrac - fixedMul(worldHigh, scale1));
        pixhighstep = -fixedMul(scaleStep, worldHigh);
      } else {
        pixhigh = topfrac; // not used when no top texture
      }
      if (worldLow > worldBottom) {
        pixlow = toInt32(state.centerYFrac - fixedMul(worldLow, scale1));
        pixlowstep = -fixedMul(scaleStep, worldLow);
      } else {
        pixlow = bottomfrac;
      }
    }

    // Hook up planes for this subsector.
    if (markCeiling) {
      ceilingPlane = ceilingPlane == null
          ? null
          : planes.checkPlane(ceilingPlane!, start, stop);
    }
    if (markFloor) {
      floorPlane = floorPlane == null
          ? null
          : planes.checkPlane(floorPlane!, start, stop);
    }

    final Int16List ceilingClip = state.ceilingClip;
    final Int16List floorClip = state.floorClip;
    final int viewH = state.viewHeight;

    fixed_t scale = scale1;
    for (int x = start; x <= stop; x++) {
      int yl = (topfrac + (kFracUnit - 1)) >> kFracBits;
      if (yl < ceilingClip[x] + 1) yl = ceilingClip[x] + 1;
      int yh = bottomfrac >> kFracBits;
      if (yh >= floorClip[x]) yh = floorClip[x] - 1;

      // Mark ceiling visplane (region between ceilingclip and wall top).
      if (markCeiling && ceilingPlane != null) {
        int top = ceilingClip[x] + 1;
        int bottom = yl - 1;
        if (bottom >= floorClip[x]) bottom = floorClip[x] - 1;
        if (top <= bottom) {
          ceilingPlane!.top[x] = top;
          ceilingPlane!.bottom[x] = bottom;
        }
      }
      // Mark floor visplane (region between wall bottom and floorclip).
      if (markFloor && floorPlane != null) {
        int top = yh + 1;
        if (top <= ceilingClip[x]) top = ceilingClip[x] + 1;
        int bottom = floorClip[x] - 1;
        if (top <= bottom) {
          floorPlane!.top[x] = top;
          floorPlane!.bottom[x] = bottom;
        }
      }

      // Texture column index for this screen column.
      angle_t a = normAngle(rwCenterAngle + state.xToViewAngle[x]);
      // texturecolumn = rw_offset - FixedMul(finetangent[a>>shift], rw_distance)
      final int tanIdx = (a >> kAngleToFineShift) & (kFineAngles ~/ 2 - 1);
      int texColumn =
          toInt32(rwOffset - fixedMul(finetangent[tanIdx], rwDistance));
      texColumn >>= kFracBits;

      // Light index from scale.
      int li = scale >> kLightScaleShift;
      if (li >= kMaxLightScale) li = kMaxLightScale - 1;
      if (li < 0) li = 0;
      final int cmIndex = wallLights[li];
      final Uint8List colormap = state.colormap.mapAt(cmIndex);

      final fixed_t invScale =
          scale != 0 ? fixedDiv(kFracUnit, scale) : kFracUnit;

      if (backSector == null) {
        // Solid wall: draw the whole mid texture column.
        if (midTexture && yl <= yh) {
          _drawWallColumn(x, yl, yh, midTexNum, texColumn, midTexMid,
              invScale, colormap);
        }
        // Wall occludes everything: close both clips.
        ceilingClip[x] = viewH;
        floorClip[x] = -1;
      } else {
        // Two-sided: upper and lower steps.
        // Upper texture
        if (worldHigh < worldTop) {
          int mid = (pixhigh + (kFracUnit - 1)) >> kFracBits;
          if (mid >= floorClip[x]) mid = floorClip[x] - 1;
          if (mid >= yl) {
            if (topTexture) {
              _drawWallColumn(x, yl, mid, topTexNum, texColumn, topTexMid,
                  invScale, colormap);
            }
            ceilingClip[x] = mid;
          } else {
            ceilingClip[x] = yl - 1;
          }
          pixhigh = toInt32(pixhigh + pixhighstep);
        } else {
          if (markCeiling) ceilingClip[x] = yl - 1;
        }
        // Lower texture
        if (worldLow > worldBottom) {
          int mid = (pixlow + (kFracUnit - 1)) >> kFracBits;
          if (mid <= ceilingClip[x]) mid = ceilingClip[x] + 1;
          if (mid <= yh) {
            if (bottomTexture) {
              _drawWallColumn(x, mid, yh, botTexNum, texColumn, botTexMid,
                  invScale, colormap);
            }
            floorClip[x] = mid;
          } else {
            floorClip[x] = yh + 1;
          }
          pixlow = toInt32(pixlow + pixlowstep);
        } else {
          if (markFloor) floorClip[x] = yh + 1;
        }

        // Record masked midtexture column for the masked pass.
        if (ds.silhouetteMasked) {
          ds.maskedTextureCol[x] = texColumn;
          ds.sprTopClip[x] = ceilingClip[x];
          ds.sprBottomClip[x] = floorClip[x];
        }
      }

      topfrac = toInt32(topfrac + topstep);
      bottomfrac = toInt32(bottomfrac + bottomstep);
      scale = toInt32(scale + scaleStep);
    }
  }

  // Draw a single textured wall column with masking-free (solid) sampling.
  void _drawWallColumn(int x, int yl, int yh, int texNum, int texColumn,
      fixed_t texMid, fixed_t invScale, Uint8List colormap) {
    if (yl < 0) yl = 0;
    if (yh >= state.viewHeight) yh = state.viewHeight - 1;
    if (yl > yh) return;
    final Texture tex = textures.texture(texNum);
    final int col = texColumn & 0x7fffffff; // textureColumn handles modulo
    final Uint8List source = textures.textureColumn(texNum, col % tex.width);
    draw.dcX = x;
    draw.dcYl = yl;
    draw.dcYh = yh;
    draw.dcIScale = invScale;
    draw.dcTextureMid = texMid;
    draw.dcSource = source;
    draw.dcSourceLen = tex.height;
    draw.dcColormap = colormap;
    draw.drawColumn();
  }

  // R_ScaleFromGlobalAngle, faithful to r_main.c.
  fixed_t _scaleFromGlobalAngle(
      angle_t visAngle, angle_t rwNormal, fixed_t rwDistance) {
    // anglea = ANG90 + (visangle - viewangle)
    final angle_t anglea = normAngle(kAng90 + toInt32(visAngle - state.viewAngle));
    final angle_t angleb = normAngle(kAng90 + toInt32(visAngle - rwNormal));
    final fixed_t sinea = finesine[angleToFineIndex(anglea)];
    final fixed_t sineb = finesine[angleToFineIndex(angleb)];
    // num = projection * sineb; den = rwdistance * sinea
    int num = fixedMul(state.projection, sineb);
    int den = fixedMul(rwDistance, sinea);
    fixed_t scale;
    if (den > num >> 16) {
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
}
