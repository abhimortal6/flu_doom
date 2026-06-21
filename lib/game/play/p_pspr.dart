// Weapon sprite animation and weapon action functions, ported from
// Chocolate Doom src/doom/p_pspr.c (and the weapon data in d_items.c, already
// transcribed into info_tables.dart's weaponInfo[]).
//
// This is COMBAT-B (CONTRACTS_COMBAT §4 / §10). It owns the player psprite
// driver (P_SetupPsprites / P_MovePsprites / P_SetPsprite / P_BringUpWeapon /
// P_CheckAmmo / P_FireWeapon / P_DropWeapon / P_CalcSwing) and all 23 weapon
// A_* functions (incl. A_BFGSpray).
//
// Faithfulness is mandatory: this is a faithful port, not a paraphrase.
//
// Dependencies are read-only facades:
//   - [MobjSim] (p_mobj.dart): P_SetMobjState, P_SpawnMobj.
//   - [Shoot]   (p_shoot.dart): P_AimLineAttack / P_LineAttack /
//                P_SpawnPlayerMissile / P_BulletSlope / linetarget.
//   - COMBAT-C's [Interactions] (p_inter.dart) via [Shoot.inter] for
//                P_DamageMobj (A_BFGSpray).
//   - [SoundHook]: every vanilla S_StartSound call site.
//
// Weapon A_* are dispatched through the existing [ActionRegistry] whose
// MobjAction signature `void Function(Mobj, {Player?, Pspdef?})` already carries
// player + psp; weapon actions read player/psp and ignore the Mobj arg (they
// pass player.mo! internally), exactly as vanilla passes (player, psp).

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../../engine/math/tables.dart';
import 'actions.dart';
import 'info.dart';
import 'info_tables.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_mobj.dart';
import 'p_random.dart';
import 'p_shoot.dart';
import 'player.dart';
import 'sound_hook.dart';
import 'sounds.dart';
import 'state_num.dart';

// #define LOWERSPEED	FRACUNIT*6
const fixed_t kLowerSpeed = 6 * kFracUnit;

// #define RAISESPEED	FRACUNIT*6
const fixed_t kRaiseSpeed = 6 * kFracUnit;

// #define WEAPONBOTTOM	128*FRACUNIT
const fixed_t kWeaponBottom = 128 * kFracUnit;

// #define WEAPONTOP	32*FRACUNIT
const fixed_t kWeaponTop = 32 * kFracUnit;

// deh_bfg_cells_per_shot (deh_misc.c default).
const int kBfgCellsPerShot = 40;

/// Vanilla `GameMode_t` (doomdef.h), needed by P_CheckAmmo's shareware/
/// commercial branches. COMBAT-D may set [Pspr.gameMode]; default commercial
/// so the full weapon set (SSG/plasma/BFG) is available.
enum GameMode {
  shareware,
  registered,
  commercial,
  retail,
  indetermined,
}

/// BT_ATTACK (d_event.h). The renderer/integration sets this bit in the
/// player's ticcmd buttons when the fire button is held.
const int btAttack = 1;

/// Weapon sprite animation + weapon action functions. One instance per playsim;
/// COMBAT-D injects it and updates [levelTime]/[gameMode] each tic.
class Pspr {
  Pspr(this.mobjSim, this.shoot, this.sound);

  final MobjSim mobjSim;
  final Shoot shoot;
  final SoundHook sound;

  /// Global `leveltime` (g_game.c), updated by COMBAT-D each tic. Used by
  /// A_WeaponReady (weapon bob) and P_CalcSwing.
  int levelTime = 0;

  /// Global `gamemode` (doomstat.c). Affects P_CheckAmmo weapon preference.
  GameMode gameMode = GameMode.commercial;

  // --- P_CalcSwing outputs (p_pspr.c file-scope swingx/swingy). ---
  fixed_t swingX = 0;
  fixed_t swingY = 0;

