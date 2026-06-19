# flu_doom — Shared World Data Layer Contracts (Phase 2)

This document is the **stable contract** for the shared world data layer. The
**renderer** and the **play-simulation** agents code against THIS document
without seeing the implementation. It builds strictly on the Phase-1 foundation
(`lib/INTERFACES.md`): `fixed_t`/`angle_t` math, `WadFile`/`Lump`, `Palette`.

Faithful port of Chocolate Doom `r_defs.h`, `p_setup.c`, `r_data.c`,
`d_ticcmd.h`. Spatial quantities are `fixed_t` (16.16); BAM angles are
`angle_t`. **Web is out of scope** (native AOT int semantics, per Phase 1).

---

## 0. File layout (this layer)

```
lib/
  CONTRACTS_WORLD.md                 This file.
  engine/data/
    textures.dart                    Textures: PNAMES/TEXTURE1[/2], flats, sprites.
  game/world/
    defs.dart                        Geometry structs (r_defs.h port).
    level.dart                       Level + Level.load (p_setup.c port),
                                     Blockmap, Reject, MapLump indices.
    ticcmd.dart                      TicCmd (d_ticcmd.h) + BT_* / BTS_* consts.
    world.dart                       World container + Viewpoint.
test/world/
  level_load_test.dart               Loads real E1M1; counts + consistency.
```

Default map loaded: **`E1M1`**.

---

## 1. Read / mutate boundary (the core contract)

Both agents hold one `World`. Ownership of mutation is split as follows.

### RENDERER — reads only, never mutates
- `world.viewpoint` — camera (`x,y,z` fixed_t, `angle` angle_t).
- `world.level` — all geometry arrays (vertexes, sectors, sides, lines, segs,
  subsectors, nodes), `blockmap`, `reject`.
- `world.textures` — composite texture columns, flat pixels, sprite bytes.
- Per-frame it reads the **dynamic** sector/side fields below as inputs.

### PLAYSIM — mutates
- `world.viewpoint` — set after moving the player each tic (vanilla
  R_SetupFrame copies player mobj pos + viewz here).
- `world.cmd` — consumes this tic's `TicCmd` (input fills it).
- `world.validCount` — bump before a blockmap/BSP traversal.
- Dynamic `Level` fields, listed per struct below. **Topology is static**
  (vertexes, sides, lines/segs/nodes/subsectors connectivity, blockmap, reject
  never change after load).

> Concretely, the renderer must treat everything as `const` except that it may
> read freshly-mutated values; the playsim is the sole writer of the dynamic
> fields. No locking — single-threaded 35Hz tic then render, per the GameLoop.

**Dynamic (playsim-mutated) fields summary:**
- `Sector`: `floorHeight`, `ceilingHeight`, `floorPic`, `ceilingPic`,
  `lightLevel`, `special`, `soundTraversed`, `soundTarget`, `thingList`,
  `specialData`, `validCount`.
- `Side`: `textureOffset`, `rowOffset` (scrollers); textures normally static.
- `Line`: `flags` (e.g. clearing `mlSecret`), `special` (one-shot clear),
  `validCount`, `soundOrg`.
- `Viewpoint`: all fields.

---

## 2. Geometry structs — `game/world/defs.dart`

All are **mutable classes** (vanilla mutates in place; both agents share
instances). `import '.../game/world/defs.dart';`

