// Texture, flat and sprite resolution, ported from Chocolate Doom
// src/r_data.c (R_InitData / R_InitTextures / R_InitFlats / R_InitSpriteLumps).
//
// - PNAMES: a list of 8-char patch names; index -> WAD lump number for that
//   patch (Doom picture format).
// - TEXTURE1 (+ TEXTURE2 if present): composite texture definitions. Each
//   texture is a name, size, and a list of patches placed at offsets.
// - Flats: 64x64 = 4096-byte raw pixel lumps between F_START and F_END.
// - Sprites: patches between S_START and S_END (we index them; decoding is the
//   patch system's job).
//
// Composite texture COLUMN data is generated ON DEMAND and cached. A texture's
// column is a 1-byte-per-pixel run of palette indices `height` tall; "holes"
// (uncovered rows, only possible on a single-patched texture wider/taller than
// its patch) are left as 0 — vanilla likewise leaves garbage there and the
// renderer never samples masked single-patch walls in those rows.

import 'dart:typed_data';

import '../wad/wad.dart';

/// One patch placement inside a composite texture. Vanilla `mappatch_t` /
/// `texpatch_t`.
class TexPatch {
  TexPatch(this.originX, this.originY, this.patchLump);

  /// X offset of this patch within the texture (whole pixels).
  final int originX;

  /// Y offset of this patch within the texture (whole pixels).
  final int originY;

  /// WAD lump number of the patch (resolved through PNAMES). -1 if the patch
  /// name was not found in the WAD (vanilla would I_Error; we keep -1 so a
  /// single bad patch does not abort the whole load).
  final int patchLump;
}

/// A composite wall texture. Vanilla `texture_t` (metadata only; pixel columns
/// are composited lazily by [Textures]).
class Texture {
  Texture({
    required this.name,
    required this.width,
    required this.height,
    required this.patches,
  });

  /// Uppercased 8-char name.
  final String name;

  /// Texture width in pixels.
  final int width;

  /// Texture height in pixels.
  final int height;

  /// Patches composing this texture.
  final List<TexPatch> patches;
}

/// Texture / flat / sprite lookup tables and on-demand column compositing.
///
/// Build once via [Textures.fromWad]. Texture/flat numbers are stable indices
/// usable as `floorpic`/`ceilingpic` and side texture numbers. Texture 0 is
/// the special "no texture" / "AASHITTY" placeholder; a side texture of 0 means
/// "-" (no texture) in vanilla, and the renderer treats it as such.
class Textures {
  Textures._(
    this._wad,
    this._textures,
    this._textureByName,
    this._flatStart,
    this._flatCount,
    this._flatByName,
    this._spriteStart,
    this._spriteCount,
    this._spriteByName,
  ) : _textureCache = List<Uint8List?>.filled(_textures.length, null);

  final WadFile _wad;

  // Textures.
  final List<Texture> _textures;
  final Map<String, int> _textureByName;
  // Cached composited pixels per texture: column-major, [col*height + row].
  final List<Uint8List?> _textureCache;

  // Flats: contiguous lump range [F_START+1 .. F_END-1], indexed 0..count-1.
  final int _flatStart; // lump number of first flat
  final int _flatCount;
  final Map<String, int> _flatByName; // name -> flat number (0-based)

  // Sprites: contiguous lump range between S_START and S_END.
  final int _spriteStart; // lump number of first sprite
  final int _spriteCount;
  final Map<String, int> _spriteByName; // name -> sprite number (0-based)

  /// Number of composite textures.
  int get numTextures => _textures.length;

  /// Number of flats.
  int get numFlats => _flatCount;

  /// Number of sprite lumps.
  int get numSprites => _spriteCount;