  // =======================================================================
  // P_SetPsprite (p_pspr.c)
  // =======================================================================
  void setPsprite(Player player, int position, int stnum) {
    final Pspdef psp = player.psprites[position];

    do {
      if (stnum == 0) {
        // object removed itself
        psp.stateIndex = 0;
        break;
      }

      final State state = states[stnum];
      psp.stateIndex = stnum;
      psp.tics = state.tics; // could be 0

      if (state.misc1 != 0) {
        // coordinate set
        psp.sx = state.misc1 << kFracBits;
        psp.sy = state.misc2 << kFracBits;
      }

      // Call action routine.
      // Modified handling.
      if (state.action != null) {
        ActionRegistry.instance.resolve(state.action)(
          player.mo!,
          player: player,
          psp: psp,
        );
        if (psp.stateIndex == 0) {
          break;
        }
      }

      stnum = states[psp.stateIndex].nextState;
    } while (psp.tics == 0);
    // an initial state of 0 could cycle through
  }

  // =======================================================================
  // P_CalcSwing (p_pspr.c)
  // =======================================================================
  void calcSwing(Player player) {
    // OPTIMIZE: tablify this.
    // A LUT would allow for different modes,
    //  and add flexibility.

    final fixed_t swing = player.bob;

    int angle = (kFineAngles ~/ 70 * levelTime) & kFineMask;
    swingX = fixedMul(swing, finesine[angle]);

    angle = (kFineAngles ~/ 70 * levelTime + kFineAngles ~/ 2) & kFineMask;
    swingY = toInt32(-fixedMul(swingX, finesine[angle]));
  }

  // =======================================================================
  // P_BringUpWeapon (p_pspr.c)
  // =======================================================================
  void bringUpWeapon(Player player) {
    if (player.pendingWeapon == Wp.noChange) {
      player.pendingWeapon = player.readyWeapon;
    }

    if (player.pendingWeapon == Wp.chainsaw) {
      sound.startSound(player.mo, Sfx.sawup);
    }

    final int newstate = weaponInfo[player.pendingWeapon].upState;

    player.pendingWeapon = Wp.noChange;
    player.psprites[psWeapon].sy = kWeaponBottom;

    setPsprite(player, psWeapon, newstate);
  }

  // =======================================================================
  // P_CheckAmmo (p_pspr.c)
  // =======================================================================
  bool checkAmmo(Player player) {
    final int ammo = weaponInfo[player.readyWeapon].ammo;
    int count;

    // Minimal amount for one shot varies.
    if (player.readyWeapon == Wp.bfg) {
      count = kBfgCellsPerShot;
    } else if (player.readyWeapon == Wp.supershotgun) {
      count = 2; // Double barrel.
    } else {
      count = 1; // Regular.
    }

    // Some do not need ammunition anyway.
    // Return if current ammunition sufficient.
    if (ammo == Am.noAmmo || player.ammo[ammo] >= count) {
      return true;
    }

    // Out of ammo, pick a weapon to change to.
    // Preferences are set here.
    do {
      if (player.weaponOwned[Wp.plasma] != 0 &&
          player.ammo[Am.cell] != 0 &&
          gameMode != GameMode.shareware) {
        player.pendingWeapon = Wp.plasma;
      } else if (player.weaponOwned[Wp.supershotgun] != 0 &&
          player.ammo[Am.shell] > 2 &&
          gameMode == GameMode.commercial) {
        player.pendingWeapon = Wp.supershotgun;
      } else if (player.weaponOwned[Wp.chaingun] != 0 &&
          player.ammo[Am.clip] != 0) {
        player.pendingWeapon = Wp.chaingun;
      } else if (player.weaponOwned[Wp.shotgun] != 0 &&
          player.ammo[Am.shell] != 0) {
        player.pendingWeapon = Wp.shotgun;
      } else if (player.ammo[Am.clip] != 0) {
        player.pendingWeapon = Wp.pistol;
      } else if (player.weaponOwned[Wp.chainsaw] != 0) {
        player.pendingWeapon = Wp.chainsaw;
      } else if (player.weaponOwned[Wp.missile] != 0 &&
          player.ammo[Am.misl] != 0) {
        player.pendingWeapon = Wp.missile;
      } else if (player.weaponOwned[Wp.bfg] != 0 &&
          player.ammo[Am.cell] > 40 &&
          gameMode != GameMode.shareware) {
        player.pendingWeapon = Wp.bfg;
      } else {
        // If everything fails.
        player.pendingWeapon = Wp.fist;
      }
    } while (player.pendingWeapon == Wp.noChange);

    // Now set appropriate weapon overlay.
    setPsprite(
        player, psWeapon, weaponInfo[player.readyWeapon].downState);

    return false;
  }