```dart
class Vertex { fixed_t x, y; Vertex(this.x, this.y); }            // <<FRACBITS on load
class DegenMobj { fixed_t x, y, z; }                              // sound origin

class Sector {
  Sector({required fixed_t floorHeight, required fixed_t ceilingHeight,
          required int floorPic, required int ceilingPic,
          required int lightLevel, required int special, required int tag});
  fixed_t floorHeight, ceilingHeight;     // DYNAMIC
  int floorPic, ceilingPic;               // flat numbers; DYNAMIC (animation)
  int lightLevel;                         // 0..255; DYNAMIC
  int special, tag;                       // special DYNAMIC; tag static
  List<Line> lines;                       // built by P_GroupLines (static)
  int get lineCount;
  final List<fixed_t> blockBox;           // [Box.top,bottom,left,right] fixed_t
  late DegenMobj soundOrg;                // sector centre
  int soundTraversed;                     // DYNAMIC
  Object? soundTarget;                    // mobj; DYNAMIC (playsim casts)
  Object? thingList;                      // intrusive mobj list head; DYNAMIC
  Object? specialData;                    // active plane thinker; DYNAMIC
  int validCount;                         // DYNAMIC
}

class Side {
  Side({required fixed_t textureOffset, required fixed_t rowOffset,
        required int topTexture, required int bottomTexture,
        required int midTexture, required Sector sector});
  fixed_t textureOffset, rowOffset;       // DYNAMIC (scrollers)
  int topTexture, bottomTexture, midTexture;  // composite texture numbers; 0 = "-"
  Sector sector;                          // faces into this sector
}

abstract final class Box { static const int top=0, bottom=1, left=2, right=3; }
enum SlopeType { horizontal, vertical, positive, negative }

class Line {
  Line({required Vertex v1, required Vertex v2, required int flags,
        required int special, required int tag,
        required Side frontSide, required Side? backSide});
  Vertex v1, v2;
  fixed_t dx, dy;                         // v2-v1, precomputed
  int flags;                              // ML_* ; DYNAMIC
  int special, tag;                       // special DYNAMIC
  Side frontSide; Side? backSide;         // backSide null => one-sided
  late Sector frontSector; late Sector? backSector;
  late SlopeType slopeType;
  final List<fixed_t> boundingBox;        // [Box.*]
  int validCount;                         // DYNAMIC
  DegenMobj? soundOrg;                    // optional; playsim fills
  bool get isTwoSided;                    // (flags & mlTwoSided) != 0
}

// ML_* flags:
const int mlBlocking, mlBlockMonsters, mlTwoSided, mlDontPegTop,
          mlDontPegBottom, mlSecret, mlSoundBlock, mlDontDraw, mlMapped;

class Seg {
  Seg({required Vertex v1, required Vertex v2, required fixed_t offset,
       required angle_t angle, required Side sidedef, required Line linedef,
       required Sector frontSector, required Sector? backSector});
  Vertex v1, v2; fixed_t offset; angle_t angle;
  Side sidedef; Line linedef;
  Sector frontSector;                     // = sidedef.sector
  Sector? backSector;                     // opposite side's sector (2-sided)
}

class Subsector { Sector sector; int numLines, firstLine; }  // firstLine -> segs[]

class Node {
  fixed_t x, y, dx, dy;                   // partition line
  final List<List<fixed_t>> bbox;         // bbox[childIdx][Box.*]; 0=right,1=left
  final List<int> children;               // [right,left]; nfSubsector bit => subsector
}
const int nfSubsector = 0x8000;

class MapThing {
  MapThing({required int x, required int y, required int angle,
            required int type, required int options});
  int x, y;        // WHOLE map units (NOT fixed_t) — vanilla mapthing_t
  int angle;       // DEGREES 0..359
  int type;        // DoomEd number
  int options;     // MTF_* spawn flags
}
const int mtfEasy, mtfNormal, mtfHard, mtfAmbush, mtfNotSingle;
```

Notes:
- `Line.slopeType` is classified exactly as P_LoadLineDefs
  (`!dx`→vertical, `!dy`→horizontal, else `FixedDiv(dy,dx)>0`?positive:negative).
- `MapThing.x/y` are **whole units**, matching vanilla; playsim does
  `<<FRACBITS` at spawn (`P_SpawnMapThing`). Everything else is already fixed_t.
- `Subsector.sector` is resolved eagerly from the first seg's sidedef (vanilla
  resolves it in R_Subsector; same value).

---

## 3. Level + map loading — `game/world/level.dart`

