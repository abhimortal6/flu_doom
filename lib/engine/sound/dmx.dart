// DMX digital sound effect (DS*) lump decoder.
//
// Ported faithfully from Chocolate Doom src/i_sdlsound.c (CacheSFX). A Doom
// `DS<name>` lump is the DMX "digitized sound" format:
//
//   offset 0  u16  format           (always 3)
//   offset 2  u16  sample rate       (Hz, little-endian; usually 11025)
//   offset 4  u32  sample count      (little-endian; total incl. pad)
//   offset 8  ...  8-bit UNSIGNED PCM mono samples
//
// The DMX sound library skips the first 16 and last 16 bytes of the sample
// region (per i_sdlsound.c CacheSFX: `data += 16; length -= 32;`). The header
// is 8 bytes, so the meaningful samples begin at offset 8 + 16 = 24, and the
// usable sample count is `sampleCount - 32`.
//
// Validation matches vanilla CacheSFX:
//   - lump length >= 8 and data[0]==0x03, data[1]==0x00 (format 3),
//   - declared length must fit (length <= lumplen - 8) and length > 48
//     (DMX discards lumps under 49 samples).
//
// Output: a little-endian 16-bit mono PCM WAV (the portable, widely-accepted
// buffer for the audio backend). 8-bit unsigned [0..255] is centred at 128 and
// scaled to signed 16-bit. The original sample rate is preserved in the WAV
// header so the backend resamples to its mixer rate.

import 'dart:typed_data';

/// Thrown when a DS* lump is not a valid DMX format-3 sound.
class DmxException implements Exception {
  DmxException(this.message);
  final String message;
  @override
  String toString() => 'DmxException: $message';
}

/// A decoded DMX sound effect.
class DmxSound {
  DmxSound({
    required this.sampleRate,
    required this.sampleCount,
    required this.samples,
  });

  /// Sample rate in Hz (from the lump header; usually 11025).
  final int sampleRate;

  /// Number of usable mono samples (after stripping the 32 pad bytes).
  final int sampleCount;

  /// The usable 8-bit UNSIGNED PCM samples (a zero-copy view of the lump).
  final Uint8List samples;

  /// Encode as a little-endian 16-bit mono PCM WAV buffer. 8-bit unsigned
  /// samples are centred (s - 128) and scaled to signed 16-bit. This is the
  /// buffer handed to the audio plugin (loadMem).
  Uint8List toWav() {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final int blockAlign = channels * (bitsPerSample ~/ 8);
    final int dataBytes = sampleCount * blockAlign;
    final int totalBytes = 44 + dataBytes;

    final ByteData bd = ByteData(totalBytes);
    int p = 0;
    void putAscii(String s) {
      for (int i = 0; i < s.length; i++) {
        bd.setUint8(p++, s.codeUnitAt(i));
      }
    }

    // RIFF header.
    putAscii('RIFF');
    bd.setUint32(p, totalBytes - 8, Endian.little);
    p += 4;
    putAscii('WAVE');

    // fmt chunk.
    putAscii('fmt ');
    bd.setUint32(p, 16, Endian.little); // PCM fmt chunk size
    p += 4;
    bd.setUint16(p, 1, Endian.little); // audio format = PCM
    p += 2;
    bd.setUint16(p, channels, Endian.little);
    p += 2;
    bd.setUint32(p, sampleRate, Endian.little);
    p += 4;
    bd.setUint32(p, byteRate, Endian.little);
    p += 4;
    bd.setUint16(p, blockAlign, Endian.little);
    p += 2;
    bd.setUint16(p, bitsPerSample, Endian.little);
    p += 2;

    // data chunk.
    putAscii('data');
    bd.setUint32(p, dataBytes, Endian.little);
    p += 4;
    for (int i = 0; i < sampleCount; i++) {
      // unsigned 8-bit [0..255] -> signed 16-bit.
      final int s16 = (samples[i] - 128) << 8;
      bd.setInt16(p, s16, Endian.little);
      p += 2;
    }
    return bd.buffer.asUint8List();
  }
}

/// Parse a DMX `DS*` sound lump. Throws [DmxException] on an invalid lump.
///
/// 1:1 with i_sdlsound.c CacheSFX header parsing + pad stripping.
DmxSound decodeDmx(Uint8List data) {
  final int lumplen = data.length;

  // Validate header (CacheSFX: lumplen < 8 || data[0] != 0x03 || data[1] != 0).
  if (lumplen < 8 || data[0] != 0x03 || data[1] != 0x00) {
    throw DmxException('Not a DMX format-3 sound (len=$lumplen)');
  }

  // u16 sample rate, u32 length (little-endian), per CacheSFX.
  final int sampleRate = (data[3] << 8) | data[2];
  final int length =
      (data[7] << 24) | (data[6] << 16) | (data[5] << 8) | data[4];

  // CacheSFX: discard if declared length overruns the lump or is too short.
  if (length > lumplen - 8 || length <= 48) {
    throw DmxException(
        'Invalid DMX length=$length (lumplen=$lumplen, rate=$sampleRate)');
  }

  // DMX skips the first 16 and last 16 bytes of the sample region. The header
  // is 8 bytes, so usable samples start at offset 24 and span (length - 32).
  final int sampleStart = 8 + 16;
  final int sampleCount = length - 32;
  final Uint8List samples =
      Uint8List.sublistView(data, sampleStart, sampleStart + sampleCount);

  return DmxSound(
    sampleRate: sampleRate,
    sampleCount: sampleCount,
    samples: samples,
  );
}
