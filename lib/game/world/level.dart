// Level container + map loading, ported from Chocolate Doom src/p_setup.c
// (P_SetupLevel and the P_Load* helpers).
//
// A [Level] owns every geometry array for one map plus the blockmap and reject
// matrix. It is built by [Level.load], which reads the 10 map lumps that follow
// the map marker lump (e.g. "E1M1") in the WAD and converts the raw on-disk
// shorts to the runtime structures in defs.dart (coordinates -> fixed_t via
// <<FRACBITS, exactly as vanilla).
//
// Mutability: geometry topology (vertexes, sides, lines, segs, subsectors,
// nodes, blockmap, reject) is STATIC after load. Dynamic per-sector / per-line
// state (heights, lights, specials, thinglists, flags) is mutated by playsim;
// see lib/CONTRACTS_WORLD.md for the read/mutate boundary.

import 'dart:typed_data';

import '../../engine/data/textures.dart';
import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../../engine/wad/wad.dart';
import 'defs.dart';

/// The standard map-data lumps that follow the map marker, in WAD order.
/// Matches the layout produced by every Doom node builder.
abstract final class MapLump {
  static const int things = 1;
  static const int linedefs = 2;
  static const int sidedefs = 3;
  static const int vertexes = 4;
  static const int segs = 5;
  static const int ssectors = 6;
  static const int nodes = 7;
  static const int sectors = 8;
  static const int reject = 9;
  static const int blockmap = 10;
}

/// A fully-loaded level. Vanilla scatters these as globals in p_setup.c /
/// r_state.h; we group them into one object that is the renderer's "level"
/// input and the playsim's mutable world geometry.
class Level {
  Level._({
    required this.name,
    required this.vertexes,
    required this.sectors,
    required this.sides,
    required this.lines,
    required this.segs,
    required this.subsectors,
    required this.nodes,
    required this.things,
    required this.blockmap,
    required this.reject,
  });

  /// Map name as it appears in the WAD (e.g. "E1M1").
  final String name;

  /// All vertexes (P_LoadVertexes).
  final List<Vertex> vertexes;

  /// All sectors (P_LoadSectors). Dynamic fields mutated by playsim.
  final List<Sector> sectors;

  /// All sidedefs (P_LoadSidedefs).
  final List<Side> sides;

  /// All linedefs (P_LoadLineDefs + P_LoadLineDefs2 resolution).
  final List<Line> lines;

  /// All BSP segs (P_LoadSegs).
  final List<Seg> segs;

  /// All BSP subsectors (P_LoadSubsectors).
  final List<Subsector> subsectors;

  /// All BSP nodes (P_LoadNodes). The root node is `nodes.last`.
  final List<Node> nodes;

  /// All map things (P_LoadThings). Playsim spawns mobjs from these.
  final List<MapThing> things;

  /// The blockmap (P_LoadBlockMap).
  final Blockmap blockmap;

  /// The reject matrix (P_LoadReject); may be empty if absent/zero-size.
  final Reject reject;

  /// Index of the root BSP node (vanilla `numnodes - 1`).
  int get rootNode => nodes.length - 1;

  /// Load a named map (default "E1M1") from [wad]. [textures] resolves flat and
  /// wall texture names to numbers as vanilla does during P_Load*.
  factory Level.load(
    WadFile wad,
    Textures textures, {
    String mapName = 'E1M1',
  }) {
    final int marker = wad.lumpNumForName(mapName);
    if (marker < 0) {
      throw WadException('Map not found: $mapName');
    }

    final List<Vertex> vertexes =
        _loadVertexes(wad.lumpByIndex(marker + MapLump.vertexes));
    final List<Sector> sectors =
        _loadSectors(wad.lumpByIndex(marker + MapLump.sectors), textures);
    final List<Side> sides = _loadSidedefs(
        wad.lumpByIndex(marker + MapLump.sidedefs), sectors, textures);
    final List<Line> lines = _loadLinedefs(
        wad.lumpByIndex(marker + MapLump.linedefs), vertexes, sides);
    final List<Seg> segs = _loadSegs(
        wad.lumpByIndex(marker + MapLump.segs), vertexes, sides, lines);
    final List<Subsector> subsectors = _loadSubsectors(
        wad.lumpByIndex(marker + MapLump.ssectors), segs);
    final List<Node> nodes =
        _loadNodes(wad.lumpByIndex(marker + MapLump.nodes));
    final List<MapThing> things =
        _loadThings(wad.lumpByIndex(marker + MapLump.things));
    final Blockmap blockmap =
        Blockmap.fromLump(wad.lumpByIndex(marker + MapLump.blockmap));
    final Reject reject =
        Reject.fromLump(wad.lumpByIndex(marker + MapLump.reject), sectors.length);

    final Level level = Level._(
      name: mapName,
      vertexes: vertexes,
      sectors: sectors,
      sides: sides,
      lines: lines,
      segs: segs,
      subsectors: subsectors,
      nodes: nodes,
      things: things,
      blockmap: blockmap,
      reject: reject,
    );
    _groupLines(level);
    return level;
  }

