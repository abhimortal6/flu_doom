import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/state/dummy_player_status.dart';
import 'package:flu_doom/game/state/interfaces.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/hud/status_bar.dart';

WadFile _loadWad() {
  final Uint8List bytes =
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync());
  return WadFile.fromBytes(bytes);
}

int _nonZeroPixels(Framebuffer fb, int y0, int y1) {
  int count = 0;
  for (int y = y0; y < y1; y++) {
    for (int x = 0; x < fb.width; x++) {
      if (fb.getPixel(x, y) != 0) count++;
    }
  }
  return count;
}

void main() {
  test('status bar lumps load (STBAR, fonts, STARMS, face)', () {
    final WadFile wad = _loadWad();
    final GraphicsCache gc = GraphicsCache(wad);
    expect(gc.has('STBAR'), isTrue);
    expect(gc.has('STTNUM0'), isTrue);
    expect(gc.has('STTPRCNT'), isTrue);
    expect(gc.has('STYSNUM0'), isTrue);
    expect(gc.has('STARMS'), isTrue);
    expect(gc.has('STFST00'), isTrue);
    expect(gc.has('STFGOD0'), isTrue);
  });

  test('ST_Drawer renders the bar into the bottom 32 rows (non-blank)', () {
    final WadFile wad = _loadWad();
    final StatusBar bar = StatusBar(GraphicsCache(wad));
    final Framebuffer fb = Framebuffer();
    fb.clear(0);
    final DummyPlayerStatus p = DummyPlayerStatus()
      ..health = 100
      ..armor = 50
      ..ammoCounts[AmmoType.clip] = 42;

    // tick a few times to settle the face animation, then draw.
    for (int i = 0; i < 4; i++) {
      bar.tick(p);
    }
    bar.draw(fb, p);

    // The bar occupies y 168..199; assert many non-zero pixels there.
    final int barPixels =
        _nonZeroPixels(fb, StatusBar.barY, StatusBar.barY + StatusBar.barHeight);
    expect(barPixels, greaterThan(1000),
        reason: 'STBAR + numbers + face should fill the bar region');

    // The 3D-view region above the bar must stay untouched (still 0).
    final int aboveBar = _nonZeroPixels(fb, 0, StatusBar.barY);
    expect(aboveBar, 0,
        reason: 'status bar must not draw above its 32-row region');
  });

  test('face changes to dead when health <= 0', () {
    final WadFile wad = _loadWad();
    final StatusBar bar = StatusBar(GraphicsCache(wad));
    final Framebuffer fbAlive = Framebuffer()..clear(0);
    final Framebuffer fbDead = Framebuffer()..clear(0);
    final DummyPlayerStatus alive = DummyPlayerStatus()..health = 100;
    final DummyPlayerStatus dead = DummyPlayerStatus()..health = 0;

    bar.draw(fbAlive, alive);
    bar.draw(fbDead, dead);

    // The face region should differ between alive and dead.
    bool differs = false;
    for (int y = StatusBar.faceY; y < StatusBar.faceY + 32 && !differs; y++) {
      for (int x = StatusBar.faceX; x < StatusBar.faceX + 40; x++) {
        if (fbAlive.getPixel(x, y) != fbDead.getPixel(x, y)) {
          differs = true;
          break;
        }
      }
    }
    expect(differs, isTrue, reason: 'dead face must differ from alive face');
  });
}
