// Widget tests for the context-aware overlay modes:
//   * MENU mode shows the D-pad nav cluster (Up/Down/Left/Right) + Confirm/Back,
//     each posting a clean DoomKey down/up tap, and HIDES the gameplay
//     stick/look/fire controls.
//   * GAMEPLAY mode shows the stick/look/fire controls and HIDES the menu nav
//     cluster.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/controls_settings.dart';
import 'package:flu_doom/ui/controls/touch_controls_overlay.dart';

Widget _host(EventQueue q, OverlayMode mode, {OverlaySettings? settings}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
          TouchControlsOverlay(
            sink: EventQueueActionSink(q),
            settings: settings ?? const OverlaySettings(),
            mode: mode,
          ),
        ],
      ),
    ),
  );
}

/// Tap a momentary nav button by its semantic label and assert it posted a
/// clean keyDown+keyUp pair of [expectedKey].
Future<void> _expectTapPostsKey(
  WidgetTester tester,
  EventQueue q,
  String label,
  int expectedKey,
) async {
  q.drain(); // clear anything pending
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pump();
  // Min-hold: the keyDown edge lands immediately so the menu (discrete-event
  // reader) responds on key-down; the keyUp is deferred so the key survives a
  // per-tic key-state sample.
  final List<DoomEvent> events = q.drain();
  expect(events, hasLength(1), reason: '$label should post keyDown now');
  expect(events[0].type, EventType.keyDown, reason: '$label down');
  expect(events[0].data1, expectedKey, reason: '$label down key');
  // Let the min-hold + flash timers fire; the keyUp lands and no timer pends.
  await tester.pump(const Duration(milliseconds: 200));
  final List<DoomEvent> after = q.drain();
  expect(after, hasLength(1), reason: '$label should post keyUp after hold');
  expect(after[0].type, EventType.keyUp, reason: '$label up');
  expect(after[0].data1, expectedKey, reason: '$label up key');
}

void main() {
  group('MENU mode', () {
    testWidgets('D-pad arms post discrete arrow-key taps', (tester) async {
      final q = EventQueue();
      await tester.pumpWidget(_host(q, OverlayMode.menu));

      await _expectTapPostsKey(tester, q, 'UP', DoomKey.upArrow);
      await _expectTapPostsKey(tester, q, 'DOWN', DoomKey.downArrow);
      await _expectTapPostsKey(tester, q, 'LEFT', DoomKey.leftArrow);
      await _expectTapPostsKey(tester, q, 'RIGHT', DoomKey.rightArrow);
    });

    testWidgets('Confirm posts enter, Back posts escape', (tester) async {
      final q = EventQueue();
      await tester.pumpWidget(_host(q, OverlayMode.menu));

      await _expectTapPostsKey(tester, q, 'CONFIRM', DoomKey.enter);
      await _expectTapPostsKey(tester, q, 'BACK', DoomKey.escape);
    });

    testWidgets('gameplay controls are NOT present in menu mode',
        (tester) async {
      final q = EventQueue();
      await tester.pumpWidget(_host(q, OverlayMode.menu));

      expect(find.bySemanticsLabel('FIRE'), findsNothing);
      expect(find.bySemanticsLabel('USE'), findsNothing);
      expect(find.bySemanticsLabel('W+'), findsNothing);
      expect(find.bySemanticsLabel('W-'), findsNothing);
      // Menu nav cluster IS present.
      expect(find.bySemanticsLabel('UP'), findsOneWidget);
      expect(find.bySemanticsLabel('CONFIRM'), findsOneWidget);
      expect(find.bySemanticsLabel('BACK'), findsOneWidget);
    });

    testWidgets('lays out in portrait, landscape, and left-handed',
        (tester) async {
      final q = EventQueue();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_host(q, OverlayMode.menu));
      expect(find.bySemanticsLabel('UP'), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1400, 800);
      await tester.pumpWidget(_host(q, OverlayMode.menu));
      await tester.pump();
      expect(find.bySemanticsLabel('UP'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_host(q, OverlayMode.menu,
          settings: const OverlaySettings(handed: HandedLayout.left)));
      await tester.pump();
      expect(find.bySemanticsLabel('UP'), findsOneWidget);
      expect(find.bySemanticsLabel('CONFIRM'), findsOneWidget);
      expect(find.bySemanticsLabel('BACK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('GAMEPLAY mode', () {
    testWidgets('gameplay controls present, menu nav cluster absent',
        (tester) async {
      final q = EventQueue();
      await tester.pumpWidget(_host(q, OverlayMode.gameplay));

      // Gameplay controls.
      expect(find.bySemanticsLabel('FIRE'), findsOneWidget);
      expect(find.bySemanticsLabel('USE'), findsOneWidget);
      expect(find.bySemanticsLabel('MENU'), findsOneWidget);

      // Menu nav cluster is NOT present.
      expect(find.bySemanticsLabel('UP'), findsNothing);
      expect(find.bySemanticsLabel('DOWN'), findsNothing);
      expect(find.bySemanticsLabel('CONFIRM'), findsNothing);
      expect(find.bySemanticsLabel('BACK'), findsNothing);
    });

    testWidgets('FIRE still posts rCtrl down/up in gameplay mode',
        (tester) async {
      final q = EventQueue();
      await tester.pumpWidget(_host(q, OverlayMode.gameplay));

      final gesture = await tester.startGesture(
          tester.getCenter(find.bySemanticsLabel('FIRE')));
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
  });
}
