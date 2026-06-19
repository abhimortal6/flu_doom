// Sprite / masked pass — faithful Dart port of Chocolate Doom
// (commit 353cf500) src/doom/r_things.c (R_ClearSprites, R_NewVisSprite,
// R_ProjectSprite, R_SortVisSprites, R_DrawVisSprite, R_DrawMaskedColumn,
// R_DrawSprite, R_DrawMasked) plus R_RenderMaskedSegRange from r_segs.c.
//
// Sprites arrive via a [SpriteSource]/[SpriteResolver] (dependency inversion);
// vanilla R_AddSprites walks sector thinglists during BSP. Here addSprites is a
// no-op hook kept for the BSP call site; the SpriteSource collects every
// drawable thing and we project them all at the start of R_DrawMasked (the
// vissprite list only needs to exist before drawing, and projection does not
// read the clip arrays — so the result is identical).

import 'dart:typed_data';

import '../data/textures.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../video/patch.dart';
import '../../game/world/defs.dart';
import 'draw.dart';
import 'psprite_source.dart';
import 'render_state.dart';
import 'segs.dart';
import 'sprite_source.dart';

const int kMinZ = kFracUnit * 4;

/// BASEYCENTER (r_things.c): SCREENHEIGHT/2 = 100. Psprite vertical anchor.
const int kBaseYCenter = 100;

/// vissprite_t.
class _VisSprite {
  fixed_t scale = 0;
  fixed_t gx = 0;
  fixed_t gy = 0;
  fixed_t gz = 0;
  fixed_t gzt = 0;
  int x1 = 0;
  int x2 = 0;
  fixed_t startFrac = 0;
  fixed_t xiScale = 0;
  fixed_t textureMid = 0;
  Patch? patch;
  Uint8List? colormap; // null => fuzz/shadow draw
  // Seg side test inputs reused from the request.
  fixed_t segV1x = 0, segV1y = 0, segV2x = 0, segV2y = 0;
}

class ThingRenderer {
  ThingRenderer({
    required this.state,
    required this.draw,
    required this.segRenderer,
    required this.textures,
  })  : _clipBot = Int16List(state.screenWidth),
        _clipTop = Int16List(state.screenWidth);

  final RenderState state;
  final DrawContext draw;
  final SegRenderer segRenderer;
  final Textures textures;

  final List<_VisSprite> _pool = <_VisSprite>[];
  int _visCount = 0;
  final List<SpriteRequest> _scratch = <SpriteRequest>[];
  late SpriteResolver _resolver;

  // R_DrawSprite scratch clip arrays (clipbot/cliptop).
  final Int16List _clipBot;
  final Int16List _clipTop;

  // R_DrawMaskedColumn / R_DrawVisSprite shared mfloorclip/mceilingclip.
  Int16List? _mFloorClip;
  int _mFloorClipBase = 0;
  Int16List? _mCeilingClip;
  int _mCeilingClipBase = 0;
  fixed_t _spryscale = 0;
  fixed_t _sprtopscreen = 0;

  // R_DrawPlayerSprites / R_DrawPSprite scratch (avis is a stack var in vanilla).
  final _VisSprite _psprVis = _VisSprite();
  final List<PspriteRequest> _psprScratch = <PspriteRequest>[];
  Int32List _psprLights = Int32List(kMaxLightScale);
  bool _psprInvisible = false;

  /// R_ClearSprites.
  void clearSprites() {
    _visCount = 0;
  }

  // R_AddSprites hook (BSP call site). Projection happens in drawMasked; this
  // is intentionally empty (see file header).
  void addSprites(Object sector) {}

  _VisSprite _newVisSprite() {
    while (_pool.length <= _visCount) {
      _pool.add(_VisSprite());
    }
    return _pool[_visCount++];
  }

