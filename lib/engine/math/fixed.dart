// Fixed-point (16.16) arithmetic, ported from Chocolate Doom src/m_fixed.{c,h}.
//
// Doom's `fixed_t` is a C `int` (signed 32-bit) interpreted as 16.16
// fixed-point. The arithmetic relies on 32-bit signed integer overflow
// semantics. Dart native ints are 64-bit, so we perform the math in 64-bit
// and mask/sign-extend back to signed 32-bit to reproduce vanilla behaviour
// exactly (including overflow wraparound that real Doom code depends on).
//
// NOTE: This targets Dart NATIVE (AOT) semantics. Web int behaviour is out of
// scope for this phase.

/// Number of fractional bits in a [fixed_t]. (Doom FRACBITS.)
const int kFracBits = 16;

/// 1.0 in 16.16 fixed-point. (Doom FRACUNIT.)
const int kFracUnit = 1 << kFracBits;

/// Maximum/minimum values of a signed 32-bit integer, used by [fixedDiv]'s
/// overflow guard (matches C INT_MAX / INT_MIN).
const int kInt32Max = 0x7FFFFFFF;
const int kInt32Min = -0x80000000;

const int _mask32 = 0xFFFFFFFF;

/// Truncate [v] to a signed 32-bit integer, reproducing C `(int)` cast /
/// overflow wraparound on a 64-bit Dart int.
int toInt32(int v) {
  final int m = v & _mask32;
  // Sign-extend bit 31.
  return (m & 0x80000000) != 0 ? m - 0x100000000 : m;
}

/// `fixed_t` type alias. A 16.16 fixed-point value stored in a Dart int that
/// must be kept within signed 32-bit range by the math helpers below.
///
/// We use a typedef rather than a wrapper class for performance and to mirror
/// the C code; treat any `fixed_t` as a plain [int].
// ignore: camel_case_types
typedef fixed_t = int;

/// Convert an integer to fixed-point (multiply by FRACUNIT).
int intToFixed(int v) => toInt32(v << kFracBits);

/// Truncate a fixed-point value to an integer (arithmetic shift right).
int fixedToInt(int v) => v >> kFracBits;

/// FixedMul: (a * b) >> FRACBITS, in 64-bit then back to signed 32-bit.
///
/// Faithful to Chocolate Doom:
///   `return ((int64_t) a * (int64_t) b) >> FRACBITS;`
int fixedMul(int a, int b) {
  // a, b are conceptually 32-bit; do the product in full 64-bit precision.
  final int product = a * b; // Dart int is 64-bit; ample for 32x32.
  return toInt32(product >> kFracBits);
}

/// FixedDiv: (a << FRACBITS) / b with vanilla overflow guard.
///
/// Faithful to Chocolate Doom:
///   if ((abs(a) >> 14) >= abs(b))
///       return (a^b) < 0 ? INT_MIN : INT_MAX;
///   else
///       return (fixed_t)(((int64_t) a << FRACBITS) / b);
int fixedDiv(int a, int b) {
  if ((a.abs() >> 14) >= b.abs()) {
    return (a ^ b) < 0 ? kInt32Min : kInt32Max;
  }
  // 64-bit signed division, truncating toward zero (C semantics; Dart `~/`
  // also truncates toward zero).
  final int result = (a << kFracBits) ~/ b;
  return toInt32(result);
}
