// Widget tests: overlay button taps -> DoomEvents on the EventQueue, and the
// overlay arranges in both portrait and landscape / both handedness modes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/controls_settings.dart';
import 'package:flu_doom/ui/controls/touch_controls_overlay.dart';

Widget _host(EventQueue q, OverlaySettings s) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
          TouchControlsOverlay(
            sink: EventQueueActionSink(q),
            settings: s,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('FIRE button hold posts keyDown then keyUp of rCtrl',
      (tester) async {
    final q = EventQueue();
    await tester.pumpWidget(_host(q, const OverlaySettings()));

    final fire = find.bySemanticsLabel('FIRE');
    expect(fire, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(fire));
    await tester.pump();
    var events = q.drain();
    expect(events.single.type, EventType.keyDown);
    expect(events.single.data1, DoomKey.rCtrl);

    await gesture.up();
    await tester.pump();
    events = q.drain();
    expect(events.single.type, EventType.keyUp);
    expect(events.single.data1, DoomKey.rCtrl);
  });

  testWidgets('USE button posts spacebar', (tester) async {
    final q = EventQueue();
    await tester.pumpWidget(_host(q, const OverlaySettings()));

    await tester.tap(find.bySemanticsLabel('USE'));
    await tester.pump();
    final events = q.drain();
    expect(events.any((e) => e.data1 == DoomKey.spacebar), isTrue);
  });

  testWidgets('NEXT weapon button emits a tap (down+up) of equals',
      (tester) async {
    final q = EventQueue();
    await tester.pumpWidget(_host(q, const OverlaySettings()));

    final next = find.bySemanticsLabel('NEXT');
    expect(next, findsOneWidget);
    await tester.tap(next);
    await tester.pump();
    final events = q.drain();
    expect(events, hasLength(2));
    expect(events[0].type, EventType.keyDown);
    expect(events[0].data1, DoomKey.equals);
    expect(events[1].type, EventType.keyUp);
    expect(events[1].data1, DoomKey.equals);
    // Let the momentary-flash timer fire so no timer is pending at teardown.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('PREV weapon button emits a tap (down+up) of minus',
      (tester) async {
    final q = EventQueue();
    await tester.pumpWidget(_host(q, const OverlaySettings()));

    final prev = find.bySemanticsLabel('PREV');
    expect(prev, findsOneWidget);
    await tester.tap(prev);
    await tester.pump();
    final events = q.drain();
    expect(events, hasLength(2));
    expect(events[0].type, EventType.keyDown);
    expect(events[0].data1, DoomKey.minus);
    expect(events[1].type, EventType.keyUp);
    expect(events[1].data1, DoomKey.minus);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
      'weapon buttons are present and hittable in portrait, landscape, and '
      'left-handed; tap on right-side weapon button fires weapon (not look)',
      (tester) async {
    // A weapon button stacked above the look region must WIN the touch: the
    // tap should post the weapon DoomKey and NOT be swallowed as a look-drag
    // (which would leave the EventQueue empty). We verify both buttons present
    // and that a tap produces exactly the weapon key edges, across orientations
    // and handedness.
    Future<void> check(OverlaySettings s, Size size) async {
      final q = EventQueue();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(q, s));
      await tester.pump();

      expect(find.bySemanticsLabel('PREV'), findsOneWidget);
      expect(find.bySemanticsLabel('NEXT'), findsOneWidget);

      // Tap NEXT; it must register as the weapon action, not a look-drag.
      await tester.tap(find.bySemanticsLabel('NEXT'));
      await tester.pump();
      final events = q.drain();
      expect(events, hasLength(2));
      expect(events[0].type, EventType.keyDown);
      expect(events[0].data1, DoomKey.equals);
      expect(events[1].type, EventType.keyUp);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await check(const OverlaySettings(), const Size(800, 1400)); // portrait
    await check(const OverlaySettings(), const Size(1400, 800)); // landscape
    await check(
      const OverlaySettings(handed: HandedLayout.left),
      const Size(1400, 800),
    ); // left-handed landscape
  });

  testWidgets('hidden overlay renders nothing interactive', (tester) async {
    final q = EventQueue();
    await tester.pumpWidget(
      _host(q, const OverlaySettings(visible: false)),
    );
    expect(find.bySemanticsLabel('FIRE'), findsNothing);
  });

  testWidgets('lays out in portrait and landscape', (tester) async {
    final q = EventQueue();

    // Portrait.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_host(q, const OverlaySettings()));
    expect(find.bySemanticsLabel('FIRE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Landscape.
    tester.view.physicalSize = const Size(1400, 800);
    await tester.pumpWidget(_host(q, const OverlaySettings()));
    await tester.pump();
    expect(find.bySemanticsLabel('FIRE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('left-handed layout still renders all controls', (tester) async {
    final q = EventQueue();
    await tester.pumpWidget(
      _host(q, const OverlaySettings(handed: HandedLayout.left)),
    );
    expect(find.bySemanticsLabel('FIRE'), findsOneWidget);
    expect(find.bySemanticsLabel('MENU'), findsOneWidget);
    expect(find.bySemanticsLabel('MAP'), findsOneWidget);
  });
}
