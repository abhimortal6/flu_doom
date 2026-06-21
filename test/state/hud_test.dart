import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/hud/hud.dart';

GraphicsCache _gc() {
  final Uint8List bytes =
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync());
  return GraphicsCache(WadFile.fromBytes(bytes));
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  test('HUD font loads (STCFN glyphs)', () {
    final GraphicsCache gc = _gc();
    expect(gc.has('STCFN065'), isTrue); // 'A'
  });

  test('message posts, draws, and times out', () {
    final Hud hud = Hud(_gc());
    expect(hud.hasMessage, isFalse);

    hud.postMessage('PICKED UP A CLIP.');
    expect(hud.hasMessage, isTrue);

    final Framebuffer fb = Framebuffer()..clear(0);
    hud.draw(fb);
    int nonZero = 0;
    // Only check the top message rows.
    for (int y = 0; y < 12; y++) {
      for (int x = 0; x < fb.width; x++) {
        if (fb.getPixel(x, y) != 0) nonZero++;
      }
    }
    expect(nonZero, greaterThan(20), reason: 'message text should render');

    // Tick past the timeout: message clears.
    for (int i = 0; i < Hud.messageTimeout + 1; i++) {
      hud.tick();
    }
    expect(hud.hasMessage, isFalse);
  });
}
