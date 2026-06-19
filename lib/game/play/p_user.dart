// Player simulation, ported from Chocolate Doom src/p_user.c.
//
// P_PlayerThink applies the player's TicCmd: turn, thrust (P_Thrust), then
// move + view bob (P_MovePlayer/P_CalcHeight). Weapon firing, use lines and
// damage tinting hooks are present but their downstream behaviour is deferred
// (use-lines handled by p_doors.dart; weapons stubbed).

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_mobj.dart';
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

    // Movement.
    movePlayer(player);
    calcHeight(player);

    // USE button edge -> P_UseLines (doors/switches). Deferred behaviour via
    // the onUse hook.
    if ((player.cmd.buttons & 2 /*BT_USE*/) != 0) {
      if (!player.useDown) {
        onUse?.call(player);
        player.useDown = true;
      }
    } else {
      player.useDown = false;
    }

    // Keep HUD health in sync with the mobj.
    player.health = mo.health;

    // Tint counters decay (palette flashes; rendering deferred).
    if (player.damageCount > 0) player.damageCount--;
    if (player.bonusCount > 0) player.bonusCount--;

    // Weapon firing is deferred (stubbed). The attack latch is tracked so a
    // later wave can wire P_FireWeapon without re-plumbing input.
    if ((player.cmd.buttons & 1 /*BT_ATTACK*/) != 0) {
      player.attackDown = true;
    } else {
      player.attackDown = false;
    }

    // Mark the player solid/shootable consistent with vanilla (no-op if set).
    mo.flags |= mfSolid;
  }
}
