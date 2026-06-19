// Bitmap fonts used by the status bar and HUD, ported from the lump sets in
// Chocolate Doom st_stuff.c (STTNUM / STYSNUM / STTPRCNT / STTMINUS) and
// hu_stuff.c (STCFN, the "console"/HUD font).
//
// Doom has no scalable text: each glyph is a patch lump. We wrap the relevant
// lump ranges into small font objects that know how to draw a string / number.

import '../../engine/video/framebuffer.dart';
import '../../engine/video/patch.dart';
import 'graphics_cache.dart';
import 'patch_draw.dart';

/// A fixed set of digit glyphs (0..9) plus optional percent / minus, as used by
/// the status bar number widgets (st_number_t / st_percent_t). Numbers are
/// drawn RIGHT-justified at a given x (vanilla STlib_drawNum).
class NumberFont {
  NumberFont({
    required this.digits,
    this.percent,
    this.minus,
  });

  /// Glyph patches for 0..9.
  final List<Patch?> digits;

  /// Optional '%' glyph (STTPRCNT).
  final Patch? percent;

  /// Optional '-' glyph (STTMINUS).
  final Patch? minus;

  /// Glyph width (all digits share a width in the Doom fonts).
  int get width => digits.isNotEmpty && digits[0] != null ? digits[0]!.width : 0;

  /// Glyph height.
  int get height => digits.isNotEmpty && digits[0] != null ? digits[0]!.height : 0;

  /// Build the big red status-bar font: STTNUM0..9 + STTPRCNT + STTMINUS.
  factory NumberFont.big(GraphicsCache gc) => NumberFont(
        digits: List<Patch?>.generate(10, (int i) => gc.patch('STTNUM$i')),
        percent: gc.patch('STTPRCNT'),
        minus: gc.patch('STTMINUS'),
      );

  /// Build the small yellow font: STYSNUM0..9 (no percent/minus glyphs exist).
  factory NumberFont.smallYellow(GraphicsCache gc) => NumberFont(
        digits: List<Patch?>.generate(10, (int i) => gc.patch('STYSNUM$i')),
      );

  /// Build the grey "arsenal" font: STGNUM0..9.
  factory NumberFont.grey(GraphicsCache gc) => NumberFont(
        digits: List<Patch?>.generate(10, (int i) => gc.patch('STGNUM$i')),
      );

  /// Draw [num] right-justified so its rightmost digit ends at x = [x]
  /// (the digits are drawn leaving x as the right edge), top at [y]. Mirrors
  /// STlib_drawNum: at most [maxDigits] digits, negative shown with [minus].
  /// Returns the x of the left edge drawn.
  int drawNum(Framebuffer fb, int x, int y, int num, {int maxDigits = 3}) {
    final int w = width;
    if (w == 0) return x;
    final bool neg = num < 0;
    int n = neg ? -num : num;

    // Clamp to maxDigits like vanilla (drawNum: 99 / 999 cap).
    int cap = 1;
    for (int i = 0; i < maxDigits; i++) {
      cap *= 10;
    }
    if (n >= cap) n = cap - 1;

    int cx = x;
    // Special case 0.
    if (n == 0) {
      cx -= w;
      digits[0]?.drawV(fb, cx, y);
      if (neg && minus != null) {
        cx -= w;
        minus!.drawV(fb, cx, y);
      }
      return cx;
    }
    while (n != 0) {
      cx -= w;
      digits[n % 10]?.drawV(fb, cx, y);
      n ~/= 10;
    }
    if (neg && minus != null) {
      cx -= w;
      minus!.drawV(fb, cx, y);
    }
    return cx;
  }

  /// Draw a percentage (st_percent_t). Faithful to STlib_drawPercent: the '%'
  /// glyph is drawn with its LEFT edge at [x] (V_DrawPatch at per->n.x), and the
  /// number is drawn right-justified so its rightmost digit's right edge is also
  /// at [x] (the number sits to the left of the '%').
  void drawPercent(Framebuffer fb, int x, int y, int num) {
    if (percent != null) {
      percent!.drawV(fb, x, y);
    }
    drawNum(fb, x, y, num);
  }
}

/// The HUD / message text font (STCFN). Vanilla loads STCFN033..STCFN095
/// covering printable ASCII from '!' (33) up; index 0 corresponds to '!'.
/// Lowercase letters reuse the uppercase glyphs (vanilla uppercases input).
class HudFont {
  HudFont(this._glyphs, this.spaceWidth, this.height);

  /// Glyphs indexed by (ascii - 33). Null = no glyph (e.g. space).
  final List<Patch?> _glyphs;

  /// Width to advance for a space character.
  final int spaceWidth;

  /// Common glyph height (line height).
  final int height;

  /// First ASCII code with a glyph (HU_FONTSTART = '!').
  static const int fontStart = 33;

  /// Number of font glyphs (HU_FONTSIZE = '_' - '!' + 1 = 63).
  static const int fontSize = 63;

  /// Load the STCFN font set from the cache.
  factory HudFont.stcfn(GraphicsCache gc) {
    final List<Patch?> glyphs = <Patch?>[];
    int h = 0;
    int sp = 4;
    for (int i = 0; i < fontSize; i++) {
      final int code = fontStart + i;
      // Vanilla builds the lump name as STCFN%.3d (e.g. STCFN033).
      final String name = 'STCFN${code.toString().padLeft(3, '0')}';
      final Patch? p = gc.patch(name);
      glyphs.add(p);
      if (p != null && p.height > h) h = p.height;
      if (code == 'A'.codeUnitAt(0) && p != null) sp = p.width;
    }
    return HudFont(glyphs, sp, h == 0 ? 8 : h);
  }

  /// Width of [text] if drawn (for centring / right-justify).
  int widthOf(String text) {
    int w = 0;
    final String s = text.toUpperCase();
    for (int i = 0; i < s.length; i++) {
      final int c = s.codeUnitAt(i);
      if (c == 0x20) {
        w += spaceWidth;
        continue;
      }
      final int idx = c - fontStart;
      if (idx < 0 || idx >= _glyphs.length || _glyphs[idx] == null) {
        w += spaceWidth;
      } else {
        w += _glyphs[idx]!.width;
      }
    }
    return w;
  }

  /// Draw [text] left-aligned at (x, y). Returns the x just past the last glyph
  /// (vanilla HUlib drawing advances a cursor). Unmapped chars advance by a
  /// space. Input is uppercased to match the available glyph set.
  int draw(Framebuffer fb, int x, int y, String text) {
    int cx = x;
    final String s = text.toUpperCase();
    for (int i = 0; i < s.length; i++) {
      final int c = s.codeUnitAt(i);
      if (c == 0x20) {
        cx += spaceWidth;
        continue;
      }
      final int idx = c - fontStart;
      if (idx < 0 || idx >= _glyphs.length || _glyphs[idx] == null) {
        cx += spaceWidth;
        continue;
      }
      final Patch g = _glyphs[idx]!;
      g.drawV(fb, cx, y);
      cx += g.width;
    }
    return cx;
  }
}
