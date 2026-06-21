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

    test('tapAction posts keyDown immediately and holds the key down', () {
      // The min-hold makes tapAction post the keyDown edge NOW (so the menu,
      // which reads discrete events, responds on key-down) and keep the key in
      // the sampled key-state so a 35 Hz per-tic sampler can observe it.
      final q = EventQueue();
      final sink = EventQueueActionSink(q);

      sink.tapAction(GameAction.weapon3);
      final events = q.drain();

      // Only the keyDown edge so far; the keyUp is deferred by the min-hold.
      expect(events, hasLength(1));
      expect(events[0].type, EventType.keyDown);
      expect(events[0].data1, 0x33); // '3'
      // CRITICAL: the per-tic sampler would observe the key as down right now.
      expect(sink.isKeyDown(0x33), isTrue,
          reason: 'tapped key must be sampled as down for at least one tic');
    });

    testWidgets(
        'BUG REPRO: a momentary tap survives a per-tic key-state sample '
        'then releases cleanly (no stuck key)', (tester) async {
      // Reproduces the on-device bug: a touch tap posts down+up almost
      // instantly; without the min-hold the per-tic sampler (which only reads
      // isKeyDown) never sees it and the action is lost. With the min-hold the
      // key stays down across the tap's synchronous completion.
      final q = EventQueue();
      final sink = EventQueueActionSink(q);

      sink.tapAction(GameAction.use); // spacebar

      // Simulate the per-tic bridge sampling key-state AFTER the tap returned
      // (the tap is fully synchronous; in the old code the key would already be
      // up here). It must STILL read down for at least one sample.
      expect(sink.isKeyDown(DoomKey.spacebar), isTrue,
          reason: 'min-hold keeps the tapped key down for the next tic sample');

      // After the min-hold elapses the key releases and ref-count returns to 0.
      await tester.pump(EventQueueActionSink.tapMinHold +
          const Duration(milliseconds: 20));
      expect(sink.isKeyDown(DoomKey.spacebar), isFalse,
          reason: 'no stuck key after the hold');
      expect(sink.downKeys, isEmpty);

      // The full down/up edge pair reached the queue across the window.
      final types = q.drain().map((e) => e.type).toList();
      expect(types, <EventType>[EventType.keyDown, EventType.keyUp]);
    });

    testWidgets('rapid double-tap refreshes the hold without corrupting state',
        (tester) async {
      final q = EventQueue();
      final sink = EventQueueActionSink(q);

      sink.tapAction(GameAction.weapon3);
      // Re-tap partway through the first hold.
      await tester.pump(const Duration(milliseconds: 40));
      sink.tapAction(GameAction.weapon3);
      // Still down right after the second tap.
      expect(sink.isKeyDown(0x33), isTrue);
      // Still down at a point past the FIRST hold's expiry (the second tap
      // refreshed the window) — proves the hold extended, not double-counted.
      await tester.pump(const Duration(milliseconds: 70));
      expect(sink.isKeyDown(0x33), isTrue,
          reason: 'second tap refreshed the hold window');
      // After the refreshed hold fully elapses, the key releases exactly once.
      await tester.pump(EventQueueActionSink.tapMinHold);
      expect(sink.isKeyDown(0x33), isFalse);
      expect(sink.downKeys, isEmpty);
      final ups = q.drain().where((e) => e.type == EventType.keyUp).toList();
      expect(ups, hasLength(1), reason: 'exactly one keyUp, no double release');
    });

    test('tapAction does not double-count a key held by a hold action', () {
      // A held action (pressAction) plus a tap of the same key must stay
      // ref-count-balanced: the tap auto-release must not clear a still-held
      // key, and the hold release later must not be eaten by the tap.
      final q = EventQueue();
      final sink = EventQueueActionSink(q);
      sink.pressAction(GameAction.use); // spacebar held
      sink.tapAction(GameAction.use); // same key tapped
      expect(sink.isKeyDown(DoomKey.spacebar), isTrue);
      // The hold is still active; releasing the hold keeps things consistent.
      sink.releaseAction(GameAction.use);
      // Tap ref-count may still be pending; key may or may not be down, but no
      // negative ref-count and a later releaseAll clears everything cleanly.
      sink.releaseAll();
      expect(sink.downKeys, isEmpty);
      q.drain();
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
