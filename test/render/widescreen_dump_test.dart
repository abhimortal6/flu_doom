// Widescreen vs 4:3 present-layer screenshot dump. Renders the E1M1 start scene
// to BOTH a widescreen framebuffer (wider FOV) and a 4:3 framebuffer, then blits
// each through the real VideoView painter onto a 16:9 device surface and writes:
//   debug_shots/wide_16x9.png  (widescreen render -> fills the screen, wider FOV)
//   debug_shots/wide_4x3.png   (4:3 render -> letterboxed, same scene narrower)
//
// Reading the two side by side confirms the widescreen path shows MORE of the
// scene horizontally with correct vertical proportions and clean edges, vs a
// stretched 4:3 (it is NOT stretched — the geometry is genuinely wider).
//
// Opt-in (does not run under a normal `flutter test`):
//   DUMP_WIDE=1 flutter test test/render/widescreen_dump_test.dart -d macos

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
import 'package:flu_doom/engine/video/widescreen.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/integration/sprite_adapter.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/state/dummy_player_status.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/hud/status_bar.dart';

import 'png_writer.dart';
import 'render_support.dart';

void main() {
  final bool enabled = Platform.environment['DUMP_WIDE'] != null;

  testWidgets(
      'dump widescreen vs 4:3 to debug_shots/ (set DUMP_WIDE=1 to enable)',
      (tester) async {
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

    // Render the SAME viewpoint into both a widescreen and a 4:3 framebuffer.
    final int wideW = widescreenWidthFor(16 / 9); // 428

    // Decode each framebuffer image OUTSIDE the fake-async zone.
    final Framebuffer wideFb = Framebuffer(width: wideW);
    world.viewpoint.set(x: vx, y: vy, z: vz, angle: baseAngle);
    Renderer(framebuffer: wideFb, world: world).renderPlayerView(sprites);
    final ui.Image wideImg =
        (await tester.runAsync<ui.Image>(() => wideFb.toImage(palette)))!;

    final Framebuffer narrowFb = Framebuffer(width: kBaseWidth);
    world.viewpoint.set(x: vx, y: vy, z: vz, angle: baseAngle);
    Renderer(framebuffer: narrowFb, world: world).renderPlayerView(sprites);
    final ui.Image narrowImg =
        (await tester.runAsync<ui.Image>(() => narrowFb.toImage(palette)))!;

    // A widescreen frame WITH the status bar overlaid, to verify the HUD is
    // centred on the wider buffer with clean black side strips (no garbage).
    final Framebuffer hudFb = Framebuffer(width: wideW);
    world.viewpoint.set(x: vx, y: vy, z: vz, angle: baseAngle);
    Renderer(framebuffer: hudFb, world: world).renderPlayerView(sprites);
    final GraphicsCache gc = GraphicsCache(wad);
    final StatusBar bar = StatusBar(gc);
    final DummyPlayerStatus p = DummyPlayerStatus()
      ..health = 100
      ..armor = 75;
    p.weapons[2] = true;
    p.weapons[3] = true;
    p.weapons[5] = true;
    bar.draw(hudFb, p);
    final ui.Image hudImg =
        (await tester.runAsync<ui.Image>(() => hudFb.toImage(palette)))!;

    // A 16:9 device surface. Both are blitted with ScaleMode.fit + 4:3 pixel
    // aspect: the widescreen image fills it (its aspect already matches), the
    // 4:3 image letterboxes. Neither is horizontally stretched.
    const Size surface = Size(1280, 720);

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
      'wide_16x9',
      VideoView(
        image: wideImg,
        scaleMode: ScaleMode.fit,
        pixelAspectCorrection: true,
        filterQuality: FilterQuality.medium,
      ),
    );
    await dump(
      'wide_4x3',
      VideoView(
        image: narrowImg,
        scaleMode: ScaleMode.fit,
        pixelAspectCorrection: true,
        filterQuality: FilterQuality.medium,
      ),
    );

    await dump(
      'wide_16x9_hud',
      VideoView(
        image: hudImg,
        scaleMode: ScaleMode.fit,
        pixelAspectCorrection: true,
        filterQuality: FilterQuality.medium,
      ),
    );

    wideImg.dispose();
    narrowImg.dispose();
    hudImg.dispose();
  }, skip: !enabled);
}