  /// R_DrawMasked: project + sort + draw all sprites, then masked midtextures,
  /// then the player weapon psprites on top of everything (R_DrawPlayerSprites).
  void drawMasked(SpriteSource source,
      [PspriteSource psprites = const EmptyPspriteSource()]) {
    _resolver = source.resolver;
    _scratch.clear();
    source.collect(_scratch);
    for (final SpriteRequest req in _scratch) {
      _projectSprite(req);
    }

    // R_SortVisSprites: back to front (ascending scale = farthest first).
    final List<_VisSprite> sorted = _pool.sublist(0, _visCount);
    sorted.sort((a, b) => a.scale.compareTo(b.scale));

    for (final _VisSprite spr in sorted) {
      _drawSprite(spr);
    }

    // render any remaining masked mid textures, back drawseg to front.
    for (int i = segRenderer.dsP - 1; i >= 0; i--) {
      final DrawSeg ds = segRenderer.drawSegs[i];
      if (ds.maskedTextureCol != null) {
        _renderMaskedSegRange(ds, ds.x1, ds.x2);
      }
    }
    // draw the psprites on top of everything (vanilla R_DrawPlayerSprites;
    // viewangleoffset is always 0 here — no side views).
    _drawPlayerSprites(psprites);
  }

  // R_DrawPlayerSprites (r_things.c).
  void _drawPlayerSprites(PspriteSource source) {
    // get light level
    int lightnum =
        (source.sectorLightLevel >> kLightSegShift) + source.extraLight;
    if (lightnum < 0) {
      _psprLights = state.scaleLight[0];
    } else if (lightnum >= kLightLevels) {
      _psprLights = state.scaleLight[kLightLevels - 1];
    } else {
      _psprLights = state.scaleLight[lightnum];
    }

    // clip to screen bounds: mfloorclip = screenheightarray, mceilingclip =
    // negonearray (every column: floor at viewheight, ceiling at -1).
    _mFloorClip = state.screenHeightArray;
    _mFloorClipBase = 0;
    _mCeilingClip = state.negOneArray;
    _mCeilingClipBase = 0;

    _resolver = source.resolver;
    _psprInvisible = source.invisible;

    // add all active psprites
    _psprScratch.clear();
    source.collect(_psprScratch);
    for (final PspriteRequest psp in _psprScratch) {
      _drawPSprite(psp);
    }
  }

  // R_DrawPSprite (r_things.c).
  void _drawPSprite(PspriteRequest psp) {
    // decide which patch to use (psprites always use rotation 0 / lump[0]).
    final SpriteFrameInfo? fi = _resolver.frameInfo(psp.spriteNum, psp.frame, 0);
    if (fi == null) return;
    final Patch patch = Patch.fromBytes(Uint8List.fromList(fi.lumpPatchBytes));
    final bool flip = fi.flip;

    // calculate edges of the shape
    // tx = psp->sx - (SCREENWIDTH/2)*FRACUNIT;
    fixed_t tx = toInt32(psp.sx - (state.screenWidth ~/ 2) * kFracUnit);
    tx = toInt32(tx - (patch.leftOffset << kFracBits));
    int x1 = (state.centerXFrac + fixedMul(tx, state.pspriteScale)) >> kFracBits;
    // off the right side
    if (x1 > state.viewWidth) return;

    tx = toInt32(tx + (patch.width << kFracBits));
    int x2 =
        ((state.centerXFrac + fixedMul(tx, state.pspriteScale)) >> kFracBits) -
            1;
    // off the left side
    if (x2 < 0) return;

    // store information in a vissprite
    final _VisSprite vis = _psprVis;
    // vis->texturemid = (BASEYCENTER<<FRACBITS) + FRACUNIT/2
    //                   - (psp->sy - spritetopoffset[lump]);
    vis.textureMid = toInt32(kBaseYCenter * kFracUnit +
        kFracUnit ~/ 2 -
        toInt32(psp.sy - (patch.topOffset << kFracBits)));
    vis.x1 = x1 < 0 ? 0 : x1;
    vis.x2 = x2 >= state.viewWidth ? state.viewWidth - 1 : x2;
    vis.scale = state.pspriteScale; // <<detailshift (0)

    if (flip) {
      vis.xiScale = -state.pspriteIScale;
      vis.startFrac = (patch.width << kFracBits) - 1;
    } else {
      vis.xiScale = state.pspriteIScale;
      vis.startFrac = 0;
    }

    if (vis.x1 > x1) {
      vis.startFrac = toInt32(vis.startFrac + vis.xiScale * (vis.x1 - x1));
    }

    vis.patch = patch;

    if (_psprInvisible) {
      // shadow draw
      vis.colormap = null;
    } else if (state.fixedColormap != null) {
      // fixed color
      vis.colormap = state.fixedColormap;
    } else if (psp.fullBright) {
      // full bright
      vis.colormap = state.colormap.mapAt(0);
    } else {
      // local light
      vis.colormap = state.colormap.mapAt(_psprLights[kMaxLightScale - 1]);
    }

    _drawVisSprite(vis, vis.x1, vis.x2);
  }

