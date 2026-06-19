// Player simulation, ported from Chocolate Doom src/p_user.c.
//
// P_PlayerThink applies the player's TicCmd: turn, thrust (P_Thrust), then
// move + view bob (P_MovePlayer/P_CalcHeight). Weapon firing, use lines and
// damage tinting hooks are present but their downstream behaviour is deferred
// (use-lines handled by p_doors.dart; weapons stubbed).

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../world/ticcmd.dart';
import 'info_tables.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_mobj.dart';
import 'p_pspr.dart' show Pspr, GameMode;
import 'player.dart';
import 'state_num.dart';

/// MAXBOB (fixed_t, 16 units). Vanilla P_CalcHeight cap.
const fixed_t kMaxBob = 0x100000;

/// FORWARD/SIDE move thrust scale: cmd move values are multiplied by 2048
/// (vanilla applies `cmd->forwardmove * 2048` via P_Thrust with forwardmove
/// already scaled in G_BuildTiccmd). We follow vanilla P_MovePlayer which
/// thrusts by `cmd->forwardmove * 2048`.
const int kMoveScale = 2048;

/// Drives player-controlled mobjs. Holds the [MobjSim] for thrust/move and a
/// hook for "use" (set by the doors module so P_UseLines stays decoupled).
class PlayerSim {
  PlayerSim(this.mobjSim);

  MobjSim mobjSim;

  /// Hook invoked when the USE button is newly pressed (P_UseLines). Set by the
  /// integration / doors module. No-op if unset.
  void Function(Player player)? onUse;

  /// The weapon-psprite driver (COMBAT-B). Set by the integration; when present,
  /// P_PlayerThink cycles psprites and lets A_WeaponReady/A_ReFire fire the
  /// weapon (vanilla drives firing from the psprite action, not P_PlayerThink).
  Pspr? pspr;

  /// Hook invoked when the player actually fires a weapon (P_FireWeapon calls
  /// P_NoiseAlert(player->mo, player->mo) to wake nearby monsters). Set by the
  /// integration; called after a fire is detected this tic. No-op if unset.
  void Function(Player player)? onPlayerFire;

  /// Vanilla `gamemode` (doomstat.c), used by the weapon-change branches
  /// (SSG only in commercial; plasma/BFG blocked in shareware). Set by the
  /// integration; defaults to shareware (the bundled doom1.wad).
  GameMode gameMode = GameMode.shareware;

  /// P_Thrust: add to the player's momentum in the given [angle] by [move].
  void thrust(Player player, angle_t angle, int move) {
    final Mobj mo = player.mo!;
    mo.momX = toInt32(mo.momX + fixedMul(move, cosineOf(angle)));
    mo.momY = toInt32(mo.momY + fixedMul(move, sineOf(angle)));
  }

  /// P_CalcHeight: compute the player's view Z (eye height + bob). Faithful.
  void calcHeight(Player player) {
    final Mobj mo = player.mo!;

    // bob = (momx^2 + momy^2) >> 2, clamped to MAXBOB.
    player.bob = toInt32(
        (fixedMul(mo.momX, mo.momX) >> 2) + (fixedMul(mo.momY, mo.momY) >> 2));
    if (player.bob > kMaxBob) player.bob = kMaxBob;

    if (player.playerState == PlayerState.dead) {
      player.viewZ = toInt32(mo.z + (6 * kFracUnit));
      if (player.viewZ > toInt32(mo.ceilingZ - 4 * kFracUnit)) {
        player.viewZ = toInt32(mo.ceilingZ - 4 * kFracUnit);
      }
      return;
    }

    // Bob the view using a sine of the level time. We track an internal phase.
    final int angle = (kFineAngles ~/ 20 * _leveltime) & kFineMask;
    final fixed_t bobDelta =
        fixedMul(player.bob ~/ 2, fineSineTable[angle]);

    if (player.playerState == PlayerState.live) {
      player.viewHeight = toInt32(player.viewHeight + player.deltaViewHeight);
      if (player.viewHeight > kViewHeight) {
        player.viewHeight = kViewHeight;
        player.deltaViewHeight = 0;
      }
      if (player.viewHeight < kViewHeight ~/ 2) {
        player.viewHeight = kViewHeight ~/ 2;
        if (player.deltaViewHeight <= 0) player.deltaViewHeight = 1;
      }
      if (player.deltaViewHeight != 0) {
        player.deltaViewHeight = toInt32(player.deltaViewHeight + kFracUnit ~/ 4);
        if (player.deltaViewHeight == 0) player.deltaViewHeight = 1;
      }
    }

    player.viewZ = toInt32(mo.z + player.viewHeight + bobDelta);
    if (player.viewZ > toInt32(mo.ceilingZ - 4 * kFracUnit)) {
      player.viewZ = toInt32(mo.ceilingZ - 4 * kFracUnit);
    }
  }

  /// P_MovePlayer: apply turn + thrust from the player's command.
  void movePlayer(Player player) {
    final Mobj mo = player.mo!;
    // player->mo->angle += (cmd->angleturn<<16);
    mo.angle = normAngle(mo.angle + (player.cmd.angleTurn << 16));

    final bool onGround = mo.z <= mo.floorZ;

    if (player.cmd.forwardMove != 0 && onGround) {
      thrust(player, mo.angle, player.cmd.forwardMove * kMoveScale);
    }
    if (player.cmd.sideMove != 0 && onGround) {
      thrust(player, normAngle(mo.angle - kAng90),
          player.cmd.sideMove * kMoveScale);
    }

    // Running animation: enter PLAY_RUN if moving and currently in PLAY idle.
    if ((player.cmd.forwardMove != 0 || player.cmd.sideMove != 0) &&
        mo.stateIndex == St.sPlay) {
      mobjSim.setMobjState(mo, St.sPlayRun1);
    }
  }

