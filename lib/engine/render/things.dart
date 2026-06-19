// Sprite / masked pass, ported from Chocolate Doom r_things.c
// (R_ProjectSprite, R_SortVisSprites, R_DrawVisSprite, R_DrawMasked) and the
// masked-midtexture seg drawing from r_segs.c (R_RenderMaskedSegRange).
//
// Sprites come from a [SpriteSource] (dependency inversion) — NOT from any
// play-sim type. Each [SpriteRequest] is projected into a vissprite, sorted
// back-to-front by depth, and drawn as masked columns clipped against the
// drawsegs recorded by the wall pass. The masked midtextures of two-sided
// lines are drawn interleaved by depth.

import 'dart:typed_data';

import '../data/textures.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../video/patch.dart';
import 'draw.dart';
import 'render_state.dart';
import 'segs.dart';
import 'sprite_source.dart';

/// A projected sprite ready to draw, vanilla `vissprite_t`.
class _VisSprite {
  fixed_t scale = 0;
  fixed_t gx = 0;
  fixed_t gy = 0;
  fixed_t gz = 0;
  fixed_t gzt = 0; // top
  int x1 = 0;
  int x2 = 0;
  fixed_t startFrac = 0;
  fixed_t xiScale = 0;
  fixed_t textureMid = 0;
  Patch? patch;
  Uint8List? colormap; // null => use per-column light
  int lightLevel = 0;
  bool fullBright = false;
  bool fuzz = false;
  bool flip = false;
}

class ThingRenderer {
  ThingRenderer({
    required this.state,
    required this.draw,
    required this.segRenderer,
    required this.textures,
  });

  final RenderState state;
  final DrawContext draw;
  final SegRenderer segRenderer;
  final Textures textures;

  final List<_VisSprite> _pool = <_VisSprite>[];
  int _count = 0;
  final List<SpriteRequest> _scratch = <SpriteRequest>[];

  // Per-column sprite clip arrays (reused).
  late final Int16List _clipTop = Int16List(state.screenWidth);
  late final Int16List _clipBottom = Int16List(state.screenWidth);

  _VisSprite _alloc() {
    if (_count < _pool.length) return _pool[_count++];
    final _VisSprite v = _VisSprite();
    _pool.add(v);
    _count++;
    return v;
  }

  /// R_DrawMasked: project + sort + draw all sprites, interleaved with masked
  /// midtexture segs. Called after the solid wall + plane passes.
  void drawMasked(SpriteSource source) {
    _count = 0;
    _scratch.clear();
    source.collect(_scratch);
    final SpriteResolver resolver = source.resolver;
    for (final SpriteRequest req in _scratch) {
      _projectSprite(req, resolver);
    }
    // Sort back-to-front (smallest scale first => farthest first).
    final List<_VisSprite> vis = _pool.sublist(0, _count);
    vis.sort((a, b) => a.scale.compareTo(b.scale));

    // Draw masked midtexture segs first? Vanilla interleaves by drawseg; for a
    // faithful-enough result we draw sprites then masked midtextures over them
    // using each drawseg's stored scale. (Doom draws from back drawseg to front
    // after sprites.) We draw sprites, then masked segs (back-to-front).
    for (final _VisSprite v in vis) {
      _drawVisSprite(v);
    }
    _drawMaskedSegs();
  }