```dart
abstract final class MapLump {                 // offsets from the map marker lump
  static const int things=1, linedefs=2, sidedefs=3, vertexes=4, segs=5,
                   ssectors=6, nodes=7, sectors=8, reject=9, blockmap=10;
}

class Level {
  final String name;
  final List<Vertex> vertexes;
  final List<Sector> sectors;
  final List<Side> sides;
  final List<Line> lines;
  final List<Seg> segs;
  final List<Subsector> subsectors;
  final List<Node> nodes;
  final List<MapThing> things;
  final Blockmap blockmap;
  final Reject reject;
  int get rootNode;                            // nodes.length - 1

  factory Level.load(WadFile wad, Textures textures, {String mapName = 'E1M1'});
}
```

`Level.load` is the `P_SetupLevel` port: reads the 10 lumps after the marker,
converts shorts→fixed_t (`<<FRACBITS`), resolves all cross-references to object
instances, runs `P_GroupLines` (per-sector `lines`, `blockBox`, `soundOrg`).
Throws `WadException` if `mapName` is absent.

```dart
class Blockmap {
  final int originX, originY;     // WHOLE units (multiply by FRACUNIT for fixed_t)
  final int width, height;        // blocks (128-unit cells)
  final Int16List offsets;        // width*height cell offsets into lumpData
  final Int16List lumpData;       // entire blockmap as int16
  factory Blockmap.fromLump(Lump lump);
  List<int> linesInBlock(int bx, int by);  // line indices in a cell (no terminator)
}

class Reject {
  final Uint8List bits; final int numSectors;
  factory Reject.fromLump(Lump lump, int numSectors);
  bool rejected(int i, int j);    // sectors i,j cannot see each other (false if absent)
}
```

---

## 4. Textures / flats / sprites — `engine/data/textures.dart`

```dart
class TexPatch { final int originX, originY, patchLump; }  // patchLump: WAD lump#, -1 if missing
class Texture  { final String name; final int width, height; final List<TexPatch> patches; }

class Textures {
  factory Textures.fromWad(WadFile wad);          // R_InitData order
  int get numTextures, numFlats, numSprites;

  // Wall textures
  Texture texture(int num);
  int checkTextureNumForName(String name);        // -1 if missing; "-" => 0
  int textureNumForName(String name);             // 0 (placeholder) if missing
  Uint8List textureColumns(int texNum);           // composited, COLUMN-MAJOR: [col*h + row]; cached
  Uint8List textureColumn(int texNum, int col);   // single column, height bytes (view into cache)

  // Flats (64x64, 4096 bytes, ROW-MAJOR [y*64 + x])
  int checkFlatNumForName(String name);           // -1 if missing
  int flatNumForName(String name);                // 0 if missing
  Uint8List flatPixels(int flatNum);              // 4096-byte zero-copy WAD view
  int flatLumpNum(int flatNum);

  // Sprites (Doom picture format; decode with engine/video/patch.dart Patch)
  int checkSpriteNumForName(String name);         // -1 if missing
  int spriteLumpNum(int spriteNum);
  Uint8List spriteBytes(int spriteNum);
}
```

**Caching:** `textureColumns` composites on first call and caches the full
`width*height` buffer for the texture's lifetime; `textureColumn` is a
zero-copy view into it. Flats/sprites are zero-copy views over the WAD bytes
(no caching needed). Compositing draws each patch's posts into the buffer in
column-major order (faithful to `R_GenerateComposite`); uncovered rows stay 0.

**Renderer usage:** sample wall columns via `textureColumn(side.midTexture, c)`
(0 means "-"/no texture — skip). Sample floor/ceiling via
`flatPixels(sector.floorPic)`. Map the resulting palette indices through
`Colormap` then `Palette` (Phase 1).

**Shareware note:** `doom1.wad` has **no TEXTURE2**; only TEXTURE1 is parsed.
Loaded counts for E1M1: 125 textures, 56 flats, 483 sprite lumps.

---

## 5. ticcmd — `game/world/ticcmd.dart`

