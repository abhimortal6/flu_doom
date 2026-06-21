// mobj_t, ported from Chocolate Doom src/p_mobj.h / p_mobj.c.
//
// A [Mobj] is a map object: the player, monsters, projectiles, items and
// decorations. It is a [Thinker] (linked into the global thinker list and
// updated each tic by P_MobjThinker) and is also linked into per-sector
// thinglists and per-blockmap blocklinks for collision/visibility queries.
//
// Spatial fields are `fixed_t` (16.16); angle is `angle_t`. Field set is
// faithful to vanilla mobj_t (subsector/sector links, momentum, height refs,
// state pointer, info pointer, flags, target/tracer, player back-reference).

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import 'info.dart';
import 'info_tables.dart';
import 'thinker.dart';

/// Per-tic callback for a mobj. Set by the simulation at spawn so the thinker
/// list's [Thinker.tick] can delegate to P_MobjThinker without a back-import.
typedef MobjThinkFn = void Function(Mobj mobj);

/// Map object. Vanilla `mobj_t`.
class Mobj extends Thinker {
  Mobj();

  /// The function run each tic (P_MobjThinker). Assigned by the simulation.
  MobjThinkFn? thinkFn;

  @override
  void tick() {
    thinkFn?.call(this);
  }

  // --- Position / orientation ---
  /// X position (fixed_t).
  fixed_t x = 0;

  /// Y position (fixed_t).
  fixed_t y = 0;

  /// Z position (fixed_t). Feet height.
  fixed_t z = 0;

  /// Facing angle (angle_t / BAM).
  angle_t angle = 0;

  // --- Frame interpolation (render-only), Crispy per-mobj oldx/oldy/oldz ---
  // The PREVIOUS tic's position, captured by the sim at tic start (and set equal
  // to x/y/z at spawn / teleport so the first frame does not lerp across a
  // discontinuity). Read ONLY by the render path (sprite adapter); never by the
  // sim. [interpInit] guards the spawn snap.
  fixed_t oldX = 0;
  fixed_t oldY = 0;
  fixed_t oldZ = 0;

  /// False until the first old-position capture; while false the sprite adapter
  /// treats old == current (no lerp) so a freshly spawned mobj does not smear in
  /// from (0,0,0). Set true by [captureOld].
  bool interpInit = false;

  /// Snapshot the current position as the interpolation "old" state. Called by
  /// the sim at the start of each tic and on spawn/teleport (snap).
  void captureOld() {
    oldX = x;
    oldY = y;
    oldZ = z;
    interpInit = true;
  }

  // --- Sector / blockmap intrusive links ---
  /// Next thing in the same sector's thinglist (vanilla `snext`). Intrusive.
  Mobj? sNext;

  /// Previous thing in the sector's thinglist (vanilla `sprev`).
  Mobj? sPrev;

  /// The sector that currently owns this thing's thinglist entry.
  Sector? subsectorSector;

  /// Next thing in the blockmap cell list (vanilla `bnext`).
  Mobj? bNext;

  /// Previous thing in the blockmap cell list (vanilla `bprev`).
  Mobj? bPrev;

  /// Blockmap cell index this thing is linked into, or -1 if unlinked.
  int blockIndex = -1;

  // --- Appearance / state ---
  /// Current sprite (vanilla `sprite`).
  SpriteNum sprite = SpriteNum.troo;

  /// Current frame (sub-frame + FF_FULLBRIGHT). Vanilla `frame`.
  int frame = 0;

  /// Index into the states[] table of the current state. -1 = no state.
  int stateIndex = 0;

  /// Tics left in the current state before transition. Vanilla `tics`.
  int tics = -1;

  /// Index into mobjInfo[] of this thing's type. Vanilla `type`.
  int type = 0;

  /// Cached MF_* flags from the info (mutable per-mobj). Vanilla `flags`.
  int flags = 0;

  /// Current hit points. Vanilla `health`.
  int health = 0;

  // --- Physics ---
  /// X momentum (fixed_t). Vanilla `momx`.
  fixed_t momX = 0;

  /// Y momentum (fixed_t). Vanilla `momy`.
  fixed_t momY = 0;

  /// Z momentum (fixed_t). Vanilla `momz`.
  fixed_t momZ = 0;

  /// Radius for collision (fixed_t). Vanilla `radius`.
  fixed_t radius = 0;

  /// Height for collision (fixed_t). Vanilla `height`.
  fixed_t height = 0;

  /// Floor height of the sector under this thing (fixed_t). Vanilla `floorz`.
  fixed_t floorZ = 0;

  /// Ceiling height of the sector under this thing (fixed_t). Vanilla `ceilingz`.
  fixed_t ceilingZ = 0;

  // --- AI / misc ---
  /// Movement direction (DI_*); 0..7 or DI_NODIR. Vanilla `movedir`.
  int moveDir = 0;

  /// Tics until next move decision. Vanilla `movecount`.
  int moveCount = 0;

  /// Reaction time before AI acts. Vanilla `reactiontime`.
  int reactionTime = 0;

  /// Threshold before the monster gives up its current target. Vanilla.
  int threshold = 0;

  /// Random offset for staggering thinker work. Vanilla `lastlook`.
  int lastLook = 0;

  /// Current target (mobj). Vanilla `target`.
  Mobj? target;

  /// Tracer (homing) target. Vanilla `tracer`.
  Mobj? tracer;

  /// Back-reference to the player controlling this mobj, if any. Vanilla
  /// `player` (null for non-player mobjs). Typed Object? to avoid a cyclic
  /// import with player.dart; the playsim casts to Player.
  Object? player;

  /// The spawn point (mapthing) for respawn. Vanilla `spawnpoint`.
  MapThing? spawnPoint;

  /// Static info for this type.
  MobjInfo get info => mobjInfo[type];
}

/// DI_NODIR sentinel for [Mobj.moveDir].
const int diNoDir = 8;
