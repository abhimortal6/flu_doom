// Offline frame dump (runs under `flutter test` for dart:ui-free toRgba access).
// Renders E1M1 from the player start + two extra angles and writes PNGs to
// debug_shots/. Set DUMP_PREFIX env (before/after) to name the output.
//
//   DUMP_PREFIX=before flutter test test/render/dump_frame_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';
import 'package:flu_doom/game/world/world.dart';

import 'png_writer.dart';
import 'render_support.dart';

void main() {
  // Opt-in only: this test WRITES PNGs to debug_shots/ and must not run during a
  // normal `flutter test` (it would overwrite the committed before/after shots).
  // Enable with:  DUMP_PREFIX=after flutter test test/render/dump_frame_test.dart
  final String? prefixEnv = Platform.environment['DUMP_PREFIX'];

  test('dump E1M1 frames to debug_shots/', () {
    final World world = loadE1M1();
    final Palette palette = Palette.fromWad(world.wad);
    Directory('debug_shots').createSync(recursive: true);
    final String prefix = prefixEnv!;

    for (final int delta in <int>[0, 45, -90]) {
      setViewToPlayerStart(world, angleDeltaDeg: delta);
      final Framebuffer fb = Framebuffer();
      Renderer(framebuffer: fb, world: world)
          .renderPlayerView(const EmptySpriteSource());
      final String suffix = delta == 0 ? '' : (delta == 45 ? '_1' : '_2');
      writeFramebufferPng('debug_shots/$prefix$suffix.png', fb, palette);
    }
  }, skip: prefixEnv == null ? 'set DUMP_PREFIX to write debug PNGs' : false);
}
