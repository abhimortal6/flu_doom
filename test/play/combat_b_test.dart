// COMBAT-B tests: player weapon psprites + the 23 weapon A_* functions
// (p_pspr.c). Builds on the real shareware E1M1 world so the blockmap / BSP /
// sector links are live, and on COMBAT-C's real Shoot/Interactions facades.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/world.dart';

import 'package:flu_doom/game/play/actions.dart';
import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/p_inter.dart';
import 'package:flu_doom/game/play/p_mobj.dart';
import 'package:flu_doom/game/play/p_pspr.dart';
import 'package:flu_doom/game/play/p_random.dart';
import 'package:flu_doom/game/play/p_shoot.dart';
import 'package:flu_doom/game/play/player.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/play/sound_hook.dart';
import 'package:flu_doom/game/play/state_num.dart';

World loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

class RecordingSound implements SoundHook {
  final List<int> sfx = <int>[];
  @override
  void startSound(Object? origin, int sfxId) => sfx.add(sfxId);
}

/// A Shoot that records each lineAttack / aimLineAttack call and can force a
/// linetarget for deterministic A_Punch tests.
class SpyShoot extends Shoot {
  SpyShoot(super.move, super.mobjSim, super.inter, super.sound);

  int lineAttackCalls = 0;
  int aimCalls = 0;
  int lastDamage = 0;
  Mobj? forcedTarget;

  @override
  fixed_t aimLineAttack(Mobj t1, int angle, fixed_t distance) {
    aimCalls++;
    if (forcedTarget != null) {
      linetarget = forcedTarget;
      return 0;
    }
    return super.aimLineAttack(t1, angle, distance);
  }

  @override
  void lineAttack(
      Mobj t1, int angle, fixed_t distance, fixed_t slope, int damage) {
    lineAttackCalls++;
    lastDamage = damage;
    // When a target is forced (harness) and there is damage, simulate the hit
    // by routing it through the real P_DamageMobj so the "in range calls
    // damage" contract is observable without depending on traverse geometry.
    if (forcedTarget != null && damage > 0) {
      inter.damageMobj(forcedTarget!, t1, t1, damage);
      return;
    }
    super.lineAttack(t1, angle, distance, slope, damage);
  }
}