  /// Build all lookup tables from a WAD. Mirrors R_InitData ordering.
  factory Textures.fromWad(WadFile wad) {
    // --- PNAMES ---
    final ByteData pn = wad.getLump('PNAMES').data;
    final int numPatches = pn.getInt32(0, Endian.little);
    final List<int> patchLumps = List<int>.filled(numPatches, -1);
    for (int i = 0; i < numPatches; i++) {
      final int off = 4 + i * 8;
      final String name = _readName8(pn, off);
      patchLumps[i] = wad.lumpNumForName(name);
    }

    // --- TEXTURE1 / TEXTURE2 ---
    final List<Texture> textures = <Texture>[];
    final Map<String, int> textureByName = <String, int>{};
    for (final String lname in const <String>['TEXTURE1', 'TEXTURE2']) {
      if (!wad.hasLump(lname)) continue;
      _parseTextureLump(wad.getLump(lname).data, patchLumps, wad, textures);
    }
    // Build name map: first definition wins (vanilla R_TextureNumForName uses
    // the first matching entry; later we scan linearly, but map is fine since
    // duplicate texture names are not expected within an IWAD).
    for (int i = 0; i < textures.length; i++) {
      textureByName.putIfAbsent(textures[i].name, () => i);
    }

    // --- Flats (F_START .. F_END) ---
    int fStart = wad.lumpNumForName('F_START');
    int fEnd = wad.lumpNumForName('F_END');
    final Map<String, int> flatByName = <String, int>{};
    int flatStart = 0;
    int flatCount = 0;
    if (fStart >= 0 && fEnd >= 0 && fEnd > fStart) {
      // Vanilla: firstflat = F_START+1, lastflat = F_END-1. Marker lumps
      // (and any zero-size sub-markers like FF_START) are skipped by name.
      flatStart = fStart + 1;
      flatCount = fEnd - 1 - fStart;
      int fnum = 0;
      for (int l = flatStart; l <= fEnd - 1; l++) {
        flatByName.putIfAbsent(wad.lumpByIndex(l).name, () => fnum);
        fnum++;
      }
    }

    // --- Sprites (S_START .. S_END) ---
    int sStart = wad.lumpNumForName('S_START');
    int sEnd = wad.lumpNumForName('S_END');
    final Map<String, int> spriteByName = <String, int>{};
    int spriteStart = 0;
    int spriteCount = 0;
    if (sStart >= 0 && sEnd >= 0 && sEnd > sStart) {
      spriteStart = sStart + 1;
      spriteCount = sEnd - 1 - sStart;
      int snum = 0;
      for (int l = spriteStart; l <= sEnd - 1; l++) {
        spriteByName.putIfAbsent(wad.lumpByIndex(l).name, () => snum);
        snum++;
      }
    }

    final Textures t = Textures._(
      wad,
      textures,
      textureByName,
      flatStart,
      flatCount,
      flatByName,
      spriteStart,
      spriteCount,
      spriteByName,
    );
    return t;
  }

  static void _parseTextureLump(
    ByteData bd,
    List<int> patchLumps,
    WadFile wad,
    List<Texture> out,
  ) {
    final int numTextures = bd.getInt32(0, Endian.little);
    for (int i = 0; i < numTextures; i++) {
      final int dirOff = bd.getInt32(4 + i * 4, Endian.little);
      // maptexture_t: name[8], masked(int32), width(int16), height(int16),
      // columndirectory(int32, unused), patchcount(int16), patches[...]
      final String name = _readName8(bd, dirOff);
      final int width = bd.getInt16(dirOff + 12, Endian.little);
      final int height = bd.getInt16(dirOff + 14, Endian.little);
      final int patchCount = bd.getInt16(dirOff + 20, Endian.little);
      final List<TexPatch> patches = <TexPatch>[];
      int p = dirOff + 22;
      for (int j = 0; j < patchCount; j++) {
        final int originX = bd.getInt16(p, Endian.little);
        final int originY = bd.getInt16(p + 2, Endian.little);
        final int patchNum = bd.getInt16(p + 4, Endian.little);
        // p+6 stepdir, p+8 colormap (both unused in vanilla composite).
        final int lump =
            (patchNum >= 0 && patchNum < patchLumps.length)
                ? patchLumps[patchNum]
                : -1;
        patches.add(TexPatch(originX, originY, lump));
        p += 10;
      }
      out.add(Texture(
          name: name, width: width, height: height, patches: patches));
    }
  }

