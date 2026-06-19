// Doom "patch" / picture format decoder, ported from R_DrawPatch logic in
// Chocolate Doom (src/r_data.c, src/v_video.c) and the patch_t struct in
// src/r_defs.h.
//
// Header (little-endian):
//   int16 width, int16 height, int16 leftoffset, int16 topoffset
//   uint32 columnofs[width]   -- byte offsets (from patch start) of each column
//
// Each column is a series of "posts":
//   uint8 topdelta            -- y of the post (0xFF = end of column)
//   uint8 length              -- number of pixels
//   uint8 unused              -- padding byte (ignored)
//   uint8 pixels[length]      -- palette indices
//   uint8 unused              -- padding byte (ignored)
// Posts repeat until topdelta == 0xFF.
//
// Transparent pixels (gaps between posts) are left untouched in the target.

import 'dart:typed_data';

import 'framebuffer.dart';

/// A decoded Doom patch. Pixels not covered by any post are transparent
/// (represented by index -1 in [pixelAt]).
class Patch {
  Patch({
    required this.width,
    required this.height,
    required this.leftOffset,
    required this.topOffset,
    required this.bytes,
    required this.columnOffsets,
  });

  final int width;
  final int height;
  final int leftOffset;
  final int topOffset;

  final Uint8List bytes;
  final Uint32List columnOffsets;

  /// Parse a patch from raw lump bytes.
  factory Patch.fromBytes(Uint8List bytes) {
    final ByteData bd = ByteData.sublistView(bytes);
    final int width = bd.getInt16(0, Endian.little);
    final int height = bd.getInt16(2, Endian.little);
    final int leftOffset = bd.getInt16(4, Endian.little);
    final int topOffset = bd.getInt16(6, Endian.little);
    final Uint32List columnOffsets = Uint32List(width);
    for (int i = 0; i < width; i++) {
      columnOffsets[i] = bd.getUint32(8 + i * 4, Endian.little);
    }
    return Patch(
      width: width,
      height: height,
      leftOffset: leftOffset,
      topOffset: topOffset,
      bytes: bytes,
      columnOffsets: columnOffsets,
    );
  }

  /// Draw this patch into [fb] with its top-left at (x, y) in framebuffer
  /// space, honouring transparency (gaps left untouched). This is the
  /// equivalent of V_DrawPatch (without scaling). Pixels outside the
  /// framebuffer are clipped.
  void draw(Framebuffer fb, int x, int y) {
    final Uint8List src = bytes;
    final Uint8List dst = fb.pixels;
    final int fbw = fb.width;
    final int fbh = fb.height;
    for (int col = 0; col < width; col++) {
      final int destX = x + col;
      if (destX < 0 || destX >= fbw) continue;
      int p = columnOffsets[col];
      // Walk posts.
      while (true) {
        final int topDelta = src[p];
        if (topDelta == 0xFF) break;
        final int len = src[p + 1];
        int srcPos = p + 3; // skip topdelta, length, unused
        for (int i = 0; i < len; i++) {
          final int destY = y + topDelta + i;
          if (destY >= 0 && destY < fbh) {
            dst[destY * fbw + destX] = src[srcPos];
          }
          srcPos++;
        }
        p += len + 4; // topdelta, length, unused, pixels[len], unused
      }
    }
  }
}
