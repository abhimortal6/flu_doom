// Gesture tests for the PUBG-style touch overlay:
//   (a) dragging the LEFT analog stick up-left writes a forward>0 + strafe-left
//       analog vector, and run engages near full deflection;
//   (b) dragging on the RIGHT look region accumulates a horizontal look delta
//       (the camera turns), while vertical drag is ignored;
//   (c) a TAP on a button inside the look region fires the button (and does NOT
//       turn the camera) — buttons take priority over the look-drag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/analog_input.dart';
import 'package:flu_doom/input_actions/controls_settings.dart';
import 'package:flu_doom/ui/controls/overlay_widgets.dart';
import 'package:flu_doom/ui/controls/touch_controls_overlay.dart';

Widget _host(EventQueue q, AnalogInput analog, OverlaySettings s) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
          TouchControlsOverlay(
            sink: EventQueueActionSink(q),
            analog: analog,
            settings: s,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('left analog stick drag up-left => forward>0, strafe-left, run',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800); // landscape
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final q = EventQueue();
    final analog = AnalogInput();
    await tester.pumpWidget(_host(q, analog, const OverlaySettings()));

    // Find the analog move stick and drag from its center toward up-left, near
    // full deflection (so the run tier engages).
    final stickFinder = find.byType(OverlayMoveStick);
    expect(stickFinder, findsOneWidget);
    final Offset center = tester.getCenter(stickFinder);
    final Size stickSize = tester.getSize(stickFinder);
    final double r = stickSize.width / 2;
    // Move almost to the top-left edge of the stick (magnitude ~ full).
    final Offset target = center + Offset(-r * 0.92, -r * 0.92);

    final g = await tester.startGesture(center);
    await tester.pump();
    await g.moveTo(target);
    await tester.pump();

    // forward (up) is positive; side (left) is negative; run at full deflection.
    expect(analog.forwardMove, greaterThan(0.0),
        reason: 'pushing up should move forward');
    expect(analog.sideMove, lessThan(0.0),
        reason: 'pushing left should strafe left');
    expect(analog.run, isTrue,
        reason: 'near-full deflection engages the run tier');

    // Lifting recenters and clears the vector.
    await g.up();
    await tester.pump();
    expect(analog.forwardMove, 0.0);
    expect(analog.sideMove, 0.0);
    expect(analog.run, isFalse);
  });

  testWidgets('right look region: horizontal drag turns; vertical ignored',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final q = EventQueue();
    final analog = AnalogInput();
    await tester.pumpWidget(_host(q, analog, const OverlaySettings()));

    // Drag horizontally on the right portion of the screen (away from buttons:
    // pick a point in the vertical middle, well right of center).
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Offset lookStart = Offset(screen.width * 0.75, screen.height * 0.5);

    final g = await tester.startGesture(lookStart);
    await tester.pump();
    // Drag right by 120px in two steps.
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    // Horizontal drag accumulated a positive look delta -> turning.
    expect(analog.lookDeltaX, greaterThan(0.0),
        reason: 'dragging right should turn the camera (mousex+)');

    // takeMouseX consumes (clears) it like vanilla mousex.
    final int mx = analog.takeMouseX();
    expect(mx, greaterThan(0));
    expect(analog.lookDeltaX, 0.0);

    // Now a purely VERTICAL drag must not produce any look delta.
    final g2 = await tester.startGesture(lookStart);
    await tester.pump();
    await g2.moveBy(const Offset(0, 120));
    await tester.pump();
    await g2.up();
    await tester.pump();
    expect(analog.lookDeltaX, 0.0,
        reason: 'vertical drag is ignored (Doom has no pitch)');
  });

  testWidgets('button tap inside look region fires button, does NOT turn',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final q = EventQueue();
    final analog = AnalogInput();
    await tester.pumpWidget(_host(q, analog, const OverlaySettings()));

    // FIRE sits in the bottom-right, over the look region. A tap on it must
    // fire (rCtrl down) and leave the camera untouched.
    final fire = find.bySemanticsLabel('FIRE');
    expect(fire, findsOneWidget);

    final g = await tester.startGesture(tester.getCenter(fire));
    await tester.pump();
    final downEvents = q.drain();
    expect(downEvents.single.type, EventType.keyDown);
    expect(downEvents.single.data1, DoomKey.rCtrl);
    // The button captured the gesture; no look delta accumulated.
    expect(analog.lookDeltaX, 0.0);

    await g.up();
    await tester.pump();
    final upEvents = q.drain();
    expect(upEvents.single.type, EventType.keyUp);
    expect(upEvents.single.data1, DoomKey.rCtrl);
  });
}