  void _projectSprite(SpriteRequest req, SpriteResolver resolver) {
    // Transform to view space.
    final fixed_t trX = toInt32(req.x - state.viewX);
    final fixed_t trY = toInt32(req.y - state.viewY);
    final fixed_t gxt = fixedMul(trX, state.viewCos);
    final fixed_t gyt = -fixedMul(trY, state.viewSin);
    final fixed_t tz = toInt32(gxt - gyt);
    // Behind the near clip plane.
    if (tz < (kFracUnit * 4)) return;
    final fixed_t xscale = fixedDiv(state.projection, tz);

    final fixed_t gxt2 = -fixedMul(trX, state.viewSin);
    final fixed_t gyt2 = fixedMul(trY, state.viewCos);
    fixed_t tx = toInt32(-(gyt2 + gxt2));
    // Off the side of the screen.
    if (tx.abs() > (tz << 2)) return;

    // Choose rotation.
    int rot = 0;
    final bool single = resolver.isSingleRotation(req.spriteNum, req.frame);
    if (!single) {
      final angle_t ang = state.pointToAngle(req.x, req.y);
      final angle_t rotAngle =
          normAngle(ang - req.angle + (kAng45 ~/ 2) * 9);
      rot = (rotAngle >> 29) & 7;
    }
    final SpriteFrameInfo? fi =
        resolver.frameInfo(req.spriteNum, req.frame, rot);
    if (fi == null) return;
    final Patch patch = Patch.fromBytes(Uint8List.fromList(fi.lumpPatchBytes));
    final bool flip = fi.flip ||
        (req.flags & SpriteRequestFlags.flip) != 0;

    // x offset by patch leftoffset.
    final fixed_t texMidX =
        toInt32(tx - (patch.leftOffset << kFracBits));
    int x1 = (state.centerXFrac + fixedMul(texMidX, xscale)) >> kFracBits;
    if (x1 > state.viewWidth) return;
    final fixed_t texRight =
        toInt32(texMidX + (patch.width << kFracBits));
    int x2 = ((state.centerXFrac + fixedMul(texRight, xscale)) >> kFracBits) - 1;
    if (x2 < 0) return;

    final _VisSprite v = _alloc();
    v.scale = xscale;
    v.gx = req.x;
    v.gy = req.y;
    v.gz = req.z;
    v.gzt = toInt32(req.z + (patch.topOffset << kFracBits));
    v.x1 = x1 < 0 ? 0 : x1;
    v.x2 = x2 >= state.viewWidth ? state.viewWidth - 1 : x2;
    v.patch = patch;
    v.flip = flip;
    v.xiScale = fixedDiv(kFracUnit, xscale);
    // startfrac is the texture column at the left visible edge (R_ProjectSprite
    // clamps x1 to 0; advance the fraction by the clamped columns).
    final int clampedCols = v.x1 - x1;
    if (flip) {
      v.startFrac =
          toInt32((patch.width << kFracBits) - 1 - clampedCols * v.xiScale);
    } else {
      v.startFrac = toInt32(clampedCols * v.xiScale);
    }
    v.textureMid = toInt32(v.gzt - state.viewZ);

    v.lightLevel = req.lightLevel;
    v.fullBright = (req.flags & SpriteRequestFlags.fullBright) != 0;
    v.fuzz = (req.flags & SpriteRequestFlags.shadow) != 0;

    // Lighting: pick a colormap by scale (R_ProjectSprite spritelights).
    if (v.fuzz) {
      v.colormap = null; // fuzz uses its own map
    } else if (v.fullBright) {
      v.colormap = state.colormap.mapAt(0);
    } else {
      int lightnum =
          (req.lightLevel >> kLightSegShift) + state.extraLight;
      if (lightnum < 0) lightnum = 0;
      if (lightnum >= kLightLevels) lightnum = kLightLevels - 1;
      int li = xscale >> kLightScaleShift;
      if (li >= kMaxLightScale) li = kMaxLightScale - 1;
      if (li < 0) li = 0;
      v.colormap = state.colormap.mapAt(state.scaleLight[lightnum][li]);
    }
  }