  // --- P_LoadVertexes: int16 x, int16 y -> fixed_t ---
  static List<Vertex> _loadVertexes(Lump lump) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 4;
    final List<Vertex> out = List<Vertex>.generate(n, (int i) {
      final int o = i * 4;
      return Vertex(
        intToFixed(bd.getInt16(o, Endian.little)),
        intToFixed(bd.getInt16(o + 2, Endian.little)),
      );
    });
    return out;
  }

  // --- P_LoadSectors: 26 bytes each ---
  static List<Sector> _loadSectors(Lump lump, Textures textures) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 26;
    return List<Sector>.generate(n, (int i) {
      final int o = i * 26;
      final int floorH = bd.getInt16(o, Endian.little);
      final int ceilH = bd.getInt16(o + 2, Endian.little);
      final String floorName = _name8(bd, o + 4);
      final String ceilName = _name8(bd, o + 12);
      final int light = bd.getInt16(o + 20, Endian.little);
      final int special = bd.getInt16(o + 22, Endian.little);
      final int tag = bd.getInt16(o + 24, Endian.little);
      return Sector(
        floorHeight: intToFixed(floorH),
        ceilingHeight: intToFixed(ceilH),
        floorPic: textures.flatNumForName(floorName),
        ceilingPic: textures.flatNumForName(ceilName),
        lightLevel: light,
        special: special,
        tag: tag,
      );
    });
  }

  // --- P_LoadSidedefs: 30 bytes each ---
  static List<Side> _loadSidedefs(
      Lump lump, List<Sector> sectors, Textures textures) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 30;
    return List<Side>.generate(n, (int i) {
      final int o = i * 30;
      final int texOff = bd.getInt16(o, Endian.little);
      final int rowOff = bd.getInt16(o + 2, Endian.little);
      final String top = _name8(bd, o + 4);
      final String bottom = _name8(bd, o + 12);
      final String mid = _name8(bd, o + 20);
      final int secNum = bd.getInt16(o + 28, Endian.little);
      return Side(
        textureOffset: intToFixed(texOff),
        rowOffset: intToFixed(rowOff),
        topTexture: textures.textureNumForName(top),
        bottomTexture: textures.textureNumForName(bottom),
        midTexture: textures.textureNumForName(mid),
        sector: sectors[secNum],
      );
    });
  }

  // --- P_LoadLineDefs: 14 bytes each ---
  static List<Line> _loadLinedefs(
      Lump lump, List<Vertex> vertexes, List<Side> sides) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 14;
    return List<Line>.generate(n, (int i) {
      final int o = i * 14;
      final int v1 = bd.getUint16(o, Endian.little);
      final int v2 = bd.getUint16(o + 2, Endian.little);
      final int flags = bd.getInt16(o + 4, Endian.little);
      final int special = bd.getInt16(o + 6, Endian.little);
      final int tag = bd.getInt16(o + 8, Endian.little);
      // Sidedef numbers; -1 (0xFFFF) means "no side".
      final int sNum0 = bd.getInt16(o + 10, Endian.little);
      final int sNum1 = bd.getInt16(o + 12, Endian.little);
      final Side front = sides[sNum0];
      final Side? back = sNum1 == -1 ? null : sides[sNum1];
      return Line(
        v1: vertexes[v1],
        v2: vertexes[v2],
        flags: flags,
        special: special,
        tag: tag,
        frontSide: front,
        backSide: back,
      );
    });
  }

  // --- P_LoadSegs: 12 bytes each ---
  static List<Seg> _loadSegs(
    Lump lump,
    List<Vertex> vertexes,
    List<Side> sides,
    List<Line> lines,
  ) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 12;
    return List<Seg>.generate(n, (int i) {
      final int o = i * 12;
      final int v1 = bd.getUint16(o, Endian.little);
      final int v2 = bd.getUint16(o + 2, Endian.little);
      final int angle = bd.getInt16(o + 4, Endian.little);
      final int lineNum = bd.getUint16(o + 6, Endian.little);
      final int side = bd.getInt16(o + 8, Endian.little); // 0 front, 1 back
      final int offset = bd.getInt16(o + 10, Endian.little);
      final Line line = lines[lineNum];
      // ldef->sidenum[side] selects the sidedef this seg draws.
      final Side segSide = side == 0 ? line.frontSide : line.backSide!;
      final Sector frontSector = segSide.sector;
      // Back sector: the OTHER side's sector, only for two-sided lines.
      Sector? backSector;
      if ((line.flags & mlTwoSided) != 0) {
        final Side? otherSide = side == 0 ? line.backSide : line.frontSide;
        backSector = otherSide?.sector;
      }
      return Seg(
        v1: vertexes[v1],
        v2: vertexes[v2],
        // angle stored as int16 in the upper 16 bits of a BAM angle_t.
        angle: normAngle(angle << 16),
        offset: intToFixed(offset),
        sidedef: segSide,
        linedef: line,
        frontSector: frontSector,
        backSector: backSector,
      );
    });
  }

  // --- P_LoadSubsectors: 4 bytes each (uint16 numsegs, uint16 firstseg) ---
  static List<Subsector> _loadSubsectors(Lump lump, List<Seg> segs) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 4;
    return List<Subsector>.generate(n, (int i) {
      final int o = i * 4;
      final int numSegs = bd.getUint16(o, Endian.little);
      final int firstSeg = bd.getUint16(o + 2, Endian.little);
      // Sector is taken from the first seg's sidedef (vanilla R_Subsector
      // derives it; p_setup leaves subsector->sector resolved in R_Subsector,
      // but we resolve eagerly here for the renderer's convenience).
      final Sector sector = segs[firstSeg].sidedef.sector;
      return Subsector(
        sector: sector,
        numLines: numSegs,
        firstLine: firstSeg,
      );
    });
  }

  // --- P_LoadNodes: 28 bytes each ---
  static List<Node> _loadNodes(Lump lump) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 28;
    return List<Node>.generate(n, (int i) {
      final int o = i * 28;
      final fixed_t x = intToFixed(bd.getInt16(o, Endian.little));
      final fixed_t y = intToFixed(bd.getInt16(o + 2, Endian.little));
      final fixed_t dx = intToFixed(bd.getInt16(o + 4, Endian.little));
      final fixed_t dy = intToFixed(bd.getInt16(o + 6, Endian.little));
      // Two child bboxes, each 4 shorts: top,bottom,left,right.
      final List<List<fixed_t>> bbox = <List<fixed_t>>[
        <fixed_t>[0, 0, 0, 0],
        <fixed_t>[0, 0, 0, 0],
      ];
      for (int c = 0; c < 2; c++) {
        for (int b = 0; b < 4; b++) {
          bbox[c][b] =
              intToFixed(bd.getInt16(o + 8 + (c * 4 + b) * 2, Endian.little));
        }
      }
      final List<int> children = <int>[
        bd.getUint16(o + 24, Endian.little),
        bd.getUint16(o + 26, Endian.little),
      ];
      return Node(x: x, y: y, dx: dx, dy: dy, bbox: bbox, children: children);
    });
  }

  // --- P_LoadThings: 10 bytes each (kept as whole map units) ---
  static List<MapThing> _loadThings(Lump lump) {
    final ByteData bd = lump.data;
    final int n = lump.size ~/ 10;
    return List<MapThing>.generate(n, (int i) {
      final int o = i * 10;
      return MapThing(
        x: bd.getInt16(o, Endian.little),
        y: bd.getInt16(o + 2, Endian.little),
        angle: bd.getInt16(o + 4, Endian.little),
        type: bd.getInt16(o + 6, Endian.little),
        options: bd.getInt16(o + 8, Endian.little),
      );
    });
  }

  // --- P_GroupLines: build per-sector line lists, bboxes, sound origins ---
  static void _groupLines(Level level) {
    for (final Line line in level.lines) {
      line.frontSector.lines.add(line);
      if (line.backSector != null && !identical(line.backSector, line.frontSector)) {
        line.backSector!.lines.add(line);
      }
    }
    for (final Sector sec in level.sectors) {
      fixed_t bbTop = kInt32Min;
      fixed_t bbBottom = kInt32Max;
      fixed_t bbLeft = kInt32Max;
      fixed_t bbRight = kInt32Min;
      for (final Line line in sec.lines) {
        for (final Vertex v in <Vertex>[line.v1, line.v2]) {
          if (v.x < bbLeft) bbLeft = v.x;
          if (v.x > bbRight) bbRight = v.x;
          if (v.y < bbBottom) bbBottom = v.y;
          if (v.y > bbTop) bbTop = v.y;
        }
      }
      sec.blockBox[Box.top] = bbTop;
      sec.blockBox[Box.bottom] = bbBottom;
      sec.blockBox[Box.left] = bbLeft;
      sec.blockBox[Box.right] = bbRight;
      // Sound origin: centre of the bounding box.
      sec.soundOrg = DegenMobj(
        (bbLeft + bbRight) ~/ 2,
        (bbBottom + bbTop) ~/ 2,
        0,
      );
    }
  }

  static String _name8(ByteData bd, int off) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 8; i++) {
      final int c = bd.getUint8(off + i);
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString().toUpperCase();
  }
}

