// Regression test for the macOS keyboard auto-repeat bug.
//
// When a key is HELD on macOS, the OS emits one KeyDownEvent followed by a
// stream of KeyRepeatEvents, then a KeyUpEvent on release. Vanilla Doom is
// edge-triggered: a key produces exactly one keyDown on press and one keyUp on
// release, ignoring OS auto-repeat. The live keyboard handler
// (ActionKeyboardListener -> EventQueueActionSink) must therefore post exactly
// one keyDown on press, NOTHING on each repeat, and exactly one keyUp on
// release, keeping the sink's ref-count balanced (no stuck keys, no re-trigger
// of menu/move/use/fire sounds while the key is held).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/key_bindings.dart';
import 'package:flu_doom/input_actions/action_keyboard_listener.dart';

void main() {
  // Pump the *real* ActionKeyboardListener with a real EventQueueActionSink so
  // the test exercises the actual _onKey handler, not a reimplementation.
  Future<EventQueueActionSink> pumpListener(WidgetTester tester) async {
    final EventQueue queue = EventQueue();
    final EventQueueActionSink sink = EventQueueActionSink(queue);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ActionKeyboardListener(
          bindings: KeyBindings.defaults(),
          sink: sink,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump(); // let autofocus settle
    return sink;
  }

  testWidgets(
    'held key: one keyDown on press, none on repeats, one keyUp on release',
    (WidgetTester tester) async {
      final EventQueueActionSink sink = await pumpListener(tester);
      // moveForward is bound to arrowUp by default -> Doom upArrow keycode.
      const LogicalKeyboardKey key = LogicalKeyboardKey.arrowUp;

      // 1) Initial press -> exactly one keyDown edge.
      await tester.sendKeyDownEvent(key);
      List<DoomEvent> events = sink.queue.drain();
      expect(events, hasLength(1), reason: 'press posts exactly one event');
      expect(events.single.type, EventType.keyDown);
      expect(events.single.data1, DoomKey.upArrow);
      expect(sink.isKeyDown(DoomKey.upArrow), isTrue,
          reason: 'key stays down while held');

      // 2) OS auto-repeat while held -> ZERO additional edges, key still down.
      for (int i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(key);
      }
      events = sink.queue.drain();
      expect(events, isEmpty,
          reason: 'auto-repeat must not re-post keyDown or any event');
      expect(sink.isKeyDown(DoomKey.upArrow), isTrue,
          reason: 'key remains down through repeats');

      // 3) Release -> exactly one keyUp edge, key-state cleared.
      await tester.sendKeyUpEvent(key);
      events = sink.queue.drain();
      expect(events, hasLength(1), reason: 'release posts exactly one event');
      expect(events.single.type, EventType.keyUp);
      expect(events.single.data1, DoomKey.upArrow);
      expect(sink.isKeyDown(DoomKey.upArrow), isFalse);
      expect(sink.downKeys, isEmpty,
          reason: 'ref-count balanced: down once, up once');
    },
  );

  testWidgets(
    'held fire key does not re-trigger while repeating',
    (WidgetTester tester) async {
      final EventQueueActionSink sink = await pumpListener(tester);
      // fire is bound to left-ctrl by default -> Doom rCtrl keycode.
      const LogicalKeyboardKey key = LogicalKeyboardKey.controlLeft;

      await tester.sendKeyDownEvent(key);
      expect(sink.queue.drain(), hasLength(1));
      expect(sink.isKeyDown(DoomKey.rCtrl), isTrue);

      for (int i = 0; i < 10; i++) {
        await tester.sendKeyRepeatEvent(key);
      }
      expect(sink.queue.drain(), isEmpty,
          reason: 'no repeated fire edges while held');

      await tester.sendKeyUpEvent(key);
      final List<DoomEvent> events = sink.queue.drain();
      expect(events, hasLength(1));
      expect(events.single.type, EventType.keyUp);
      expect(sink.downKeys, isEmpty);
    },
  );
}
