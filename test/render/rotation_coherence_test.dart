// STRUCTURAL multi-angle turning-artifact test (the kind that was missing and
// let the "smear while turning" bug ship). Renders the E1M1 start from several
// view angles and, FOR EACH angle, asserts:
//   * high column-to-column horizontal coherence (torn/merged geometry would
//     drop this sharply), and
//   * coherent ceiling and floor bands (a small set of indices dominate the top
//     and bottom thirds — noise/smear would explode the distinct-index count).
//
// Unlike a single golden frame, this runs across a full rotation so a per-frame
// clear / angle-math regression that only manifests while turning is caught.

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/world.dart';

import 'render_support.dart';

Framebuffer _renderAt(World world, fixed_t vx, fixed_t vy, fixed_t vz,
    angle_t angle) {
  world.viewpoint.set(x: vx, y: vy, z: vz, angle: angle);
  final Framebuffer fb = Framebuffer();
  Renderer(framebuffer: fb, world: world)
      .renderPlayerView(const EmptySpriteSource());
  return fb;
}

double _horizontalCoherence(Framebuffer fb) {
  int matches = 0;
  int total = 0;
  for (int x = 1; x < fb.width; x++) {
    for (int y = 0; y < fb.height; y++) {
      total++;
      if (fb.getPixel(x, y) == fb.getPixel(x - 1, y)) matches++;
    }
  }
  return matches / total;
}

int _distinctInBand(Framebuffer fb, int y0, int y1) {
  final Set<int> s = <int>{};
  for (int y = y0; y < y1; y++) {
    for (int x = 0; x < fb.width; x++) {
      s.add(fb.getPixel(x, y));
    }
  }
  return s.length;
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  test('walls stay coherent across a full 360-degree rotation', () {
    final World world = loadE1M1();
    final MapThing start =
        world.level.things.firstWhere((MapThing t) => t.type == 1);
    final fixed_t vx = intToFixed(start.x);
    final fixed_t vy = intToFixed(start.y);
    final fixed_t vz = toInt32(floorHeightAt(world, vx, vy) + kEyeHeight);
    final angle_t base = normAngle((kAng45 ~/ 45) * start.angle);

    for (int i = 0; i < 16; i++) {
      final angle_t a = normAngle(base + 0x10000000 * i);
      final Framebuffer fb = _renderAt(world, vx, vy, vz, a);

      // Non-empty.
      expect(fb.pixels.any((int p) => p != 0), isTrue,
          reason: 'blank frame at step $i');

      // Horizontal coherence: a coherent perspective scene keeps adjacent
      // columns highly correlated. Torn/merged geometry (the bug) collapses
      // this. The start area is texture-rich, so use a conservative floor.
      final double coh = _horizontalCoherence(fb);
      expect(coh, greaterThan(0.30),
          reason: 'low horizontal coherence ($coh) at rotation step $i '
              '-> torn/merged geometry while turning');

      // Ceiling band (top sixth) and floor band (bottom sixth) must each be
      // dominated by a small set of flat indices, not smear/noise.
      final int h = fb.height;
      expect(_distinctInBand(fb, 0, h ~/ 6), lessThan(64),
          reason: 'noisy ceiling band at rotation step $i');
      expect(_distinctInBand(fb, h * 5 ~/ 6, h), lessThan(80),
          reason: 'noisy floor band at rotation step $i');
    }
  });

  test('rotation is deterministic (same angle -> identical frame)', () {
    final World world = loadE1M1();
    final MapThing start =
        world.level.things.firstWhere((MapThing t) => t.type == 1);
    final fixed_t vx = intToFixed(start.x);
    final fixed_t vy = intToFixed(start.y);
    final fixed_t vz = toInt32(floorHeightAt(world, vx, vy) + kEyeHeight);
    final angle_t a = normAngle((kAng45 ~/ 45) * start.angle + 0x30000000);

    final Framebuffer f1 = _renderAt(world, vx, vy, vz, a);
    final Framebuffer f2 = _renderAt(world, vx, vy, vz, a);
    expect(f1.pixels, equals(f2.pixels));
  });
}