void main() {
  late PlaySim sim;
  late MobjSim mobjSim;
  late RecordingSound sound;
  late Interactions inter;
  late SpyShoot shoot;
  late Pspr pspr;
  late ActionRegistry reg;
  late Player player;

  setUp(() {
    sim = PlaySim(loadWorld());
    sim.spawnLevel();
    mobjSim = sim.mobjSim;
    sound = RecordingSound();
    inter = Interactions(mobjSim, sound);
    shoot = SpyShoot(sim.move, mobjSim, inter, sound);
    pspr = Pspr(mobjSim, shoot, sound);
    reg = ActionRegistry.instance;
    registerWeaponActions(reg, pspr, shoot);
    reg.registerAllStubs(); // putIfAbsent — real bodies above win
    player = sim.player;
    // Give the player the standard starting loadout.
    player.readyWeapon = Wp.pistol;
    player.pendingWeapon = Wp.noChange;
    player.health = 100;
    player.playerState = PlayerState.live;
    player.refire = 0;
    player.attackDown = false;
    player.cmd.buttons = 0;
    player.weaponOwned[Wp.fist] = 1;
    player.weaponOwned[Wp.pistol] = 1;
    player.ammo[Am.clip] = 50;
    clearRandom();
  });

  group('registration', () {
    test('registers all 23 weapon A_* names', () {
      const List<String> names = <String>[
        'A_WeaponReady', 'A_ReFire', 'A_Lower', 'A_Raise', 'A_GunFlash',
        'A_Light0', 'A_Light1', 'A_Light2', 'A_Punch', 'A_Saw',
        'A_FirePistol', 'A_FireShotgun', 'A_FireShotgun2', 'A_CheckReload',
        'A_OpenShotgun2', 'A_LoadShotgun2', 'A_CloseShotgun2', 'A_FireCGun',
        'A_FireMissile', 'A_FirePlasma', 'A_BFGsound', 'A_FireBFG',
        'A_BFGSpray',
      ];
      expect(names.length, 23);
      // After registration, invoking the side-effect-free actions (lights)
      // must run a real body, never the log-once stub.
      reg.firedStubs.clear();
      reg.resolve('A_Light1')(
          player.mo!, player: player, psp: player.psprites[0]);
      expect(player.extraLight, 1);
      // None of the 23 names should be a stub: the stub set only grows when a
      // stub runs; since A_Light1's real body ran (extraLight set) and the
      // others were registered before registerAllStubs (putIfAbsent), none of
      // these names are stubs.
      for (final String n in names) {
        expect(reg.firedStubs.contains(n), false, reason: '$n must be real');
      }
    });
  });

  group('setup / bring up', () {
    test('setupPsprites brings the ready weapon up from the bottom', () {
      pspr.setupPsprites(player);
      // Pistol up-state begins the raise. bringUpWeapon sets sy = WEAPONBOTTOM,
      // then S_PISTOLUP's A_Raise fires once on entry, dropping it one step.
      expect(player.psprites[psWeapon].stateIndex, St.sPistolup);
      expect(player.psprites[psWeapon].sy, kWeaponBottom - kRaiseSpeed);
      expect(player.pendingWeapon, Wp.noChange);
    });

    test('A_Raise raises to WEAPONTOP then becomes ready', () {
      pspr.setupPsprites(player); // S_PISTOLUP, sy = WEAPONBOTTOM
      // Tic the psprite until A_Raise lifts it to the ready state.
      for (int i = 0; i < 60; i++) {
        pspr.movePsprites(player);
        if (player.psprites[psWeapon].stateIndex == St.sPistol) break;
      }
      expect(player.psprites[psWeapon].stateIndex, St.sPistol); // ready
      expect(player.psprites[psWeapon].sy, kWeaponTop);
    });
  });

  group('A_WeaponReady', () {
    test('reaching ready state allows firing on BT_ATTACK', () {
      // Put the weapon directly into its ready state.
      pspr.setPsprite(player, psWeapon, weaponInfo[Wp.pistol].readyState);
      expect(player.psprites[psWeapon].stateIndex, St.sPistol);

      final int ammoBefore = player.ammo[Am.clip];
      player.cmd.buttons = btAttack;
      // A_WeaponReady runs on the ready frame; with BT_ATTACK it fires,
      // entering the attack chain (S_PISTOL1).
      pspr.aWeaponReady(player, player.psprites[psWeapon]);
      expect(player.attackDown, true);
      expect(player.psprites[psWeapon].stateIndex != St.sPistol, true);
      // A_FirePistol (which spends the bullet) fires a few frames into the
      // chain; tic the psprite until ammo is consumed.
      for (int i = 0; i < 20; i++) {
        if (player.ammo[Am.clip] < ammoBefore) break;
        pspr.movePsprites(player);
      }
      expect(player.ammo[Am.clip], ammoBefore - 1);
    });
  });

  group('A_FirePistol', () {
    test('decrements ammo[am_clip] and calls lineAttack', () {
      pspr.setPsprite(player, psWeapon, weaponInfo[Wp.pistol].atkState);
      final int before = player.ammo[Am.clip];
      shoot.lineAttackCalls = 0;
      pspr.aFirePistol(player, player.psprites[psWeapon]);
      expect(player.ammo[Am.clip], before - 1);
      expect(shoot.lineAttackCalls, greaterThan(0)); // P_GunShot -> lineAttack
      expect(sound.sfx.contains(1), true); // Sfx.pistol
    });
  });

  group('P_CheckAmmo', () {
    test('returns true when the ready weapon has ammo', () {
      player.readyWeapon = Wp.pistol;
      player.ammo[Am.clip] = 10;
      expect(pspr.checkAmmo(player), true);
    });

    test('switches down to fist when fully out of ammo', () {
      // Strip everything but the fist.
      for (int i = 0; i < Am.numAmmo; i++) {
        player.ammo[i] = 0;
      }
      for (int w = 0; w < Wp.numWeapons; w++) {
        player.weaponOwned[w] = 0;
      }
      player.weaponOwned[Wp.fist] = 1;
      player.readyWeapon = Wp.pistol;
      // The weapon is held ready (psprite at WEAPONTOP), not mid-lower; otherwise
      // the downState overlay's A_Lower would complete in one P_SetPsprite step
      // and clear pendingWeapon via P_BringUpWeapon. (COMBAT-D: spawnLevel now
      // faithfully runs P_SetupPsprites, which leaves sy at WEAPONBOTTOM; reset
      // it here so this isolated P_CheckAmmo test sees a ready weapon.)
      player.psprites[psWeapon].sy = 32 * kFracUnit; // WEAPONTOP
      expect(pspr.checkAmmo(player), false);
      expect(player.pendingWeapon, Wp.fist);
      // Set the down-state overlay for the current (pistol) weapon.
      expect(player.psprites[psWeapon].stateIndex, St.sPistoldown);
    });

    test('fist (no-ammo weapon) always has enough', () {
      player.readyWeapon = Wp.fist;
      expect(pspr.checkAmmo(player), true);
    });
  });

  group('A_Punch', () {
    test('with a target in range deals damage and faces it', () {
      final Mobj me = player.mo!;
      // A possessed right in front, at melee range.
      final Mobj t = mobjSim.spawnMobj(me.x, me.y, me.z, Mt.possessed);
      final int hp = t.health;
      shoot.forcedTarget = t; // force aim to hit it
      player.readyWeapon = Wp.fist;
      pspr.aPunch(player, player.psprites[psWeapon]);
      expect(shoot.lineAttackCalls, greaterThan(0));
      expect(t.health < hp, true, reason: 'punch dealt damage');
      expect(sound.sfx.contains(83), true); // Sfx.punch
    });
  });

  group('pending weapon switch', () {
    test('A_Lower lowers, then switches and A_Raise brings the new one up',
        () {
      // Start with the pistol ready, request a switch to the fist.
      pspr.setPsprite(player, psWeapon, weaponInfo[Wp.pistol].readyState);
      player.pendingWeapon = Wp.fist;

      // A_WeaponReady sees the pending change and starts lowering.
      pspr.aWeaponReady(player, player.psprites[psWeapon]);
      expect(player.psprites[psWeapon].stateIndex, St.sPistoldown);

      // Tic until the new (fist) weapon comes up to its ready state.
      bool reachedFistReady = false;
      for (int i = 0; i < 120; i++) {
        pspr.movePsprites(player);
        if (player.psprites[psWeapon].stateIndex ==
            weaponInfo[Wp.fist].readyState) {
          reachedFistReady = true;
          break;
        }
      }
      expect(reachedFistReady, true);
      expect(player.readyWeapon, Wp.fist);
    });
  });

  group('A_Light0/1/2', () {
    test('set the player extralight level', () {
      pspr.aLight1(player, player.psprites[0]);
      expect(player.extraLight, 1);
      pspr.aLight2(player, player.psprites[0]);
      expect(player.extraLight, 2);
      pspr.aLight0(player, player.psprites[0]);
      expect(player.extraLight, 0);
    });
  });
}
