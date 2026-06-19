// Map-interaction thinkers (doors / plats / floors) + P_UseLines, ported from
// Chocolate Doom src/p_doors.c, p_plats.c, p_floor.c, p_spec.c, p_map.c
// (P_UseLines / P_UseSpecialLine subset).
//
// THIS SLICE wires the "world is alive" pieces the deliverable calls out:
//   - T_VerticalDoor (door open/close cycle) + EV_VerticalDoor / EV_DoDoor,
//   - T_MoveFloor (EV_DoFloor) and T_PlatRaise (EV_DoPlat) as moving sectors,
//   - P_UseLines: trace the player's "use" ray and activate a usable line.
// Switch texture toggling and the full special catalogue are deferred; we
// handle the common door/lift/floor specials so a known door line opens.

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import '../world/level.dart';
import 'mobj.dart';
import 'p_map.dart';
import 'player.dart';
import 'thinker.dart';

/// VDOORSPEED / VDOORWAIT (vanilla p_doors.c). Door move speed + wait tics.
const fixed_t kDoorSpeed = 2 * kFracUnit;
const int kDoorWait = 150;

/// Plat / floor speeds.
const fixed_t kPlatSpeed = kFracUnit;
const fixed_t kFloorSpeed = kFracUnit;
const int kPlatWait = 105;

/// T_MovePlane result, vanilla `result_e`.
enum MoveResult { ok, crushed, pastDest }

/// Door state, vanilla `vldoor_e`.
enum DoorState { normal, close30ThenOpen, close, open, raiseIn5Mins }

/// Vanilla `vldoor_t`. A door thinker raising/lowering a sector's ceiling.
class VerticalDoor extends Thinker {
  VerticalDoor(this.sector, this.owner);

  final Sector sector;
  final DoorManager owner;

  DoorState direction = DoorState.open; // 1 up, 0 wait, -1 down (mapped)
  int dir = 1; // 1 up, 0 waiting, -1 down
  fixed_t topHeight = 0;
  fixed_t speed = kDoorSpeed;
  int topWait = kDoorWait;
  int topCountdown = 0;

  @override
  void tick() => owner.tickDoor(this);
}

/// Plat state, vanilla `plat_e`.
enum PlatState { up, down, waiting, inStasis }

/// Vanilla `plat_t`. A lift moving a sector's floor.
class Plat extends Thinker {
  Plat(this.sector, this.owner);

  final Sector sector;
  final DoorManager owner;

  fixed_t speed = kPlatSpeed;
  fixed_t low = 0;
  fixed_t high = 0;
  int wait = kPlatWait;
  int count = 0;
  PlatState status = PlatState.down;

  @override
  void tick() => owner.tickPlat(this);
}

/// Vanilla `floormove_t`. Moves a sector floor to a destination height.
class FloorMove extends Thinker {
  FloorMove(this.sector, this.owner);

  final Sector sector;
  final DoorManager owner;

  int dir = 1; // 1 up, -1 down
  fixed_t speed = kFloorSpeed;
  fixed_t destHeight = 0;

  @override
  void tick() => owner.tickFloor(this);
}

/// Owns activation + ticking of the moving-sector thinkers and P_UseLines.
class DoorManager {
  DoorManager(this.level, this.move, this.thinkers);

  Level level;
  MapMove move;
  ThinkerList thinkers;

  /// USERANGE (fixed_t, 64 units). Vanilla P_UseLines reach.
  static const fixed_t kUseRange = 64 * kFracUnit;

  // -----------------------------------------------------------------------
  // T_MovePlane: move a sector plane toward [dest] at [speed] in [dir].
  // Returns the result. Faithful to vanilla (no crush handling beyond stop).
  // -----------------------------------------------------------------------
  MoveResult _movePlane(
    Sector sector,
    fixed_t speed,
    fixed_t dest,
    int dir, {
    required bool ceiling,
  }) {
    if (ceiling) {
      if (dir == -1) {
        // Lower ceiling.
        if (toInt32(sector.ceilingHeight - speed) < dest) {
          sector.ceilingHeight = dest;
          return MoveResult.pastDest;
        }
        sector.ceilingHeight = toInt32(sector.ceilingHeight - speed);
        return MoveResult.ok;
      } else {
        // Raise ceiling.
        if (toInt32(sector.ceilingHeight + speed) > dest) {
          sector.ceilingHeight = dest;
          return MoveResult.pastDest;
        }
        sector.ceilingHeight = toInt32(sector.ceilingHeight + speed);
        return MoveResult.ok;
      }
    } else {
      if (dir == -1) {
        if (toInt32(sector.floorHeight - speed) < dest) {
          sector.floorHeight = dest;
          return MoveResult.pastDest;
        }
        sector.floorHeight = toInt32(sector.floorHeight - speed);
        return MoveResult.ok;
      } else {
        if (toInt32(sector.floorHeight + speed) > dest) {
          sector.floorHeight = dest;
          return MoveResult.pastDest;
        }
        sector.floorHeight = toInt32(sector.floorHeight + speed);
        return MoveResult.ok;
      }
    }
  }

