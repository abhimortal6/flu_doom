# flu_doom — 3D Renderer Contracts (Phase 2.x)

Faithful pure-Dart port of the Chocolate Doom software renderer (`r_main`,
`r_bsp`, `r_segs`, `r_plane`, `r_things`, `r_draw`, `r_sky`, `r_data`). Builds
strictly on `lib/INTERFACES.md` (foundation) and `lib/CONTRACTS_WORLD.md`
(world data layer). The renderer **reads** the `World` and **never mutates** it,
per the world contract's read/mutate boundary.

---

## 1. File layout (this module)

```
lib/
  CONTRACTS_RENDER.md            This file.
  render_preview_main.dart       Visual preview entry (flutter run -t ... -d macos).
  engine/render/
    renderer.dart                Renderer (R_RenderPlayerView) — public entry point.
    render_state.dart            RenderState: R_SetupFrame, R_InitTables,
                                 R_InitLightTables, R_PointToAngle/Dist, projection
                                 tables (viewangletox/xtoviewangle), light tables.
    draw.dart                    DrawContext: R_DrawColumn / R_DrawSpan /
                                 R_DrawFuzzColumn (typed-data inner loops).
    planes.dart                  PlaneRenderer + VisPlane: R_FindPlane / R_CheckPlane
                                 / R_MapPlane / R_MakeSpans / R_DrawPlanes + sky.
    segs.dart                    SegRenderer + DrawSeg: R_StoreWallRange /
                                 R_RenderSegLoop (solid + 2-sided walls,
                                 upper/lower/mid textures, openings).
    bsp.dart                     BspRenderer: R_RenderBSPNode / R_Subsector /
                                 R_AddLine / R_Clip{Solid,Pass}WallSegment /
                                 R_CheckBBox + solidsegs cliprange list.
    things.dart                  ThingRenderer: R_ProjectSprite / sort /
                                 R_DrawVisSprite / R_DrawMasked +
                                 R_RenderMaskedSegRange.
    sprite_source.dart           SpriteSource / SpriteResolver interfaces
                                 (dependency inversion for the masked pass).
test/render/
  render_frame_test.dart         Loads real E1M1, renders from player-1 start,
                                 asserts a real, deterministic, varied scene.
```

No files outside `lib/engine/render/`, `test/render/`, and
`lib/render_preview_main.dart` were created or modified.

---

## 2. Per-frame integration entry point

```dart
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';

// Construct ONCE (after the World exists, e.g. in DoomGame._boot):
final Renderer renderer = Renderer(framebuffer: fb, world: world);

// Each frame, inside the GameLoop onRender hook (after playsim wrote viewpoint):
renderer.renderPlayerView(spriteSource);   // spriteSource optional
// then: final ui.Image img = await fb.toImage(palette);  // existing foundation
```

Signature:

```dart
class Renderer {
  Renderer({required Framebuffer framebuffer, required World world});
  World world;                                   // reassignable on level change
  RenderState get state;                         // debug/introspection
  void renderPlayerView([SpriteSource sprites = const EmptySpriteSource()]);
}
```

- The renderer reads `world.viewpoint` (x/y/z/angle) and `world.level` /
  `world.textures` only. It loads `COLORMAP` and `PLAYPAL`-derived data itself
  via the foundation (`Colormap.fromWad`); the caller supplies the `Palette`
  when converting the framebuffer to an image (unchanged foundation flow).
- On a level change, set `renderer.world = newWorld` (tables/state are reused;
  the screen size is fixed at construction).
- `renderPlayerView` writes palette indices into `framebuffer.pixels`. It does
  **not** clear to a background colour — a full frame always covers every pixel
  (walls + floors + ceilings + sky), so no clear is needed. (If a future map
  exposes the void, add `framebuffer.clear()` first.)

---

## 3. SpriteSource interface (what play-sim must adapt to)

The masked/sprite pass is fully decoupled from the play-sim `mobj_t`. Play-sim
implements two interfaces in `engine/render/sprite_source.dart`:

```dart
abstract interface class SpriteSource {
  SpriteResolver get resolver;
  void collect(List<SpriteRequest> out);   // append all drawable things/frame
}

abstract interface class SpriteResolver {
  // rot: 0..7 view-relative rotation (0 faces viewer). null => skip the thing.
  SpriteFrameInfo? frameInfo(int spriteNum, int frame, int rot);
  bool isSingleRotation(int spriteNum, int frame);
}

class SpriteRequest {                       // one drawable thing (value type)
  const SpriteRequest({
    required fixed_t x, required fixed_t y, required fixed_t z, // world pos
    required angle_t angle,                  // thing facing (rotation pick)
    required int spriteNum,                  // opaque key -> resolver
    required int frame,                      // 0..28 (FF_FRAMEMASK)
    required int lightLevel,                 // sector lightlevel 0..255
    int flags = 0,                           // SpriteRequestFlags.*
  });
}

abstract final class SpriteRequestFlags {
  static const int shadow     = 1 << 0;      // MF_SHADOW (spectre fuzz)
  static const int fullBright = 1 << 1;      // FF_FULLBRIGHT
  static const int flip       = 1 << 2;      // pre-resolved mirror
}

class SpriteFrameInfo {
  const SpriteFrameInfo({required List<int> lumpPatchBytes, required bool flip});
}
```

