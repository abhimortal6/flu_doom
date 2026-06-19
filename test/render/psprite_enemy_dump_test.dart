// Offline dumps proving (1) the player weapon psprite renders, and (2) a spawned
// enemy renders. Writes debug_shots/gun.png and debug_shots/enemy.png.
//
//   flutter test test/render/psprite_enemy_dump_test.dart
//
// Runs under flutter test (dart:ui-free toRgba). Always writes the PNGs.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/render/psprite_source.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/integration/psprite_adapter.dart';
import 'package:flu_doom/game/integration/sprite_adapter.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/mobj_flags.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/play/thinker.dart';
import 'package:flu_doom/game/world/world.dart';

import 'png_writer.dart';

void main() {
  test('dump gun.png + enemy.png', () {
    final Uint8List bytes = File('assets/doom1.wad').readAsBytesSync();
    final WadFile wad = WadFile.fromBytes(bytes);
    final PlaySim sim = PlaySim(World.fromWad(wad, mapName: 'E1M1'));
    sim.spawnLevel();

    // Let the weapon raise fully to its ready frame (P_BringUpWeapon ->
    // A_Raise climbs to WEAPONTOP, then A_WeaponReady). ~30 tics is plenty.
    for (int i = 0; i < 35; i++) {
      sim.tic();
    }

    final Palette palette = Palette.fromWad(wad);
    Directory('debug_shots').createSync(recursive: true);

    final PlaySpriteAdapter sprites = PlaySpriteAdapter(sim, wad);
    final PlayPspriteAdapter psprites =
        PlayPspriteAdapter(sim, sprites.spriteResolver);

    // --- gun.png: render from the player start with the pistol psprite up. ---
    {
      final Framebuffer fb = Framebuffer();
      Renderer(framebuffer: fb, world: sim.world)
          .renderPlayerView(sprites, psprites);
      writeFramebufferPng('debug_shots/gun.png', fb, palette);

      // Report active psprites.
      final out = <PspriteRequest>[];
      psprites.collect(out);
      stderr.writeln('gun.png: active psprites=${out.length}'
          '${out.map((r) => ' spr=${r.spriteNum} frame=${r.frame}'
              ' sx=${r.sx >> kFracBits} sy=${r.sy >> kFracBits}').join()}');
    }

    // --- enemy.png: face a spawned monster from ~160 units away. ---
    Mobj? monster;
    for (final Thinker t in sim.thinkers.thinkers) {
      if (t is Mobj && (t.flags & mfCountKill) != 0) {
        monster = t;
        break;
      }
    }
    expect(monster, isNotNull, reason: 'no monster spawned');
    final Mobj m = monster!;

    // Camera 160 units from the monster, on the side it faces (so we see its
    // front rotation). Look straight at it.
    const fixed_t dist = 160 * kFracUnit;
    final double ang = m.angle / 4294967296.0 * 2 * math.pi; // BAM -> rad
    final fixed_t camX = toInt32(m.x + (dist * math.cos(ang)).round());
    final fixed_t camY = toInt32(m.y + (dist * math.sin(ang)).round());
    // Eye height 41 above the monster's floor.
    final fixed_t camZ = toInt32(m.floorZ + 41 * kFracUnit);
    // Angle from camera to monster (BAM): atan2 of the reverse vector.
    final double back = math.atan2(
        (m.y - camY) / 65536.0, (m.x - camX) / 65536.0);
    final int camAngle = (back / (2 * math.pi) * 4294967296.0).round() & 0xffffffff;

    sim.world.viewpoint.set(x: camX, y: camY, z: camZ, angle: camAngle);
    stderr.writeln('enemy.png: monster type=${m.type} sprite=${m.sprite}'
        ' at (${m.x >> kFracBits},${m.y >> kFracBits})'
        ' cam=(${camX >> kFracBits},${camY >> kFracBits})');

    {
      final Framebuffer fb = Framebuffer();
      // No psprites for the enemy shot so the weapon doesn't cover it.
      Renderer(framebuffer: fb, world: sim.world).renderPlayerView(sprites);
      writeFramebufferPng('debug_shots/enemy.png', fb, palette);
    }
  });
}
