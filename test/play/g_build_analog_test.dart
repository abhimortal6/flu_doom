// G_BuildTiccmd analog-channel tests: the touch movement stick (forward/strafe
// via FRACUNIT-scaled deflection, run tier) and the drag-to-look turn
// (mousex-equivalent -> angleturn), plus a regression check that zero analog
// input produces byte-identical output to the keyboard-only path.

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/game/play/g_build.dart';
import 'package:flu_doom/game/world/ticcmd.dart';

// Vanilla tables (g_game.c) for reference assertions.
const int _fwdWalk = 0x19; // 25
const int _fwdRun = 0x32; // 50  (== MAXPLMOVE)
const int _sideWalk = 0x18; // 24
const int _sideRun = 0x28; // 40

void main() {
  group('TicCmdBuilder analog movement stick', () {
    test('full-forward stick at run tier == forwardmove[run] (MAXPLMOVE)', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      b.build(
        cmd,
        KeyState()
          ..analogForward = kFracUnit // +1.0 forward
          ..analogRun = true,
      );
      // FixedMul(forwardmove[1], FRACUNIT) == forwardmove[1] == MAXPLMOVE.
      expect(cmd.forwardMove, _fwdRun);
      expect(cmd.sideMove, 0);
      expect(cmd.angleTurn, 0);
    });

    test('full-forward stick at walk tier == forwardmove[walk]', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      b.build(cmd, KeyState()..analogForward = kFracUnit);
      expect(cmd.forwardMove, _fwdWalk);
    });

    test('up-left strafe vector: forward>0 and strafe-left (side<0), run tier',
        () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      // Up-left: forward push (+) and strafe LEFT (side -1).
      b.build(
        cmd,
        KeyState()
          ..analogForward = kFracUnit
          ..analogSide = -kFracUnit
          ..analogRun = true,
      );
      expect(cmd.forwardMove, greaterThan(0));
      expect(cmd.forwardMove, _fwdRun); // full forward at run
      expect(cmd.sideMove, lessThan(0)); // strafing left
      expect(cmd.sideMove, -_sideRun); // full strafe-left at run
      expect(cmd.angleTurn, 0); // stick never turns
    });

    test('half-deflection forward at walk tier ~ half forwardmove', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      b.build(cmd, KeyState()..analogForward = kFracUnit ~/ 2);
      // FixedMul(25, 0.5) == 12.
      expect(cmd.forwardMove, _fwdWalk ~/ 2);
    });

    test('backward stick (negative forward) thrusts backward', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      b.build(cmd, KeyState()..analogForward = -kFracUnit);
      expect(cmd.forwardMove, -_fwdWalk);
    });

    test('full strafe-right at walk tier == sidemove[walk]', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      b.build(cmd, KeyState()..analogSide = kFracUnit);
      expect(cmd.sideMove, _sideWalk);
      expect(cmd.forwardMove, 0);
    });
  });

  group('TicCmdBuilder analog look (drag-to-look)', () {
    test('positive analogTurn (drag right) yields negative angleturn '
        '(turn right) via mousex*8', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      b.build(cmd, KeyState()..analogTurn = 10);
      // angleturn -= mousex*0x8  => -80.
      expect(cmd.angleTurn, -80);
      // Look does not move the player.
      expect(cmd.forwardMove, 0);
      expect(cmd.sideMove, 0);
    });

    test('negative analogTurn (drag left) yields positive angleturn '
        '(turn left)', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      b.build(cmd, KeyState()..analogTurn = -4);
      expect(cmd.angleTurn, 32);
    });
  });

  group('analog + keyboard cooperate; clamp to MAXPLMOVE', () {
    test('keyboard forward + analog forward sum and clamp to MAXPLMOVE', () {
      final b = TicCmdBuilder();
      final cmd = TicCmd();
      // Keyboard run-forward (50) + analog full-forward run (50) = 100 -> clamp.
      b.build(
        cmd,
        KeyState()
          ..forward = true
          ..run = true
          ..analogForward = kFracUnit
          ..analogRun = true,
      );
      expect(cmd.forwardMove, _fwdRun); // MAXPLMOVE, not 100
    });
  });

  group('zero analog == keyboard-only (no regression)', () {
    KeyState ks() => KeyState();

    void expectSame(void Function(KeyState) setup) {
      final base = TicCmdBuilder();
      final withAnalog = TicCmdBuilder();
      final a = TicCmd();
      final c = TicCmd();
      final k1 = ks()..run = false;
      final k2 = ks()..run = false;
      setup(k1);
      setup(k2);
      // k2 leaves all analog fields at their zero defaults.
      base.build(a, k1);
      withAnalog.build(c, k2);
      expect(c.forwardMove, a.forwardMove);
      expect(c.sideMove, a.sideMove);
      expect(c.angleTurn, a.angleTurn);
      expect(c.buttons, a.buttons);
    }

    test('forward+turnleft+run identical with idle analog', () {
      expectSame((k) => k
        ..forward = true
        ..turnLeft = true
        ..run = true);
    });

    test('strafe-right + fire identical with idle analog', () {
      expectSame((k) => k
        ..strafeRight = true
        ..attack = true);
    });

    test('pure backward identical', () {
      expectSame((k) => k..backward = true);
    });
  });
}
