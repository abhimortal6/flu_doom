// mobj lifecycle + movement, ported from Chocolate Doom src/p_mobj.c.
//
// P_SetMobjState advances the state machine (and fires the named action).
// P_XYMovement / P_ZMovement integrate momentum with friction and gravity.
// P_MobjThinker is the per-tic [Mobj.tick]. P_SpawnMobj / P_RemoveMobj create
// and destroy mobjs, linking them into the thinker list and sector/blockmap.

import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import 'actions.dart';
import 'info.dart';
import 'info_tables.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_map.dart';
import 'player.dart';
import 'thinker.dart';

/// GRAVITY (fixed_t). Vanilla.
const fixed_t kGravity = kFracUnit;

/// MAXMOVE: momentum cap per tic (fixed_t, 30 units). Vanilla.
const fixed_t kMaxMove = 30 * kFracUnit;

/// STOPSPEED / FRICTION (fixed_t). Vanilla P_XYMovement constants.
const fixed_t kStopSpeed = 0x1000;
const fixed_t kFriction = 0xe800;

/// FLOATSPEED: monster float adjustment (unused this slice but defined).
const fixed_t kFloatSpeed = 4 * kFracUnit;

/// Owns the mobj-side simulation against a [MapMove] + [ThinkerList].
class MobjSim {
  MobjSim(this.move, this.thinkers);

  MapMove move;
  ThinkerList thinkers;

  /// P_SetMobjState: switch [mobj] to [stateNum], firing the state's action.
  /// Returns false if the chain led to S_NULL (mobj should be removed), true
  /// otherwise. Faithful to vanilla's loop over zero-tic states.
  bool setMobjState(Mobj mobj, int stateNum) {
    int sn = stateNum;
    do {
      if (sn == 0) {
        // S_NULL: remove the mobj.
        mobj.stateIndex = 0;
        removeMobj(mobj);
        return false;
      }
      final State st = states[sn];
      mobj.stateIndex = sn;
      mobj.tics = st.tics;
      mobj.sprite = st.sprite;
      mobj.frame = st.frame;
      // Fire the action (stubbed for unimplemented A_*).
      if (st.action != null) {
        ActionRegistry.instance.resolve(st.action)(mobj);
      }
      sn = st.nextState;
    } while (mobj.tics == 0);
    return true;
  }

  /// P_SpawnMobj: create a mobj of [type] at (x,y,z) and link it everywhere.
  /// z may be the sentinel [onFloorZ] / [onCeilingZ].
  Mobj spawnMobj(fixed_t x, fixed_t y, fixed_t z, int type) {
    final MobjInfo info = mobjInfo[type];
    final Mobj mobj = Mobj()
      ..type = type
      ..x = x
      ..y = y
      ..radius = info.radius
      ..height = info.height
      ..flags = info.flags
      ..health = info.spawnHealth
      ..reactionTime = info.reactionTime
      ..lastLook = 0;

    // Set its initial state without firing actions on the very first frame
    // through the normal path (vanilla calls P_SetMobjState here too).
    final State st = states[info.spawnState];
    mobj.stateIndex = info.spawnState;
    mobj.tics = st.tics;
    mobj.sprite = st.sprite;
    mobj.frame = st.frame;

    // Link into sector/blockmap first so floorz/ceilingz are known.
    move.setThingPosition(mobj);
    final Sector sec = mobj.subsectorSector!;
    mobj.floorZ = sec.floorHeight;
    mobj.ceilingZ = sec.ceilingHeight;

    if (z == onFloorZ) {
      mobj.z = mobj.floorZ;
    } else if (z == onCeilingZ) {
      mobj.z = toInt32(mobj.ceilingZ - mobj.height);
    } else {
      mobj.z = z;
    }

    mobj.thinkFn = mobjThinker;
    thinkers.add(mobj);
    return mobj;
  }

  /// P_RemoveMobj: unlink from sector/blockmap and mark the thinker removed.
  void removeMobj(Mobj mobj) {
    move.unsetThingPosition(mobj);
    thinkers.remove(mobj);
  }

