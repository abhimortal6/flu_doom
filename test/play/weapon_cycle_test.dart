// Weapon-cycling tests for the touch PREV/NEXT weapon buttons.
//
// Vanilla Doom has NO next/previous-weapon mechanic — only direct select 1..7
// via BT_CHANGE. This port adds source-port-style cycling: from readyWeapon,
// scan weaponOwned[] in the requested direction to the next OWNED & available
// weapon, then drive the SAME KeyState.weapon -> BT_CHANGE path the number keys
// use. These tests prove:
//   * resolveWeaponCycle picks the right OWNED slot (prev from pistol -> fist),
//     wraps, skips unowned, and honors SSG/shareware availability gates;
//   * the full input -> ticcmd path (action sink -> bridge -> resolver ->
//     builder) emits the correct BT_CHANGE | (weapon<<BT_WEAPONSHIFT) bits;
//   * weapon1..7 direct select still works exactly as vanilla;
//   * zero input produces no weapon change.

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/game/integration/key_state_bridge.dart';
import 'package:flu_doom/game/play/g_build.dart';
import 'package:flu_doom/game/play/info_tables.dart' show Wp;
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/game_action.dart';

/// Build the BT_CHANGE bit pattern the playsim expects for a given weapontype.
int _btChangeFor(int weaponType) =>
    btChangeWeapon | ((weaponType << btWeaponShift) & btWeaponMask);

/// Decode the requested weapontype from a ticcmd's buttons (== P_PlayerThink).
int _decodeWeapon(TicCmd cmd) =>
    (cmd.buttons & btWeaponMask) >> btWeaponShift;