  // R_ProjectSprite.
  void _projectSprite(SpriteRequest thing) {
    final fixed_t trX = toInt32(thing.x - state.viewX);
    final fixed_t trY = toInt32(thing.y - state.viewY);

    fixed_t gxt = fixedMul(trX, state.viewCos);
    fixed_t gyt = -fixedMul(trY, state.viewSin);
    final fixed_t tz = toInt32(gxt - gyt);

    if (tz < kMinZ) return;
    final fixed_t xscale = fixedDiv(state.projection, tz);

    gxt = -fixedMul(trX, state.viewSin);
    gyt = fixedMul(trY, state.viewCos);
    fixed_t tx = toInt32(-(gyt + gxt));

    if (tx.abs() > (tz << 2)) return; // too far off the side

    // decide which patch to use
    int rot = 0;
    final bool single = _resolver.isSingleRotation(thing.spriteNum, thing.frame);
    if (!single) {
      final angle_t ang = state.pointToAngle(thing.x, thing.y);
      rot = (normAngle(ang - thing.angle + (kAng45 ~/ 2) * 9) >> 29) & 7;
    }
    final SpriteFrameInfo? fi =
        _resolver.frameInfo(thing.spriteNum, thing.frame, rot);
    if (fi == null) return;
    final Patch patch = Patch.fromBytes(Uint8List.fromList(fi.lumpPatchBytes));
    final bool flip = fi.flip || (thing.flags & SpriteRequestFlags.flip) != 0;

    // calculate edges of the shape
    tx = toInt32(tx - (patch.leftOffset << kFracBits));
    int x1 = (state.centerXFrac + fixedMul(tx, xscale)) >> kFracBits;
    if (x1 > state.viewWidth) return;

    tx = toInt32(tx + (patch.width << kFracBits));
    int x2 = ((state.centerXFrac + fixedMul(tx, xscale)) >> kFracBits) - 1;
    if (x2 < 0) return;

    final _VisSprite vis = _newVisSprite();
    vis.scale = xscale;
    vis.gx = thing.x;
    vis.gy = thing.y;
    vis.gz = thing.z;
    vis.gzt = toInt32(thing.z + (patch.topOffset << kFracBits));
    vis.textureMid = toInt32(vis.gzt - state.viewZ);
    vis.x1 = x1 < 0 ? 0 : x1;
    vis.x2 = x2 >= state.viewWidth ? state.viewWidth - 1 : x2;
    final fixed_t iscale = fixedDiv(kFracUnit, xscale);

    if (flip) {
      vis.startFrac = (patch.width << kFracBits) - 1;
      vis.xiScale = -iscale;
    } else {
      vis.startFrac = 0;
      vis.xiScale = iscale;
    }
    if (vis.x1 > x1) {
      vis.startFrac = toInt32(vis.startFrac + vis.xiScale * (vis.x1 - x1));
    }
    vis.patch = patch;

    // light level
    if ((thing.flags & SpriteRequestFlags.shadow) != 0) {
      vis.colormap = null; // shadow draw
    } else if ((thing.flags & SpriteRequestFlags.fullBright) != 0) {
      vis.colormap = state.colormap.mapAt(0);
    } else {
      int lightnum =
          (thing.lightLevel >> kLightSegShift) + state.extraLight;
      Int32List spriteLights;
      if (lightnum < 0) {
        spriteLights = state.scaleLight[0];
      } else if (lightnum >= kLightLevels) {
        spriteLights = state.scaleLight[kLightLevels - 1];
      } else {
        spriteLights = state.scaleLight[lightnum];
      }
      int index = xscale >> kLightScaleShift;
      if (index >= kMaxLightScale) index = kMaxLightScale - 1;
      if (index < 0) index = 0;
      vis.colormap = state.colormap.mapAt(spriteLights[index]);
    }
  }

