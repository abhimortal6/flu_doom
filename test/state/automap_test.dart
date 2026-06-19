import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/ui/automap/automap.dart';

World _loadWorld() {
  final Uint8List bytes =
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync());
  final WadFile wad = WadFile.fromBytes(bytes);
  return World.fromWad(wad, mapName: 'E1M1');
}

void main() {
  test('AM_Drawer draws E1M1 line geometry (non-blank, lines > 0)', () {
    final World world = _loadWorld();
    expect(world.level.lines.length, greaterThan(0));

    final Automap am = Automap()..revealAll = true;
    am.open(world);
    final Framebuffer fb = Framebuffer()..clear(0);
    am.draw(fb, world);

    expect(am.linesDrawn, greaterThan(100),
        reason: 'E1M1 has hundreds of lines and most should map to pixels');

    int nonZero = 0;
    for (int i = 0; i < fb.pixels.length; i++) {
      if (fb.pixels[i] != 0) nonZero++;
    }
    expect(nonZero, greaterThan(500),
        reason: 'projected line geometry should fill many pixels');
  });

  test('AM_Responder toggles with Tab and pans/zooms', () {
    final Automap am = Automap();
    expect(am.active, isFalse);

    // Tab toggles on.
    expect(am.responder(const DoomEvent.keyDown(DoomKey.tab)), isTrue);
    expect(am.active, isTrue);

    // Pan disables follow and is consumed.
    expect(am.responder(const DoomEvent.keyDown(DoomKey.upArrow)), isTrue);

    // Tab toggles off.
    expect(am.responder(const DoomEvent.keyDown(DoomKey.tab)), isTrue);
    expect(am.active, isFalse);
  });
}
