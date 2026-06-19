// Sprite / masked-pass dependency inversion boundary.
//
// The 3D renderer must draw "things" (mobjs) without depending on the play
// simulation's `mobj_t` type. Vanilla R_AddSprites walks every sector's
// thinglist and projects each mobj into a vissprite. Here, the playsim adapts
// its mobjs to this interface; the renderer consumes lightweight records and
// never touches play-sim types.
//
// An EMPTY SpriteSource (one yielding no [SpriteRequest]s) is valid and renders
// a complete view with no things — see [EmptySpriteSource].
//
// Faithful to Chocolate Doom r_things.c (R_AddSprites / R_ProjectSprite): the
// renderer needs, per drawable thing, its world position (fixed_t), the sprite
// number + frame + rotation it is displaying, and the lighting/flags context
// (full-bright, shadow/spectre, the sector light level to shade by).

import '../math/angle.dart';
import '../math/fixed.dart';

/// Sprite frame flags, mirroring vanilla `spriteframe_t.rotate` semantics and
/// the per-thing flags the renderer cares about (MF_SHADOW, full-bright frame).
abstract final class SpriteRequestFlags {
  /// Thing is rendered as a translucent "fuzz" shadow (MF_SHADOW: spectre).
  static const int shadow = 1 << 0;

  /// Sprite is drawn at full brightness regardless of sector light
  /// (frame bit FF_FULLBRIGHT).
  static const int fullBright = 1 << 1;

  /// Mirror the sprite horizontally (per-rotation `flip` flag from the lump).
  /// Normally derived by the source via [SpriteFrameInfo]; included here so a
  /// source may pre-resolve it.
  static const int flip = 1 << 2;
}

/// One drawable thing, as the renderer consumes it. A lightweight value type
/// (Dart has no zero-cost records with named mutable fields, so this is a
/// small final class). The playsim builds one per visible mobj each frame.
///
/// Positions are world-space `fixed_t` (16.16); [angle] is the thing's facing
/// `angle_t`. The renderer computes the view-relative rotation itself.
class SpriteRequest {
  const SpriteRequest({
    required this.x,
    required this.y,
    required this.z,
    required this.angle,
    required this.spriteNum,
    required this.frame,
    required this.lightLevel,
    this.flags = 0,
  });

  /// World X (fixed_t). Vanilla mobj->x.
  final fixed_t x;

  /// World Y (fixed_t). Vanilla mobj->y.
  final fixed_t y;

  /// World Z of the thing's feet (fixed_t). Vanilla mobj->z.
  final fixed_t z;

  /// Facing angle (angle_t). Vanilla mobj->angle. Used to pick the rotation.
  final angle_t angle;

  /// Sprite index into [SpriteResolver] (vanilla `mobj->sprite`, an enum the
  /// playsim owns). The renderer treats it as an opaque key passed back to the
  /// resolver — it does NOT assume Doom's sprnum_t ordering.
  final int spriteNum;

  /// Frame number, 0..28 (vanilla `mobj->frame & FF_FRAMEMASK`). The
  /// FF_FULLBRIGHT bit should be surfaced via [flags] instead.
  final int frame;

  /// Sector light level (0..255) to shade this thing by, unless full-bright.
  /// Vanilla reads thing->subsector->sector->lightlevel.
  final int lightLevel;

  /// Bitwise-or of [SpriteRequestFlags].
  final int flags;
}

/// Metadata for a single sprite frame's chosen rotation: which WAD sprite-lump
/// to decode and whether to mirror it. Vanilla `spriteframe_t` holds 8
/// rotations + flip flags; the resolver picks the right one for a view angle.
class SpriteFrameInfo {
  const SpriteFrameInfo({required this.lumpPatchBytes, required this.flip});

  /// Raw Doom-picture bytes for the chosen rotation's patch (decode with
  /// `engine/video/patch.dart` Patch, or sample columns directly). The renderer
  /// reads width/height/offsets and column posts from these bytes.
  final List<int> lumpPatchBytes;

  /// Whether to draw the sprite mirrored horizontally.
  final bool flip;
}

/// Resolves a ([spriteNum], [frame], rotation) triple to the actual patch bytes
/// the renderer decodes. Vanilla R_InitSprites builds `sprites[]` (a
/// `spritedef_t[]` of `spriteframe_t`s) from the S_START..S_END lumps; this
/// interface lets the playsim (which owns the sprite-name table / state table)
/// provide that mapping without the renderer importing play-sim code.
abstract interface class SpriteResolver {
  /// Return the frame info for the given sprite/frame at view-relative
  /// rotation index [rot] (0..7, where 0 faces the viewer). If the frame has
  /// only one rotation, [rot] is ignored. Returns null if the sprite/frame is
  /// missing (the renderer then skips the thing — vanilla I_Errors).
  SpriteFrameInfo? frameInfo(int spriteNum, int frame, int rot);

  /// Whether the given sprite/frame uses a single rotation (`rotate == false`
  /// in vanilla). When true the renderer does not compute a rotation index.
  bool isSingleRotation(int spriteNum, int frame);
}

/// Supplies the set of things to draw this frame. Implemented by the playsim
/// adapter. The renderer calls [collect] once per frame during the masked pass.
///
/// Contract: [collect] should append every potentially-visible thing. The
/// renderer performs its own view-frustum / depth culling; the source need not
/// (but may) pre-cull. Order is irrelevant — the renderer sorts by depth.
abstract interface class SpriteSource {
  /// The resolver used to turn requests into patch bytes.
  SpriteResolver get resolver;

  /// Append all drawable things for this frame into [out].
  void collect(List<SpriteRequest> out);
}

/// A SpriteSource that yields no things. Renders a valid view (geometry only).
class EmptySpriteSource implements SpriteSource {
  const EmptySpriteSource();

  @override
  SpriteResolver get resolver => const _NullResolver();

  @override
  void collect(List<SpriteRequest> out) {
    // No things.
  }
}

class _NullResolver implements SpriteResolver {
  const _NullResolver();
  @override
  SpriteFrameInfo? frameInfo(int spriteNum, int frame, int rot) => null;
  @override
  bool isSingleRotation(int spriteNum, int frame) => true;
}
