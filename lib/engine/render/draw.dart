// Low-level column / span drawers, ported from Chocolate Doom r_draw.c
// (R_DrawColumn, R_DrawSpan) plus the fuzz column (R_DrawFuzzColumn) used for
// spectre sprites.
//
// These write palette indices directly into the [Framebuffer]'s pixel buffer,
// applying a colormap (light/distance shading) and a source texture/flat. Inner
// loops use typed-data and allocate nothing per pixel.
//
// All drawers share a [DrawContext] holding the current source data, colormap,
// scale/step and screen extents — the Dart analogue of r_draw.c's file-scope
// `dc_*` / `ds_*` globals.

import 'dart:typed_data';

import '../math/fixed.dart';
import '../video/framebuffer.dart';

/// Shared drawer parameters (vanilla dc_*/ds_* globals).
class DrawContext {
  DrawContext(this.fb) : pixels = fb.pixels, screenWidth = fb.width, screenHeight = fb.height;

  final Framebuffer fb;
  final Uint8List pixels;
  final int screenWidth;
  final int screenHeight;

  // --- Column drawer state (dc_*) ---
  int dcX = 0;
  int dcYl = 0;
  int dcYh = 0;
  fixed_t dcIScale = 0; // 1/scale, the texture step per screen pixel
  fixed_t dcTextureMid = 0; // dc_texturemid
  Uint8List? dcSource; // column texture data (height bytes)
  Uint8List? dcColormap; // 256-byte light map
  int dcSourceLen = 0;

  // --- Span drawer state (ds_*) ---
  int dsY = 0;
  int dsX1 = 0;
  int dsX2 = 0;
  Uint8List? dsColormap;
  fixed_t dsXfrac = 0;
  fixed_t dsYfrac = 0;
  fixed_t dsXstep = 0;
  fixed_t dsYstep = 0;
  Uint8List? dsSource; // 64x64 flat (4096 bytes)

  /// R_DrawColumn: draw a vertical run of texels for one screen column,
  /// sampling [dcSource] (a texture column, `height` bytes, but indexed mod the
  /// texture height via masking) through [dcColormap].
  ///
  /// Faithful to r_draw.c: `frac = dc_texturemid + (dc_yl-centery)*dc_iscale`,
  /// then for each y, `dest = colormap[source[(frac>>FRACBITS)&heightmask]]`.
  void drawColumn() {
    final int yl = dcYl;
    final int yh = dcYh;
    if (yl > yh) return;
    final Uint8List source = dcSource!;
    final Uint8List colormap = dcColormap!;
    final Uint8List dst = pixels;
    final int sw = screenWidth;
    final int x = dcX;

    // heightmask: source length must be a power of two for the cheap mask;
    // textures in vanilla are power-of-two tall. Fall back to modulo otherwise.
    final int len = dcSourceLen;
    final bool pow2 = (len & (len - 1)) == 0 && len > 0;
    final int mask = len - 1;

    fixed_t frac = dcTextureMid + (yl - centerY) * dcIScale;
    final fixed_t step = dcIScale;
    int dest = yl * sw + x;
    if (pow2) {
      for (int y = yl; y <= yh; y++) {
        final int s = (frac >> kFracBits) & mask;
        dst[dest] = colormap[source[s]];
        dest += sw;
        frac += step;
      }
    } else {
      for (int y = yl; y <= yh; y++) {
        int s = (frac >> kFracBits) % len;
        if (s < 0) s += len;
        dst[dest] = colormap[source[s]];
        dest += sw;
        frac += step;
      }
    }
  }

  /// R_DrawSpan: draw a horizontal run of a 64x64 flat for one scanline,
  /// stepping (xfrac,yfrac) by (xstep,ystep) per pixel and shading through
  /// [dsColormap]. Faithful to r_draw.c (spot = ((yfrac>>10)&0xFC0)+((xfrac>>16)&0x3F)).
  void drawSpan() {
    final int x1 = dsX1;
    final int x2 = dsX2;
    if (x1 > x2) return;
    final Uint8List source = dsSource!;
    final Uint8List colormap = dsColormap!;
    final Uint8List dst = pixels;
    fixed_t xfrac = dsXfrac;
    fixed_t yfrac = dsYfrac;
    final fixed_t xstep = dsXstep;
    final fixed_t ystep = dsYstep;
    int dest = dsY * screenWidth + x1;
    for (int x = x1; x <= x2; x++) {
      final int spot = ((yfrac >> 10) & 0xFC0) + ((xfrac >> 16) & 0x3F);
      dst[dest] = colormap[source[spot]];
      dest++;
      xfrac = toInt32(xfrac + xstep);
      yfrac = toInt32(yfrac + ystep);
    }
  }

  /// R_DrawMaskedColumn helper for sprites/masked midtextures: like drawColumn
  /// but the source column is the post-decoded sprite column and transparent
  /// regions are handled by the caller (it only calls this for opaque runs).
  /// Here we reuse drawColumn with a non-masked, exact-length source by using
  /// the modulo path; sprites are not power-of-two tall.
  void drawMaskedColumn() => drawColumn();

  /// R_DrawFuzzColumn: the spectre "fuzz" effect. Instead of sampling the
  /// source, it darkens the existing pixels using a fixed colormap (map 6) and
  /// a vertical jitter pattern. Faithful to r_draw.c's fuzzoffset table.
  void drawFuzzColumn() {
    int yl = dcYl;
    int yh = dcYh;
    // Clamp away from screen edges (vanilla does the same).
    if (yl <= 0) yl = 1;
    if (yh >= screenHeight - 1) yh = screenHeight - 2;
    if (yl > yh) return;
    final Uint8List dst = pixels;
    final int sw = screenWidth;
    final int x = dcX;
    final Uint8List fuzzMap = dcColormap!; // caller sets to colormap map 6
    int dest = yl * sw + x;
    for (int y = yl; y <= yh; y++) {
      // Sample a neighbouring pixel offset vertically by the fuzz pattern.
      final int srcIdx = dest + _fuzzOffset[_fuzzPos] * sw;
      final int sample =
          (srcIdx >= 0 && srcIdx < dst.length) ? dst[srcIdx] : dst[dest];
      dst[dest] = fuzzMap[sample];
      _fuzzPos = (_fuzzPos + 1) % _fuzzOffset.length;
      dest += sw;
    }
  }

  int _fuzzPos = 0;
  static const List<int> _fuzzOffset = <int>[
    1, -1, 1, -1, 1, 1, -1, 1, 1, -1, 1, 1, 1, -1, 1, 1, //
    1, -1, -1, -1, -1, 1, -1, -1, 1, 1, 1, 1, -1, 1, -1, 1, //
    1, -1, -1, 1, 1, -1, -1, -1, -1, 1, 1, 1, 1, -1, 1, 1, -1, 1
  ];

  // centery == screen vertical centre. Mirrors RenderState.centerY; set once.
  int centerY = kScreenHeight ~/ 2;
}
