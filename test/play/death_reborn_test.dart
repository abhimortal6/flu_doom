// DEATH -> REBORN flow (p_user.c P_DeathThink + p_inter.c P_KillMobj player
// branch + g_game.c G_DoReborn) plus the ST_doPaletteStuff palette selection.
//
// Built on the real shareware E1M1 world so the BSP / blockmap / sector links
// are all live and the level genuinely reloads on reborn.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/game/world/ticcmd.dart';

import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/p_user.dart';
import 'package:flu_doom/game/play/player.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/play/state_num.dart';

import 'package:flu_doom/game/state/interfaces.dart';

World loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  final WadFile wad =
      WadFile.fromBytes(Uint8List.fromList(f.readAsBytesSync()));
  return World.fromWad(wad);
}

/// The contiguous player death-animation state indices (S_PLAY_DIE1..DIE7 and
/// the gib S_PLAY_XDIE1..XDIE9). The mobj should be in one of these after a
/// lethal P_KillMobj.
bool isPlayerDeathState(int idx) =>
    (idx >= St.sPlayDie1 && idx <= St.sPlayDie7) ||
    (idx >= St.sPlayXdie1 && idx <= St.sPlayXdie1 + 8);

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  group('death -> reborn', () {
    test('lethal damage kills the player and starts the death animation', () {
      final PlaySim sim = PlaySim(loadWorld());
      sim.spawnLevel();
      final Player p = sim.player;

      // Give some inventory that death must NOT carry.
      p.weaponOwned[Wp.shotgun] = 1;
      p.weaponOwned[Wp.chaingun] = 1;
      p.cards[0] = true; // blue card
      p.ammo[Am.shell] = 20;
      p.armorPoints = 100;
      p.armorType = 1;

      expect(p.playerState, PlayerState.live);

      // P_DamageMobj the player past 0 -> P_KillMobj player branch.
      sim.interactions.damageMobj(p.mo!, null, null, 1000);

      expect(p.health, lessThanOrEqualTo(0));
      expect(p.playerState, PlayerState.dead);
      expect(isPlayerDeathState(p.mo!.stateIndex), isTrue,
          reason: 'player mobj should be in a death state '
              '(was ${p.mo!.stateIndex})');
      // MF_SOLID cleared in the player branch is left to the mobj-flag check.
    });

    test('P_DeathThink lowers the view toward 6*FRACUNIT', () {
      final PlaySim sim = PlaySim(loadWorld());
      sim.spawnLevel();
      final Player p = sim.player;

      sim.interactions.damageMobj(p.mo!, null, null, 1000);
      expect(p.playerState, PlayerState.dead);

      final int before = p.viewHeight;
      expect(before, greaterThan(kDeathViewHeight));

      // Run a few tics with no buttons: viewheight falls by FRACUNIT/tic.
      final TicCmd cmd = TicCmd();
      for (int i = 0; i < 3; i++) {
        sim.tic(cmd);
      }

      expect(p.viewHeight, lessThan(before));

      // Eventually settles at exactly 6*FRACUNIT.
      for (int i = 0; i < 60; i++) {
        sim.tic(cmd);
      }
      expect(p.viewHeight, kDeathViewHeight);
    });

    test('BT_USE after death reborns: current map reloads, inventory reset', () {
      final PlaySim sim = PlaySim(loadWorld());
      sim.spawnLevel();
      final Player p = sim.player;
      final String mapBefore = sim.world.level.name;

      // Inventory that death should lose.
      p.weaponOwned[Wp.shotgun] = 1;
      p.weaponOwned[Wp.chaingun] = 1;
      p.cards[2] = true; // red card
      p.ammo[Am.shell] = 30;
      p.backpack = true;

      sim.interactions.damageMobj(p.mo!, null, null, 1000);
      expect(p.playerState, PlayerState.dead);

      // Settle the death view, then press USE -> PST_REBORN -> G_DoReborn.
      final TicCmd idle = TicCmd();
      for (int i = 0; i < 5; i++) {
        sim.tic(idle);
      }

      final TicCmd use = TicCmd()..buttons = btUse;
      sim.tic(use);

      // Map reloaded (same map, single-player) and the player is fully reset.
      expect(sim.world.level.name, mapBefore);
      expect(sim.player.playerState, PlayerState.live);
      expect(sim.player.health, 100);
      expect(sim.player.readyWeapon, Wp.pistol);
      expect(sim.player.weaponOwned[Wp.fist], 1);
      expect(sim.player.weaponOwned[Wp.pistol], 1);
      expect(sim.player.weaponOwned[Wp.shotgun], 0,
          reason: 'death must NOT carry weapons (unlike level exit)');
      expect(sim.player.weaponOwned[Wp.chaingun], 0);
      expect(sim.player.ammo[Am.clip], 50);
      expect(sim.player.ammo[Am.shell], 0);
      expect(sim.player.cards[2], isFalse);
      expect(sim.player.backpack, isFalse);
    });
  });

  group('ST_doPaletteStuff palette selection', () {
    test('damagecount selects a red palette in 1..8', () {
      for (final int dc in <int>[1, 8, 16, 100]) {
        final int idx = stPaletteIndex(
          damageCount: dc,
          bonusCount: 0,
          strengthTics: 0,
          ironfeetTics: 0,
        );
        expect(idx, inInclusiveRange(kStartRedPals, kStartRedPals + kNumRedPals - 1),
            reason: 'damageCount $dc should map to a red palette');
      }
    });

    test('bonuscount selects a yellow palette in 9..12 (no damage)', () {
      for (final int bc in <int>[1, 8, 24]) {
        final int idx = stPaletteIndex(
          damageCount: 0,
          bonusCount: bc,
          strengthTics: 0,
          ironfeetTics: 0,
        );
        expect(
            idx,
            inInclusiveRange(
                kStartBonusPals, kStartBonusPals + kNumBonusPals - 1),
            reason: 'bonusCount $bc should map to a yellow palette');
      }
    });

    test('radsuit selects RADIATIONPAL (13), base otherwise', () {
      expect(
        stPaletteIndex(
            damageCount: 0,
            bonusCount: 0,
            strengthTics: 0,
            ironfeetTics: 5 * 32),
        kRadiationPal,
      );
      expect(
        stPaletteIndex(
            damageCount: 0, bonusCount: 0, strengthTics: 0, ironfeetTics: 0),
        0,
      );
    });

    test('damage outranks bonus, and berserk fade tints red', () {
      // damage present -> red even with bonus also set.
      expect(
        stPaletteIndex(
                damageCount: 4,
                bonusCount: 4,
                strengthTics: 0,
                ironfeetTics: 0) >=
            kStartRedPals,
        isTrue,
      );
      // fresh berserk (powers[pw_strength]==1) -> bzc = 12 -> red.
      final int idx = stPaletteIndex(
          damageCount: 0, bonusCount: 0, strengthTics: 1, ironfeetTics: 0);
      expect(idx, inInclusiveRange(kStartRedPals, kStartRedPals + kNumRedPals - 1));
    });
  });
}
