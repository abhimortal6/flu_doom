// Game-loop inter-tic fraction tests: the loop derives a 16.16 sub-tic fraction
// from the wall-clock remainder after running due 35Hz tics, clamped to
// [0, FRACUNIT]. This is the Crispy/Woof `fractionaltic` the renderer blends with.

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/system/gameloop.dart';

void main() {
  testWidgets('subTicFrac16 is 0 before any time elapses and stays clamped',
      (WidgetTester tester) async {
    int tics = 0;
    int frames = 0;
    final GameLoop loop = GameLoop(
      vsync: const TestVSync(),
      onTic: (_) => tics++,
      onRender: () => frames++,
    );
    addTearDown(loop.dispose);

    // Before starting, no time has accumulated.
    expect(loop.subTicFrac16, 0);

    loop.start();
    // Pump a sequence of frames; the Ticker delivers elapsed durations.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    loop.stop();

    // The fraction is always a valid 16.16 value in [0, FRACUNIT].
    expect(loop.subTicFrac16, greaterThanOrEqualTo(0));
    expect(loop.subTicFrac16, lessThanOrEqualTo(kFracUnit));

    // Some frames rendered; with ~80ms elapsed at 35Hz (~28.57ms/tic) at least
    // two tics should have run.
    expect(frames, greaterThan(0));
    expect(tics, greaterThanOrEqualTo(2));
  });

  testWidgets('the fraction stays a valid clamped 16.16 value across frames',
      (WidgetTester tester) async {
    final GameLoop loop = GameLoop(
      vsync: const TestVSync(),
      onTic: (_) {},
      onRender: () {},
    );
    addTearDown(loop.dispose);
    loop.start();

    // Pump frames at sub-tic and super-tic intervals; the fraction must always
    // remain in [0, FRACUNIT] (it is the wall-clock remainder / tic duration).
    for (final int ms in <int>[1, 5, 14, 30, 60, 7, 22]) {
      await tester.pump(Duration(milliseconds: ms));
      expect(loop.subTicFrac16, greaterThanOrEqualTo(0));
      expect(loop.subTicFrac16, lessThanOrEqualTo(kFracUnit));
    }
    loop.stop();
  });
}
