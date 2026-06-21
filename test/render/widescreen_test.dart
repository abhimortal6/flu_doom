// True-widescreen render tests: the width formula, the width-derived render
// state rebuilding correctly for a wider screen, and a coherent (non-garbled)
// widescreen E1M1 frame with no uninitialised edge columns. The 4:3 (320) path
// is asserted to still match the committed golden, so widening never regresses
// the vanilla reference.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/widescreen.dart';
import 'package:flu_doom/game/world/world.dart';

import 'render_support.dart';

/// Same golden hash as render_frame_test.dart (the 4:3 reference frame).
const int _kGoldenFrameHash = 0x36c705a0ae0e1ce0;

int _fnv1a64(Uint8List px) {
  int h = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  for (final int b in px) {
    h = (h ^ b);
    h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return h;
}

Framebuffer _renderStartFrame(int width) {
  final World world = loadE1M1();
  setViewToPlayerStart(world);
  final Framebuffer fb = Framebuffer(width: width);
  Renderer(framebuffer: fb, world: world)
      .renderPlayerView(const EmptySpriteSource());
  return fb;
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  group('widescreen width formula', () {
    test('4:3 device -> exactly 320 (no widening)', () {
      expect(widescreenWidthFor(4 / 3), equals(kBaseWidth));
      expect(widescreenWidthFor(1.0), equals(kBaseWidth)); // square -> >=320
    });

    test('16:9 -> a wider, even width in (320, 560]', () {
      final int w = widescreenWidthFor(16 / 9);
      expect(w, greaterThan(kBaseWidth));
      expect(w, lessThanOrEqualTo(kMaxWidescreenWidth));
      expect(w.isEven, isTrue);
      // round(240 * 16/9) = 427 -> even -> 428.
      expect(w, equals(428));
    });

    test('21:9 and wider is capped at the max (560)', () {
      expect(widescreenWidthFor(21 / 9), equals(kMaxWidescreenWidth));
      expect(widescreenWidthFor(3.0), equals(kMaxWidescreenWidth));
    });

    test('degenerate aspects fall back to 320', () {
      expect(widescreenWidthFor(0), equals(kBaseWidth));
      expect(widescreenWidthFor(double.nan), equals(kBaseWidth));
    });

    test('landscapeAspect normalises to >= 1 regardless of orientation', () {
      expect(landscapeAspect(1920, 1080), closeTo(16 / 9, 1e-9));
      expect(landscapeAspect(1080, 1920), closeTo(16 / 9, 1e-9));
    });
  });

  group('width-derived render state rebuilds for a widescreen width', () {
    const int w = 428; // 16:9 widescreen width.

    test('centerx, table lengths and clip arrays size to the wider width', () {
      final World world = loadE1M1();
      setViewToPlayerStart(world);
      final Framebuffer fb = Framebuffer(width: w);
      final Renderer r = Renderer(framebuffer: fb, world: world);
      final s = r.state;

      expect(s.screenWidth, equals(w));
      expect(s.viewWidth, equals(w));
      expect(s.centerX, equals(w ~/ 2)); // 214
      // xtoviewangle is SCREENWIDTH+1 long.
      expect(s.xToViewAngle.length, equals(w + 1));
      // Width-indexed clip / sprite-clip arrays.
      expect(s.ceilingClip.length, equals(w));
      expect(s.floorClip.length, equals(w));
      expect(s.negOneArray.length, equals(w));
      expect(s.screenHeightArray.length, equals(w));
    });

    test('projection tables span the FULL wider FOV', () {
      final World world = loadE1M1();
      setViewToPlayerStart(world);
      final Framebuffer fb = Framebuffer(width: w);
      final s = Renderer(framebuffer: fb, world: world).state;
      // Centre column looks straight ahead.
      expect(s.xToViewAngle[s.centerX], equals(0));
      // Edges differ from the centre (no collapse).
      expect(s.xToViewAngle[0], isNot(equals(s.xToViewAngle[s.centerX])));
      expect(s.xToViewAngle[w], isNot(equals(s.xToViewAngle[s.centerX])));
      // viewangletox spans the whole width: min 0, max == width.
      final int minX = s.viewAngleToX.reduce((a, b) => a < b ? a : b);
      final int maxX = s.viewAngleToX.reduce((a, b) => a > b ? a : b);
      expect(minX, equals(0));
      expect(maxX, equals(w));
    });
  });

  group('coherent widescreen E1M1 frame (no garbage edges)', () {
    const int w = 428;

    test('every column 0..width-1 is rendered (no uninitialised edges)', () {
      final Framebuffer fb = _renderStartFrame(w);
      expect(fb.pixels.length, equals(w * kScreenHeight));
      // Each column must have at least one non-zero pixel — the 3D view fills
      // the FULL width; an uninitialised (all-zero) edge column would be a
      // garbage/black strip the widescreen FOV failed to cover.
      for (int x = 0; x < w; x++) {
        bool any = false;
        for (int y = 0; y < kScreenHeight; y++) {
          if (fb.getPixel(x, y) != 0) {
            any = true;
            break;
          }
        }
        expect(any, isTrue, reason: 'column $x is empty (garbage edge)');
      }
    });

    test('coherent ceiling/floor bands across the FULL width', () {
      final Framebuffer fb = _renderStartFrame(w);
      int distinctIn(int y0, int y1, int x) {
        final Set<int> s = <int>{};
        for (int y = y0; y < y1; y++) {
          s.add(fb.getPixel(x, y));
        }
        return s.length;
      }

      // Sample columns across the whole width including near both edges.
      final List<int> cols = <int>[8, w ~/ 4, w ~/ 2, 3 * w ~/ 4, w - 8];
      for (final int x in cols) {
        expect(distinctIn(0, kScreenHeight ~/ 3, x), lessThan(28),
            reason: 'ceiling band noisy at x=$x');
        expect(distinctIn(kScreenHeight * 2 ~/ 3, kScreenHeight, x),
            lessThan(48),
            reason: 'floor band noisy at x=$x');
      }
    });

    test('high horizontal neighbour coherence across the wider frame', () {
      final Framebuffer fb = _renderStartFrame(w);
      int matches = 0;
      int total = 0;
      for (int x = 1; x < w; x++) {
        for (int y = 0; y < kScreenHeight; y++) {
          total++;
          if (fb.getPixel(x, y) == fb.getPixel(x - 1, y)) matches++;
        }
      }
      expect(matches / total, greaterThan(0.35),
          reason: 'low coherence -> torn/garbled widescreen geometry');
    });

    test('deterministic across two widescreen renders', () {
      final Framebuffer a = _renderStartFrame(w);
      final Framebuffer b = _renderStartFrame(w);
      expect(a.pixels, equals(b.pixels));
    });
  });

  test('4:3 (320) path still matches the committed golden', () {
    final Framebuffer fb = _renderStartFrame(kBaseWidth);
    expect(fb.pixels.length, kScreenWidth * kScreenHeight);
    expect(_fnv1a64(fb.pixels), equals(_kGoldenFrameHash),
        reason: 'widening must not change the 4:3 reference frame');
  });
}
