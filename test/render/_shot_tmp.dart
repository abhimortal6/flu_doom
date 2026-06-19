import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/world.dart';

void main() {
  test('shot', () {
    final wad = WadFile.fromBytes(File('assets/doom1.wad').readAsBytesSync());
    final world = World.fromWad(wad, mapName: 'E1M1');
    final start = world.level.things.firstWhere((t) => t.type == 1);
    final vx = intToFixed(start.x), vy = intToFixed(start.y);
    final vang = normAngle((start.angle ~/ 45) * kAng45);
    int nn = world.level.rootNode;
    while ((nn & nfSubsector) == 0) {
      final n = world.level.nodes[nn];
      int side;
      if (n.dx == 0) {
        side = vx <= n.x ? (n.dy > 0 ? 1 : 0) : (n.dy < 0 ? 1 : 0);
      } else if (n.dy == 0) {
        side = vy <= n.y ? (n.dx < 0 ? 1 : 0) : (n.dx > 0 ? 1 : 0);
      } else {
        final dx = toInt32(vx - n.x), dy = toInt32(vy - n.y);
        side = fixedMul(dy, n.dx >> 16) < fixedMul(n.dy >> 16, dx) ? 0 : 1;
      }
      nn = n.children[side];
    }
    final ss = world.level.subsectors[nn & ~nfSubsector];
    world.viewpoint.set(
        x: vx,
        y: vy,
        z: toInt32(ss.sector.floorHeight + 41 * kFracUnit),
        angle: vang);
    final fb = Framebuffer();
    Renderer(framebuffer: fb, world: world)
        .renderPlayerView(const EmptySpriteSource());
    final pal = Palette.fromWad(wad);
    // write a PPM (P6) using the palette so we can view colors faithfully.
    final out = BytesBuilder();
    out.add('P6\n320 200\n255\n'.codeUnits);
    for (int i = 0; i < fb.pixels.length; i++) {
      final c = pal.argb[fb.pixels[i]];
      out.addByte((c >> 16) & 0xFF);
      out.addByte((c >> 8) & 0xFF);
      out.addByte(c & 0xFF);
    }
    File('/tmp/doomshots/frame.ppm').writeAsBytesSync(out.toBytes());
    print('wrote /tmp/doomshots/frame.ppm');
  });
}
