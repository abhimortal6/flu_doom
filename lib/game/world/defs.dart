// Level geometry data structures, ported from Chocolate Doom src/r_defs.h.
//
// These mirror the vanilla structs field-for-field (names and semantics).
// Spatial quantities are kept as `fixed_t` (16.16) exactly as in vanilla: raw
// map shorts are sign-extended and shifted left by FRACBITS (<<16) on load.
//
// Ownership / mutability contract (see lib/CONTRACTS_WORLD.md):
//   - The renderer READS these structures and never mutates them.
//   - The play simulation MUTATES the dynamic fields documented below
//     (sector floor/ceiling heights, lightlevel, specials; thinglist hooks;
//      line flags; mobj positions) and rebuilds derived state as needed.
//
// We use plain mutable classes (not records / immutable) because vanilla
// mutates these in place every tic, and both the renderer and playsim hold
// references to the same instances.

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';

/// A map vertex. Vanilla `vertex_t`: two `fixed_t` coordinates.
///
/// Loaded from the VERTEXES lump where each vertex is two signed int16 map
/// units; we sign-extend and `<< FRACBITS` into [x]/[y].
class Vertex {
  Vertex(this.x, this.y);

  /// X coordinate in 16.16 fixed-point map units.
  fixed_t x;

  /// Y coordinate in 16.16 fixed-point map units.
  fixed_t y;

  @override
  String toString() =>
      'Vertex(${fixedToInt(x)}, ${fixedToInt(y)})';
}

/// A degenerate "vertex" used as a sound origin for a sector. Vanilla reuses
/// `degenmobj_t` here; the renderer/sound code only needs x,y,z.
class DegenMobj {
  DegenMobj(this.x, this.y, this.z);
  fixed_t x;
  fixed_t y;
  fixed_t z;
}

/// A sector. Vanilla `sector_t`.
///
/// Dynamic fields mutated by playsim: [floorHeight], [ceilingHeight],
/// [lightLevel], [special], [tag], [soundTraversed], [soundTarget],
/// [thingList], [validCount], plus the moving-plane bookkeeping
/// ([specialData]). The renderer reads heights, pics, lightlevel.
class Sector {
  Sector({
    required this.floorHeight,
    required this.ceilingHeight,
    required this.floorPic,
    required this.ceilingPic,
    required this.lightLevel,
    required this.special,
    required this.tag,
  });

  /// Floor plane height (fixed_t). PLAYSIM mutates (movers/lifts).
  fixed_t floorHeight;

  /// Ceiling plane height (fixed_t). PLAYSIM mutates (doors/crushers).
  fixed_t ceilingHeight;

  // --- Frame interpolation (render-only), Crispy interpolated sector heights ---
  // The PREVIOUS tic's plane heights, captured by the sim at the start of each
  // tic for sectors with an active mover (specialData != null). The render path
  // temporarily writes lerp(old, current, frac) into [floorHeight]/[ceilingHeight]
  // around a frame and restores them after, so the ~30 renderer read sites stay
  // unchanged and the sim never observes the interpolated values. Never read by
  // the sim.
  fixed_t oldFloorHeight = 0;
  fixed_t oldCeilingHeight = 0;

  /// Flat number for the floor (index into the flats table; see
  /// engine/data/flats.dart). PLAYSIM may mutate (animated/donut etc).
  int floorPic;

  /// Flat number for the ceiling.
  int ceilingPic;

  /// Sector light level 0..255. PLAYSIM mutates (lighting effects).
  int lightLevel;

  /// Special type (damage, light blink, secret, ...). PLAYSIM reads/clears.
  int special;

  /// Tag used to associate lines with this sector. Static after load.
  int tag;

  // --- Derived / runtime fields (NOT in the map lump) ---

  /// Lines that reference this sector (front or back side). Built in
  /// P_GroupLines after load. Renderer/playsim read; static after setup.
  List<Line> lines = <Line>[];

  /// Number of lines in [lines]. Mirrors vanilla `linecount`.
  int get lineCount => lines.length;

  /// Bounding box of the sector in fixed_t, as [top, bottom, left, right]
  /// indexed by BOXTOP/BOXBOTTOM/BOXLEFT/BOXRIGHT. Built in P_GroupLines.
  final List<fixed_t> blockBox = <fixed_t>[0, 0, 0, 0];

  /// Sound origin (sector centre) for this sector. Built in P_GroupLines.
  late DegenMobj soundOrg;

  /// Sound propagation bookkeeping (P_RecursiveSound). PLAYSIM mutates.
  int soundTraversed = 0;

  /// The mobj that made a sound in this sector (target for monsters).
  /// Typed as Object? to avoid a hard dependency on the playsim mobj type;
  /// playsim casts. PLAYSIM mutates.
  Object? soundTarget;

