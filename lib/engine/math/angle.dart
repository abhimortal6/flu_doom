// Binary Angle Measurement (BAM) angles, ported from Chocolate Doom tables.h.
//
// `angle_t` is an unsigned 32-bit integer where the full circle is 2^32.
// Dart ints are signed 64-bit, so we keep angles masked to 32 bits and treat
// them as unsigned by masking. Index helpers feed the trig tables.

import 'dart:typed_data';

import 'fixed.dart';
import 'tables.dart';

/// `angle_t` type alias: an unsigned 32-bit BAM angle stored in a Dart int.
/// Always keep within [0, 0xFFFFFFFF] via [normAngle].
// ignore: camel_case_types
typedef angle_t = int;

/// Number of entries in the fine trig tables (one full circle).
const int kFineAngles = 8192;

/// Mask for a fine-angle index.
const int kFineMask = kFineAngles - 1;

/// Shift to convert an [angle_t] to a fine-angle index. (ANGLETOFINESHIFT.)
const int kAngleToFineShift = 19;

/// BAM constants (full circle = 2^32).
const int kAng45 = 0x20000000;
const int kAng90 = 0x40000000;
const int kAng180 = 0x80000000;
const int kAng270 = 0xC0000000;
const int kAngMax = 0xFFFFFFFF;

/// One degree in BAM.
const int kAng1 = kAng45 ~/ 45;

/// Slope range for [tantoangle] lookups. (SLOPERANGE.)
const int kSlopeRange = 2048;
const int kSlopeBits = 11;

/// Mask any value to an unsigned 32-bit [angle_t].
int normAngle(int a) => a & 0xFFFFFFFF;

/// Convert an [angle_t] to a fine-angle table index [0, kFineAngles).
int angleToFineIndex(int angle) =>
    (normAngle(angle) >> kAngleToFineShift) & kFineMask;

/// sin(angle) as a 16.16 [fixed_t].
int sineOf(int angle) => finesine[angleToFineIndex(angle)];

/// cos(angle) as a 16.16 [fixed_t].
int cosineOf(int angle) =>
    finesine[(angleToFineIndex(angle) + kFineAngles ~/ 4) % finesine.length];

/// tan(angle) as a 16.16 [fixed_t]. Uses the 4096-entry finetangent table;
/// the caller is responsible for keeping the index in range as vanilla does.
int tangentOf(int fineIndex) => finetangent[fineIndex & (kFineAngles ~/ 2 - 1)];

/// SlopeDiv, ported verbatim from Chocolate Doom tables.c. Returns an index
/// into [tantoangle] given an unsigned numerator/denominator.
int slopeDiv(int num, int den) {
  if (den < 512) {
    return kSlopeRange;
  }
  final int ans = (num << 3) ~/ (den >> 8);
  return ans <= kSlopeRange ? ans : kSlopeRange;
}

/// Re-export the raw tables for renderers that index them directly.
Int32List get fineSineTable => finesine;
Int32List get fineCosineTable => finecosine;
Int32List get fineTangentTable => finetangent;
Uint32List get tanToAngleTable => tantoangle;