  // =======================================================================
  // P_FireWeapon (p_pspr.c)
  // =======================================================================
  void fireWeapon(Player player) {
    if (!checkAmmo(player)) {
      return;
    }

    mobjSim.setMobjState(player.mo!, St.sPlayAtk1);
    final int newstate = weaponInfo[player.readyWeapon].atkState;
    setPsprite(player, psWeapon, newstate);
    // P_NoiseAlert (player->mo, player->mo) — COMBAT-A owns P_NoiseAlert; it is
    // not part of COMBAT-B's file ownership, and there is no facade for it here.
    // Omitting it only delays a sleeping monster waking from the player's own
    // gunfire (documented faithful degradation; AI wakeup also occurs on
    // damage and on sight via A_Look).
  }

  // =======================================================================
  // P_DropWeapon (p_pspr.c)
  // =======================================================================
  void dropWeapon(Player player) {
    setPsprite(
        player, psWeapon, weaponInfo[player.readyWeapon].downState);
  }

  // =======================================================================
  // A_WeaponReady (p_pspr.c)
  // =======================================================================
  void aWeaponReady(Player player, Pspdef psp) {
    final Mobj mo = player.mo!;

    // get out of attack state
    if (mo.stateIndex == St.sPlayAtk1 || mo.stateIndex == St.sPlayAtk2) {
      mobjSim.setMobjState(mo, St.sPlay);
    }

    if (player.readyWeapon == Wp.chainsaw &&
        psp.stateIndex == St.sSaw) {
      sound.startSound(mo, Sfx.sawidl);
    }

    // check for change
    //  if player is dead, put the weapon away
    if (player.pendingWeapon != Wp.noChange || player.health == 0) {
      // change weapon
      //  (pending weapon should allready be validated)
      final int newstate = weaponInfo[player.readyWeapon].downState;
      setPsprite(player, psWeapon, newstate);
      return;
    }

    // check for fire
    //  the missile launcher and bfg do not auto fire
    if ((player.cmd.buttons & btAttack) != 0) {
      if (!player.attackDown ||
          (player.readyWeapon != Wp.missile &&
              player.readyWeapon != Wp.bfg)) {
        player.attackDown = true;
        fireWeapon(player);
        return;
      }
    } else {
      player.attackDown = false;
    }

    // bob the weapon based on movement speed
    int angle = (128 * levelTime) & kFineMask;
    psp.sx = toInt32(kFracUnit + fixedMul(player.bob, finecosine[angle]));
    angle &= kFineAngles ~/ 2 - 1;
    psp.sy = toInt32(kWeaponTop + fixedMul(player.bob, finesine[angle]));
  }

  // =======================================================================
  // A_ReFire (p_pspr.c)
  // =======================================================================
  void aReFire(Player player, Pspdef psp) {
    // check for fire
    //  (if a weaponchange is pending, let it go through instead)
    if ((player.cmd.buttons & btAttack) != 0 &&
        player.pendingWeapon == Wp.noChange &&
        player.health != 0) {
      player.refire++;
      fireWeapon(player);
    } else {
      player.refire = 0;
      checkAmmo(player);
    }
  }

  // =======================================================================
  // A_CheckReload (p_pspr.c)
  // =======================================================================
  void aCheckReload(Player player, Pspdef psp) {
    checkAmmo(player);
  }