  /// Head of the intrusive list of things (mobjs) in this sector. Vanilla
  /// `thinglist`. PLAYSIM mutates via P_SetThingPosition/P_UnsetThingPosition.
  /// Typed Object? for the same reason as [soundTarget].
  Object? thingList;

  /// Active special (moving plane thinker) attached to this sector, or null.
  /// Vanilla `specialdata`. PLAYSIM mutates.
  Object? specialData;

  /// Traversal stamp to avoid revisiting in a single pass. PLAYSIM mutates.
  int validCount = 0;
}

/// A wall side definition. Vanilla `side_t`.
///
/// Texture offsets are `fixed_t`. Texture numbers index the composite texture
/// table (see engine/data/textures.dart). [sector] is the sector this side
/// faces into.
class Side {
  Side({
    required this.textureOffset,
    required this.rowOffset,
    required this.topTexture,
    required this.bottomTexture,
    required this.midTexture,
    required this.sector,
  });

  /// Horizontal texture offset (fixed_t). PLAYSIM may mutate (scrollers).
  fixed_t textureOffset;

  /// Vertical texture offset (fixed_t). PLAYSIM may mutate.
  fixed_t rowOffset;

  /// Upper texture number (composite texture index; 0 = no texture "-").
  int topTexture;

  /// Lower texture number.
  int bottomTexture;

  /// Middle texture number.
  int midTexture;

  /// Sector this sidedef faces into.
  Sector sector;
}

/// Bounding-box indices, matching vanilla m_bbox.h (BOXTOP/BOTTOM/LEFT/RIGHT).
abstract final class Box {
  static const int top = 0;
  static const int bottom = 1;
  static const int left = 2;
  static const int right = 3;
}

/// Slope type of a line, vanilla `slopetype_t`.
enum SlopeType { horizontal, vertical, positive, negative }

/// A linedef. Vanilla `line_t`.
///
/// Endpoint vertices and direction deltas are `fixed_t`. [frontSector] and
/// [backSector] are resolved from the sidedefs. [special]/[tag] drive playsim;
/// [flags] carry ML_* bits. Two-sided lines have a non-null [backSide].
class Line {
  Line({
    required this.v1,
    required this.v2,
    required this.flags,
    required this.special,
    required this.tag,
    required this.frontSide,
    required this.backSide,
  })  : dx = toInt32(v2.x - v1.x),
        dy = toInt32(v2.y - v1.y) {
    // slopetype, classified exactly as P_LoadLineDefs:
    //   if (!dx) ST_VERTICAL;
    //   else if (!dy) ST_HORIZONTAL;
    //   else if (FixedDiv(dy, dx) > 0) ST_POSITIVE; else ST_NEGATIVE;
    if (dx == 0) {
      slopeType = SlopeType.vertical;
    } else if (dy == 0) {
      slopeType = SlopeType.horizontal;
    } else {
      slopeType =
          (fixedDiv(dy, dx) > 0) ? SlopeType.positive : SlopeType.negative;
    }
    // Bounding box (fixed_t).
    if (v1.x < v2.x) {
      boundingBox[Box.left] = v1.x;
      boundingBox[Box.right] = v2.x;
    } else {
      boundingBox[Box.left] = v2.x;
      boundingBox[Box.right] = v1.x;
    }
    if (v1.y < v2.y) {
      boundingBox[Box.bottom] = v1.y;
      boundingBox[Box.top] = v2.y;
    } else {
      boundingBox[Box.bottom] = v2.y;
      boundingBox[Box.top] = v1.y;
    }
    frontSector = frontSide.sector;
    backSector = backSide?.sector;
  }

  /// Start vertex.
  Vertex v1;

  /// End vertex.
  Vertex v2;

  /// v2.x - v1.x (fixed_t). Precomputed for line-side tests.
  fixed_t dx;

  /// v2.y - v1.y (fixed_t).
  fixed_t dy;

  /// ML_* line flags. PLAYSIM mutates (e.g. clearing ML_SECRET on use).
  int flags;

  /// Line special / action type. PLAYSIM reads; may clear after one-shot use.
  int special;

  /// Tag linking this line to sector(s).
  int tag;

  /// Front (right) sidedef. Always present.
  Side frontSide;

  /// Back (left) sidedef, or null for one-sided lines.
  Side? backSide;

  /// Sector on the front side (= frontSide.sector).
  late Sector frontSector;

  /// Sector on the back side, or null for one-sided lines.
  late Sector? backSector;

  /// Classified slope, used by P_BoxOnLineSide etc.
  late SlopeType slopeType;

  /// Bounding box, indexed by [Box]. fixed_t.
  final List<fixed_t> boundingBox = <fixed_t>[0, 0, 0, 0];