/// The blockmap: a coarse grid over the map for fast collision/los queries.
/// Vanilla P_LoadBlockMap. Header is 4 int16: originx, originy, width, height
/// (origin in whole map units, NOT fixed_t — matches vanilla `bmaporgx` which
/// is later `<<FRACBITS`). Followed by `width*height` int16 offsets into the
/// blocklist, each pointing at a 0-terminated (`0xFFFF`) list of line indices.
class Blockmap {
  Blockmap._(
    this.originX,
    this.originY,
    this.width,
    this.height,
    this.offsets,
    this.lumpData,
  );

  /// Grid origin X in whole map units (multiply by FRACUNIT for fixed_t).
  final int originX;

  /// Grid origin Y in whole map units.
  final int originY;

  /// Grid width in blocks (128-unit cells).
  final int width;

  /// Grid height in blocks.
  final int height;

  /// Per-cell offsets (in int16 units) into [lumpData] where each cell's line
  /// list begins. There are width*height entries.
  final Int16List offsets;

  /// The entire blockmap lump as int16 values, for reading line lists. A
  /// cell's line list is the run of values at offsets[cell] up to a 0xFFFF
  /// (-1) terminator. The first value of each list is a leading 0 in vanilla.
  final Int16List lumpData;

  factory Blockmap.fromLump(Lump lump) {
    final ByteData bd = lump.data;
    final int count = lump.size ~/ 2;
    final Int16List data = Int16List(count);
    for (int i = 0; i < count; i++) {
      data[i] = bd.getInt16(i * 2, Endian.little);
    }
    final int ox = data.isNotEmpty ? data[0] : 0;
    final int oy = data.length > 1 ? data[1] : 0;
    final int w = data.length > 2 ? data[2] : 0;
    final int h = data.length > 3 ? data[3] : 0;
    final int gridCount = w * h;
    final Int16List offs = Int16List(gridCount);
    for (int i = 0; i < gridCount && 4 + i < count; i++) {
      offs[i] = data[4 + i];
    }
    return Blockmap._(ox, oy, w, h, offs, data);
  }