  int _leveltime = 0;

  /// Advance the internal bob phase clock (called once per tic by the sim).
  void advanceTime() => _leveltime++;

  /// P_PlayerThink: full per-tic player update. Applies the supplied command
  /// (already copied into player.cmd by the caller).
  void playerThink(Player player) {
    final Mobj mo = player.mo!;

    // Dead players: just calc height; respawn handling deferred.
    if (player.playerState == PlayerState.dead) {
      calcHeight(player);
      return;
    }

    // Reactiontime is used to prevent movement for a bit after a teleport.
    if (mo.reactionTime != 0) {
      mo.reactionTime--;
    } else {
      movePlayer(player);
    }

    calcHeight(player);

    // P_PlayerInSpecialSector (damaging floors etc.) is owned by the
    // world/specials layer and not yet wired; omitted here.

    // Check for weapon change. A special event has no other buttons.
    if ((player.cmd.buttons & btSpecial) != 0) {
      player.cmd.buttons = 0;
    }

    if ((player.cmd.buttons & btChangeWeapon) != 0) {
      // The actual changing of the weapon is done when the weapon psprite can
      // do it (read: not in the middle of an attack).
      int newweapon = (player.cmd.buttons & btWeaponMask) >> btWeaponShift;

      if (newweapon == Wp.fist &&
          player.weaponOwned[Wp.chainsaw] != 0 &&
          !(player.readyWeapon == Wp.chainsaw &&
              player.powers[_pwStrength] != 0)) {
        newweapon = Wp.chainsaw;
      }

      if (gameMode == GameMode.commercial &&
          newweapon == Wp.shotgun &&
          player.weaponOwned[Wp.supershotgun] != 0 &&
          player.readyWeapon != Wp.supershotgun) {
        newweapon = Wp.supershotgun;
      }

      if (player.weaponOwned[newweapon] != 0 &&
          newweapon != player.readyWeapon) {
        // Do not go to plasma or BFG in shareware, even if cheated.
        if ((newweapon != Wp.plasma && newweapon != Wp.bfg) ||
            gameMode != GameMode.shareware) {
          player.pendingWeapon = newweapon;
        }
      }
    }

    // USE button edge -> P_UseLines (doors/switches), via the onUse hook.
    if ((player.cmd.buttons & btUse) != 0) {
      if (!player.useDown) {
        onUse?.call(player);
        player.useDown = true;
      }
    } else {
      player.useDown = false;
    }

    // Cycle psprites. A_WeaponReady / A_ReFire perform the BT_ATTACK ->
    // P_FireWeapon and pending-weapon change (vanilla drives firing here, not
    // directly from P_PlayerThink). We detect the fire transition by comparing
    // the weapon ammo before/after so the fire-noise hook (P_NoiseAlert) can
    // wake nearby monsters from the player's own gunfire.
    final Pspr? psprDriver = pspr;
    if (psprDriver != null) {
      final int aType = weaponInfo[player.readyWeapon].ammo;
      final int beforeState = player.psprites[psWeapon].stateIndex;
      final int beforeAmmo =
          aType == Am.noAmmo ? 0 : player.ammo[aType];

      psprDriver.movePsprites(player);

      // Fire was issued this tic if the weapon entered an attack/flash chain or
      // consumed ammo. Use the simple ammo-decrement signal (fist/saw consume
      // none, but they wake monsters via melee damage anyway).
      final int afterAmmo =
          aType == Am.noAmmo ? 0 : player.ammo[aType];
      final int afterState = player.psprites[psWeapon].stateIndex;
      final bool fired = (aType != Am.noAmmo && afterAmmo < beforeAmmo) ||
          (afterState != beforeState && player.attackDown);
      if (fired) {
        onPlayerFire?.call(player);
      }
    } else {
      // No psprite driver wired: keep the attack latch faithful so a later
      // wave can attach the driver without re-plumbing input.
      player.attackDown = (player.cmd.buttons & btAttack) != 0;
    }

    // Counters, time-dependent power-ups.
    if (player.powers[_pwStrength] != 0) {
      // Strength counts up to diminish fade.
      player.powers[_pwStrength]++;
    }
    if (player.powers[_pwInvulnerability] != 0) {
      player.powers[_pwInvulnerability]--;
    }
    if (player.powers[_pwInvisibility] != 0) {
      if (--player.powers[_pwInvisibility] == 0) {
        mo.flags &= ~mfShadow;
      }
    }
    if (player.powers[_pwInfrared] != 0) {
      player.powers[_pwInfrared]--;
    }
    if (player.powers[_pwIronfeet] != 0) {
      player.powers[_pwIronfeet]--;
    }
    if (player.damageCount > 0) player.damageCount--;
    if (player.bonusCount > 0) player.bonusCount--;

    // Keep HUD health in sync with the mobj.
    player.health = mo.health;

    // Mark the player solid/shootable consistent with vanilla (no-op if set).
    mo.flags |= mfSolid;
  }
}

// powertype_t (doomdef.h) indices into player.powers, used by P_PlayerThink.
const int _pwInvulnerability = 0;
const int _pwStrength = 1;
const int _pwInvisibility = 2;
const int _pwIronfeet = 3;
const int _pwInfrared = 5;
