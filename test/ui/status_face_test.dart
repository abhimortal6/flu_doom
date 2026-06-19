// Verifies the status-bar face widget cadence is vanilla-faithful (st_stuff.c
// ST_updateFaceWidget): the idle look-left/right/forward cycle holds each face
// for ST_STRAIGHTFACECOUNT (TICRATE/2 = ~17) tics rather than flickering every
// tic, and special states (god/dead) take priority.

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/patch.dart';
import 'package:flu_doom/game/state/dummy_player_status.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/hud/status_bar.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'dart:io';
import 'dart:typed_data';

// Capture the face glyph each tic by hashing the face region of the rendered
// bar; if the face holds, consecutive tics produce identical face pixels.
int _faceRegionHash(Framebuffer fb) {
  int h = 0;
  // Face region (ST_FACESX=143, y=168, ~24x32).
  for (int y = 168; y < 200; y++) {
    for (int x = 143; x < 167; x++) {
      h = (h * 31 + fb.getPixel(x, y)) & 0x7fffffff;
    }
  }
  return h;
}

void main() {
  final File wadFile = File('assets/doom1.wad');

  test('idle face holds for several tics (not per-tic flicker)', () {
    final WadFile wad = WadFile.fromBytes(wadFile.readAsBytesSync());
    final GraphicsCache gc = GraphicsCache(wad);
    final StatusBar bar = StatusBar(gc);
    final DummyPlayerStatus p = DummyPlayerStatus()..health = 100;

    // Tick 40 tics, record the face hash each tic.
    final List<int> hashes = <int>[];
    for (int t = 0; t < 40; t++) {
      bar.tick(p);
      final Framebuffer fb = Framebuffer();
      bar.draw(fb, p);
      hashes.add(_faceRegionHash(fb));
    }

    // Count how many tics the face CHANGED from the previous tic. With a
    // faithful ST_STRAIGHTFACECOUNT (~17 tic) hold, there should be very few
    // changes across 40 tics (a per-tic flicker would change ~every tic).
    int changes = 0;
    for (int i = 1; i < hashes.length; i++) {
      if (hashes[i] != hashes[i - 1]) changes++;
    }
    expect(changes, lessThan(6),
        reason: 'face flickered $changes times in 40 tics (should hold ~17 '
            'tics per straight face)');
  });

  test('dead player shows the dead face immediately', () {
    final WadFile wad = WadFile.fromBytes(wadFile.readAsBytesSync());
    final GraphicsCache gc = GraphicsCache(wad);
    final StatusBar bar = StatusBar(gc);
    final DummyPlayerStatus alive = DummyPlayerStatus()..health = 100;
    final DummyPlayerStatus dead = DummyPlayerStatus()..health = 0;

    bar.tick(alive);
    final Framebuffer aliveFb = Framebuffer();
    bar.draw(aliveFb, alive);
    final int aliveHash = _faceRegionHash(aliveFb);

    // Now the player dies.
    bar.tick(dead);
    final Framebuffer deadFb = Framebuffer();
    bar.draw(deadFb, dead);
    final int deadHash = _faceRegionHash(deadFb);

    expect(deadHash, isNot(equals(aliveHash)),
        reason: 'dead face should differ from the alive face');
  });

  test('face glyphs are loaded (STFST00 decodes)', () {
    final WadFile wad = WadFile.fromBytes(wadFile.readAsBytesSync());
    final GraphicsCache gc = GraphicsCache(wad);
    final Patch? face = gc.patch('STFST00');
    expect(face, isNotNull);
    expect(face!.width, greaterThan(0));
    // Silence unused import lint.
    expect(Uint8List(0).length, 0);
  });
}
