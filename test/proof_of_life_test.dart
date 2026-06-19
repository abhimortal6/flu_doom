// Proof-of-life integration test: loads the REAL shareware doom1.wad, builds
// the palette, decodes TITLEPIC, blits it into the framebuffer, and verifies
// the pipeline produced sensible pixel data. Runs the exact runtime path
// (minus the dart:ui Image decode, which needs a live engine).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';
import 'package:flu_doom/engine/video/patch.dart';
import 'package:flu_doom/engine/wad/wad.dart';

void main() {
  test('decode TITLEPIC from real doom1.wad and blit to framebuffer', () {
    final File f = File('assets/doom1.wad');
    expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');

    final Uint8List bytes = f.readAsBytesSync();
    final WadFile wad = WadFile.fromBytes(bytes);

    expect(wad.isIwad, true);
    expect(wad.numLumps, greaterThan(1000));
    expect(wad.hasLump('PLAYPAL'), true);
    expect(wad.hasLump('COLORMAP'), true);
    expect(wad.hasLump('TITLEPIC'), true);

    final Palette palette = Palette.fromWad(wad);
    final Colormap colormap = Colormap.fromWad(wad);
    expect(palette.argb.length, 256);
    // Every palette entry must be opaque.
    for (final int c in palette.argb) {
      expect((c >> 24) & 0xFF, 0xFF);
    }
    // Standard Doom COLORMAP has 34 maps.
    expect(colormap.numMaps, 34);

    final Patch title = Patch.fromBytes(wad.getLump('TITLEPIC').bytes);
    expect(title.width, 320);
    expect(title.height, 200);

    final Framebuffer fb = Framebuffer();
    fb.clear(0);
    title.draw(fb, 0, 0);

    // A full-screen TITLEPIC must cover essentially every pixel; ensure the
    // framebuffer is not blank and uses many distinct palette indices.
    final Set<int> used = <int>{};
    int nonZero = 0;
    for (final int p in fb.pixels) {
      used.add(p);
      if (p != 0) nonZero++;
    }
    expect(nonZero, greaterThan(fb.pixels.length ~/ 2),
        reason: 'TITLEPIC should fill most of the screen');
    expect(used.length, greaterThan(32),
        reason: 'TITLEPIC should use many palette colors');

    // Convert through the palette to RGBA and sanity-check size + opacity.
    final Uint8List rgba = fb.toRgba(palette);
    expect(rgba.length, fb.width * fb.height * 4);
    expect(rgba[3], 0xFF); // first pixel alpha opaque
  });
}
