// Renders one real E1M1 frame from the player-1 start and asserts the output is
// the CORRECT vanilla scene — via a committed golden fingerprint plus structural
// assertions that would have caught the "walls merging / broken view" bugs.
//
// REGENERATING THE GOLDEN (do this only after VISUALLY confirming the frame is
// correct, e.g. via `DUMP_PREFIX=after flutter test test/render/dump_frame_test.dart`
// and inspecting debug_shots/after*.png):
//   1. Temporarily print fnv64(fb.pixels) from the player-start frame.
//   2. Replace [_kGoldenFrameHash] below with the printed value and commit.
// The hash is over the raw 320x200 indexed framebuffer, so any pixel change
// (geometry, texture mapping, shading) trips it.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/game/world/world.dart';

import 'render_support.dart';

/// Golden hash of the player-start E1M1 frame (FNV-1a 64-bit over fb.pixels).
/// Captured after the frame was visually verified correct (techbase start room:
/// STARTAN walls, computer banks, grey ceiling, distance-shaded floor, the
/// central liquid pool). See the file header to regenerate.
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

Framebuffer _renderStartFrame() {
  final World world = loadE1M1();
  setViewToPlayerStart(world);
  final Framebuffer fb = Framebuffer();
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
  test('projection tables span the FOV (R_InitTextureMapping)', () {
    final World world = loadE1M1();
    setViewToPlayerStart(world);
    final Framebuffer fb = Framebuffer();
    final Renderer r = Renderer(framebuffer: fb, world: world);
    final s = r.state;
    // xToViewAngle must vary across the screen (a collapse -> noise frame).
    expect(s.xToViewAngle[0], isNot(equals(s.xToViewAngle[s.centerX])));
    expect(s.xToViewAngle[s.screenWidth],
        isNot(equals(s.xToViewAngle[s.centerX])));
    // Centre column looks straight ahead (angle ~0).
    expect(s.xToViewAngle[s.centerX], equals(0));
    // viewAngleToX must span the whole view width.
    final int minX = s.viewAngleToX.reduce((int a, int b) => a < b ? a : b);
    final int maxX = s.viewAngleToX.reduce((int a, int b) => a > b ? a : b);
    expect(minX, equals(0));
    expect(maxX, equals(s.screenWidth));
  });

  test('player-start frame matches the committed golden fingerprint', () {
    final Framebuffer fb = _renderStartFrame();
    expect(fb.pixels.length, kScreenWidth * kScreenHeight);
    expect(
      _fnv1a64(fb.pixels),
      equals(_kGoldenFrameHash),
      reason: 'Frame changed vs golden. If this was an intentional renderer '
          'change, VISUALLY re-verify debug_shots/after.png then update '
          '_kGoldenFrameHash (see file header).',
    );
  });

  test('frame has a coherent ceiling band, wall band and floor band', () {
    // Structural sanity that a single noisy/garbage frame (the original bug)
    // would fail: scan the centre column top->bottom. A real techbase view has
    // a contiguous ceiling region up top and a contiguous floor region at the
    // bottom, with wall geometry between — i.e. the top and bottom thirds are
    // each dominated by a small set of indices, not random noise.
    final Framebuffer fb = _renderStartFrame();
    const int cx = kScreenWidth ~/ 2;

    int distinctIn(int y0, int y1, int x) {
      final Set<int> s = <int>{};
      for (int y = y0; y < y1; y++) {
        s.add(fb.getPixel(x, y));
      }
      return s.length;
    }

    // Sample three columns to avoid landing exactly on a doorway gap.
    for (final int x in <int>[cx - 60, cx, cx + 60]) {
      // Ceiling third: a flat/sky region -> few distinct indices.
      expect(distinctIn(0, kScreenHeight ~/ 3, x), lessThan(24),
          reason: 'ceiling band noisy at x=$x (broken visplanes/clip arrays)');
      // Floor third: a flat region -> few distinct indices.
      expect(distinctIn(kScreenHeight * 2 ~/ 3, kScreenHeight, x),
          lessThan(40),
          reason: 'floor band noisy at x=$x');
    }
  });

  test('vertical wall coherence: adjacent columns are correlated', () {
    // The "walls merging / torn geometry" bug produced columns that bore no
    // relation to their neighbours. A correct perspective view has high
    // column-to-column similarity (textures vary smoothly horizontally).
    final Framebuffer fb = _renderStartFrame();
    int matches = 0;
    int total = 0;
    for (int x = 1; x < kScreenWidth; x++) {
      for (int y = 0; y < kScreenHeight; y++) {
        total++;
        if (fb.getPixel(x, y) == fb.getPixel(x - 1, y)) matches++;
      }
    }
    final double ratio = matches / total;
    // A coherent scene: >35% of vertically-aligned neighbour pixels are equal.
    // (Pure noise would be ~1/numcolours; the original broken frame was ~low.)
    expect(ratio, greaterThan(0.35),
        reason: 'low horizontal coherence ($ratio) -> torn/merged geometry');
  });

  test('a clear horizon split exists (ceiling above, floor below)', () {
    // The top rows must be dominated by the ceiling flat and the bottom rows by
    // floor/liquid flats; a broken renderer that smeared walls over everything
    // would not show this split.
    final Framebuffer fb = _renderStartFrame();
    final Map<int, int> top = <int, int>{};
    final Map<int, int> bot = <int, int>{};
    for (int y = 0; y < 24; y++) {
      for (int x = 0; x < kScreenWidth; x++) {
        final int v = fb.getPixel(x, y);
        top[v] = (top[v] ?? 0) + 1;
      }
    }
    for (int y = kScreenHeight - 24; y < kScreenHeight; y++) {
      for (int x = 0; x < kScreenWidth; x++) {
        final int v = fb.getPixel(x, y);
        bot[v] = (bot[v] ?? 0) + 1;
      }
    }
    int dominant(Map<int, int> m) =>
        m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    // The dominant top index differs from the dominant bottom index.
    expect(dominant(top), isNot(equals(dominant(bot))),
        reason: 'ceiling and floor regions are indistinguishable');
  });

  test('is deterministic across two renders', () {
    final Framebuffer fb1 = _renderStartFrame();
    final Framebuffer fb2 = _renderStartFrame();
    expect(fb1.pixels, equals(fb2.pixels));
  });

  test('empty sprite source renders a valid (non-empty) view', () {
    final Framebuffer fb = _renderStartFrame();
    expect(fb.pixels.any((int p) => p != 0), isTrue);
  });
}