```dart
class TicCmd {
  int forwardMove, sideMove;      // signed; *2048 applied to momentum
  int angleTurn;                  // signed short; player.angle += angleTurn << 16
  int consistancy;               // net consistency (vanilla spelling)
  int chatChar, buttons, buttons2, inventory;  // buttons2/inventory unused in Doom
  void clear();
  void copyFrom(TicCmd other);
}

// Buttons: btAttack, btUse, btChangeWeapon, btWeaponMask, btWeaponShift,
//          btSpecial, btSpecialMask; btsPause, btsSaveGame, btsSaveMask, btsSaveShift.
```

Pure data. Input builds it (`G_BuildTiccmd`), playsim consumes it
(`P_PlayerThink`). `buttons2`/`inventory` kept for struct parity (Strife),
unused in Doom.

---

## 6. World container + Viewpoint — `game/world/world.dart`

```dart
class Viewpoint {                  // R_SetupFrame inputs; PLAYSIM writes, RENDERER reads
  fixed_t x, y, z;                 // viewx, viewy, viewz
  angle_t angle;                   // viewangle
  void set({required fixed_t x, required fixed_t y, required fixed_t z,
            required angle_t angle});   // angle is normAngle'd
}

class World {
  World({required WadFile wad, required Textures textures, required Level level});
  factory World.fromWad(WadFile wad, {String mapName = 'E1M1'});  // bootstrap
  final WadFile wad;
  final Textures textures;
  Level level;                     // replaced by changeLevel
  final Viewpoint viewpoint;       // PLAYSIM writes, RENDERER reads
  final TicCmd cmd;                // input fills, PLAYSIM consumes
  int validCount;                  // bump before traversals
  void changeLevel(String mapName);
}
```

- **Renderer obtains a viewpoint + level:** read `world.viewpoint` and
  `world.level` / `world.textures`. Nothing else needed.
- **Playsim obtains mutable level + things:** mutate `world.level.sectors/...`,
  spawn mobjs from `world.level.things`, write `world.viewpoint` after moving
  the player, consume `world.cmd`, bump `world.validCount`.

---

## 7. Assumptions / deviations from vanilla

- **Graceful name resolution:** `textureNumForName`/`flatNumForName` return the
  placeholder `0` (not `I_Error`) on a miss; the `check*` variants return `-1`
  for callers that need to detect absence. A missing composite patch is stored
  as `patchLump == -1` and skipped during compositing instead of aborting.
- **Eager subsector sector / seg backSector resolution** at load (vanilla
  resolves the subsector's sector lazily in R_Subsector); the value is identical.
- **`thingList`/`soundTarget`/`specialData` typed `Object?`** to avoid a hard
  dependency on the playsim `mobj_t`/thinker types (which this layer does not
  own). Playsim casts. This keeps the data layer decoupled.
- **`MapThing` stores whole units / degrees** (raw lump form); playsim converts
  to fixed_t / BAM at spawn — matches vanilla `mapthing_t` vs `mobj_t`.
- **No node-builder / GL nodes / extended (DeePBSP/ZDBSP) formats** — only the
  classic vanilla lump layout is parsed (sufficient for the shareware IWAD).
- **No locking** — single-threaded tic-then-render model from the Phase-1
  GameLoop; the read/mutate split is a discipline, not enforced at runtime.
- Texture composite buffers are kept for the life of the `Textures` object (no
  eviction); fine for vanilla map sizes.

---

## 8. Verification status

- `flutter analyze lib/game/world lib/engine/data test/world` → **clean**.
- `flutter test` → **all pass** (incl. `test/world/level_load_test.dart`:
  loads real `assets/doom1.wad` E1M1, asserts exact counts
  467 verts / 85 sectors / 648 sides / 475 lines / 732 segs / 237 subsectors /
  236 nodes / 138 things, full index-range consistency, resolves STARTAN3
  texture + FLOOR4_8 flat + PLAYA1 sprite).

## 9. Notes for the integration phase (files this layer may NOT touch)

- `lib/game/doom_game.dart` should construct a `World.fromWad(wad)` and pass
  `world` to both the renderer (`onRender`) and playsim (`onTic`) hooks.
- No changes were needed to `lib/INTERFACES.md`, `pubspec.yaml`, `main.dart`,
  or any `engine/{math,wad,video,input,system}` file — this layer builds purely
  on the existing public APIs.
