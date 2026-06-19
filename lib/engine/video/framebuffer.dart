// Indexed framebuffer (Doom's screen buffer) and conversion to a dart:ui Image.
//
// Doom renders into a 320x200 8-bit indexed surface (SCREENWIDTH x
// SCREENHEIGHT). Renderers write palette indices directly. To display, we
// convert through the active palette into RGBA8888 and decode to a ui.Image
// with nearest-neighbour filtering at draw time.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'palette.dart';

/// Doom screen dimensions.
const int kScreenWidth = 320;
const int kScreenHeight = 200;

/// An 8-bit indexed framebuffer. Renderers obtain [pixels] and write palette
/// indices. Coordinates are row-major: index = y * width + x.
class Framebuffer {
  Framebuffer({this.width = kScreenWidth, this.height = kScreenHeight})
      : pixels = Uint8List(width * height),
        _rgba = Uint8List(width * height * 4);

  final int width;
  final int height;

  /// Indexed pixel data (palette indices). Length == width*height.
  /// Renderers write here directly.
  final Uint8List pixels;

  final Uint8List _rgba;

  /// Clear the whole surface to palette index [color] (default 0).
  void clear([int color = 0]) {
    pixels.fillRange(0, pixels.length, color);
  }

  /// Write a single pixel (bounds-checked-free hot path; caller ensures range).
  void setPixel(int x, int y, int colorIndex) {
    pixels[y * width + x] = colorIndex;
  }

  /// Read a single pixel's palette index.
  int getPixel(int x, int y) => pixels[y * width + x];

  /// Convert the indexed buffer to packed RGBA8888 bytes using [palette].
  /// The result is stored in an internal reusable buffer and returned.
  Uint8List toRgba(Palette palette) {
    final Uint32List argb = palette.argb;
    final Uint8List rgba = _rgba;
    final Uint8List px = pixels;
    int o = 0;
    for (int i = 0; i < px.length; i++) {
      final int c = argb[px[i]];
      rgba[o++] = (c >> 16) & 0xFF; // R
      rgba[o++] = (c >> 8) & 0xFF; // G
      rgba[o++] = c & 0xFF; // B
      rgba[o++] = (c >> 24) & 0xFF; // A
    }
    return rgba;
  }

  /// Decode the current indexed buffer (via [palette]) into a ui.Image.
  /// Uses RGBA8888 straight pixel format with nearest-neighbour scaling
  /// applied later at draw time (see VideoView).
  Future<ui.Image> toImage(Palette palette) async {
    final Uint8List rgba = toRgba(palette);
    // fromUint8List copies the bytes, so reusing [_rgba] across frames is safe.
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    buffer.dispose();
    descriptor.dispose();
    codec.dispose();
    return frame.image;
  }
}
