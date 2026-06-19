// Thing spawning, ported from Chocolate Doom src/p_mobj.c (P_SpawnPlayer,
// P_SpawnMapThing) and the p_setup.c spawn loop.
//
// P_SpawnMapThing converts a [MapThing] (whole units / degrees) into a runtime
// [Mobj] at fixed_t coordinates, honouring skill flags. Player starts (DoomEd
// 1..4) record the start point and spawn the player on level load.

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import 'info_tables.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_mobj.dart';
import 'player.dart';
import 'state_num.dart';

/// Game skill, vanilla `skill_t`. Spawn filtering uses these.
enum Skill { baby, easy, medium, hard, nightmare }

/// Coordinates a level's thing spawn pass.
class Spawner {
  Spawner(this.mobjSim);

  MobjSim mobjSim;

  /// Recorded player start points by player number (0-based). Vanilla
  /// `playerstarts[MAXPLAYERS]`.
  final List<MapThing?> playerStarts = List<MapThing?>.filled(4, null);

  /// Deathmatch starts (recorded but unused in single-player). Vanilla.
  final List<MapThing> deathmatchStarts = <MapThing>[];

  /// P_SpawnPlayer: spawn [player]'s mobj at [mthing], wire the back-reference
  /// and set its initial view height. Faithful to vanilla.
  Mobj spawnPlayer(MapThing mthing, Player player) {
    final fixed_t x = mthing.x << kFracBits;
    final fixed_t y = mthing.y << kFracBits;
    final Mobj mobj = mobjSim.spawnMobj(x, y, onFloorZ, Mt.player);

    mobj.angle = normAngle(_angleFromDegrees(mthing.angle));
    mobj.player = player;
    mobj.health = mobjInfo[Mt.player].spawnHealth;

    player.mo = mobj;
    player.playerState = PlayerState.live;
    player.health = mobj.health;
    player.viewHeight = kViewHeight;
    player.deltaViewHeight = 0;
    player.bob = 0;

    // Set up the player's initial weapon sprite (fist/pistol idle). Behaviour
    // (firing) is deferred, but the psprite state is faithful.
    player.psprites[psWeapon]
      ..stateIndex = St.sPistol
      ..tics = states[St.sPistol].tics
      ..sx = kFracUnit
      ..sy = kFracUnit;

    // Put the player mobj into the idle PLAY state.
    mobjSim.setMobjState(mobj, St.sPlay);

    return mobj;
  }

  /// P_SpawnMapThing: spawn (or record) a single map thing. Player starts are
  /// recorded; monster/item/decoration things are spawned subject to skill and
  /// single-player flags. Returns the spawned mobj, or null if not spawned.
  Mobj? spawnMapThing(MapThing mthing, {Skill skill = Skill.medium}) {
    final int type = mthing.type;

    // Player 1..4 starts: record the position (used by spawnPlayer).
    if (type >= 1 && type <= 4) {
      playerStarts[type - 1] = mthing;
      return null;
    }
    // Deathmatch start (DoomEd 11).
    if (type == 11) {
      deathmatchStarts.add(mthing);
      return null;
    }

    // Single-player skip flag (MTF_NOTSINGLE).
    if ((mthing.options & mtfNotSingle) != 0) {
      return null;
    }

    // Skill filtering.
    final int bit;
    switch (skill) {
      case Skill.baby:
      case Skill.easy:
        bit = mtfEasy;
        break;
      case Skill.medium:
        bit = mtfNormal;
        break;
      case Skill.hard:
      case Skill.nightmare:
        bit = mtfHard;
        break;
    }
    if ((mthing.options & bit) == 0) {
      return null;
    }

    // Resolve the DoomEd number to a mobjtype.
    final int? mt = doomedToMobjType[type];
    if (mt == null) {
      // Unknown thing type: skip (vanilla I_Errors; we tolerate for safety).
      return null;
    }

    final fixed_t x = mthing.x << kFracBits;
    final fixed_t y = mthing.y << kFracBits;
    final int z = (mobjInfo[mt].flags & mfSpawnCeiling) != 0
        ? onCeilingZ
        : onFloorZ;

    final Mobj mobj = mobjSim.spawnMobj(x, y, z, mt);
    mobj.spawnPoint = mthing;
    mobj.angle = normAngle(_angleFromDegrees(mthing.angle));
    if ((mthing.options & mtfAmbush) != 0) {
      mobj.flags |= mfAmbush;
    }
    return mobj;
  }

  /// Convert a DEGREES facing (0..359) to a BAM angle. Vanilla:
  /// `ANG45 * (angle/45)` (snaps to 45-degree increments).
  angle_t _angleFromDegrees(int degrees) => normAngle(kAng45 * (degrees ~/ 45));
}
