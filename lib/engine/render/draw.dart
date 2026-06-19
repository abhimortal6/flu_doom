// Low-level column / span drawers — faithful Dart port of Chocolate
// Doom (commit 353cf500) src/doom/r_draw.c (R_DrawColumn, R_DrawSpan,
// R_DrawFuzzColumn).
//
// These write palette indices directly into the [Framebuffer]'s pixel buffer,
// applying a colormap (light/distance shading). All drawers share a
// [DrawContext] holding the current dc_*/ds_* state — the Dart analogue of
// r_draw.c's file-scope globals.

import 'dart:typed_data';

import '../math/fixed.dart';
import '../video/framebuffer.dart';

/// Shared drawer parameters (vanilla dc_*/ds_* globals).
class DrawContext {
  DrawContext(this.fb)
      : pixels = fb.pixels,
        screenWidth = fb.width,
        screenHeight = fb.height;

  final Framebuffer fb;
  final Uint8List pixels;
  final int screenWidth;
  final int screenHeight;

  // --- Column drawer state (dc_*) ---
  int dcX = 0;
  int dcYl = 0;
  int dcYh = 0;
  fixed_t dcIScale = 0;
  fixed_t dcTextureMid = 0;
  Uint8List? dcSource;
  Uint8List? dcColormap;
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
  Uint8List? dsSource; // 64x64 flat (4096 bytes), row-major (y*64+x).

  /// R_DrawColumn. Faithful to r_draw.c:
  ///   count = dc_yh - dc_yl; if (count < 0) return;
  ///   dest = ...; fracstep = dc_iscale;
  ///   frac = dc_texturemid + (dc_yl-centery)*fracstep;
  ///   heightmask = (sourcelen)-1;  // dc_source is a column of `len` bytes
  ///   do { *dest = colormap[source[(frac>>FRACBITS)&heightmask]];
  ///        dest += SCREENWIDTH; frac += fracstep; } while (count--);
  ///
  /// Vanilla R_DrawColumn always uses heightmask = 127 (column height fixed by
  /// the texture system to a power of two). We support a general power-of-two
  /// height and fall back to a true modulo for non-pow2 sprite posts.
  void drawColumn() {
    final int yl = dcYl;
    final int yh = dcYh;
    int count = yh - yl;
    if (count < 0) return;
    final Uint8List source = dcSource!;
    final Uint8List colormap = dcColormap!;
    final Uint8List dst = pixels;
    final int sw = screenWidth;

    final int len = dcSourceLen;
    final bool pow2 = (len & (len - 1)) == 0 && len > 0;
    final int mask = len - 1;

    final fixed_t fracstep = dcIScale;
    fixed_t frac = dcTextureMid + (yl - centerY) * fracstep;
    int dest = yl * sw + dcX;

    if (pow2) {
      do {
        dst[dest] = colormap[source[(frac >> kFracBits) & mask]];
        dest += sw;
        frac = toInt32(frac + fracstep);
      } while (count-- != 0);
    } else {
      do {
        int s = (frac >> kFracBits) % len;
        if (s < 0) s += len;
        dst[dest] = colormap[source[s]];
        dest += sw;
        frac = toInt32(frac + fracstep);
      } while (count-- != 0);
    }
  }

  /// R_DrawSpan. Faithful to r_draw.c:
  ///   spot = ((yfrac>>(16-6))&(0x3f<<6)) + ((xfrac>>16)&0x3f);
  ///         == ((yfrac>>10)&0xFC0) + ((xfrac>>16)&0x3F)
  void drawSpan() {
    final int x1 = dsX1;
    final int x2 = dsX2;
    if (x2 < x1) return;
    final Uint8List source = dsSource!;
    final Uint8List colormap = dsColormap!;
    final Uint8List dst = pixels;
    fixed_t xfrac = dsXfrac;
    fixed_t yfrac = dsYfrac;
    final fixed_t xstep = dsXstep;
    final fixed_t ystep = dsYstep;
    int dest = dsY * screenWidth + x1;
    int count = x2 - x1;
    do {
      final int spot = ((yfrac >> 10) & 0xFC0) + ((xfrac >> 16) & 0x3F);
      dst[dest] = colormap[source[spot]];
      dest++;
      xfrac = toInt32(xfrac + xstep);
      yfrac = toInt32(yfrac + ystep);
    } while (count-- != 0);
  }

  /// R_DrawFuzzColumn: the spectre "fuzz" effect (r_draw.c). Darkens existing
  /// pixels through colormap[6] sampled with a vertical jitter pattern.
  void drawFuzzColumn() {
    int yl = dcYl;
    int yh = dcYh;
    // Adjust borders, exactly as vanilla.
    if (yl == 0) yl = 1;
    if (yh == screenHeight - 1) yh = screenHeight - 2;
    int count = yh - yl;
    if (count < 0) return;
    final Uint8List dst = pixels;
    final int sw = screenWidth;
    final Uint8List fuzzMap = dcColormap!; // caller sets colormaps + 6*256
    int dest = yl * sw + dcX;
    do {
      final int srcIdx = dest + _fuzzOffset[_fuzzPos] * sw;
      final int sample =
          (srcIdx >= 0 && srcIdx < dst.length) ? dst[srcIdx] : dst[dest];
      dst[dest] = fuzzMap[sample];
      _fuzzPos = (_fuzzPos + 1) % _fuzzOffset.length;
      dest += sw;
    } while (count-- != 0);
  }

  int _fuzzPos = 0;
  static const List<int> _fuzzOffset = <int>[
    1, -1, 1, -1, 1, 1, -1, 1, 1, -1, 1, 1, 1, -1, 1, 1, //
    1, -1, -1, -1, -1, 1, -1, -1, 1, 1, 1, 1, -1, 1, -1, 1, //
    1, -1, -1, 1, 1, -1, -1, -1, -1, 1, 1, 1, 1, -1, 1, 1, -1, 1
  ];

  // centery == screen vertical centre (set once by the owning Renderer).
  int centerY = kScreenHeight ~/ 2;
}
