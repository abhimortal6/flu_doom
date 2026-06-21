// Shared test fixture for the bring-your-own-WAD layout.
//
// flu_doom ships NO game data and the WAD is gitignored, so a fresh clone (or CI)
// may not have assets/doom1.wad on disk. WAD-dependent tests must therefore SKIP
// gracefully when it's absent rather than fail — while still asserting the exact
// Doom-specific values when the WAD IS present.
//
// Usage patterns:
//
//   // 1) Skip an entire test/group when the WAD is missing:
//   test('...', () { ... }, skip: wadFixtureSkip());
//
//   // 2) Guard a setUpAll / body with an early return:
//   final Uint8List? bytes = wadFixtureBytesOrNull();
//   if (bytes == null) return; // never reached when skip: is also set
//
//   // 3) Load the WAD bytes, asserting presence (use only when the test/group
//   //    is already guarded by skip: wadFixtureSkip()):
//   final WadFile wad = WadFile.fromBytes(wadFixtureBytes());
//
// The assertions in the tests themselves are UNCHANGED — they still expect the
// shareware doom1.wad values.

import 'dart:io';
import 'dart:typed_data';

import 'package:flu_doom/engine/wad/wad.dart';

/// Canonical path to the test WAD (relative to the package root, where
/// `flutter test` runs).
const String wadFixturePath = 'assets/doom1.wad';

/// True if the test WAD is present on disk.
bool get wadFixtureExists => File(wadFixturePath).existsSync();

/// A `skip:` reason when the WAD is absent, or `false` (don't skip) when it is
/// present. Pass directly to `test(...)` / `group(...)`'s `skip:` argument so a
/// clone without the WAD runs green (these tests skipped) instead of failing.
Object get wadFixtureSkip => wadFixtureExists
    ? false
    : 'assets/doom1.wad not present (bring-your-own-WAD): skipping '
        'WAD-dependent test. Place a Doom IWAD at $wadFixturePath to run it.';

/// The raw WAD bytes if the WAD exists, else null (so a body can early-return).
Uint8List? wadFixtureBytesOrNull() {
  final File f = File(wadFixturePath);
  if (!f.existsSync()) return null;
  return Uint8List.fromList(f.readAsBytesSync());
}

/// The raw WAD bytes, asserting presence. Only call from a test/group already
/// guarded by `skip: wadFixtureSkip` (or after a `wadFixtureBytesOrNull` null
/// check) so a clone without the WAD never reaches this.
Uint8List wadFixtureBytes() {
  final Uint8List? b = wadFixtureBytesOrNull();
  if (b == null) {
    throw StateError('wadFixtureBytes() called but $wadFixturePath is absent. '
        'Guard the test with skip: wadFixtureSkip.');
  }
  return b;
}

/// Parse the test WAD, asserting presence. Convenience over [wadFixtureBytes].
WadFile wadFixtureFile() => WadFile.fromBytes(wadFixtureBytes());
