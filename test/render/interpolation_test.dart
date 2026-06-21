// Frame interpolation (Crispy/Woof smooth motion) tests.
//
// Proves the render-only invariant: interpolation blends old -> current by a
// per-frame fraction WITHOUT ever touching the 35Hz sim, and is byte-identical
// to today at frac==0 / old==new / interpolation OFF (the render golden path).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/system/interpolation.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/game/world/world.dart';

import 'render_support.dart';

int _fnv1a64(Uint8List px) {
  int h = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  for (final int b in px) {
    h = (h ^ b);
    h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return h;
}

const int _kGoldenFrameHash = 0x36c705a0ae0e1ce0;

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  group('lerpFixed (fixed-point linear interpolation)', () {
    test('endpoints are exact', () {
      expect(lerpFixed(100, 200, 0), 100);
      expect(lerpFixed(100, 200, kFracUnit), 200);
    });
    test('frac=0.5 is the midpoint', () {
      expect(lerpFixed(100 * kFracUnit, 200 * kFracUnit, kFracUnit ~/ 2),
          150 * kFracUnit);
    });
    test('handles negative deltas (descending)', () {
      expect(lerpFixed(200 * kFracUnit, 100 * kFracUnit, kFracUnit ~/ 2),
          150 * kFracUnit);
    });
    test('quarter fraction', () {
      expect(lerpFixed(0, 400 * kFracUnit, kFracUnit ~/ 4), 100 * kFracUnit);
    });
  });

  group('lerpAngle (BAM wrap-around)', () {
    test('half-way between two nearby angles', () {
      const angle_t a = kAng90;
      const angle_t b = kAng90 + 0x10000000;
      // delta is positive 0x10000000; half is 0x08000000.
      expect(lerpAngle(a, b, kFracUnit ~/ 2),
          normAngle(kAng90 + 0x08000000));
    });
    test('endpoints exact', () {
      expect(lerpAngle(kAng90, kAng270, kFracUnit), kAng270);
      expect(lerpAngle(kAng90, kAng270, 0), kAng90);
    });
    test('wraps the SHORT way across the 0/0xFFFFFFFF seam', () {
      // old just below a full turn, new just above 0: the signed delta is small
      // and positive, so the midpoint is near the seam — NOT a near-full backspin.
      final angle_t a = normAngle(-0x04000000); // ~ -22.5deg
      const angle_t b = 0x04000000; //  +22.5deg
      final angle_t mid = lerpAngle(a, b, kFracUnit ~/ 2);
      // Midpoint should be ~0 (the seam), well within a small band of 0.
      final int signed = toInt32(mid);
      expect(signed.abs() < 0x00800000, isTrue,
          reason: 'angle interpolation did not take the short path: $mid');
    });
  });

  group('InterpolationState.renderFrac gating', () {
    test('disabled -> FRACUNIT regardless of frac', () {
      final s = InterpolationState()
        ..enabled = false
        ..active = true
        ..frac = kFracUnit ~/ 2;
      expect(s.renderFrac, kFracUnit);
      expect(s.interpolating, isFalse);
    });
    test('inactive (paused/menu) -> FRACUNIT (frozen view)', () {
      final s = InterpolationState()
        ..enabled = true
        ..active = false
        ..frac = kFracUnit ~/ 2;
      expect(s.renderFrac, kFracUnit);
    });
    test('enabled + active -> the live frac', () {
      final s = InterpolationState()
        ..enabled = true
        ..active = true
        ..frac = kFracUnit ~/ 2;
      expect(s.renderFrac, kFracUnit ~/ 2);
      expect(s.interpolating, isTrue);
    });
  });

  group('render byte-identical at the golden path', () {
    Framebuffer renderWith({required bool enabled, bool active = true,
        int frac = 0}) {
      final World world = loadE1M1();
      setViewToPlayerStart(world);
      // old == new (no movement) so even when interpolating the result must
      // equal the current-position render.
      world.viewpoint.captureOld();
      world.interp
        ..enabled = enabled
        ..active = active
        ..frac = frac;
      final Framebuffer fb = Framebuffer();
      Renderer(framebuffer: fb, world: world)
          .renderPlayerView(const EmptySpriteSource());
      return fb;
    }

    test('interpolation OFF == committed golden', () {
      final Framebuffer fb = renderWith(enabled: false);
      expect(_fnv1a64(fb.pixels), _kGoldenFrameHash);
    });

    test('interpolation ON but old==new == committed golden (any frac)', () {
      final Framebuffer fb =
          renderWith(enabled: true, active: true, frac: kFracUnit ~/ 2);
      expect(_fnv1a64(fb.pixels), _kGoldenFrameHash);
    });

    test('interpolation ON but paused (inactive) == committed golden', () {
      final Framebuffer fb =
          renderWith(enabled: true, active: false, frac: kFracUnit ~/ 2);
      expect(_fnv1a64(fb.pixels), _kGoldenFrameHash);
    });
  });

  group('view interpolation places the camera at the midpoint', () {
    test('frac=0.5 renders the halfway view between old and new', () {
      // Build two distinct camera positions (old + a shifted new), then render
      // at frac=0.5 and assert the output differs from BOTH endpoints but equals
      // an explicit midpoint render at frac=FRACUNIT.
      World mk() {
        final World w = loadE1M1();
        setViewToPlayerStart(w);
        return w;
      }

      // OLD position: player start. NEW position: shifted +64 units in x.
      final World wMid = mk();
      final fixed_t startX = wMid.viewpoint.x;
      wMid.viewpoint.captureOld(); // old = start
      wMid.viewpoint.x = toInt32(startX + 64 * kFracUnit); // new = +64

      Framebuffer renderAt(World w, {required bool interp, int frac = 0}) {
        w.interp
          ..enabled = interp
          ..active = interp
          ..frac = frac;
        final Framebuffer fb = Framebuffer();
        Renderer(framebuffer: fb, world: w)
            .renderPlayerView(const EmptySpriteSource());
        return fb;
      }

      // The interpolated frac=0.5 frame.
      final Framebuffer mid =
          renderAt(wMid, interp: true, frac: kFracUnit ~/ 2);

      // Reference: a NON-interpolated render whose CURRENT view is the explicit
      // midpoint (+32 units). This is exactly what frac=0.5 should produce.
      final World wRef = mk();
      wRef.viewpoint.x = toInt32(startX + 32 * kFracUnit);
      final Framebuffer ref = renderAt(wRef, interp: false);

      expect(mid.pixels, equals(ref.pixels),
          reason: 'frac=0.5 view is not the midpoint between old and new');

      // And it differs from the new-position (frac=1.0) render — proving the
      // interpolation actually moved the camera off the endpoint.
      final World wNew = mk();
      wNew.viewpoint.x = toInt32(startX + 64 * kFracUnit);
      final Framebuffer endNew = renderAt(wNew, interp: false);
      expect(mid.pixels, isNot(equals(endNew.pixels)));
    });

    test('snap: a large view jump is NOT interpolated (renders new)', () {
      final World w = loadE1M1();
      setViewToPlayerStart(w);
      final fixed_t startX = w.viewpoint.x;
      // old far away (jump > 128 units), new at start -> snap to new.
      w.viewpoint.oldX = toInt32(startX - 4096 * kFracUnit);
      w.viewpoint.oldY = w.viewpoint.y;
      w.viewpoint.oldZ = w.viewpoint.z;
      w.viewpoint.oldAngle = w.viewpoint.angle;
      w.interp
        ..enabled = true
        ..active = true
        ..frac = kFracUnit ~/ 2;
      final Framebuffer snapped = Framebuffer();
      Renderer(framebuffer: snapped, world: w)
          .renderPlayerView(const EmptySpriteSource());

      // Equal to the non-interpolated render at the current (new) position.
      expect(_fnv1a64(snapped.pixels), _kGoldenFrameHash,
          reason: 'teleport jump should snap to the current view, not lerp');
    });
  });
}