  // R_DrawMaskedColumn: draw a sprite/masked-midtex column from its posts,
  // clipped against mfloorclip/mceilingclip.
  void _drawMaskedColumn(Patch patch, int texCol) {
    final Uint8List src = patch.bytes;
    int p = patch.columnOffsets[texCol];
    final fixed_t baseTextureMid = draw.dcTextureMid;
    final int x = draw.dcX;
    final int floorClip = _mFloorClip![_mFloorClipBase + x];
    final int ceilingClip = _mCeilingClip![_mCeilingClipBase + x];

    while (true) {
      final int topDelta = src[p];
      if (topDelta == 0xff) break;
      final int len = src[p + 1];
      final int pixStart = p + 3;

      // topscreen = sprtopscreen + spryscale*topdelta;
      final fixed_t topscreen =
          toInt32(_sprtopscreen + _spryscale * topDelta);
      final fixed_t bottomscreen = toInt32(topscreen + _spryscale * len);

      int yl = (topscreen + kFracUnit - 1) >> kFracBits;
      int yh = (bottomscreen - 1) >> kFracBits;

      if (yh >= floorClip) yh = floorClip - 1;
      if (yl <= ceilingClip) yl = ceilingClip + 1;

      if (yl <= yh) {
        // dc_source = column+3; dc_texturemid = base - (topdelta<<FRACBITS).
        _postSource(src, pixStart, len, topDelta);
        draw.dcYl = yl;
        draw.dcYh = yh;
        draw.dcTextureMid = toInt32(baseTextureMid - (topDelta << kFracBits));
        draw.drawColumn();
      }
      p += len + 4;
    }
    draw.dcTextureMid = baseTextureMid;
  }

  // Build a contiguous source for one post so that source[(frac>>FRACBITS)] for
  // frac measured from dc_texturemid - (topdelta<<FRACBITS) reads pixel[i]. The
  // vanilla dc_source points at column+3 with dc_texturemid shifted so index 0
  // is the post's first pixel; we present exactly `len` bytes via the modulo
  // path of R_DrawColumn (sprites are not power-of-two tall, posts even less).
  Uint8List _postBuf = Uint8List(256);
  void _postSource(Uint8List src, int pixStart, int len, int topDelta) {
    if (_postBuf.length < len) _postBuf = Uint8List(len + 64);
    for (int i = 0; i < len; i++) {
      _postBuf[i] = src[pixStart + i];
    }
    draw.dcSource = _postBuf;
    draw.dcSourceLen = len;
  }

  // R_DrawVisSprite.
  void _drawVisSprite(_VisSprite vis, int x1, int x2) {
    final Patch patch = vis.patch!;
    draw.dcColormap = vis.colormap;
    final bool fuzz = vis.colormap == null;

    draw.dcIScale = vis.xiScale.abs();
    draw.dcTextureMid = vis.textureMid;
    fixed_t frac = vis.startFrac;
    _spryscale = vis.scale;
    _sprtopscreen = toInt32(state.centerYFrac - fixedMul(vis.textureMid, vis.scale));

    for (int dcX = vis.x1; dcX <= vis.x2; dcX++, frac = toInt32(frac + vis.xiScale)) {
      final int texturecolumn = frac >> kFracBits;
      if (texturecolumn < 0 || texturecolumn >= patch.width) continue;
      draw.dcX = dcX;
      if (fuzz) {
        _drawFuzzPost(patch, texturecolumn, dcX);
      } else {
        _drawMaskedColumn(patch, texturecolumn);
      }
    }
  }

  // Fuzz variant of a masked column (R_DrawFuzzColumn per post run).
  void _drawFuzzPost(Patch patch, int texCol, int x) {
    final Uint8List src = patch.bytes;
    int p = patch.columnOffsets[texCol];
    final int floorClip = _mFloorClip![_mFloorClipBase + x];
    final int ceilingClip = _mCeilingClip![_mCeilingClipBase + x];
    while (true) {
      final int topDelta = src[p];
      if (topDelta == 0xff) break;
      final int len = src[p + 1];
      final fixed_t topscreen = toInt32(_sprtopscreen + _spryscale * topDelta);
      final fixed_t bottomscreen = toInt32(topscreen + _spryscale * len);
      int yl = (topscreen + kFracUnit - 1) >> kFracBits;
      int yh = (bottomscreen - 1) >> kFracBits;
      if (yh >= floorClip) yh = floorClip - 1;
      if (yl <= ceilingClip) yl = ceilingClip + 1;
      if (yl <= yh) {
        draw.dcX = x;
        draw.dcYl = yl;
        draw.dcYh = yh;
        draw.dcColormap = state.colormap.mapAt(6);
        draw.drawFuzzColumn();
      }
      p += len + 4;
    }
  }

