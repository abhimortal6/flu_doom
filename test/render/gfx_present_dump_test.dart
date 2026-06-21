// Present-layer screenshot dump: renders the E1M1 start scene to the 320x200
// framebuffer, then blits it UPSCALED through the real VideoView painter at a
// large device size with each graphics setting, capturing the result to:
//   debug_shots/gfx_sharp.png  (FilterQuality.none — blocky/pixelated)
//   debug_shots/gfx_smooth.png (FilterQuality.medium — softened)
//   debug_shots/gfx_crt.png    (smooth + scanline/glow overlay)
//
// This is what actually exercises the present quality lever (the raw 320x200
// PNG cannot show it). Captured offline via a RepaintBoundary -> toImage.
//
// Opt-in (does not run under a normal `flutter test`):
//   DUMP_GFX=1 flutter test test/render/gfx_present_dump_test.dart -d macos
//   (also runs headless on the default device; macOS just uses the GPU blit).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';
import 'package:flu_doom/engine/video/video_view.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/integration/sprite_adapter.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/world.dart';

import 'png_writer.dart';
import 'render_support.dart';

void main() {
  final bool enabled = Platform.environment['DUMP_GFX'] != null;

  testWidgets(
      'dump present-layer sharp/smooth/crt to debug_shots/ '
      '(set DUMP_GFX=1 to enable)', (tester) async {
    final Uint8List bytes = File('assets/doom1.wad').readAsBytesSync();
    final WadFile wad = WadFile.fromBytes(bytes);
    final World world = World.fromWad(wad, mapName: 'E1M1');
    final Palette palette = Palette.fromWad(wad);
    Directory('debug_shots').createSync(recursive: true);

    final PlaySim sim = PlaySim(world);
    final SpriteSource sprites = PlaySpriteAdapter(sim, wad);

    final MapThing start =
        world.level.things.firstWhere((MapThing t) => t.type == 1);
    final fixed_t vx = intToFixed(start.x);
    final fixed_t vy = intToFixed(start.y);
    final fixed_t floorZ = floorHeightAt(world, vx, vy);
    final fixed_t vz = toInt32(floorZ + kEyeHeight);
    final angle_t baseAngle = normAngle((kAng45 ~/ 45) * start.angle);

    final Framebuffer fb = Framebuffer();
    world.viewpoint.set(x: vx, y: vy, z: vz, angle: baseAngle);
    Renderer(framebuffer: fb, world: world).renderPlayerView(sprites);

    // Decode the framebuffer image OUTSIDE the fake-async zone.
    final ui.Image frame =
        (await tester.runAsync<ui.Image>(() => fb.toImage(palette)))!;

    // Upscale 3x to 960x600 so the filter difference is obvious.
    const Size surface = Size(960, 600);

    Future<void> dump(String name, VideoView view) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
                width: surface.width, height: surface.height, child: view),
          ),
        ),
      );
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image shot =
          (await tester.runAsync<ui.Image>(() => boundary.toImage()))!;
      final ByteData data = (await tester.runAsync<ByteData?>(
          () => shot.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      writeRgbaPng('debug_shots/$name.png', data.buffer.asUint8List(),
          shot.width, shot.height);
      shot.dispose();
    }

    await dump(
      'gfx_sharp',
      VideoView(
        image: frame,
        scaleMode: ScaleMode.fill,
        filterQuality: FilterQuality.none,
      ),
    );
    await dump(
      'gfx_smooth',
      VideoView(
        image: frame,
        scaleMode: ScaleMode.fill,
        filterQuality: FilterQuality.medium,
      ),
    );
    await dump(
      'gfx_crt',
      VideoView(
        image: frame,
        scaleMode: ScaleMode.fill,
        filterQuality: FilterQuality.medium,
        crtScanlines: true,
      ),
    );

    frame.dispose();
  }, skip: !enabled);
}