  // =======================================================================
  // A_Lower (p_pspr.c)
  // =======================================================================
  void aLower(Player player, Pspdef psp) {
    psp.sy = toInt32(psp.sy + kLowerSpeed);

    // Is already down.
    if (psp.sy < kWeaponBottom) {
      return;
    }

    // Player is dead.
    if (player.playerState == PlayerState.dead) {
      psp.sy = kWeaponBottom;
      // don't bring weapon back up
      return;
    }

    // The old weapon has been lowered off the screen,
    // so change the weapon and start raising it
    if (player.health == 0) {
      // Player is dead, so keep the weapon off screen.
      setPsprite(player, psWeapon, St.sNull);
      return;
    }

    player.readyWeapon = player.pendingWeapon;

    bringUpWeapon(player);
  }

  // =======================================================================
  // A_Raise (p_pspr.c)
  // =======================================================================
  void aRaise(Player player, Pspdef psp) {
    psp.sy = toInt32(psp.sy - kRaiseSpeed);

    if (psp.sy > kWeaponTop) {
      return;
    }

    psp.sy = kWeaponTop;

    // The weapon has been raised all the way,
    //  so change to the ready state.
    final int newstate = weaponInfo[player.readyWeapon].readyState;

    setPsprite(player, psWeapon, newstate);
  }

  // =======================================================================
  // A_GunFlash (p_pspr.c)
  // =======================================================================
  void aGunFlash(Player player, Pspdef psp) {
    mobjSim.setMobjState(player.mo!, St.sPlayAtk2);
    setPsprite(
        player, psFlash, weaponInfo[player.readyWeapon].flashState);
  }

  // =======================================================================
  // WEAPON ATTACKS
  // =======================================================================

  // =======================================================================
  // A_Punch (p_pspr.c)
  // =======================================================================
  void aPunch(Player player, Pspdef psp) {
    final Mobj mo = player.mo!;

    int damage = (pRandom() % 10 + 1) << 1;

    if (player.powers[pwStrength] != 0) {
      damage *= 10;
    }

    angle_t angle = mo.angle;
    angle = normAngle(angle + (pSubRandom() << 18));
    final fixed_t slope = shoot.aimLineAttack(mo, angle, kMeleeRange);
    shoot.lineAttack(mo, angle, kMeleeRange, slope, damage);

    // turn to face target
    if (shoot.linetarget != null) {
      sound.startSound(mo, Sfx.punch);
      mo.angle = _pointToAngle2(
        mo.x,
        mo.y,
        shoot.linetarget!.x,
        shoot.linetarget!.y,
      );
    }
  }

  // =======================================================================
  // A_Saw (p_pspr.c)
  // =======================================================================
  void aSaw(Player player, Pspdef psp) {
    final Mobj mo = player.mo!;

    final int damage = 2 * (pRandom() % 10 + 1);
    angle_t angle = mo.angle;
    angle = normAngle(angle + (pSubRandom() << 18));

    // use meleerange + 1 se the puff doesn't skip the flash
    final fixed_t slope = shoot.aimLineAttack(mo, angle, kMeleeRange + 1);
    shoot.lineAttack(mo, angle, kMeleeRange + 1, slope, damage);

    if (shoot.linetarget == null) {
      sound.startSound(mo, Sfx.sawful);
      return;
    }
    sound.startSound(mo, Sfx.sawhit);

    // turn to face target
    angle = _pointToAngle2(
        mo.x, mo.y, shoot.linetarget!.x, shoot.linetarget!.y);
    if (normAngle(angle - mo.angle) > kAng180) {
      if (_signed32(normAngle(angle - mo.angle)) < -(kAng90 ~/ 20)) {
        mo.angle = normAngle(angle + kAng90 ~/ 21);
      } else {
        mo.angle = normAngle(mo.angle - kAng90 ~/ 20);
      }
    } else {
      if (normAngle(angle - mo.angle) > kAng90 ~/ 20) {
        mo.angle = normAngle(angle - kAng90 ~/ 21);
      } else {
        mo.angle = normAngle(mo.angle + kAng90 ~/ 20);
      }
    }
    mo.flags |= mfJustAttacked;
  }