void main() {
  group('resolveWeaponCycle', () {
    List<int> owned(List<int> have) {
      final w = List<int>.filled(Wp.numWeapons, 0);
      for (final i in have) {
        w[i] = 1;
      }
      return w;
    }

    test('prev from pistol reaches the fist', () {
      final w = resolveWeaponCycle(
        dir: -1,
        readyWeapon: Wp.pistol,
        weaponOwned: owned(<int>[Wp.fist, Wp.pistol]),
        commercial: true,
        shareware: false,
      );
      expect(w, Wp.fist);
    });

    test('next from pistol reaches the shotgun when owned', () {
      final w = resolveWeaponCycle(
        dir: 1,
        readyWeapon: Wp.pistol,
        weaponOwned: owned(<int>[Wp.fist, Wp.pistol, Wp.shotgun]),
        commercial: true,
        shareware: false,
      );
      expect(w, Wp.shotgun);
    });

    test('next from pistol wraps to fist when no higher weapon owned', () {
      final w = resolveWeaponCycle(
        dir: 1,
        readyWeapon: Wp.pistol,
        weaponOwned: owned(<int>[Wp.fist, Wp.pistol]),
        commercial: true,
        shareware: false,
      );
      expect(w, Wp.fist);
    });

    test('prev from fist wraps to highest owned (chaingun)', () {
      final w = resolveWeaponCycle(
        dir: -1,
        readyWeapon: Wp.fist,
        weaponOwned: owned(<int>[Wp.fist, Wp.pistol, Wp.shotgun, Wp.chaingun]),
        commercial: true,
        shareware: false,
      );
      expect(w, Wp.chaingun);
    });

    test('skips unowned weapons in the cycle', () {
      // Own fist, pistol, chaingun (NOT shotgun): next from pistol -> chaingun.
      final w = resolveWeaponCycle(
        dir: 1,
        readyWeapon: Wp.pistol,
        weaponOwned: owned(<int>[Wp.fist, Wp.pistol, Wp.chaingun]),
        commercial: true,
        shareware: false,
      );
      expect(w, Wp.chaingun);
    });

    test('super shotgun only reachable in commercial', () {
      final ownSsg = owned(<int>[Wp.fist, Wp.pistol, Wp.supershotgun]);
      // commercial: reachable.
      expect(
        resolveWeaponCycle(
          dir: 1,
          readyWeapon: Wp.pistol,
          weaponOwned: ownSsg,
          commercial: true,
          shareware: false,
        ),
        Wp.supershotgun,
      );
      // non-commercial: skipped, wraps back to fist.
      expect(
        resolveWeaponCycle(
          dir: 1,
          readyWeapon: Wp.pistol,
          weaponOwned: ownSsg,
          commercial: false,
          shareware: false,
        ),
        Wp.fist,
      );
    });

    test('plasma/bfg never reachable in shareware', () {
      final ownAll =
          owned(<int>[Wp.fist, Wp.pistol, Wp.plasma, Wp.bfg]);
      // shareware: plasma & bfg skipped, next from pistol wraps to fist.
      expect(
        resolveWeaponCycle(
          dir: 1,
          readyWeapon: Wp.pistol,
          weaponOwned: ownAll,
          commercial: false,
          shareware: true,
        ),
        Wp.fist,
      );
      // non-shareware: plasma reachable.
      expect(
        resolveWeaponCycle(
          dir: 1,
          readyWeapon: Wp.pistol,
          weaponOwned: ownAll,
          commercial: true,
          shareware: false,
        ),
        Wp.plasma,
      );
    });

    test('single-weapon player: cycle is a no-op (stays put)', () {
      final w = resolveWeaponCycle(
        dir: 1,
        readyWeapon: Wp.pistol,
        weaponOwned: owned(<int>[Wp.pistol]),
        commercial: true,
        shareware: false,
      );
      expect(w, Wp.pistol);
    });
  });

  group('resolved cycle -> BT_CHANGE ticcmd bits', () {
    test('prev-cycle to fist emits BT_CHANGE | (fist<<shift)', () {
      // Simulate the playsim: resolve target, set KeyState.weapon = target+1,
      // build the cmd, assert the decoded weapon is the fist.
      final target = resolveWeaponCycle(
        dir: -1,
        readyWeapon: Wp.pistol,
        weaponOwned: List<int>.filled(Wp.numWeapons, 0)
          ..[Wp.fist] = 1
          ..[Wp.pistol] = 1,
        commercial: true,
        shareware: false,
      );
      final cmd = TicCmd();
      TicCmdBuilder().build(cmd, KeyState()..weapon = target + 1);
      expect(cmd.buttons & btChangeWeapon, btChangeWeapon);
      expect(_decodeWeapon(cmd), Wp.fist);
      expect(cmd.buttons & (btChangeWeapon | btWeaponMask), _btChangeFor(Wp.fist));
    });
  });

  group('full input -> ticcmd path (sink -> bridge -> builder)', () {
    late EventQueue queue;
    late EventQueueActionSink sink;
    late KeyStateBridge bridge;
    late TicCmdBuilder builder;

    setUp(() {
      queue = EventQueue();
      sink = EventQueueActionSink(queue);
      bridge = KeyStateBridge(sink);
      builder = TicCmdBuilder();
    });

    /// Replicates PlaySim.buildTiccmd's cycle resolution on top of the bridge's
    /// KeyState, then builds the cmd. Returns the produced cmd.
    TicCmd buildWithInventory({
      required KeyState keys,
      required int readyWeapon,
      required List<int> weaponOwned,
      required bool commercial,
      required bool shareware,
      required bool cycleHeldPrev,
    }) {
      final cycleReq = keys.prevWeapon || keys.nextWeapon;
      if (cycleReq && !cycleHeldPrev && keys.weapon == 0) {
        final dir = keys.nextWeapon ? 1 : -1;
        final target = resolveWeaponCycle(
          dir: dir,
          readyWeapon: readyWeapon,
          weaponOwned: weaponOwned,
          commercial: commercial,
          shareware: shareware,
        );
        if (target != readyWeapon) keys.weapon = target + 1;
      }
      final cmd = TicCmd();
      builder.build(cmd, keys);
      return cmd;
    }

    test('prevWeapon action from pistol -> fist BT_CHANGE', () {
      // Press the PREV-weapon action; the bridge samples the held minus key.
      sink.pressAction(GameAction.prevWeapon);
      expect(sink.isKeyDown(DoomKey.minus), isTrue);

      final keys = bridge.build();
      expect(keys.prevWeapon, isTrue);
      expect(keys.weapon, 0); // unresolved at the bridge layer

      final cmd = buildWithInventory(
        keys: keys,
        readyWeapon: Wp.pistol,
        weaponOwned: List<int>.filled(Wp.numWeapons, 0)
          ..[Wp.fist] = 1
          ..[Wp.pistol] = 1,
        commercial: false,
        shareware: true,
        cycleHeldPrev: false,
      );
      expect(_decodeWeapon(cmd), Wp.fist);
      expect(cmd.buttons & btChangeWeapon, btChangeWeapon);
    });

    test('nextWeapon from pistol -> shotgun when owned', () {
      sink.pressAction(GameAction.nextWeapon);
      final keys = bridge.build();
      expect(keys.nextWeapon, isTrue);

      final cmd = buildWithInventory(
        keys: keys,
        readyWeapon: Wp.pistol,
        weaponOwned: List<int>.filled(Wp.numWeapons, 0)
          ..[Wp.fist] = 1
          ..[Wp.pistol] = 1
          ..[Wp.shotgun] = 1,
        commercial: false,
        shareware: true,
        cycleHeldPrev: false,
      );
      expect(_decodeWeapon(cmd), Wp.shotgun);
    });

    test('edge-triggered: held cycle key resolves only on rising edge', () {
      sink.pressAction(GameAction.prevWeapon);
      final keys = bridge.build();
      // Second tic with the key STILL held but cycleHeldPrev true: no change.
      final cmd = buildWithInventory(
        keys: keys,
        readyWeapon: Wp.pistol,
        weaponOwned: List<int>.filled(Wp.numWeapons, 0)
          ..[Wp.fist] = 1
          ..[Wp.pistol] = 1,
        commercial: false,
        shareware: true,
        cycleHeldPrev: true, // already held last tic
      );
      expect(cmd.buttons & btChangeWeapon, 0);
    });

    test('weapon1..7 direct select still works (vanilla)', () {
      for (var slot = 1; slot <= 7; slot++) {
        final s2 = EventQueueActionSink(EventQueue());
        final b2 = KeyStateBridge(s2);
        final action = <int, GameAction>{
          1: GameAction.weapon1,
          2: GameAction.weapon2,
          3: GameAction.weapon3,
          4: GameAction.weapon4,
          5: GameAction.weapon5,
          6: GameAction.weapon6,
          7: GameAction.weapon7,
        }[slot]!;
        s2.pressAction(action);
        final keys = b2.build();
        expect(keys.weapon, slot, reason: 'weapon$slot key -> slot');
        expect(keys.prevWeapon, isFalse);
        expect(keys.nextWeapon, isFalse);
        final cmd = TicCmd();
        TicCmdBuilder().build(cmd, keys);
        expect(_decodeWeapon(cmd), slot - 1,
            reason: 'weapon$slot -> weapontype ${slot - 1}');
        expect(cmd.buttons & btChangeWeapon, btChangeWeapon);
      }
    });

    test('zero input => no weapon change', () {
      final keys = bridge.build();
      expect(keys.weapon, 0);
      expect(keys.prevWeapon, isFalse);
      expect(keys.nextWeapon, isFalse);
      final cmd = buildWithInventory(
        keys: keys,
        readyWeapon: Wp.pistol,
        weaponOwned: List<int>.filled(Wp.numWeapons, 0)
          ..[Wp.fist] = 1
          ..[Wp.pistol] = 1,
        commercial: false,
        shareware: true,
        cycleHeldPrev: false,
      );
      expect(cmd.buttons & btChangeWeapon, 0);
    });

    test('direct number-key select takes precedence over a cycle key', () {
      // Both '1' and '-' down: the bridge picks slot 1 and suppresses prev.
      sink.pressAction(GameAction.weapon1);
      sink.pressAction(GameAction.prevWeapon);
      final keys = bridge.build();
      expect(keys.weapon, 1);
      expect(keys.prevWeapon, isFalse);
    });
  });
}