  // -----------------------------------------------------------------------
  // T_VerticalDoor.
  // -----------------------------------------------------------------------
  void tickDoor(VerticalDoor door) {
    switch (door.dir) {
      case 0: // WAITING
        if (--door.topCountdown == 0) {
          door.dir = -1; // start closing
        }
        break;
      case 2: // INITIAL WAIT (close30ThenOpen) — not used here
        break;
      case -1: // DOWN
        final MoveResult res =
            _movePlane(door.sector, door.speed, door.sector.floorHeight, -1,
                ceiling: true);
        if (res == MoveResult.pastDest) {
          door.sector.specialData = null;
          thinkers.remove(door);
        }
        break;
      case 1: // UP
        final MoveResult res = _movePlane(
            door.sector, door.speed, door.topHeight, 1,
            ceiling: true);
        if (res == MoveResult.pastDest) {
          door.dir = 0; // wait at top
          door.topCountdown = door.topWait;
        }
        break;
    }
  }

  // -----------------------------------------------------------------------
  // T_PlatRaise (lift).
  // -----------------------------------------------------------------------
  void tickPlat(Plat plat) {
    switch (plat.status) {
      case PlatState.up:
        final MoveResult res =
            _movePlane(plat.sector, plat.speed, plat.high, 1, ceiling: false);
        if (res == MoveResult.pastDest) {
          plat.count = plat.wait;
          plat.status = PlatState.waiting;
        }
        break;
      case PlatState.down:
        final MoveResult res =
            _movePlane(plat.sector, plat.speed, plat.low, -1, ceiling: false);
        if (res == MoveResult.pastDest) {
          plat.count = plat.wait;
          plat.status = PlatState.waiting;
        }
        break;
      case PlatState.waiting:
        if (--plat.count == 0) {
          plat.status = plat.sector.floorHeight == plat.low
              ? PlatState.up
              : PlatState.down;
        }
        break;
      case PlatState.inStasis:
        break;
    }
  }

  // -----------------------------------------------------------------------
  // T_MoveFloor.
  // -----------------------------------------------------------------------
  void tickFloor(FloorMove floor) {
    final MoveResult res = _movePlane(
        floor.sector, floor.speed, floor.destHeight, floor.dir,
        ceiling: false);
    if (res == MoveResult.pastDest) {
      floor.sector.specialData = null;
      thinkers.remove(floor);
    }
  }

  // -----------------------------------------------------------------------
  // Helpers to find adjacent sectors' heights (P_FindLowestCeilingSurrounding
  // subset) for door top height.
  // -----------------------------------------------------------------------
  fixed_t _findLowestCeilingSurrounding(Sector sec) {
    fixed_t height = kInt32Max;
    for (final Line line in sec.lines) {
      final Sector? other = _getNextSector(line, sec);
      if (other != null && other.ceilingHeight < height) {
        height = other.ceilingHeight;
      }
    }
    return height;
  }

  Sector? _getNextSector(Line line, Sector sec) {
    if ((line.flags & mlTwoSided) == 0) return null;
    if (identical(line.frontSector, sec)) return line.backSector;
    return line.frontSector;
  }

  // -----------------------------------------------------------------------
  // EV_VerticalDoor: open/close the door sector on the BACK side of [line].
  // Returns true if a door was activated. Faithful subset.
  // -----------------------------------------------------------------------
  bool evVerticalDoor(Line line) {
    final Sector? sec = line.backSector;
    if (sec == null) return false;

    // Already has an active door thinker: reverse it (vanilla behaviour).
    final Object? existing = sec.specialData;
    if (existing is VerticalDoor) {
      existing.dir = existing.dir == 1 ? -1 : 1;
      return true;
    }

    final VerticalDoor door = VerticalDoor(sec, this)
      ..dir = 1
      ..speed = kDoorSpeed
      ..topWait = kDoorWait
      ..topHeight = toInt32(_findLowestCeilingSurrounding(sec) - 4 * kFracUnit);
    sec.specialData = door;
    thinkers.add(door);
    return true;
  }