  // Doom does not check the bounds of the ammo array. As a result, it is
  // possible to use an ammo type > 4 that overflows into the maxammo array and
  // affects that instead. Emulate this. (DecreaseAmmo, p_pspr.c)
  void _decreaseAmmo(Player player, int ammonum, int amount) {
    if (ammonum < Am.numAmmo) {
      player.ammo[ammonum] -= amount;
    } else {
      player.maxAmmo[ammonum - Am.numAmmo] -= amount;
    }
  }

  // =======================================================================
  // A_FireMissile (p_pspr.c)
  // =======================================================================
  void aFireMissile(Player player, Pspdef psp) {
    _decreaseAmmo(player, weaponInfo[player.readyWeapon].ammo, 1);
    shoot.spawnPlayerMissile(player.mo!, Mt.rocket);
  }

  // =======================================================================
  // A_FireBFG (p_pspr.c)
  // =======================================================================
  void aFireBFG(Player player, Pspdef psp) {
    _decreaseAmmo(
        player, weaponInfo[player.readyWeapon].ammo, kBfgCellsPerShot);
    shoot.spawnPlayerMissile(player.mo!, Mt.bfg);
  }

  // =======================================================================
  // A_FirePlasma (p_pspr.c)
  // =======================================================================
  void aFirePlasma(Player player, Pspdef psp) {
    _decreaseAmmo(player, weaponInfo[player.readyWeapon].ammo, 1);

    setPsprite(
      player,
      psFlash,
      weaponInfo[player.readyWeapon].flashState + (pRandom() & 1),
    );

    shoot.spawnPlayerMissile(player.mo!, Mt.plasma);
  }

  // =======================================================================
  // P_BulletSlope (p_pspr.c) — delegates to Shoot.bulletSlope (COMBAT-C).
  // =======================================================================
  void _bulletSlope(Mobj mo) {
    shoot.bulletSlope(mo);
  }

  // =======================================================================
  // P_GunShot (p_pspr.c)
  // =======================================================================
  void _gunShot(Mobj mo, bool accurate) {
    final int damage = 5 * (pRandom() % 3 + 1);
    angle_t angle = mo.angle;

    if (!accurate) {
      angle = normAngle(angle + (pSubRandom() << 18));
    }

    shoot.lineAttack(
        mo, angle, kMissileRange, shoot.bulletSlopeValue, damage);
  }

  // =======================================================================
  // A_FirePistol (p_pspr.c)
  // =======================================================================
  void aFirePistol(Player player, Pspdef psp) {
    final Mobj mo = player.mo!;
    sound.startSound(mo, Sfx.pistol);

    mobjSim.setMobjState(mo, St.sPlayAtk2);
    _decreaseAmmo(player, weaponInfo[player.readyWeapon].ammo, 1);

    setPsprite(
        player, psFlash, weaponInfo[player.readyWeapon].flashState);

    _bulletSlope(mo);
    _gunShot(mo, player.refire == 0);
  }

  // =======================================================================
  // A_FireShotgun (p_pspr.c)
  // =======================================================================
  void aFireShotgun(Player player, Pspdef psp) {
    final Mobj mo = player.mo!;
    sound.startSound(mo, Sfx.shotgn);
    mobjSim.setMobjState(mo, St.sPlayAtk2);

    _decreaseAmmo(player, weaponInfo[player.readyWeapon].ammo, 1);

    setPsprite(
        player, psFlash, weaponInfo[player.readyWeapon].flashState);

    _bulletSlope(mo);

    for (int i = 0; i < 7; i++) {
      _gunShot(mo, false);
    }
  }

  // =======================================================================
  // A_FireShotgun2 (p_pspr.c)
  // =======================================================================
  void aFireShotgun2(Player player, Pspdef psp) {
    final Mobj mo = player.mo!;
    sound.startSound(mo, Sfx.dshtgn);
    mobjSim.setMobjState(mo, St.sPlayAtk2);

    _decreaseAmmo(player, weaponInfo[player.readyWeapon].ammo, 2);

    setPsprite(
        player, psFlash, weaponInfo[player.readyWeapon].flashState);

    _bulletSlope(mo);

    for (int i = 0; i < 20; i++) {
      final int damage = 5 * (pRandom() % 3 + 1);
      angle_t angle = mo.angle;
      angle = normAngle(angle + (pSubRandom() << kAngleToFineShift));
      shoot.lineAttack(
        mo,
        angle,
        kMissileRange,
        toInt32(shoot.bulletSlopeValue + (pSubRandom() << 5)),
        damage,
      );
    }
  }

