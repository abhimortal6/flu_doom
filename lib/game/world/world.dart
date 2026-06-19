// The shared world / game-state container.
//
// [World] is the single object both the renderer and the play simulation hold.
// It bundles:
//   - the loaded [Level] (all geometry arrays + blockmap/reject),
//   - the [Textures] lookup (textures/flats/sprites),
//   - the current [Viewpoint] (camera position + angle the renderer reads),
//   - the active [TicCmd] (this tic's player intent the playsim consumes).
//
// Read/mutate boundary (see lib/CONTRACTS_WORLD.md for the full contract):
//
//   RENDERER reads (never mutates):
//     world.level (geometry), world.textures (pixels), world.viewpoint.
//   PLAYSIM mutates:
//     world.viewpoint (after moving the player), dynamic Level fields
//     (sector heights/lights/specials, line flags/specials, sector thinglists),
//     and consumes world.cmd each tic.
//
// The container itself does no simulation; it is plain shared state.

import '../../engine/data/textures.dart';
import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../../engine/wad/wad.dart';
import 'level.dart';
import 'ticcmd.dart';

/// The renderer's camera, vanilla R_SetupFrame inputs (viewx/viewy/viewz/
/// viewangle). All spatial values are `fixed_t`; the angle is an `angle_t`.
///
/// PLAYSIM writes these after moving the player (R_SetupFrame copies them from
/// the player's mobj + viewz each frame in vanilla); the RENDERER only reads.
class Viewpoint {
  Viewpoint();

  /// Camera X (fixed_t). Vanilla viewx.
  fixed_t x = 0;

  /// Camera Y (fixed_t). Vanilla viewy.
  fixed_t y = 0;

  /// Camera/eye Z (fixed_t). Vanilla viewz = player z + viewheight.
  fixed_t z = 0;

  /// View angle (angle_t / BAM). Vanilla viewangle.
  angle_t angle = 0;

  /// Set the full viewpoint at once.
  void set({
    required fixed_t x,
    required fixed_t y,
    required fixed_t z,
    required angle_t angle,
  }) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.angle = normAngle(angle);
  }
}

/// The shared mutable game world.
class World {
  World({
    required this.wad,
    required this.textures,
    required this.level,
  });

  /// The source WAD (for any further lump access).
  final WadFile wad;

  /// Texture / flat / sprite lookup and compositing.
  final Textures textures;

  /// The currently loaded level. Replaced by [changeLevel].
  Level level;

  /// The renderer's camera. PLAYSIM writes, RENDERER reads.
  final Viewpoint viewpoint = Viewpoint();

  /// This tic's player command. Input fills it; PLAYSIM consumes it.
  final TicCmd cmd = TicCmd();

  /// Global traversal stamp, vanilla `validcount`. PLAYSIM bumps this before a
  /// blockmap/BSP traversal and compares against per-line/per-sector stamps.
  int validCount = 0;

  /// Build a [World] from a WAD: parse textures and load the default (or named)
  /// map. This is the one-call bootstrap the integration layer uses.
  factory World.fromWad(WadFile wad, {String mapName = 'E1M1'}) {
    final Textures textures = Textures.fromWad(wad);
    final Level level = Level.load(wad, textures, mapName: mapName);
    return World(wad: wad, textures: textures, level: level);
  }

  /// Load a different map into this world (reuses the texture tables).
  void changeLevel(String mapName) {
    level = Level.load(wad, textures, mapName: mapName);
    validCount = 0;
  }
}
