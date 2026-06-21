// Offline interpolation evidence dump: render the SAME old/new tic pair at
// frac=0 (draws the OLD-ish current view) and frac=0.5 (the midpoint) and write
// debug_shots/interp_0.png + interp_50.png. The two images must differ — the
// camera at frac=0.5 sits visibly between the two tic positions, proving the
// interpolation render path actually moves the view.
//
//   DUMP_INTERP=1 flutter test test/render/dump_interp_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';
import 'package:flu_doom/game/world/world.dart';

import 'png_writer.dart';
import 'render_support.dart';

void main() {
  final bool on = Platform.environment['DUMP_INTERP'] != null;

  test('dump frac=0 and frac=0.5 interpolated frames', () {
    final Palette palette = Palette.fromWad(loadE1M1().wad);
    Directory('debug_shots').createSync(recursive: true);

    Framebuffer renderAtFrac(int frac) {
      final World w = loadE1M1();
      // OLD view = player start. NEW view = moved +96 units forward in x and
      // turned +20deg, so a frac=0.5 render is a clearly different camera.
      setViewToPlayerStart(w);
      w.viewpoint.captureOld(); // old = start
      w.viewpoint.x = toInt32(w.viewpoint.x + 96 * kFracUnit);
      w.viewpoint.angle = normAngle(w.viewpoint.angle + (kAng45 ~/ 45) * 20);
      w.interp
        ..enabled = true
        ..active = true
        ..frac = frac;
      final Framebuffer fb = Framebuffer();
      Renderer(framebuffer: fb, world: w)
          .renderPlayerView(const EmptySpriteSource());
      return fb;
    }

    final Framebuffer f0 = renderAtFrac(0);
    final Framebuffer f50 = renderAtFrac(kFracUnit ~/ 2);

    writeFramebufferPng('debug_shots/interp_0.png', f0, palette);
    writeFramebufferPng('debug_shots/interp_50.png', f50, palette);

    // The midpoint frame must differ from the frac=0 frame (camera moved).
    expect(f0.pixels, isNot(equals(f50.pixels)),
        reason: 'frac=0.5 did not move the camera — interpolation not applied');
  }, skip: on ? false : 'set DUMP_INTERP=1 to write debug PNGs');
}
