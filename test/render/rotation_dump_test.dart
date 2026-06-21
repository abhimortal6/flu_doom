// Offline motion+sprite dump: renders a full 360-deg rotation (16 steps) and a
// short forward walk from the E1M1 player start, WITH the level's actual things
// populated via the play-sim PlaySpriteAdapter (NOT EmptySpriteSource). Writes
// debug_shots/rot_00..15.png and debug_shots/walk_0..2.png.
//
// This is the harness that catches turning/moving artifacts (a single static
// frame looks fine even when the per-frame clears are wrong).
//
// Opt-in (does not run under a normal `flutter test`):
//   DUMP_ROT=1 fvm flutter test test/render/rotation_dump_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/math/tables.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/integration/sprite_adapter.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/world.dart';

import 'png_writer.dart';
import 'render_support.dart';

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  final bool enabled = Platform.environment['DUMP_ROT'] != null;

  test('dump rotation + walk frames (with sprites) to debug_shots/', () {
    final Uint8List bytes = File('assets/doom1.wad').readAsBytesSync();
    final WadFile wad = WadFile.fromBytes(bytes);
    final World world = World.fromWad(wad, mapName: 'E1M1');
    final Palette palette = Palette.fromWad(wad);
    Directory('debug_shots').createSync(recursive: true);

    // Spin up the play-sim so the level's mobjs (barrels, etc.) exist, and feed
    // them to the renderer via the faithful PlaySpriteAdapter.
    final PlaySim sim = PlaySim(world);
    final SpriteSource sprites = PlaySpriteAdapter(sim, wad);

    final MapThing start =
        world.level.things.firstWhere((MapThing t) => t.type == 1);
    final fixed_t vx = intToFixed(start.x);
    final fixed_t vy = intToFixed(start.y);
    final fixed_t floorZ = floorHeightAt(world, vx, vy);
    final fixed_t vz = toInt32(floorZ + kEyeHeight);
    final angle_t baseAngle = normAngle((kAng45 ~/ 45) * start.angle);

    // 16 rotation steps through 360 degrees (ANG360/16 = 0x10000000).
    for (int i = 0; i < 16; i++) {
      final angle_t a = normAngle(baseAngle + 0x10000000 * i);
      world.viewpoint.set(x: vx, y: vy, z: vz, angle: a);
      final Framebuffer fb = Framebuffer();
      Renderer(framebuffer: fb, world: world).renderPlayerView(sprites);
      writeFramebufferPng(
          'debug_shots/rot_${i.toString().padLeft(2, '0')}.png', fb, palette);
    }

    // Walk forward into the room along the start facing, 3 steps.
    final int fineIdx = (baseAngle >> 19) & 8191;
    for (int s = 0; s < 3; s++) {
      final fixed_t dist = intToFixed((s + 1) * 96);
      final fixed_t nx = toInt32(vx + fixedMul(finecosine[fineIdx], dist));
      final fixed_t ny = toInt32(vy + fixedMul(finesine[fineIdx], dist));
      world.viewpoint.set(x: nx, y: ny, z: vz, angle: baseAngle);
      final Framebuffer fb = Framebuffer();
      Renderer(framebuffer: fb, world: world).renderPlayerView(sprites);
      writeFramebufferPng('debug_shots/walk_$s.png', fb, palette);
    }
  }, skip: enabled ? false : 'set DUMP_ROT=1 to write debug PNGs');
}
