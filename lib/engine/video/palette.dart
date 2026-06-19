// Palette (PLAYPAL) and colormap (COLORMAP) handling.
//
// PLAYPAL: 14 palettes, each 256 entries of 3 bytes (R,G,B). Palette 0 is the
// base/normal palette; others are damage/bonus/radsuit tints (unused this
// phase). We expose palette 0 as a 256-entry ARGB table for the framebuffer.
//
// COLORMAP: 34 colormaps, each 256 bytes, mapping a palette index to another
// palette index for a given light level / effect. Map 0 = brightest,
// 31 = darkest, 32 = invulnerability inverse map, 33 unused.

import 'dart:typed_data';

import '../wad/wad.dart';

/// A 256-entry color palette converted to 32-bit ARGB (0xAARRGGBB) values,
/// ready to splat into a framebuffer.
class Palette {
  Palette(this.argb) : assert(argb.length == 256);

  /// 256 ARGB colors. Alpha is always 0xFF (opaque).
  final Uint32List argb;

  /// Build the base palette (palette index 0) from a PLAYPAL lump.
  factory Palette.fromPlaypal(Uint8List playpal, {int paletteIndex = 0}) {
    final Uint32List out = Uint32List(256);
    final int base = paletteIndex * 768;
    for (int i = 0; i < 256; i++) {
      final int o = base + i * 3;
      final int r = playpal[o];
      final int g = playpal[o + 1];
      final int b = playpal[o + 2];
      out[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
    }
    return Palette(out);
  }

  /// Convenience: load palette 0 from a WAD's PLAYPAL lump.
  factory Palette.fromWad(WadFile wad) =>
      Palette.fromPlaypal(wad.getLump('PLAYPAL').bytes);

  /// Number of distinct palettes in a standard PLAYPAL lump.
  static const int paletteCount = 14;
}

/// COLORMAP: index-remap tables for light diminishing and special effects.
class Colormap {
  Colormap(this.maps, this.numMaps);

  /// Flat array: maps[mapIndex * 256 + paletteIndex] -> remapped index.
  final Uint8List maps;

  /// Number of 256-byte colormaps loaded.
  final int numMaps;

  /// Look up a remapped palette index for the given colormap and source index.
  int remap(int mapIndex, int paletteIndex) =>
      maps[mapIndex * 256 + paletteIndex];

  /// View of a single 256-byte colormap (zero-copy).
  Uint8List mapAt(int mapIndex) =>
      Uint8List.sublistView(maps, mapIndex * 256, mapIndex * 256 + 256);

  /// Load from a COLORMAP lump.
  factory Colormap.fromLump(Uint8List colormap) {
    final int numMaps = colormap.length ~/ 256;
    return Colormap(Uint8List.fromList(colormap.sublist(0, numMaps * 256)),
        numMaps);
  }

  /// Convenience: load from a WAD's COLORMAP lump.
  factory Colormap.fromWad(WadFile wad) =>
      Colormap.fromLump(wad.getLump('COLORMAP').bytes);
}