- `spriteNum` is an **opaque key** owned by play-sim (its `sprnum_t` /
  `state_t.sprite`); the renderer never assumes Doom's enum ordering. The
  resolver maps `(spriteNum, frame, rot)` to the actual WAD patch bytes
  (decoded via the foundation `Patch`). Play-sim builds this from the
  S_START..S_END lumps it already has via `Textures.spriteBytes`.
- `EmptySpriteSource` (provided) yields no things and renders a valid view.
- The renderer does its own view-frustum + depth culling and vissprite sort;
  the source need not pre-cull or pre-sort.

> NOTE for integration: the renderer currently calls `Patch.fromBytes` per
> visible sprite each frame. If profiling shows this matters, the resolver
> should return a pre-decoded `Patch` instead of raw bytes — a one-line
> interface change deferred to the play-sim integration phase.

---

## 4. View / projection setup (faithful to vanilla)

- FOV = 90 degrees (`FIELDOFVIEW = 2048` fineangles), screen 320x200.
- `R_InitTextureMapping` builds `viewAngleToX[FINEANGLES/2]` and
  `xToViewAngle[viewWidth+1]`; `projection = centerxfrac`.
- `R_InitLightTables` builds `scaleLight[16][48]` and `zLight[16][128]`
  (LIGHTLEVELS / MAXLIGHTSCALE / MAXLIGHTZ) indexing into the 32-map
  `COLORMAP`. Walls shade by scale (`scalelight`), flats by distance
  (`zlight`), with fake-contrast +/-1 on axis-aligned walls and `extralight`
  support (wired to 0 until play-sim supplies weapon flashes).
- `R_SetupFrame` copies `viewx/viewy/viewz/viewangle` from `world.viewpoint`,
  precomputes `viewsin/viewcos`, and resets `ceilingclip[]=-1`,
  `floorclip[]=viewheight`.

---

## 5. Deviations from vanilla (documented)

1. **Status bar ignored — full-height 3D view.** `viewheight == screenheight`
   (200), `viewwidth == 320`, view window at (0,0). Vanilla reserves the bottom
   32px for the status bar (`ST_HEIGHT`); we render the 3D view full-screen for
   this phase. When the status bar is added, set the view window accordingly in
   `RenderState` (single place) — all projection/light tables derive from it.
2. **No `R_DrawColumnLow` / detail modes.** Only the high-detail (1x) drawers
   are implemented (vanilla's "low detail" mode is obsolete).
3. **Masked midtextures sampled from the composited texture column** (holes are
   palette index 0) rather than re-walking the patch posts. Faithful for the
   common case; fully-transparent regions of a masked midtexture may draw index
   0. (Sprites *do* honour real post transparency — they walk patch posts.)
4. **`R_CheckBBox` is a coverage test, not the exact vanilla `checkcoord`
   table micro-optimisation.** It only ever *adds* visited far subsectors;
   solidsegs still clips everything, so output is identical — it is purely an
   early-out optimisation and never changes pixels.
5. **Fuzz (spectre) effect uses COLORMAP map 6** with vanilla's `fuzzoffset`
   jitter; identical look, computed against the live framebuffer.
6. **64-bit math masked to signed 32-bit** via `toInt32` throughout (same as
   the foundation), reproducing C overflow where the algorithms rely on it.
7. **Sky** rendered as vertical full-bright columns from the SKY1 texture,
   wrapped by `viewangle >> ANGLETOSKYSHIFT(22)`; episode-1 only resolves SKY1
   (shareware IWAD has no SKY2/SKY3).
8. **Per-frame sprite Patch decode** (see section 3 note) — deferred optimisation.

---

## 6. Verification status

- `flutter analyze lib/engine/render lib/render_preview_main.dart test/render`
  → **No issues found.**
- `flutter test test/render/render_frame_test.dart` → **all pass**:
  - real E1M1, camera at player-1 start (type-1 MapThing, eye height
    `41*FRACUNIT` above the start sector floor, angle BAM-converted from
    degrees), empty SpriteSource;
  - asserts >8 distinct palette indices, no colour fills >90% of the screen,
    >25% of pixels non-zero, and byte-for-byte determinism across two renders.
  - Observed scene (center-column scan): grey ceiling band on top, STARTAN wall
    band, then a distance-shaded FLOOR4_8 floor (light indices stepping 5→6→7→8
    with distance) and the room's far walls/steps below — the recognizable E1M1
    starting room.
- `flutter run -t lib/render_preview_main.dart -d macos` renders the same first
  room; arrow keys move/turn for visual inspection (ESC handled by the OS).

---

## 7. Notes for the integration phase (files this module did NOT touch)

- `lib/game/doom_game.dart`: construct `Renderer(framebuffer: fb, world: world)`
  once after `World.fromWad`, then call `renderer.renderPlayerView(source)` in
  the `onRender` hook, then `fb.toImage(palette)` as today.
- The play-sim phase must provide a `SpriteSource` adapter over its mobjs +
  sprite tables (section 3). Until then, pass nothing / `EmptySpriteSource`.
- No new dependencies were added. (None required.)