  static String _readName8(ByteData bd, int off) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 8; i++) {
      final int c = bd.getUint8(off + i);
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString().toUpperCase();
  }

  // ---- Texture lookups ----

  /// Texture metadata by number.
  Texture texture(int num) => _textures[num];

  /// R_CheckTextureNumForName: returns -1 if not found. Texture name "-"
  /// (no texture) maps to 0 in vanilla side loading; callers handle "-".
  int checkTextureNumForName(String name) {
    if (name.startsWith('-')) return 0;
    return _textureByName[name.toUpperCase()] ?? -1;
  }

  /// R_TextureNumForName: like [checkTextureNumForName] but returns 0 (the
  /// placeholder texture) instead of -1 so callers never index out of range.
  /// Vanilla I_Errors; we degrade gracefully for a partial/PWAD-less IWAD.
  int textureNumForName(String name) {
    final int n = checkTextureNumForName(name);
    return n < 0 ? 0 : n;
  }

  /// Composited pixels for a texture, column-major: index = col*height + row.
  /// Cached after first call. Length = width*height. Faithful to
  /// R_GenerateComposite drawing each patch's posts into the texture.
  Uint8List textureColumns(int texNum) {
    final Uint8List? cached = _textureCache[texNum];
    if (cached != null) return cached;
    final Texture tex = _textures[texNum];
    final Uint8List pixels = Uint8List(tex.width * tex.height);
    for (final TexPatch tp in tex.patches) {
      if (tp.patchLump < 0) continue;
      _drawPatchInto(pixels, tex.width, tex.height, tp);
    }
    _textureCache[texNum] = pixels;
    return pixels;
  }

  /// A single composited column (height pixels) of a texture (zero-copy view).
  Uint8List textureColumn(int texNum, int col) {
    final Texture tex = _textures[texNum];
    final Uint8List all = textureColumns(texNum);
    final int c = col % tex.width;
    return Uint8List.sublistView(all, c * tex.height, (c + 1) * tex.height);
  }

  // Decode a patch (Doom picture format) directly into the texture buffer at
  // the patch's origin, in column-major order. Mirrors the post loop in
  // R_DrawColumnInCache / R_GenerateComposite.
  void _drawPatchInto(
      Uint8List dest, int texWidth, int texHeight, TexPatch tp) {
    final ByteData pd = _wad.lumpByIndex(tp.patchLump).data;
    final int pWidth = pd.getInt16(0, Endian.little);
    // height pd.getInt16(2); leftoffset pd.getInt16(4); topoffset pd.getInt16(6)
    for (int col = 0; col < pWidth; col++) {
      final int destCol = tp.originX + col;
      if (destCol < 0 || destCol >= texWidth) continue;
      int postOfs = pd.getUint32(8 + col * 4, Endian.little);
      while (true) {
        final int topDelta = pd.getUint8(postOfs);
        if (topDelta == 0xFF) break;
        final int length = pd.getUint8(postOfs + 1);
        // postOfs+2 is an unused pad byte; pixels start at +3.
        final int pixStart = postOfs + 3;
        for (int row = 0; row < length; row++) {
          final int destRow = tp.originY + topDelta + row;
          if (destRow < 0 || destRow >= texHeight) continue;
          dest[destCol * texHeight + destRow] = pd.getUint8(pixStart + row);
        }
        // advance: length + 4 bytes (topdelta, length, pad, pixels[], pad).
        postOfs = pixStart + length + 1;
      }
    }
  }

  // ---- Flat lookups ----

  /// R_FlatNumForName: returns -1 if not found (vanilla I_Errors; we don't).
  int checkFlatNumForName(String name) =>
      _flatByName[name.toUpperCase()] ?? -1;

  /// Like above but returns 0 if not found, so callers never go out of range.
  int flatNumForName(String name) {
    final int n = checkFlatNumForName(name);
    return n < 0 ? 0 : n;
  }

  /// Raw 4096-byte (64x64) pixel data for a flat (zero-copy WAD view).
  /// Index = y*64 + x (row-major), palette indices.
  Uint8List flatPixels(int flatNum) =>
      _wad.lumpByIndex(_flatStart + flatNum).bytes;

  /// WAD lump number backing a flat (for callers that need raw access).
  int flatLumpNum(int flatNum) => _flatStart + flatNum;

  // ---- Sprite lookups ----

  /// Sprite lump number (0-based, into the sprite namespace) for a name, or -1.
  int checkSpriteNumForName(String name) =>
      _spriteByName[name.toUpperCase()] ?? -1;

  /// WAD lump number backing a sprite (for the patch decoder).
  int spriteLumpNum(int spriteNum) => _spriteStart + spriteNum;

  /// Raw sprite patch bytes (Doom picture format; decode with Patch).
  Uint8List spriteBytes(int spriteNum) =>
      _wad.lumpByIndex(_spriteStart + spriteNum).bytes;
}