  // R_DrawSprite.
  void _drawSprite(_VisSprite spr) {
    for (int x = spr.x1; x <= spr.x2; x++) {
      _clipBot[x] = -2;
      _clipTop[x] = -2;
    }

    // Scan drawsegs from end to start for obscuring segs.
    for (int dsi = segRenderer.dsP - 1; dsi >= 0; dsi--) {
      final DrawSeg ds = segRenderer.drawSegs[dsi];

      if (ds.x1 > spr.x2 ||
          ds.x2 < spr.x1 ||
          (ds.silhouette == 0 && ds.maskedTextureCol == null)) {
        continue;
      }

      final int r1 = ds.x1 < spr.x1 ? spr.x1 : ds.x1;
      final int r2 = ds.x2 > spr.x2 ? spr.x2 : ds.x2;

      fixed_t scale;
      fixed_t lowscale;
      if (ds.scale1 > ds.scale2) {
        lowscale = ds.scale2;
        scale = ds.scale1;
      } else {
        lowscale = ds.scale1;
        scale = ds.scale2;
      }

      if (scale < spr.scale ||
          (lowscale < spr.scale &&
              _pointOnSegSide(spr.gx, spr.gy, ds.curLine!) == 0)) {
        if (ds.maskedTextureCol != null) {
          _renderMaskedSegRange(ds, r1, r2);
        }
        continue; // seg is behind sprite
      }

      int silhouette = ds.silhouette;
      if (spr.gz >= ds.bsilHeight) silhouette &= ~kSilBottom;
      if (spr.gzt <= ds.tsilHeight) silhouette &= ~kSilTop;

      if (silhouette == 1) {
        for (int x = r1; x <= r2; x++) {
          if (_clipBot[x] == -2) _clipBot[x] = ds.bottomClip(x);
        }
      } else if (silhouette == 2) {
        for (int x = r1; x <= r2; x++) {
          if (_clipTop[x] == -2) _clipTop[x] = ds.topClip(x);
        }
      } else if (silhouette == 3) {
        for (int x = r1; x <= r2; x++) {
          if (_clipBot[x] == -2) _clipBot[x] = ds.bottomClip(x);
          if (_clipTop[x] == -2) _clipTop[x] = ds.topClip(x);
        }
      }
    }

    // check for unclipped columns
    for (int x = spr.x1; x <= spr.x2; x++) {
      if (_clipBot[x] == -2) _clipBot[x] = state.viewHeight;
      if (_clipTop[x] == -2) _clipTop[x] = -1;
    }

    _mFloorClip = _clipBot;
    _mFloorClipBase = 0;
    _mCeilingClip = _clipTop;
    _mCeilingClipBase = 0;
    _drawVisSprite(spr, spr.x1, spr.x2);
  }

  // R_PointOnSegSide (r_main.c). Returns 0 (front) or 1 (back).
  int _pointOnSegSide(fixed_t x, fixed_t y, Seg seg) {
    final fixed_t lx = seg.v1.x;
    final fixed_t ly = seg.v1.y;
    final fixed_t ldx = toInt32(seg.v2.x - lx);
    final fixed_t ldy = toInt32(seg.v2.y - ly);

    if (ldx == 0) {
      if (x <= lx) return ldy > 0 ? 1 : 0;
      return ldy < 0 ? 1 : 0;
    }
    if (ldy == 0) {
      if (y <= ly) return ldx < 0 ? 1 : 0;
      return ldx > 0 ? 1 : 0;
    }
    final fixed_t dx = toInt32(x - lx);
    final fixed_t dy = toInt32(y - ly);
    if (((ldy ^ ldx ^ dx ^ dy) & 0x80000000) != 0) {
      if (((ldy ^ dx) & 0x80000000) != 0) return 1;
      return 0;
    }
    final int left = fixedMul(ldy >> kFracBits, dx);
    final int right = fixedMul(dy, ldx >> kFracBits);
    if (right < left) return 0;
    return 1;
  }

