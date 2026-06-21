// Screen-melt wipe — a pure Dart port of Chocolate Doom src/doom/f_wipe.c
// (the MELT wipe: wipe_initMelt / wipe_doMelt / wipe_exitMelt, plus the
// wipe_StartScreen / wipe_EndScreen screen-capture and the wipe_ScreenWipe
// driver), operating on the project's 320x200 8-bit indexed framebuffer bytes.
//
// THE EFFECT: on a game-state transition the OLD screen "melts" downward in
// vertical strips, revealing the NEW screen underneath. Each column starts at a
// small random negative offset (not-yet-moving), then accelerates downward
// until the whole old column has slid off the bottom.
//
// FIDELITY NOTES (deviations from the C, all behaviour-preserving):
//   * C packs two 8-bit pixels into one `dpixel_t` (a 32-bit int) and halves
//     `width` so a "column" is a 2-pixel-wide strip. We keep raw bytes and a
//     `kScreenWidth/2` column count, copying TWO bytes per dpixel step. The
//     column/byte math (offsets, the column-major transform, the dy ramp) is
//     identical to vanilla.
//   * The C `wipe_shittyColMajorXform` reorders start/end into column-major to
//     make doMelt's inner copy sequential; we replicate it exactly so the byte
//     indexing in doMelt matches the C 1:1.
//   * `wipe_scr` (the live output) stays ROW-MAJOR exactly as vanilla
//     (I_VideoBuffer); only the start/end source buffers are column-major.
//   * The melt init uses M_Random (the cosmetic stream — [mRandom]), NOT the
//     gameplay pRandom, exactly as vanilla (m_random.c in f_wipe.c).
//   * Vanilla runs the melt in a blocking loop inside D_RunFrame (sleeping until
//     a tic elapses, then calling wipe_ScreenWipe(..., tics)); we instead drive
//     it across Ticker frames via [update] (one tic = ticks==1 per call), which
//     the present-path hook calls once per frame. The per-tic math is identical;
//     only the loop host differs (frames vs a blocking while-loop). See
//     CONTRACTS_WIPE.md.

import 'dart:typed_data';

import '../../game/play/p_random.dart';
import 'framebuffer.dart';

/// Doom's screen-melt wipe over the 320x200 indexed framebuffer.
///
/// Lifecycle (mirrors wipe_StartScreen -> wipe_EndScreen -> wipe_ScreenWipe):
///   1. capture the OLD screen   -> [WipeMelt.start] (wipe_StartScreen)
///   2. capture the NEW screen   -> pass `endBytes` to [WipeMelt.start]
///      (wipe_EndScreen)         then [init] runs (wipe_initMelt).
///   3. each tic: [update] (wipe_doMelt) advances the melt; [compose] writes the
///      current melted frame into a [Framebuffer]. When [update] returns true the
///      wipe is complete (wipe_exitMelt has effectively run).
class WipeMelt {
  WipeMelt._(this._wipeScr, this._scrStart, this._scrEnd, this._y, this._width);

  /// Screen width in pixels (SCREENWIDTH). 320 in 4:3, wider in widescreen.
  /// Always even (so the dpixel half-width is an integer). [_height] is the
  /// fixed SCREENHEIGHT (200).
  final int _width;
  static const int _height = kScreenHeight;

  /// The live output buffer (row-major, == I_VideoBuffer / `wipe_scr`).
  final Uint8List _wipeScr;

  /// The OLD screen, stored COLUMN-MAJOR after the init transform
  /// (`wipe_scr_start` post wipe_shittyColMajorXform).
  final Uint8List _scrStart;

  /// The NEW screen, stored COLUMN-MAJOR after the init transform
  /// (`wipe_scr_end` post wipe_shittyColMajorXform).
  final Uint8List _scrEnd;

  /// Per-column vertical offset (`y[]`). Length == SCREENWIDTH/2 (one entry per
  /// 2-pixel-wide dpixel column). Negative => not yet started scrolling.
  final Int32List _y;

  /// True once the melt has fully completed (last [update] returned done).
  bool _done = false;

  /// Whether the melt has finished (every column has slid off the bottom).
  bool get isComplete => _done;

  /// Read-only view of the per-column start offsets, for tests/inspection.
  Int32List get columnOffsets => Int32List.fromList(_y);

  // -------------------------------------------------------------------------
  // Construction: wipe_StartScreen + wipe_EndScreen + wipe_initMelt.
  // -------------------------------------------------------------------------