  /// Iterate the line indices stored in cell (bx, by). Returns an empty list
  /// for out-of-range cells. The terminator (-1) is not included.
  List<int> linesInBlock(int bx, int by) {
    if (bx < 0 || by < 0 || bx >= width || by >= height) return const <int>[];
    int p = offsets[by * width + bx];
    final List<int> out = <int>[];
    // Vanilla: list starts with a 0 padding entry, then line numbers, then -1.
    if (p < lumpData.length && lumpData[p] == 0) p++;
    while (p < lumpData.length && lumpData[p] != -1) {
      out.add(lumpData[p] & 0xFFFF);
      p++;
    }
    return out;
  }
}

/// The reject matrix: a width = numsectors bit array per sector pair, used to
/// short-circuit line-of-sight checks. Vanilla P_LoadReject. Bit (i*n + j)
/// set means sector i cannot see sector j. May be empty for IWADs without a
/// valid reject (we then report all-visible).
class Reject {
  Reject._(this.bits, this.numSectors);

  /// Raw reject bytes (may be empty).
  final Uint8List bits;

  /// Number of sectors the matrix is dimensioned for.
  final int numSectors;

  factory Reject.fromLump(Lump lump, int numSectors) {
    return Reject._(lump.bytes, numSectors);
  }

  /// True if line-of-sight between sectors [i] and [j] is rejected (impossible).
  /// Conservatively returns false (visible) if the matrix is missing/short.
  bool rejected(int i, int j) {
    final int bit = i * numSectors + j;
    final int byteIndex = bit >> 3;
    if (byteIndex >= bits.length) return false;
    return (bits[byteIndex] & (1 << (bit & 7))) != 0;
  }
}