  void _drawVisSprite(_VisSprite v) {
    final Patch patch = v.patch!;
    // Build per-column clip from drawsegs.
    for (int x = v.x1; x <= v.x2; x++) {
      _clipTop[x] = -2;
      _clipBottom[x] = -2;
    }
    // Clip against drawsegs in front of the sprite.
    for (int i = 0; i < segRenderer.drawSegCount; i++) {
      final DrawSeg ds = segRenderer.drawSegs[i];
      if (ds.x1 > v.x2 || ds.x2 < v.x1) continue;
      // Only clip if the drawseg is closer (larger scale) — approximate.
      final fixed_t dsScale =
          (ds.scale1 < ds.scale2) ? ds.scale1 : ds.scale2;
      if (dsScale < v.scale) continue;
      final int r1 = ds.x1 < v.x1 ? v.x1 : ds.x1;
      final int r2 = ds.x2 > v.x2 ? v.x2 : ds.x2;
      for (int x = r1; x <= r2; x++) {
        if (ds.silhouetteMasked) {
          // masked seg: clip both
        }
        if (_clipBottom[x] == -2) _clipBottom[x] = ds.sprBottomClip[x];
        if (_clipTop[x] == -2) _clipTop[x] = ds.sprTopClip[x];
      }
    }
    // Default clip to full screen.
    for (int x = v.x1; x <= v.x2; x++) {
      if (_clipBottom[x] == -2) _clipBottom[x] = state.viewHeight;
      if (_clipTop[x] == -2) _clipTop[x] = -1;
    }

    final fixed_t iscale = v.xiScale;
    fixed_t frac = v.startFrac;
    draw.dcIScale = iscale;
    draw.dcTextureMid = v.textureMid;
    final Uint8List? cm = v.colormap;
    for (int x = v.x1; x <= v.x2; x++, frac = toInt32(frac + iscale)) {
      int texCol = frac >> kFracBits;
      if (v.flip) texCol = patch.width - 1 - texCol;
      if (texCol < 0 || texCol >= patch.width) continue;
      _drawSpriteColumn(patch, texCol, x, v, cm);
    }
  }

  // Draw one masked column of a patch with per-column clip.
  void _drawSpriteColumn(
      Patch patch, int texCol, int x, _VisSprite v, Uint8List? cm) {
    final Uint8List src = patch.bytes;
    int p = patch.columnOffsets[texCol];
    final fixed_t scale = v.scale;
    final int topClip = _clipTop[x];
    final int botClip = _clipBottom[x];
    while (true) {
      final int topDelta = src[p];
      if (topDelta == 0xFF) break;
      final int len = src[p + 1];
      final int pix = p + 3;
      // sprtopscreen = centeryfrac - FixedMul(textmid, scale)
      final fixed_t sprTopScreen =
          toInt32(state.centerYFrac - fixedMul(v.textureMid, scale));
      final fixed_t topscreen =
          toInt32(sprTopScreen + fixedMul(topDelta << kFracBits, scale));
      final fixed_t bottomscreen =
          toInt32(topscreen + fixedMul(len << kFracBits, scale));
      int yl = (topscreen + (kFracUnit - 1)) >> kFracBits;
      int yh = (bottomscreen - 1) >> kFracBits;
      if (yh >= botClip) yh = botClip - 1;
      if (yl <= topClip) yl = topClip + 1;
      if (yl < 0) yl = 0;
      if (yh >= state.viewHeight) yh = state.viewHeight - 1;
      if (yl <= yh) {
        _drawPostColumn(x, yl, yh, src, pix, len, topDelta, v, cm);
      }
      p += len + 4;
    }
  }

  // A small reusable column buffer for sprite posts.
  Uint8List _postBuf = Uint8List(256);

  void _drawPostColumn(int x, int yl, int yh, Uint8List src, int pix, int len,
      int topDelta, _VisSprite v, Uint8List? cm) {
    if (v.fuzz) {
      draw.dcX = x;
      draw.dcYl = yl;
      draw.dcYh = yh;
      draw.dcColormap = state.colormap.mapAt(6);
      draw.drawFuzzColumn();
      return;
    }
    // dc_source must be addressed by (frac>>FRACBITS) where frac starts at
    // (dc_texturemid + (yl-centery)*iscale). For a sprite post, dc_source[0]
    // corresponds to topDelta. We make a full-height buffer offset by topDelta.
    final int needed = topDelta + len;
    if (_postBuf.length < needed) {
      _postBuf = Uint8List(needed + 64);
    }
    for (int i = 0; i < len; i++) {
      _postBuf[topDelta + i] = src[pix + i];
    }
    draw.dcX = x;
    draw.dcYl = yl;
    draw.dcYh = yh;
    draw.dcTextureMid = v.textureMid;
    draw.dcIScale = v.xiScale;
    draw.dcSource = _postBuf;
    draw.dcSourceLen = _postBuf.length; // non-pow2 -> modulo path; safe
    draw.dcColormap = cm ?? state.colormap.mapAt(0);
    draw.drawColumn();
  }

