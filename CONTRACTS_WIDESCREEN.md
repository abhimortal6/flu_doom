# CONTRACTS_WIDESCREEN.md — true (non-stretched) widescreen rendering

Wave 2 (solo). Goal: render a WIDER field of view to fill a 16:9+ screen
**without stretching** the 4:3 image. Widescreen is a TOGGLE; 4:3 (320 wide) is
the always-available fallback and must stay byte-identical to today (the render
golden at `test/render/render_frame_test.dart` MUST still pass).

This follows the Crispy/Woof technique: keep SCREENHEIGHT=200 and the VERTICAL
projection identical to 4:3; only WIDEN SCREENWIDTH so the horizontal FOV extends
(you see more left/right). Rebuild every width-derived table; all vertical math,
light tables, and per-column/per-span drawing stay byte-faithful.

---

## 1. Width formula (single source of truth)

Add a pure helper (suggested: `lib/engine/video/widescreen.dart`):

```dart
/// 4:3 baseline render width (vanilla SCREENWIDTH).
const int kBaseWidth = 320;
const int kRenderHeight = 200;          // SCREENHEIGHT, never changes
const double kPixelAspect = 1.2;        // Doom's non-square pixel (5:6)

/// Compute the widescreen render width for a device aspect (w/h).
/// width = round(200 * 1.2 * targetAspect), snapped EVEN, clamped
/// [kBaseWidth .. maxWidth(21:9)]. 4:3 device or narrower -> 320.
int widescreenWidthFor(double deviceAspect) {
  // 200*1.2 = 240 "square-pixel" height units; width = 240 * aspect.
  int w = (kRenderHeight * kPixelAspect * deviceAspect).round();
  if (w < kBaseWidth) w = kBaseWidth;            // never narrower than 4:3
  // Cap to 21:9 to avoid fisheye on ultrawide phones.
  const int maxW = 560; // round(240 * (21/9)) = 560, even
  if (w > maxW) w = maxW;
  if (w.isOdd) w += 1;                            // even for centerx symmetry
  return w;
}
```

- 16:9 -> round(240*1.777..) = 427 -> even -> **426** (or 428; pick the even
  snap consistently — round-then-floor-to-even is fine, just be deterministic).
- 4:3 (1.333) -> 320 exactly. 21:9 capped at 560.
- The chosen widescreen width for a device is computed ONCE from the device's
  longest/short side aspect (landscape orientation aspect = max(w,h)/min(w,h)).

**Default:** widescreen ON for mobile (AspectMode.widescreen). 4:3 selectable.

---

## 2. The render core is ALREADY width-parameterized — DO NOT touch its math

`RenderState`, `SegRenderer`, `BspRenderer`, `PlaneRenderer`, `ThingRenderer`,
`DrawContext` all derive every width-sized table/array/bound from
`state.screenWidth` / `state.viewWidth` / `state.centerX` / `framebuffer.width`:

- `RenderState`: centerX=w/2, centerXFrac, projection, pspriteScale, viewAngleToX
  (FINEANGLES/2, width-independent length but width-valued), xToViewAngle[w+1],
  clipAngle, ceilingClip[w], floorClip[w], negOneArray[w], screenHeightArray[w],
  scaleLight/zLight (use w/2). The `_initTextureMapping` and `_initLightTables`
  already read screenWidth/viewWidth. **Verify they rebuild for w=426 — they do.**
- `SegRenderer`: openings = Int16List(screenWidth*64).
- `BspRenderer`: solidsegs grow on demand; clearClipSegs uses viewWidth. OK.
- `PlaneRenderer`: yslope[viewHeight], distScale[screenWidth], VisPlane(width),
  baseXScale/baseYScale use centerXFrac. OK.
- `ThingRenderer`: clipBot/clipTop[screenWidth]; psprite centering uses
  centerXFrac/screenWidth/viewWidth. OK.
- `DrawContext(fb)`: screenWidth=fb.width, screenHeight=fb.height. OK.

**=> The ONLY engine change is constructing the Framebuffer + Renderer at the
chosen width. The rasterization math is untouched. Confirm by re-running the 4:3
golden (must still match) AND adding a widescreen-table-rebuild test.**

Leave `kScreenWidth`/`kScreenHeight` consts in framebuffer.dart as-is (320/200)
— they are the DEFAULTS and the 4:3 reference. The framebuffer width is already
an instance field (`fb.width`); pass an explicit width to widen.

---

## 3. 2D centering convention (the load-bearing rule)

All 2D UI (status bar, HUD, menu, title/finale patches, intermission, pause) is
authored for a 320-wide canvas. On a wider framebuffer, draw them centered:

```
xOffset = (fb.width - kBaseWidth) ~/ 2;   // 0 when fb.width == 320
```

The 3D view fills the FULL width (renderer writes 0..fb.width). The HUD/menus sit
centered in a 320-wide band. Concretely:

- **Status bar** (`StatusBar.draw`): shift every draw x by `xOffset`. The bar is
  168..199 tall, 320 wide, centered horizontally at the bottom. Fill the exposed
  side strips (x in [0,xOffset) and [xOffset+320, fb.width)) on rows 168..199
  with a clean fill BEFORE drawing the bar: simplest acceptable = the STBAR's
  leftmost/rightmost edge color, or solid black (index 0). Pick black or edge —
  no garbage. (The 3D view already covered those side rows above y=168, but the
  bar rows need a deliberate fill so the strips aren't stale 3D pixels.)
- **HUD** (`Hud.draw` / `_drawFullscreen`): message line at x=xOffset (vanilla
  HU_MSGX=0 -> xOffset); fullscreen readout anchored to the centered 320 band
  (left = xOffset+2; right = xOffset + 320 - w - 2).
- **Menu** (`MenuController.draw` + `_drawThermo` + `_drawMessage`): banner
  center uses `(fb.width - p.width)~/2` (already centers on screen width — change
  kScreenWidth -> fb.width). Items at `xOffset + m.x`; skull at `xOffset+m.x-32`;
  thermo at `xOffset + ...`; message centering uses fb.width.
- **Title/finale** (`game_state._drawTitle/_drawFinale`): TITLEPIC/CREDIT are
  320x200 fullscreen patches. Center: `_gc.draw(fb, 'TITLEPIC', xOffset, 0)`.
  Fill the side strips (x<xOffset, x>=xOffset+320) with black first (clear fb to
  0) so the title isn't flanked by garbage.
- **Pause** (`_drawPause`): `(fb.width - p.width)~/2`.
- **Intermission** (`intermission.dart`): center WIF and all stat layout on
  fb.width / xOffset. (It draws a fullscreen WIMAP background too — center it and
  black-fill the strips, same as title.)
- **Automap** (`Automap.draw`): use the FULL width. Set `viewWidth = fb.width`
  (and `viewHeight` stays fb.height-32 for the status bar) at draw time from the
  passed `fb`, so the map fills the whole wider screen.

How to thread `fb.width`: every `draw(fb, ...)` already receives `fb`. Compute
`xOffset` locally from `fb.width` inside each draw method. NO new constructor
params needed; keep it `(fb.width - 320) ~/ 2`. When fb.width==320 the offset is
0 and behavior is identical (golden-safe for the UI tests at 320).

---

## 4. Framebuffer-width-sized buffers that are NOT the renderer

- **Wipe** (`wipe.dart`) uses `const _size = kScreenWidth*kScreenHeight` and
  `kScreenWidth~/2` column counts — HARDCODED 320. With a wider fb the melt
  would corrupt. Fix: make `WipeMelt.start(start, end)` derive width/height from
  the byte length (or accept width/height), and use those instead of the const.
  The start/end byte arrays are `_fb.pixels` copies, so width = bytes.length ~/
  kScreenHeight (height is always 200). Make `_shittyColMajorXform`, the `y[]`
  array, and `doMelt` width-relative. Keep the algorithm 1:1 — only the width
  source changes from const to variable.

---

## 5. GraphicsSettings + screen toggle (present/config layer)

`graphics_settings.dart`:
- Add `enum AspectMode { fourThree, widescreen }`.
- Add field `final AspectMode aspectMode;` (default `AspectMode.widescreen`).
- Wire into constructor, copyWith, toJson/fromJson (backward-compatible: missing
  key -> widescreen), ==, hashCode.
- (`effectiveCrtIntensity` already exists — used by the CRT one-liner below.)

`graphics_settings_screen.dart`:
- Add an "Aspect ratio" SegmentedButton (key `gfxAspectMode`): 4:3 vs Widescreen,
  selected from `_settings.aspectMode`, `_set(copyWith(aspectMode: ...))`.
- Keep the existing 4:3 pixel-aspect-correction switch (it is the PRESENT-layer
  height*1.2; orthogonal to render width). Clarify labels if helpful.

---

## 6. doom_game.dart — rebuild on boot + on toggle + the CRT one-liner

- The `_fb` and `Renderer` are currently built at 320 in field initializers /
  `_boot`. Make them rebuildable at a chosen width:
  - Add `int _renderWidth = kBaseWidth;` and make `_fb` / `_renderer` non-final
    (assigned in `_boot` and on toggle).
  - On boot: if `_gfx.aspectMode == widescreen`, compute the width from the
    device aspect. Get the device size from the first frame / MediaQuery; if not
    available at boot, default to a 16:9 widescreen width (426) and refine on the
    first build via `MediaQuery.of(context)` (landscape aspect). A fixed 426 is
    acceptable for v1 if reading the live device aspect is awkward — document it.
  - Build `Framebuffer(width: _renderWidth)` and
    `Renderer(framebuffer: _fb, world: sim.world)` (Renderer reads fb.width).
  - **Rebuild path** (`_rebuildRenderer(int width)`): create a new Framebuffer +
    new Renderer, re-point `gs.config.worldView` to the new renderer's
    renderPlayerView (the worldView closure captures `renderer`; you must rebuild
    the closure or hold the renderer in a mutable field the closure reads). The
    cleanest: store `Renderer? _renderer;` and have the worldView closure call
    `_renderer!.renderPlayerView(sprites, psprites)`. Then rebuild = swap `_fb`
    and `_renderer`. Re-render a frame after swap.
  - Call `_rebuildRenderer` from `_applyGraphics` when `aspectMode` changed, and
    (defensively) it's fine to also rebuild on level load — but a single renderer
    that reads `world.level` live already handles level changes, so width only
    needs rebuilding when the aspect toggles or the device aspect changes.
- **CRT one-liner**: in the `VideoView(...)` call, add
  `crtIntensity: _gfx.effectiveCrtIntensity,`.
- **Present (no stretch):** when widescreen, the framebuffer aspect already
  matches the device (we sized it from the device aspect), so `ScaleMode.fit`
  with `pixelAspectCorrection` gives a full-bleed, non-stretched image (minimal
  letterbox). Keep 4:3 letterboxed exactly as before. Do NOT use ScaleMode.fill
  for widescreen (that WOULD stretch). The existing VideoView already preserves
  source aspect under fit/integer — no stretch. Confirm in the screenshot.

Keep the "screen size" cosmetic inset and the touch overlay untouched.

---

## 7. Tests (test/) — keep goldens, add widescreen coverage

- **DO NOT change** `render_frame_test.dart` goldens. The default `Framebuffer()`
  is 320 -> golden unchanged.
- Add `test/render/widescreen_test.dart`:
  1. Width formula: `widescreenWidthFor(16/9)` is even, in (320, 560],
     `widescreenWidthFor(4/3)==320`, `widescreenWidthFor(21/9)==560` (cap),
     ultra-narrow -> 320.
  2. Table rebuild at a widescreen width (e.g. 426): build
     `Framebuffer(width:426)` + Renderer at E1M1 start; assert
     `state.centerX==213`, `state.xToViewAngle.length==427`,
     `state.ceilingClip.length==426`, `state.floorClip.length==426`,
     `state.viewAngleToX` min==0 && max==426, `xToViewAngle[centerX]==0`.
  3. Widescreen coherent frame: render E1M1 start at width 426; assert NO
     uninitialized/garbage edge columns — every column 0..425 has at least one
     non-zero pixel (the 3D view filled it), AND a coherent floor/ceiling/wall
     split like the 320 structural tests (reuse the horizon-split + neighbor-
     coherence checks across the FULL width). Assert width-320 still matches the
     existing golden hash too (sanity that 4:3 path is intact).
- Add a GraphicsSettings test (extend `test/settings/...` or
  `test/video/video_view_settings_test.dart`): aspectMode round-trips through
  JSON, default is widescreen, missing-key load -> widescreen.

---

## 8. Screenshots (mandatory) — wide_16x9 + wide_4x3

Add an opt-in dump test (pattern: `gfx_present_dump_test.dart`), e.g.
`test/render/widescreen_dump_test.dart`, gated on `DUMP_WIDE=1`:
- Render E1M1 start into a widescreen framebuffer (width = widescreenWidthFor(16/9)),
  decode via palette, blit through VideoView (ScaleMode.fit, pixelAspect on) onto
  a 16:9 surface (e.g. 1280x720) -> `debug_shots/wide_16x9.png`.
- Render the SAME scene into a 320 framebuffer, blit onto the same 1280x720
  surface (letterboxed) -> `debug_shots/wide_4x3.png`.
Run with `DUMP_WIDE=1 flutter test test/render/widescreen_dump_test.dart -d macos`.
The integration will READ both PNGs and compare: widescreen must show MORE scene
horizontally (wider FOV), correct vertical proportions (not squashed/fisheye),
clean edges (no garbage columns), centered intact HUD, centered weapon.

---

## 9. Verify

- `flutter analyze lib test` clean; `flutter test` all pass (4:3 golden included).
- Honest reporting: if any edge garbage / squashing / HUD misplacement remains,
  fix or clearly state it.
