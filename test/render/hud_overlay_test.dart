// Renders the status bar over a real E1M1 frame and asserts vanilla-faithful
// layout: the bar covers the bottom 32 rows, the big numbers are offset-aware
// (V_DrawPatch positioning), and the whole overlay matches a committed golden.
//
// These catch the "HUD not aligned" regression: before the patch-offset fix the
// face / digits / percent were shifted, and "100%" was truncated to "00%".

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/game/state/dummy_player_status.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/hud/status_bar.dart';

import 'render_support.dart';

/// Golden hash of the player-start frame with the status bar overlaid for a
/// 100hp / 75 armor / weapons 2,3,5 owned player. Regenerate (after a visual
/// check of debug_shots/after_hud.png) the same way as the frame golden.
const int _kGoldenHudHash = -5338542485437338766;

int _fnv1a64(Uint8List px) {
  int h = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  for (final int b in px) {
    h = (h ^ b);
    h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return h;
}

Framebuffer _renderWithHud() {
  final World world = loadE1M1();
  setViewToPlayerStart(world);
  final Framebuffer fb = Framebuffer();
  Renderer(framebuffer: fb, world: world)
      .renderPlayerView(const EmptySpriteSource());
  final GraphicsCache gc = GraphicsCache(world.wad);
  final StatusBar bar = StatusBar(gc);
  final DummyPlayerStatus p = DummyPlayerStatus()
    ..health = 100
    ..armor = 75;
  p.weapons[2] = true;
  p.weapons[3] = true;
  p.weapons[5] = true;
  bar.draw(fb, p);
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
  test('status bar covers the bottom 32 rows (STBAR overlay)', () {
    final Framebuffer fb = _renderWithHud();
    // Compare the bottom band against the same frame WITHOUT the bar: every
    // bottom-band pixel must have been overwritten by the bar (STBAR is 320x32
    // at y=168), proving the overlay sits at the right place and size.
    final World world = loadE1M1();
    setViewToPlayerStart(world);
    final Framebuffer bare = Framebuffer();
    Renderer(framebuffer: bare, world: world)
        .renderPlayerView(const EmptySpriteSource());

    int changed = 0;
    int bandPixels = 0;
    for (int y = 168; y < 200; y++) {
      for (int x = 0; x < kScreenWidth; x++) {
        bandPixels++;
        if (fb.getPixel(x, y) != bare.getPixel(x, y)) changed++;
      }
    }
    // The opaque STBAR background must overwrite essentially the entire band.
    expect(changed, greaterThan(bandPixels * 95 ~/ 100),
        reason: 'status bar does not cover the bottom 32 rows');

    // The 3D view ABOVE the bar (y < 168) must be untouched by the overlay.
    int aboveChanged = 0;
    for (int y = 0; y < 168; y++) {
      for (int x = 0; x < kScreenWidth; x++) {
        if (fb.getPixel(x, y) != bare.getPixel(x, y)) aboveChanged++;
      }
    }
    expect(aboveChanged, equals(0),
        reason: 'status bar bled above y=168');
  });

  test('status-bar overlay matches the committed golden fingerprint', () {
    final Framebuffer fb = _renderWithHud();
    expect(
      _fnv1a64(fb.pixels),
      equals(_kGoldenHudHash),
      reason: 'HUD overlay changed vs golden. If intentional, re-verify '
          'debug_shots/after_hud.png then update _kGoldenHudHash.',
    );
  });
}