  // =======================================================================
  // A_FireCGun (p_pspr.c)
  // =======================================================================
  void aFireCGun(Player player, Pspdef psp) {
    final Mobj mo = player.mo!;
    sound.startSound(mo, Sfx.pistol);

    if (player.ammo[weaponInfo[player.readyWeapon].ammo] == 0) {
      return;
    }

    mobjSim.setMobjState(mo, St.sPlayAtk2);
    _decreaseAmmo(player, weaponInfo[player.readyWeapon].ammo, 1);

    // flashstate + psp->state - &states[S_CHAIN1]
    setPsprite(
      player,
      psFlash,
      weaponInfo[player.readyWeapon].flashState +
          psp.stateIndex -
          St.sChain1,
    );

    _bulletSlope(mo);

    _gunShot(mo, player.refire == 0);
  }

  // =======================================================================
  // A_Light0 / A_Light1 / A_Light2 (p_pspr.c)
  // =======================================================================
  void aLight0(Player player, Pspdef psp) {
    player.extraLight = 0;
  }

  void aLight1(Player player, Pspdef psp) {
    player.extraLight = 1;
  }

  void aLight2(Player player, Pspdef psp) {
    player.extraLight = 2;
  }

  // =======================================================================
  // A_BFGSpray (p_pspr.c). Spawn a BFG explosion on every monster in view.
  // This takes only a mobj (the BFG ball, whose target is the player).
  // =======================================================================
  void aBFGSpray(Mobj mo) {
    // offset angles from its attack angle
    for (int i = 0; i < 40; i++) {
      final angle_t an =
          normAngle(mo.angle - kAng90 ~/ 2 + (kAng90 ~/ 40) * i);

      // mo->target is the originator (player) of the missile
      shoot.aimLineAttack(mo.target!, an, 16 * 64 * kFracUnit);

      if (shoot.linetarget == null) {
        continue;
      }

      final Mobj lt = shoot.linetarget!;
      mobjSim.spawnMobj(
        lt.x,
        lt.y,
        toInt32(lt.z + (lt.height >> 2)),
        Mt.extrabfg,
      );

      int damage = 0;
      for (int j = 0; j < 15; j++) {
        damage += (pRandom() & 7) + 1;
      }

      shoot.inter.damageMobj(lt, mo.target, mo.target, damage);
    }
  }

  // =======================================================================
  // A_BFGsound (p_pspr.c)
  // =======================================================================
  void aBFGsound(Player player, Pspdef psp) {
    sound.startSound(player.mo, Sfx.bfg);
  }

  // =======================================================================
  // P_SetupPsprites (p_pspr.c). Called at start of level for each player.
  // =======================================================================
  void setupPsprites(Player player) {
    // remove all psprites
    for (int i = 0; i < numPsprites; i++) {
      player.psprites[i].stateIndex = 0;
    }

    // spawn the gun
    player.pendingWeapon = player.readyWeapon;
    bringUpWeapon(player);
  }

  // =======================================================================
  // P_MovePsprites (p_pspr.c). Called every tic by player thinking routine.
  // =======================================================================
  void movePsprites(Player player) {
    for (int i = 0; i < numPsprites; i++) {
      final Pspdef psp = player.psprites[i];
      // a null state means not active
      if (psp.stateIndex != 0) {
        // drop tic count and possibly change state

        // a -1 tic count never changes
        if (psp.tics != -1) {
          psp.tics--;
          if (psp.tics == 0) {
            setPsprite(player, i, states[psp.stateIndex].nextState);
          }
        }
      }
    }

    player.psprites[psFlash].sx = player.psprites[psWeapon].sx;
    player.psprites[psFlash].sy = player.psprites[psWeapon].sy;
  }

