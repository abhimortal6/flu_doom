// Tests for the screen-melt wipe (lib/engine/video/wipe.dart), a faithful port of
// Chocolate Doom f_wipe.c (wipe_initMelt/doMelt/exitMelt).

import 'dart:typed_data';

import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/video/wipe.dart';
import 'package:flu_doom/game/play/p_random.dart';
import 'package:flutter_test/flutter_test.dart';

const int _kA = 7; // OLD screen palette index
const int _kB = 200; // NEW screen palette index

Uint8List _solid(int color) {
  final Uint8List b = Uint8List(kScreenWidth * kScreenHeight);
  b.fillRange(0, b.length, color);
  return b;
}

/// Count pixels equal to [color] in a row-major 320x200 buffer.
int _countColor(Uint8List px, int color) {
  int n = 0;
  for (int i = 0; i < px.length; i++) {
    if (px[i] == color) n++;
  }
  return n;
}

/// For column [x] (0..319) count how many of the 200 rows show [color].
int _colCount(Uint8List px, int x, int color) {
  int n = 0;
  for (int y = 0; y < kScreenHeight; y++) {
    if (px[y * kScreenWidth + x] == color) n++;
  }
  return n;
}

void main() {
  setUp(clearRandom);

  test('first composed frame is essentially all-OLD', () {
    final WipeMelt w = WipeMelt.start(_solid(_kA), _solid(_kB));
    final Framebuffer fb = Framebuffer();
    w.compose(fb);
    // Before any update, the live buffer is the copied start screen verbatim.
    expect(_countColor(fb.pixels, _kA), kScreenWidth * kScreenHeight);
    expect(_countColor(fb.pixels, _kB), 0);
    expect(w.isComplete, isFalse);
  });

  test('melt progresses: NEW pixels increase monotonically over time', () {
    final WipeMelt w = WipeMelt.start(_solid(_kA), _solid(_kB));
    final Framebuffer fb = Framebuffer();

    int prevNew = 0;
    int steps = 0;
    bool sawProgress = false;
    while (!w.update() && steps < 1000) {
      w.compose(fb);
      final int now = _countColor(fb.pixels, _kB);
      // NEW count never decreases (columns only ever melt downward).
      expect(now, greaterThanOrEqualTo(prevNew));
      if (now > prevNew) sawProgress = true;
      prevNew = now;
      steps++;
    }
    expect(sawProgress, isTrue, reason: 'wipe should reveal NEW over time');
  });

  test('within a column the NEW screen fills from the TOP down', () {
    final WipeMelt w = WipeMelt.start(_solid(_kA), _solid(_kB));
    final Framebuffer fb = Framebuffer();

    // Advance partway through the melt.
    for (int i = 0; i < 12; i++) {
      if (w.update()) break;
    }
    w.compose(fb);

    // Find a column that has begun melting (has both OLD and NEW), and assert
    // the NEW pixels are the contiguous TOP block (old slides down to reveal
    // new from the top).
    bool checkedAny = false;
    for (int x = 0; x < kScreenWidth; x++) {
      final int newRows = _colCount(fb.pixels, x, _kB);
      if (newRows == 0 || newRows == kScreenHeight) continue;
      checkedAny = true;
      // The top `newRows` rows should be NEW; below should not be NEW.
      for (int y = 0; y < newRows; y++) {
        expect(fb.pixels[y * kScreenWidth + x], _kB,
            reason: 'col $x row $y expected NEW (top block)');
      }
      expect(fb.pixels[newRows * kScreenWidth + x], isNot(_kB),
          reason: 'col $x first row below NEW block should not be NEW');
      break;
    }
    expect(checkedAny, isTrue, reason: 'expected a partially-melted column');
  });

  test('eventually completes with frame essentially all-NEW', () {
    final WipeMelt w = WipeMelt.start(_solid(_kA), _solid(_kB));
    final Framebuffer fb = Framebuffer();

    int steps = 0;
    while (!w.update() && steps < 2000) {
      steps++;
    }
    expect(w.isComplete, isTrue);
    w.compose(fb);
    expect(_countColor(fb.pixels, _kB), kScreenWidth * kScreenHeight);
    expect(_countColor(fb.pixels, _kA), 0);

    // ~1s at 35fps: vanilla melt completes well under 200 tics.
    expect(steps, lessThan(200));
  });

  test('update() is a no-op after completion (idempotent done)', () {
    final WipeMelt w = WipeMelt.start(_solid(_kA), _solid(_kB));
    while (!w.update()) {}
    expect(w.update(), isTrue);
    expect(w.update(), isTrue);
    expect(w.isComplete, isTrue);
  });

  test('column start offsets match vanilla wipe_initMelt pattern', () {
    clearRandom();
    final WipeMelt w = WipeMelt.start(_solid(_kA), _solid(_kB));
    final Int32List y = w.columnOffsets;

    // Recompute the expected offsets with a fresh mRandom stream and the exact
    // vanilla recurrence.
    clearRandom();
    final Int32List expected = Int32List(kScreenWidth);
    expected[0] = -(mRandom() % 16);
    for (int i = 1; i < kScreenWidth; i++) {
      final int r = (mRandom() % 3) - 1;
      expected[i] = expected[i - 1] + r;
      if (expected[i] > 0) {
        expected[i] = 0;
      } else if (expected[i] == -16) {
        expected[i] = -15;
      }
    }

    expect(y, equals(expected));
    // Invariants from the recurrence: never positive, never exactly -16.
    for (int i = 0; i < kScreenWidth; i++) {
      expect(y[i], lessThanOrEqualTo(0));
      expect(y[i], isNot(-16));
      expect(y[i], greaterThanOrEqualTo(-15));
    }
  });

  test('deterministic given a fixed mRandom seed (clearRandom)', () {
    clearRandom();
    final WipeMelt a = WipeMelt.start(_solid(_kA), _solid(_kB));
    final Int32List offA = a.columnOffsets;
    final Framebuffer fbA = Framebuffer();
    for (int i = 0; i < 10; i++) {
      a.update();
    }
    a.compose(fbA);

    clearRandom();
    final WipeMelt b = WipeMelt.start(_solid(_kA), _solid(_kB));
    final Int32List offB = b.columnOffsets;
    final Framebuffer fbB = Framebuffer();
    for (int i = 0; i < 10; i++) {
      b.update();
    }
    b.compose(fbB);

    expect(offA, equals(offB));
    expect(fbA.pixels, equals(fbB.pixels));
  });
}
