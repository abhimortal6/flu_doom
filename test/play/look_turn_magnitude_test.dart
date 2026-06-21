// Root-cause regression test for the "drag-to-look turn far too slow" bug.
//
// Traces a representative per-tic finger swipe through the FULL analog look
// path: AnalogInput (logical-px accumulation) -> takeMouseX (base gain +
// sensitivity) -> KeyState.analogTurn -> TicCmdBuilder.build -> cmd.angleTurn.
//
// Asserts the produced angleturn is in a RESPONSIVE range (hundreds-to-
// thousands, not single digits / zero), that sensitivity scales it, that zero
// look-delta produces zero turn, and that keyboard turning is unaffected.
//
// Reference scale: a full 360 deg turn is 0x4000 (16384) of summed angleturn,
// so ~1000+/tic is a brisk turn and ~2800+/tic whips ~60 deg in one tic.

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/input_actions/analog_input.dart';
import 'package:flu_doom/game/integration/key_state_bridge.dart';
import 'package:flu_doom/game/play/g_build.dart';
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';

/// Push [px] logical pixels of horizontal drag through the analog channel and
/// the bridge for one tic, returning the resulting cmd.angleTurn.
int _angleTurnForSwipe(double px, {double sensitivity = 1.0}) {
  final analog = AnalogInput()..lookSensitivity = sensitivity;
  analog.addLookDelta(px);

  // The bridge reads the analog channel into KeyState (consuming the delta) and
  // the builder turns it into an angleturn — exactly the per-tic production path
  // doom_game.dart runs.
  final bridge = KeyStateBridge(EventQueueActionSink(EventQueue()), analog: analog);
  final builder = TicCmdBuilder();
  final cmd = TicCmd();
  builder.build(cmd, bridge.build());
  return cmd.angleTurn;
}

void main() {
  group('drag-to-look turn magnitude (responsiveness regression)', () {
    test('a moderate one-tic swipe (50px @1.0x) is BRISK (angleturn >= ~1000)',
        () {
      final int at = _angleTurnForSwipe(50.0).abs();
      // px(50) * kLookBaseGain(6) * sens(1) = 300 mousex; *8 = 2400 angleturn.
      expect(at, 2400);
      // Guard against any regression that floors finger-px to a crawl.
      expect(at, greaterThanOrEqualTo(800),
          reason: 'a normal swipe must turn a good chunk per tic, not crawl');
    });

    test('a moderate swipe at the DEFAULT slider (50px @2.0x) is BRISK (~4800)',
        () {
      // The real fresh-install feel: default lookSensitivity is 2.0.
      // px(50) * kLookBaseGain(6) * sens(2) = 600 mousex; *8 = 4800 angleturn.
      final int at = _angleTurnForSwipe(50.0, sensitivity: 2.0).abs();
      expect(at, 4800);
      expect(at, greaterThan(2000),
          reason: 'default-sensitivity swipe should be brisk, ~PUBG');
    });

    test('at the MAX slider (50px @8.0x) it WHIPS very fast (~19200)', () {
      // px(50) * kLookBaseGain(6) * sens(8) = 2400 mousex; *8 = 19200 angleturn.
      // A deliberately fast ceiling the user can dial back.
      final int at = _angleTurnForSwipe(50.0, sensitivity: 8.0).abs();
      expect(at, 19200);
    });

    test('a fast one-tic flick (120px @1.0x) WHIPS (angleturn ~5760, >2000)',
        () {
      final int at = _angleTurnForSwipe(120.0).abs();
      expect(at, 5760); // 120*6*8
      expect(at, greaterThan(2000),
          reason: 'a fast flick should whip ~60deg+ in one tic');
    });

    test('sensitivity scales the turn (2x => double, 0.5x => half)', () {
      final int base = _angleTurnForSwipe(50.0).abs();
      expect(_angleTurnForSwipe(50.0, sensitivity: 2.0).abs(), base * 2);
      expect(_angleTurnForSwipe(50.0, sensitivity: 0.5).abs(), base ~/ 2);
    });

    test('even at the MIN slider (0.5x) a swipe still turns (not zero)', () {
      // 50 * 6 * 0.5 = 150 mousex; *8 = 1200. Slower but clearly non-zero.
      expect(_angleTurnForSwipe(50.0, sensitivity: 0.5).abs(), 1200);
    });

    test('drag right turns right (negative angleturn, vanilla mousex*8 sign)',
        () {
      expect(_angleTurnForSwipe(50.0), lessThan(0));
      expect(_angleTurnForSwipe(-50.0), greaterThan(0));
    });

    test('zero look delta => zero angleturn', () {
      expect(_angleTurnForSwipe(0.0), 0);
    });

    test('keyboard turn is UNAFFECTED by the look-gain change', () {
      // Keyboard-only turnRight on the first tic uses the slow tier (320) and
      // never touches the analog look path.
      final builder = TicCmdBuilder();
      final cmd = TicCmd();
      builder.build(cmd, KeyState()..turnRight = true);
      expect(cmd.angleTurn, -320); // _angleTurn[2] (slow, tic 0), unchanged
    });
  });
}