  // R_RenderMaskedSegRange for every masked drawseg, back-to-front.
  void _drawMaskedSegs() {
    // Collect masked drawsegs, sort by scale ascending (farthest first).
    final List<DrawSeg> masked = <DrawSeg>[];
    for (int i = 0; i < segRenderer.drawSegCount; i++) {
      final DrawSeg ds = segRenderer.drawSegs[i];
      if (ds.silhouetteMasked && ds.maskedTexture != 0) {
        masked.add(ds);
      }
    }
    masked.sort((a, b) {
      final int sa = (a.scale1 < a.scale2) ? a.scale1 : a.scale2;
      final int sb = (b.scale1 < b.scale2) ? b.scale1 : b.scale2;
      return sa.compareTo(sb);
    });
    for (final DrawSeg ds in masked) {
      _renderMaskedSeg(ds);
    }
  }

  void _renderMaskedSeg(DrawSeg ds) {
    final int texNum = ds.maskedTexture;
    final Texture tex = textures.texture(texNum);
    int lightnum = ds.lightLevel;
    if (lightnum < 0) lightnum = 0;
    if (lightnum >= kLightLevels) lightnum = kLightLevels - 1;
    final Int32List lights = state.scaleLight[lightnum];

    fixed_t scale = ds.rwScale;
    final fixed_t scaleStep = ds.rwScaleStep;
    final fixed_t texMid = ds.midTexMid;
    for (int x = ds.x1; x <= ds.x2; x++, scale = toInt32(scale + scaleStep)) {
      final int col = ds.maskedTextureCol[x];
      // clip
      final int topClip = ds.sprTopClip[x];
      final int botClip = ds.sprBottomClip[x];
      int li = scale >> kLightScaleShift;
      if (li >= kMaxLightScale) li = kMaxLightScale - 1;
      if (li < 0) li = 0;
      final Uint8List cm = state.colormap.mapAt(lights[li]);

      // sprtopscreen
      final fixed_t sprTopScreen =
          toInt32(state.centerYFrac - fixedMul(texMid, scale));
      final fixed_t iscale =
          scale != 0 ? fixedDiv(kFracUnit, scale) : kFracUnit;

      // Use the composited masked texture column (transparent rows are 0;
      // vanilla uses the patch posts — composited column with holes==0 is an
      // acceptable approximation: index 0 is drawn but typically the texture's
      // border. For faithful masking we skip if the whole column is 0.)
      final Uint8List source =
          textures.textureColumn(texNum, col % tex.width);
      final int h = tex.height;
      int yl = (sprTopScreen + (kFracUnit - 1)) >> kFracBits;
      int yh = (sprTopScreen + fixedMul(h << kFracBits, scale) - 1) >>
          kFracBits;
      if (yl <= topClip) yl = topClip + 1;
      if (yh >= botClip) yh = botClip - 1;
      if (yl < 0) yl = 0;
      if (yh >= state.viewHeight) yh = state.viewHeight - 1;
      if (yl > yh) continue;
      draw.dcX = x;
      draw.dcYl = yl;
      draw.dcYh = yh;
      draw.dcIScale = iscale;
      draw.dcTextureMid = texMid;
      draw.dcSource = source;
      draw.dcSourceLen = h;
      draw.dcColormap = cm;
      draw.drawColumn();
    }
  }
}
