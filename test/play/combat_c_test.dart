// COMBAT-C tests: damage / kill transitions, pickups + inventory caps, puff /
// blood spawning, radius-attack falloff, and path-traverse intercept ordering.
// Builds on the real shareware E1M1 world so the blockmap / BSP / sector links
// are all live (no hand-built fakes).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/world.dart';

import 'package:flu_doom/game/play/info.dart';
import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/mobj_flags.dart';
import 'package:flu_doom/game/play/p_inter.dart';
import 'package:flu_doom/game/play/p_mobj.dart';
import 'package:flu_doom/game/play/p_random.dart';
import 'package:flu_doom/game/play/p_shoot.dart';
import 'package:flu_doom/game/play/player.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/play/sound_hook.dart';

World loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

/// A SoundHook that records every (origin, sfx) it is told to play.
class RecordingSound implements SoundHook {
  final List<int> sfx = <int>[];
  @override
  void startSound(Object? origin, int sfxId) => sfx.add(sfxId);
}

void main() {
  late PlaySim sim;
  late MobjSim mobjSim;
  late RecordingSound sound;
  late Interactions inter;
  late Shoot shoot;

  setUp(() {
    sim = PlaySim(loadWorld());
    sim.spawnLevel();
    mobjSim = sim.mobjSim;
    sound = RecordingSound();
    inter = Interactions(mobjSim, sound);
    shoot = Shoot(sim.move, mobjSim, inter, sound);
    // Deterministic gameplay rng for the tests that read pRandom().
    clearRandom();
  });

  // Spawn a fresh possessed at the player's feet so floor/ceiling are valid.
  Mobj spawnPossessedAtPlayer() {
    final Mobj p = sim.player.mo!;
    return mobjSim.spawnMobj(p.x, p.y, p.z, Mt.possessed);
  }

  group('damageMobj', () {
    test('non-lethal damage enters painState on a forced pRandom roll', () {
      final Mobj t = spawnPossessedAtPlayer();
      expect(t.health, 20);
      // No inflictor => no thrust pRandom; pain check is the first pRandom().
      // After clearRandom the first pRandom() == rndtable[1] == 8 < 200.
      inter.damageMobj(t, null, null, 5);
      expect(t.health, 15);
      expect(t.stateIndex, t.info.painState); // 187
      expect((t.flags & mfJustHit) != 0, true);
    });

    test('lethal damage enters deathState', () {
      final Mobj t = spawnPossessedAtPlayer();
      inter.damageMobj(t, null, null, 25); // 20 - 25 = -5, >= -spawnhealth(-20)
      expect(t.health <= 0, true);
      // killMobj set the (regular) death chain.
      expect(t.stateIndex, t.info.deathState); // 189
      expect((t.flags & mfCorpse) != 0, true);
      expect((t.flags & mfShootable) == 0, true);
    });

    test('gib damage (health < -spawnhealth) enters xdeathState', () {
      final Mobj t = spawnPossessedAtPlayer();
      inter.damageMobj(t, null, null, 41); // 20 - 41 = -21 < -20 => xdeath
      expect(t.health, -21);
      expect(t.stateIndex, t.info.xdeathState); // 194
    });
  });

  group('pickups / inventory', () {
    test('giveAmmo respects maxAmmo and the backpack doubling', () {
      final Player p = sim.player;
      // Start fresh.
      p.ammo[Am.clip] = 0;
      p.maxAmmo[Am.clip] = maxAmmo[Am.clip]; // 200
      p.backpack = false;

      // One clip = clipammo[am_clip]*1 = 10.
      expect(inter.giveAmmo(p, Am.clip, 1), true);
      expect(p.ammo[Am.clip], 10);

      // Fill to the cap and confirm clamping + the no-pickup return.
      p.ammo[Am.clip] = 200;
      expect(inter.giveAmmo(p, Am.clip, 5), false);
      expect(p.ammo[Am.clip], 200);

      // Backpack via touchSpecialThing doubles maxAmmo.
      p.ammo[Am.clip] = 0;
      final Mobj bpak =
          mobjSim.spawnMobj(p.mo!.x, p.mo!.y, p.mo!.z, Mt.player);
      bpak.sprite = SpriteNum.bpak;
      inter.touchSpecialThing(bpak, p.mo!);
      expect(p.backpack, true);
      expect(p.maxAmmo[Am.clip], 400);
    });

    test('giveBody caps at MAXHEALTH and rejects when full', () {
      final Player p = sim.player;
      p.health = 100;
      expect(inter.giveBody(p, 25), false); // already at max
      p.health = 90;
      expect(inter.giveBody(p, 25), true);
      expect(p.health, 100); // capped
    });

    test('weapon pickup gives the weapon, ammo, and plays wpnup', () {
      final Player p = sim.player;
      p.weaponOwned[Wp.shotgun] = 0;
      p.ammo[Am.shell] = 0;
      final Mobj shot =
          mobjSim.spawnMobj(p.mo!.x, p.mo!.y, p.mo!.z, Mt.player);
      shot.sprite = SpriteNum.shot;
      inter.touchSpecialThing(shot, p.mo!);
      expect(p.weaponOwned[Wp.shotgun], 1);
      expect(p.ammo[Am.shell], greaterThan(0));
      expect(sound.sfx.contains(33), true); // Sfx.wpnup
    });
  });

  group('spawnPuff / spawnBlood', () {
    test('spawnPuff creates an MT_PUFF with the puff sprite', () {
      final Mobj p = sim.player.mo!;
      shoot.attackRange = kMissileRange; // not melee => no S_PUFF3 swap
      final int before = sim.thinkers.count;
      shoot.spawnPuff(p.x, p.y, p.z);
      expect(sim.thinkers.count, before + 1);
      // The most recently spawned mobj is the puff.
      final Mobj puff = _lastMobj(sim);
      expect(puff.type, Mt.puff);
      expect(puff.sprite, SpriteNum.puff);
    });

    test('spawnBlood creates an MT_BLOOD with the blood sprite', () {
      final Mobj p = sim.player.mo!;
      shoot.spawnBlood(p.x, p.y, p.z, 20); // damage > 12 => default chain
      final Mobj blood = _lastMobj(sim);
      expect(blood.type, Mt.blood);
      expect(blood.sprite, SpriteNum.blud);
    });
  });

  group('radiusAttack', () {
    test('damages a nearby mobj but not a far one', () {
      final Mobj p = sim.player.mo!;
      // Always-visible LOS so we test the falloff, not sight.
      shoot.checkSight = (Mobj a, Mobj b) => true;

      // Near target right next to the blast spot.
      final Mobj near =
          mobjSim.spawnMobj(toInt32(p.x + 16 * kFracUnit), p.y, p.z,
              Mt.possessed);
      // Far target well beyond the 128-unit blast radius.
      final Mobj far =
          mobjSim.spawnMobj(toInt32(p.x + 4000 * kFracUnit), p.y, p.z,
              Mt.possessed);
      final int nearHp = near.health;
      final int farHp = far.health;

      // Blast spot at the player; damage 128.
      final Mobj spot = mobjSim.spawnMobj(p.x, p.y, p.z, Mt.player);
      spot.flags &= ~mfShootable; // the spot itself shouldn't matter
      shoot.radiusAttack(spot, null, 128);

      expect(near.health < nearHp, true, reason: 'near target took damage');
      expect(far.health, farHp, reason: 'far target out of range');
    });
  });

  group('pathTraverse', () {
    test('visits intercepts in increasing frac order', () {
      final Mobj p = sim.player.mo!;
      final List<double> fracs = <double>[];
      // Trace a long ray; collect every intercept frac.
      shoot.pathTraverse(
        p.x,
        p.y,
        toInt32(p.x + 1024 * kFracUnit),
        p.y,
        ptAddLines | ptAddThings,
        (Intercept it) {
          fracs.add(it.frac.toDouble());
          return true; // keep going to gather all of them
        },
      );
      expect(fracs.length, greaterThan(0));
      // P_TraverseIntercepts hands them out smallest-frac first.
      for (int i = 1; i < fracs.length; i++) {
        expect(fracs[i] >= fracs[i - 1], true,
            reason: 'frac order non-decreasing');
      }
    });
  });
}

/// Returns the most-recently-added Mobj on the thinker list.
Mobj _lastMobj(PlaySim sim) {
  Mobj? last;
  for (final dynamic t in sim.thinkers.thinkers) {
    if (t is Mobj) last = t;
  }
  return last!;
}
