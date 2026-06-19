// Unit tests for the action -> DoomEvent / key-state pipeline.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/game_action.dart';
import 'package:flu_doom/input_actions/key_bindings.dart';

void main() {
  group('EventQueueActionSink', () {
    test('pressAction posts a keyDown of the mapped Doom keycode', () {
      final q = EventQueue();
      final sink = EventQueueActionSink(q);

      sink.pressAction(GameAction.fire);
      final events = q.drain();

      expect(events, hasLength(1));
      expect(events.single.type, EventType.keyDown);
      expect(events.single.data1, DoomKey.rCtrl);
      expect(sink.isKeyDown(DoomKey.rCtrl), isTrue);
      expect(sink.downKeys, contains(DoomKey.rCtrl));
    });

    test('releaseAction posts keyUp and clears key-state', () {
      final q = EventQueue();
      final sink = EventQueueActionSink(q);

      sink.pressAction(GameAction.use);
      sink.releaseAction(GameAction.use);
      final events = q.drain();

      expect(events.map((e) => e.type),
          <EventType>[EventType.keyDown, EventType.keyUp]);
      expect(events.last.data1, DoomKey.spacebar);
      expect(sink.isKeyDown(DoomKey.spacebar), isFalse);
    });

    test('tapAction emits a clean down/up pair', () {
      final q = EventQueue();
      final sink = EventQueueActionSink(q);

      sink.tapAction(GameAction.weapon3);
      final events = q.drain();

      expect(events, hasLength(2));
      expect(events[0].type, EventType.keyDown);
      expect(events[1].type, EventType.keyUp);
      expect(events[0].data1, 0x33); // '3'
    });

    test('ref-counting: shared keycode stays down until last release', () {
      // menuUp and moveForward both map to upArrow.
      final q = EventQueue();
      final sink = EventQueueActionSink(q);

      sink.pressAction(GameAction.moveForward); // upArrow down (edge)
      sink.pressAction(GameAction.menuUp); // same keycode, no new edge
      var events = q.drain();
      expect(events, hasLength(1), reason: 'only one keyDown edge');

      sink.releaseAction(GameAction.moveForward); // still held by menuUp
      events = q.drain();
      expect(events, isEmpty, reason: 'no keyUp while still held');
      expect(sink.isKeyDown(DoomKey.upArrow), isTrue);

      sink.releaseAction(GameAction.menuUp); // now released
      events = q.drain();
      expect(events.single.type, EventType.keyUp);
      expect(sink.isKeyDown(DoomKey.upArrow), isFalse);
    });

    test('releaseAll clears everything and emits keyUps', () {
      final q = EventQueue();
      final sink = EventQueueActionSink(q);
      sink.pressAction(GameAction.fire);
      sink.pressAction(GameAction.run);
      q.drain();

      sink.releaseAll();
      final events = q.drain();
      expect(events.every((e) => e.type == EventType.keyUp), isTrue);
      expect(sink.downKeys, isEmpty);
    });
  });

  group('KeyBindings', () {
    test('defaults bind vanilla-style keys', () {
      final b = KeyBindings.defaults();
      expect(b.actionFor(LogicalKeyboardKey.controlLeft), GameAction.fire);
      expect(b.actionFor(LogicalKeyboardKey.space), GameAction.use);
      expect(b.actionFor(LogicalKeyboardKey.keyW), GameAction.moveForward);
      expect(b.actionFor(LogicalKeyboardKey.arrowUp), GameAction.moveForward);
      expect(b.actionFor(LogicalKeyboardKey.tab), GameAction.automap);
      expect(b.actionFor(LogicalKeyboardKey.escape), GameAction.menuToggle);
      expect(b.actionFor(LogicalKeyboardKey.digit1), GameAction.weapon1);
    });

    test('rebind replaces the key mapping', () {
      final b = KeyBindings.defaults();
      b.bind(LogicalKeyboardKey.keyF, GameAction.fire);
      expect(b.actionFor(LogicalKeyboardKey.keyF), GameAction.fire);
      // clearAction removes the original ctrl binding too.
      b.clearAction(GameAction.fire);
      b.bind(LogicalKeyboardKey.keyF, GameAction.fire);
      expect(b.keysFor(GameAction.fire),
          <int>[LogicalKeyboardKey.keyF.keyId]);
    });

    test('round-trips through JSON', () {
      final b = KeyBindings.defaults();
      final restored = KeyBindings.fromJson(b.toJson());
      expect(restored.actionFor(LogicalKeyboardKey.controlLeft),
          GameAction.fire);
      expect(restored.actionFor(LogicalKeyboardKey.digit7),
          GameAction.weapon7);
    });
  });
}
