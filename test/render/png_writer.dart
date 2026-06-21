// Minimal RGBA PNG encoder for debug dumps (zlib via dart:io ZLibCodec).

import 'dart:io';
import 'dart:typed_data';

import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/palette.dart';

void writeFramebufferPng(String path, Framebuffer fb, Palette palette) {
  writeRgbaPng(path, fb.toRgba(palette), fb.width, fb.height);
}

/// Encode an arbitrary RGBA8888 byte buffer (length == w*h*4) to a PNG file.
void writeRgbaPng(String path, Uint8List rgba, int w, int h) {
  final BytesBuilder raw = BytesBuilder();
  for (int y = 0; y < h; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgba, y * w * 4, (y + 1) * w * 4));
  }
  final Uint8List compressed =
      ZLibCodec(level: 6).encode(raw.toBytes()) as Uint8List;

  final BytesBuilder png = BytesBuilder();
  png.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final Uint8List td = Uint8List.fromList(type.codeUnits);
    png.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    png.add(td);
    png.add(data);
    final Uint8List crcData = Uint8List(td.length + data.length)
      ..setRange(0, td.length, td)
      ..setRange(td.length, td.length + data.length, data);
    png.add((ByteData(4)..setUint32(0, _crc32(crcData))).buffer.asUint8List());
  }

  final ByteData ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', compressed);
  chunk('IEND', <int>[]);
  File(path).writeAsBytesSync(png.toBytes());
}

int _crc32(List<int> data) {
  int crc = 0xFFFFFFFF;
  for (final int b in data) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