  /// P_XYMovement: integrate horizontal momentum with wall sliding + friction.
  void xyMovement(Mobj mo) {
    if (mo.momX == 0 && mo.momY == 0) {
      return;
    }
    final Player? pl = mo.player as Player?;

    fixed_t momx = mo.momX;
    fixed_t momy = mo.momY;
    if (momx > kMaxMove) momx = kMaxMove;
    if (momx < -kMaxMove) momx = -kMaxMove;
    if (momy > kMaxMove) momy = kMaxMove;
    if (momy < -kMaxMove) momy = -kMaxMove;
    mo.momX = momx;
    mo.momY = momy;

    fixed_t xmove = momx;
    fixed_t ymove = momy;

    do {
      fixed_t ptryx;
      fixed_t ptryy;
      if (xmove > kMaxMove ~/ 2 || ymove > kMaxMove ~/ 2) {
        ptryx = toInt32(mo.x + (xmove >> 1));
        ptryy = toInt32(mo.y + (ymove >> 1));
        xmove >>= 1;
        ymove >>= 1;
      } else {
        ptryx = toInt32(mo.x + xmove);
        ptryy = toInt32(mo.y + ymove);
        xmove = 0;
        ymove = 0;
      }

      if (!move.tryMove(mo, ptryx, ptryy)) {
        // Blocked: slide (player) or stop (missiles/monsters die — deferred).
        if (mo.player != null) {
          move.slideMove(mo);
        } else if ((mo.flags & mfMissile) != 0) {
          // Missile explosion deferred; just stop.
          mo.momX = 0;
          mo.momY = 0;
        } else {
          mo.momX = 0;
          mo.momY = 0;
        }
        // After slide/stop, recompute remaining move as 0.
        xmove = 0;
        ymove = 0;
      }
    } while (xmove != 0 || ymove != 0);

    // Friction: skip for missiles / no-gravity flyers / things off the floor.
    if ((mo.flags & (mfMissile | mfSkullFly)) != 0) {
      return;
    }
    if (mo.z > mo.floorZ) {
      return; // airborne, no friction
    }
    if ((mo.flags & mfCorpse) != 0) {
      // Corpses slide off steps; only stop if on a step edge.
      if (mo.floorZ != mo.subsectorSector!.floorHeight) {
        return;
      }
    }

    if (mo.momX > -kStopSpeed &&
        mo.momX < kStopSpeed &&
        mo.momY > -kStopSpeed &&
        mo.momY < kStopSpeed &&
        (pl == null ||
            (pl.cmd.forwardMove == 0 && pl.cmd.sideMove == 0))) {
      mo.momX = 0;
      mo.momY = 0;
    } else {
      mo.momX = fixedMul(mo.momX, kFriction);
      mo.momY = fixedMul(mo.momY, kFriction);
    }
  }

  /// P_ZMovement: integrate vertical momentum, apply gravity, clamp to floor.
  void zMovement(Mobj mo) {
    final Player? pl = mo.player as Player?;

    // Adjust view bob if there is a player and we hit the floor hard.
    mo.z = toInt32(mo.z + mo.momZ);

    if ((mo.flags & mfFloat) != 0 && mo.target != null) {
      // Float toward target height — deferred (monsters); no-op here.
    }

    // Clip to floor.
    if (mo.z <= mo.floorZ) {
      if (mo.momZ < 0) {
        if (pl != null && mo.momZ < -kGravity * 8) {
          // Squat the camera on a hard landing.
          pl.deltaViewHeight = mo.momZ >> 3;
        }
        mo.momZ = 0;
      }
      mo.z = mo.floorZ;
    } else if ((mo.flags & mfNoGravity) == 0) {
      if (mo.momZ == 0) {
        mo.momZ = -kGravity * 2;
      } else {
        mo.momZ = toInt32(mo.momZ - kGravity);
      }
    }

    // Clip to ceiling.
    if (toInt32(mo.z + mo.height) > mo.ceilingZ) {
      if (mo.momZ > 0) mo.momZ = 0;
      mo.z = toInt32(mo.ceilingZ - mo.height);
    }
  }

  /// P_MobjThinker: per-tic update for a mobj's momentum + state machine.
  void mobjThinker(Mobj mo) {
    if (mo.momX != 0 || mo.momY != 0) {
      xyMovement(mo);
      if (mo.removed) return;
    }
    if (mo.z != mo.floorZ || mo.momZ != 0) {
      zMovement(mo);
      if (mo.removed) return;
    }
    // Cycle the state machine.
    if (mo.tics != -1) {
      mo.tics--;
      if (mo.tics == 0) {
        if (!setMobjState(mo, states[mo.stateIndex].nextState)) {
          return; // removed
        }
      }
    }
  }
}

/// ONFLOORZ / ONCEILINGZ sentinels for [MobjSim.spawnMobj] z. Vanilla uses
/// INT_MIN / INT_MAX; we reuse the same extremes.
const fixed_t onFloorZ = kInt32Min;
const fixed_t onCeilingZ = kInt32Max;