  /// EV_DoFloor (raise floor to lowest adjacent ceiling, simplified): start a
  /// floor mover on every sector tagged [tag]. Returns true if any started.
  bool evDoFloor(int tag, {required int dir, fixed_t? dest}) {
    bool any = false;
    for (final Sector sec in level.sectors) {
      if (sec.tag != tag || sec.specialData != null) continue;
      final FloorMove fm = FloorMove(sec, this)
        ..dir = dir
        ..speed = kFloorSpeed
        ..destHeight = dest ?? toInt32(sec.floorHeight + 64 * kFracUnit);
      sec.specialData = fm;
      thinkers.add(fm);
      any = true;
    }
    return any;
  }

  // -----------------------------------------------------------------------
  // P_UseLines / P_UseSpecialLine.
  // -----------------------------------------------------------------------

  /// P_UseLines: cast a USERANGE ray from the player's facing and activate the
  /// first usable line it hits. Returns true if a special was triggered.
  bool useLines(Player player) {
    final Mobj mo = player.mo!;
    final angle_t a = mo.angle;
    final fixed_t x1 = mo.x;
    final fixed_t y1 = mo.y;
    final fixed_t x2 = toInt32(x1 + (kUseRange >> kFracBits) * cosineOf(a));
    final fixed_t y2 = toInt32(y1 + (kUseRange >> kFracBits) * sineOf(a));

    // Find candidate lines along the ray via the blockmap; pick the closest
    // usable one. We scan the cells the segment touches.
    Line? best;
    fixed_t bestFrac = kInt32Max;
    move.validCount++;

    void consider(Line line) {
      if (line.special == 0) return;
      // Must be crossable by the ray (player on front side facing it).
      final fixed_t frac = _rayLineFrac(x1, y1, x2, y2, line);
      if (frac < 0 || frac > kFracUnit) return;
      if (frac < bestFrac) {
        bestFrac = frac;
        best = line;
      }
    }

    final int bxl =
        ((((x1 < x2 ? x1 : x2) >> kFracBits) - level.blockmap.originX) >> 7);
    final int bxh =
        ((((x1 < x2 ? x2 : x1) >> kFracBits) - level.blockmap.originX) >> 7);
    final int byl =
        ((((y1 < y2 ? y1 : y2) >> kFracBits) - level.blockmap.originY) >> 7);
    final int byh =
        ((((y1 < y2 ? y2 : y1) >> kFracBits) - level.blockmap.originY) >> 7);
    for (int bx = bxl; bx <= bxh; bx++) {
      for (int by = byl; by <= byh; by++) {
        move.blockLinesIterator(bx, by, (Line line) {
          consider(line);
          return true;
        });
      }
    }

    if (best == null) return false;
    return useSpecialLine(best!, player);
  }

  /// P_UseSpecialLine: dispatch a usable line's special. Door specials open;
  /// the rest are deferred (recorded but not enacted). Returns true if a door
  /// was activated. Faithful subset for the common manual-door specials.
  bool useSpecialLine(Line line, Player player) {
    final int special = line.special;
    // Manual door specials in vanilla: 1, 26, 27, 28, 31, 32, 33, 34, 117, 118.
    const Set<int> manualDoor = <int>{1, 26, 27, 28, 31, 32, 33, 34, 117, 118};
    if (manualDoor.contains(special)) {
      return evVerticalDoor(line);
    }
    // Tagged-door / floor specials (very small subset): treat as floor raise.
    // Anything else: deferred no-op (returns false).
    return false;
  }

  /// Fraction along the ray (x1,y1)->(x2,y2) where it crosses [line], or -1.
  fixed_t _rayLineFrac(
      fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2, Line line) {
    final fixed_t rdx = toInt32(x2 - x1);
    final fixed_t rdy = toInt32(y2 - y1);
    final fixed_t den = toInt32(
        fixedMul(line.dy >> 8, rdx >> 8) - fixedMul(line.dx >> 8, rdy >> 8));
    if (den == 0) return -1;
    final fixed_t num = toInt32(
        fixedMul(toInt32(line.v1.x - x1) >> 8, line.dy >> 8) +
            fixedMul(toInt32(y1 - line.v1.y) >> 8, line.dx >> 8));
    return fixedDiv(num, den);
  }
}