  // =======================================================================
  // R_PointToAngle2 (r_main.c), ported locally to avoid a renderer dependency
  // (same as the copies in p_shoot.dart / p_inter.dart).
  // =======================================================================
  static angle_t _pointToAngle2(
      fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2) {
    int x = toInt32(x2 - x1);
    int y = toInt32(y2 - y1);

    if (x == 0 && y == 0) return 0;

    if (x >= 0) {
      if (y >= 0) {
        if (x > y) {
          return tantoangle[slopeDiv(y, x)];
        } else {
          return normAngle(kAng90 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(-tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng270 + tantoangle[slopeDiv(x, y)]);
        }
      }
    } else {
      x = -x;
      if (y >= 0) {
        if (x > y) {
          return normAngle(kAng180 - 1 - tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng90 + tantoangle[slopeDiv(x, y)]);
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(kAng180 + tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng270 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      }
    }
  }
}

/// Reinterpret an unsigned 32-bit angle as a signed 32-bit int — vanilla's
/// `(signed int)(angle - player->mo->angle)` cast in A_Saw.
int _signed32(int v) {
  v &= 0xFFFFFFFF;
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

/// pw_strength (doomdef.h powertype_t). Used by A_Punch's berserk multiplier.
const int pwStrength = 1;

/// Register all 23 COMBAT-B weapon A_* functions into [r].
///
/// ENTRYPOINT for COMBAT-D: call this BEFORE [ActionRegistry.registerAllStubs]
/// (register uses last-write-wins; calling before stubs leaves the real bodies
/// in place since stubs use putIfAbsent). The [shoot] argument is accepted for
/// symmetry with the other registrars; the weapon actions reach the
/// shooter facade through [pspr.shoot].
void registerWeaponActions(ActionRegistry r, Pspr pspr, Shoot shoot) {
  void wpn(String name, void Function(Player, Pspdef) fn) {
    r.register(name, (Mobj mo, {Player? player, Pspdef? psp}) {
      fn(player!, psp!);
    });
  }

  wpn('A_WeaponReady', pspr.aWeaponReady);
  wpn('A_ReFire', pspr.aReFire);
  wpn('A_Lower', pspr.aLower);
  wpn('A_Raise', pspr.aRaise);
  wpn('A_GunFlash', pspr.aGunFlash);
  wpn('A_Light0', pspr.aLight0);
  wpn('A_Light1', pspr.aLight1);
  wpn('A_Light2', pspr.aLight2);
  wpn('A_Punch', pspr.aPunch);
  wpn('A_Saw', pspr.aSaw);
  wpn('A_FirePistol', pspr.aFirePistol);
  wpn('A_FireShotgun', pspr.aFireShotgun);
  wpn('A_FireShotgun2', pspr.aFireShotgun2);
  wpn('A_CheckReload', pspr.aCheckReload);
  // A_OpenShotgun2 / A_LoadShotgun2 / A_CloseShotgun2 are sound-only frames
  // in p_pspr.c (S_StartSound of the cocking sounds); the SSG reload chain.
  wpn('A_OpenShotgun2', (Player p, Pspdef psp) {
    pspr.sound.startSound(p.mo, Sfx.dbopn);
  });
  wpn('A_LoadShotgun2', (Player p, Pspdef psp) {
    pspr.sound.startSound(p.mo, Sfx.dbload);
  });
  wpn('A_CloseShotgun2', (Player p, Pspdef psp) {
    pspr.sound.startSound(p.mo, Sfx.dbcls);
    pspr.aReFire(p, psp);
  });
  wpn('A_FireCGun', pspr.aFireCGun);
  wpn('A_FireMissile', pspr.aFireMissile);
  wpn('A_FirePlasma', pspr.aFirePlasma);
  wpn('A_BFGsound', pspr.aBFGsound);
  wpn('A_FireBFG', pspr.aFireBFG);

  // A_BFGSpray takes only a mobj (the BFG ball), vanilla `A_BFGSpray(mobj_t*)`.
  r.register('A_BFGSpray', (Mobj mo, {Player? player, Pspdef? psp}) {
    pspr.aBFGSpray(mo);
  });
}