  // R_RenderMaskedSegRange (r_segs.c).
  void _renderMaskedSegRange(DrawSeg ds, int x1, int x2) {
    final Seg seg = ds.curLine!;
    final Sector frontSector = seg.frontSector;
    final Sector? backSector = seg.backSector;
    final int texnum = seg.sidedef.midTexture;
    if (texnum == 0) return;
    final Texture tex = textures.texture(texnum);

    int lightnum = (frontSector.lightLevel >> kLightSegShift) + state.extraLight;
    if (seg.v1.y == seg.v2.y) {
      lightnum--;
    } else if (seg.v1.x == seg.v2.x) {
      lightnum++;
    }
    Int32List walllights;
    if (lightnum < 0) {
      walllights = state.scaleLight[0];
    } else if (lightnum >= kLightLevels) {
      walllights = state.scaleLight[kLightLevels - 1];
    } else {
      walllights = state.scaleLight[lightnum];
    }

    _mFloorClip = ds.sprBottomClip;
    _mFloorClipBase = ds.sprBottomClipBase;
    _mCeilingClip = ds.sprTopClip;
    _mCeilingClipBase = ds.sprTopClipBase;

    final fixed_t rwScaleStep = ds.scaleStep;

    // find positioning
    fixed_t dcTextureMid;
    if ((seg.linedef.flags & mlDontPegBottom) != 0) {
      final int fh = frontSector.floorHeight;
      final int bh = backSector!.floorHeight;
      dcTextureMid = fh > bh ? fh : bh;
      dcTextureMid =
          toInt32(dcTextureMid + (tex.height << kFracBits) - state.viewZ);
    } else {
      final int fc = frontSector.ceilingHeight;
      final int bc = backSector!.ceilingHeight;
      dcTextureMid = fc < bc ? fc : bc;
      dcTextureMid = toInt32(dcTextureMid - state.viewZ);
    }
    dcTextureMid = toInt32(dcTextureMid + seg.sidedef.rowOffset);

    final Patch? mtPatch = _maskedPatch(texnum);

    fixed_t spry = toInt32(ds.scale1 + (x1 - ds.x1) * rwScaleStep);
    for (int dcX = x1; dcX <= x2; dcX++) {
      final int col = ds.maskedTextureCol![ds.maskedTextureColBase + dcX];
      if (col != kShrtMax) {
        int index = spry >> kLightScaleShift;
        if (index >= kMaxLightScale) index = kMaxLightScale - 1;
        if (index < 0) index = 0;
        draw.dcColormap = state.colormap.mapAt(walllights[index]);

        _sprtopscreen =
            toInt32(state.centerYFrac - fixedMul(dcTextureMid, spry));
        // dc_iscale = 0xffffffffu / (unsigned)spryscale
        draw.dcIScale = spry > 0 ? (0xffffffff ~/ spry) : 0;
        draw.dcX = dcX;
        draw.dcTextureMid = dcTextureMid;
        _spryscale = spry;
        if (mtPatch != null) {
          int c = col % tex.width;
          if (c < 0) c += tex.width;
          _drawMaskedColumn(mtPatch, c);
        }
        ds.maskedTextureCol![ds.maskedTextureColBase + dcX] = kShrtMax;
      }
      spry = toInt32(spry + rwScaleStep);
    }
  }

  // Masked midtextures rely on patch posts for transparency; decode the single
  // backing patch (common for grates/fences). Multi-patch masked textures fall
  // back to null (skipped) — vanilla composites them but our composite buffer
  // has no transparency channel, so skipping is the safe faithful-ish choice.
  final Map<int, Patch?> _maskedPatchCache = <int, Patch?>{};
  Patch? _maskedPatch(int texnum) {
    return _maskedPatchCache.putIfAbsent(texnum, () {
      final Uint8List? bytes = textures.singlePatchBytes(texnum);
      if (bytes == null) return null;
      return Patch.fromBytes(bytes);
    });
  }
}