  /// Begin a melt from [startBytes] (the OLD, already-presented screen) to
  /// [endBytes] (the NEW screen). Both are 320x200 indexed buffers
  /// (length == 320*200), copied defensively. This performs wipe_initMelt:
  /// the start screen is copied into the live buffer, start/end are transformed
  /// to column-major, and the per-column offsets are seeded from [mRandom].
  factory WipeMelt.start(Uint8List startBytes, Uint8List endBytes) {
    // SCREENHEIGHT is fixed (200); SCREENWIDTH is derived from the byte length so
    // the melt works on a widescreen framebuffer too. Must be even.
    final int width = startBytes.length ~/ kScreenHeight;
    assert(startBytes.length == width * kScreenHeight, 'screen height must be 200');
    assert(endBytes.length == startBytes.length,
        'start and end screens must be the same size');
    assert(width.isEven, 'screen width must be even (dpixel packing)');
    final int size = width * kScreenHeight;

    final Uint8List wipeScr = Uint8List(size);
    final Uint8List scrStart = Uint8List.fromList(startBytes);
    final Uint8List scrEnd = Uint8List.fromList(endBytes);

    // wipe_initMelt: copy start screen to main (live) screen.
    //   memcpy(wipe_scr, wipe_scr_start, ...)
    wipeScr.setAll(0, scrStart);

    // Column-major transform of start and end (width/2 because dpixel_t packs 2
    // pixels). In bytes, the "element" is 2 wide, so the transform width is
    // width/2 and the element size is 2 bytes.
    _shittyColMajorXform(scrStart, width ~/ 2, kScreenHeight);
    _shittyColMajorXform(scrEnd, width ~/ 2, kScreenHeight);

    // setup initial column positions (y<0 => not ready to scroll yet).
    //   y = Z_Malloc(width * sizeof(int))   — width == SCREENWIDTH (not halved).
    final Int32List y = Int32List(width);
    y[0] = -(mRandom() % 16);
    for (int i = 1; i < width; i++) {
      final int r = (mRandom() % 3) - 1;
      y[i] = y[i - 1] + r;
      if (y[i] > 0) {
        y[i] = 0;
      } else if (y[i] == -16) {
        y[i] = -15;
      }
    }

    return WipeMelt._(wipeScr, scrStart, scrEnd, y, width);
  }

  /// wipe_shittyColMajorXform: transpose [array] (treated as a `width` x `height`
  /// grid of 2-byte elements) into column-major order in place. 1:1 with the C,
  /// with the 2-pixel `dpixel_t` element expressed as a 2-byte stride.
  ///
  ///   dest[x*height + y] = array[y*width + x]   (per 2-byte element)
  static void _shittyColMajorXform(Uint8List array, int width, int height) {
    final Uint8List dest = Uint8List(width * height * 2);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcOff = (y * width + x) * 2;
        final int dstOff = (x * height + y) * 2;
        dest[dstOff] = array[srcOff];
        dest[dstOff + 1] = array[srcOff + 1];
      }
    }
    array.setAll(0, dest);
  }

  // -------------------------------------------------------------------------
  // wipe_doMelt: advance the melt by [ticks] tics. Returns done.
  // -------------------------------------------------------------------------

  /// Advance the melt by [ticks] tics (default 1, the per-frame tic). Returns
  /// `true` once the melt is complete. After completion this is a no-op that
  /// keeps returning `true`. The live buffer ([compose] source) is updated each
  /// call. 1:1 with wipe_doMelt.
  bool update([int ticks = 1]) {
    if (_done) return true;

    // width /= 2  (dpixel columns).
    final int width = _width ~/ 2;
    const int height = _height;

    final Uint8List wipeScr = _wipeScr;
    final Uint8List scrStart = _scrStart;
    final Uint8List scrEnd = _scrEnd;
    final Int32List y = _y;

    bool done = true;

    while (ticks-- > 0) {
      for (int i = 0; i < width; i++) {
        if (y[i] < 0) {
          y[i]++;
          done = false;
        } else if (y[i] < height) {
          int dy = (y[i] < 16) ? y[i] + 1 : 8;
          if (y[i] + dy >= height) dy = height - y[i];

          // s = &wipe_scr_end[i*height + y[i]]   (column-major, 2 bytes/element)
          // d = &wipe_scr[y[i]*width + i]        (row-major,   2 bytes/element)
          int s = (i * height + y[i]) * 2;
          int d = (y[i] * width + i) * 2;
          final int wstep = width * 2; // idx += width (in 2-byte elements)
          for (int j = dy; j != 0; j--) {
            wipeScr[d] = scrEnd[s];
            wipeScr[d + 1] = scrEnd[s + 1];
            s += 2;
            d += wstep;
          }
          y[i] += dy;

          // s = &wipe_scr_start[i*height]   d = &wipe_scr[y[i]*width + i]
          s = (i * height) * 2;
          d = (y[i] * width + i) * 2;
          for (int j = height - y[i]; j != 0; j--) {
            wipeScr[d] = scrStart[s];
            wipeScr[d + 1] = scrStart[s + 1];
            s += 2;
            d += wstep;
          }
          done = false;
        }
      }
    }

    if (done) _done = true;
    return done;
  }

  // -------------------------------------------------------------------------
  // Present the current melted frame.
  // -------------------------------------------------------------------------

  /// Write the current melted frame (the live `wipe_scr` row-major buffer) into
  /// [out]'s indexed pixels. Call after [update] each frame to present the melt.
  void compose(Framebuffer out) {
    assert(out.width == _width && out.height == _height);
    out.pixels.setAll(0, _wipeScr);
  }

  /// The current melted frame bytes (row-major, 320x200), for tests.
  Uint8List get currentBytes => _wipeScr;
}