  /// Traversal stamp (P_PathTraverse). PLAYSIM mutates.
  int validCount = 0;

  /// Sound origin for switch/door sounds (line midpoint). Optional; built by
  /// playsim if needed. Renderer does not use this.
  DegenMobj? soundOrg;

  /// Convenience: a two-sided line has a back side.
  bool get isTwoSided => (flags & mlTwoSided) != 0;
}

// --- ML_* line flags, from doomdata.h ---
/// Block players and monsters.
const int mlBlocking = 1;
/// Block monsters only.
const int mlBlockMonsters = 2;
/// Two sided: backside present, midtexture optional.
const int mlTwoSided = 4;
/// Upper texture unpegged.
const int mlDontPegTop = 8;
/// Lower texture unpegged.
const int mlDontPegBottom = 16;
/// Drawn as one-sided on the automap.
const int mlSecret = 32;
/// Blocks sound propagation.
const int mlSoundBlock = 64;
/// Never shown on the automap.
const int mlDontDraw = 128;
/// Always shown on the automap.
const int mlMapped = 256;

/// A seg (BSP wall segment). Vanilla `seg_t`.
///
/// [offset] and [angle] are precomputed in P_LoadSegs. [sidedef] and
/// [linedef] are resolved by index; [frontSector]/[backSector] derived.
class Seg {
  Seg({
    required this.v1,
    required this.v2,
    required this.offset,
    required this.angle,
    required this.sidedef,
    required this.linedef,
    required this.frontSector,
    required this.backSector,
  });

  /// Start vertex.
  Vertex v1;

  /// End vertex.
  Vertex v2;

  /// Texture offset along the seg (fixed_t).
  fixed_t offset;

  /// BAM angle of the seg (angle_t). From the SEGS lump's int16 angle << 16.
  angle_t angle;

  /// The sidedef this seg uses.
  Side sidedef;

  /// The parent linedef.
  Line linedef;

  /// Sector on the side this seg faces (= sidedef.sector). Renderer reads.
  Sector frontSector;

  /// Sector on the opposite side (back side's sector), or null if one-sided.
  Sector? backSector;
}

/// A subsector: a convex leaf of the BSP referencing a run of segs.
/// Vanilla `subsector_t`.
class Subsector {
  Subsector({
    required this.sector,
    required this.numLines,
    required this.firstLine,
  });

  /// The sector this subsector belongs to (taken from its first seg's side).
  Sector sector;

  /// Number of segs in this subsector.
  int numLines;

  /// Index of the first seg (into the segs array).
  int firstLine;
}

/// A BSP node. Vanilla `node_t`.
///
/// The partition line is (x, y) with direction (dx, dy), all fixed_t. [bbox]
/// holds the two child bounding boxes (each [top,bottom,left,right]).
/// [children] holds the two child indices; if the high bit (NF_SUBSECTOR,
/// 0x8000) is set the remaining bits index a subsector, else a node.
class Node {
  Node({
    required this.x,
    required this.y,
    required this.dx,
    required this.dy,
    required this.bbox,
    required this.children,
  });

  /// Partition line origin x (fixed_t).
  fixed_t x;

  /// Partition line origin y (fixed_t).
  fixed_t y;

  /// Partition line direction x (fixed_t).
  fixed_t dx;

  /// Partition line direction y (fixed_t).
  fixed_t dy;

  /// Two child bounding boxes; [i][Box.*] in fixed_t. i = 0 (right), 1 (left).
  final List<List<fixed_t>> bbox;

  /// Two child references (raw, with NF_SUBSECTOR bit). [0]=right, [1]=left.
  final List<int> children;
}

/// High bit in a node child indicating the child is a subsector. (NF_SUBSECTOR.)
const int nfSubsector = 0x8000;

/// A thing placed on the map. Vanilla `mapthing_t` (the on-disk THINGS record,
/// not the runtime `mobj_t`). Playsim spawns mobjs from these.
class MapThing {
  MapThing({
    required this.x,
    required this.y,
    required this.angle,
    required this.type,
    required this.options,
  });

  /// X position in WHOLE map units (NOT fixed_t) — matches vanilla mapthing_t,
  /// which stores raw shorts; P_SpawnMapThing shifts to fixed_t at spawn time.
  int x;

  /// Y position in whole map units.
  int y;

  /// Facing angle in DEGREES (0..359), as stored in the lump.
  int angle;

  /// DoomEd thing type number.
  int type;

  /// Spawn option flags (skill levels, deaf, multiplayer-only).
  int options;
}

// --- mapthing options bits (doomdata.h) ---
const int mtfEasy = 1;
const int mtfNormal = 2;
const int mtfHard = 4;
const int mtfAmbush = 8; // deaf
const int mtfNotSingle = 16;
