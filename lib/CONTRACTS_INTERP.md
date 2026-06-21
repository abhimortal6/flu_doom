# CONTRACTS_INTERP.md — frame interpolation (uncapped smooth motion)

Crispy/Woof render-only interpolation. The 35Hz sim stays byte-identical; only
what the renderer DRAWS is lerped between the previous tic and the current tic
by a per-frame fractional factor `frac` ∈ [0,1].

## CRITICAL INVARIANT
Interpolation NEVER feeds back into the sim. Physics/collision/thinkers always
use the real 35Hz fields. We only (a) ADD `old*` capture fields and (b) lerp at
render time. At `frac==0` OR `old==new` OR interpolation OFF, the rendered frame
is byte-identical to today (golden 0x36c705a0ae0e1ce0 holds).

## 1. InterpolationState (NEW: lib/engine/system/interpolation.dart)
A tiny shared holder, owned by `World` (renderer + sim both reach it):

```dart
class InterpolationState {
  bool enabled = true;          // 'Smooth motion' toggle (default ON)
  fixed_t frac = 0;             // 16.16 inter-tic fraction, [0, FRACUNIT]
  bool active = false;          // true only while the sim is advancing this frame
                                //   (frozen on pause/menu -> render at frac=FRACUNIT)
  /// Effective fraction the renderer uses: enabled&&active ? frac : FRACUNIT.
  fixed_t get renderFrac => (enabled && active) ? frac : kFracUnit;
}

/// Fixed-point lerp used everywhere: old + (new-old)*frac (16.16).
fixed_t lerpFixed(fixed_t a, fixed_t b, fixed_t frac) =>
    toInt32(a + fixedMul(toInt32(b - a), frac));

/// Angle interpolation via the SIGNED short delta (handles BAM wrap).
/// delta = (int)(new - old) as a signed 32-bit; result = old + delta*frac.
angle_t lerpAngle(angle_t a, angle_t b, fixed_t frac) { ... }
```

`World` gains: `final InterpolationState interp = InterpolationState();`

`renderFrac == FRACUNIT` means "draw current positions" → byte-identical to
today. That is the golden / interpolation-OFF / paused path.

## 2. frac computation + exposure (gameloop.dart -> doom_game.dart)
GameLoop already runs a microsecond accumulator. After running due tics, the
leftover `_accumulatorMicros` (∈ [0, kMicrosPerTic)) is the inter-tic fraction:
`frac16 = (_accumulatorMicros << 16) / kMicrosPerTic`, clamped [0, FRACUNIT].
GameLoop exposes `int get subTicFrac16`. It also tracks whether any tic ran this
frame is NOT needed; "active" = whether the SIM advanced, decided in doom_game
(`activePlay`). doom_game sets `world.interp.active = activePlay` and
`world.interp.frac = loop.subTicFrac16` each frame BEFORE render.

When `!activePlay` (menu/paused/title), set `active=false` → renderFrac=FRACUNIT
→ no interpolation jitter (Crispy freezes the view while paused).

## 3. Old-state capture (sim, ADD-ONLY — no math change)
Captured at the START of `PlaySim.tic()`, BEFORE any mutation:
- `Viewpoint`: ADD `oldX/oldY/oldZ` (fixed_t) + `oldAngle` (angle_t). At the
  start of tic, copy current viewpoint -> old*. (Viewpoint is written at END of
  the PREVIOUS tic, so at tic start it still holds last tic's value = correct old.)
- `Mobj`: ADD `oldX/oldY/oldZ`. At tic start, for every mobj thinker, copy
  x/y/z -> oldX/oldY/oldZ. New mobjs spawned DURING the tic get old==new in
  their spawn path (see snap).
- Moving sectors: `Sector` ADD `oldFloorHeight/oldCeilingHeight`. PlaySim keeps
  a registry of sectors with an active mover; at tic start copy current
  heights -> old*. The DoorManager registers/unregisters a sector when it gains/
  loses `specialData`.

NONE of these fields are read by the sim. They are pure render inputs.

## 4. Render-time interpolation (Crispy R_InterpolateView + R_RestoreInterpolations)
A helper `Interpolator` run by the render path each frame:
- View: doom_game/renderer reads `world.interp.renderFrac` and computes
  interpolated viewx/y/z = lerpFixed(old,new,frac), viewangle = lerpAngle(...),
  passing them to `RenderState.setupFrame`. (Viewpoint old/new both live on
  `world.viewpoint`.)
- Sprites: `PlaySpriteAdapter.collect` emits lerpFixed(mobj.oldX, mobj.x, frac)
  etc. when interp active; current x/y/z when renderFrac==FRACUNIT.
- Psprites: psprite `sx/sy` interpolated. ADD `oldSx/oldSy` to `Pspdef`,
  captured each tic; adapter lerps.
- Sectors: BECAUSE ~30 renderer read sites use `sector.floorHeight` directly,
  use Crispy's write-then-restore: just before render, for each registered
  moving sector, save real heights, write lerped heights INTO floorHeight/
  ceilingHeight; after render, restore the real heights. This keeps every read
  site unchanged and the sim never sees the lerped values (restored before the
  next tic). Guard: only when renderFrac != FRACUNIT.

At renderFrac==FRACUNIT every lerp returns `new` exactly → golden byte-identical.

## 5. Snap (no lerp across discontinuities)
Set old==new so no smear:
- Level load / new game / reborn / spawnLevel: after spawning, old=new for the
  viewpoint, every mobj, every sector.
- Mobj spawn: in the spawn path set oldX/Y/Z = x/y/z.
- Teleport: P_Teleport sets the mobj's old==new (and viewpoint old==new for the
  player) so the jump doesn't lerp.
- Defensive global: if |new-old| for a mobj/view exceeds a large threshold
  (e.g. > 128 units in x or y), snap that axis (old=new) that frame. Crispy uses
  explicit flags; the threshold is a belt-and-suspenders backstop.

## 6. Toggle (graphics_settings.dart + screen + doom_game)
ADD `bool smoothMotion = true` (default ON) to `GraphicsSettings` (+ copyWith,
toJson/fromJson back-compat default true, ==/hashCode). Add a switch row in
graphics_settings_screen.dart. doom_game applies it: `world.interp.enabled =
gfx.smoothMotion`. Persisted via the existing store.

## Touched files (by module region)
- engine/system/interpolation.dart (NEW), gameloop.dart
- game/world/world.dart (+InterpolationState ref), defs.dart (Sector old fields),
  game/play/mobj.dart (old fields), playsim.dart (capture+snap),
  p_doors.dart (register movers), spawn.dart (spawn snap),
  p_pspr.dart/player.dart (psprite old fields), p_user.dart? (no — viewz already in viewpoint)
- engine/render/render_state.dart (unchanged signature ok), renderer.dart
  (read renderFrac for view + run sector interp wrap)
- game/integration/sprite_adapter.dart, psprite_adapter.dart (lerp emit)
- game/doom_game.dart (wire frac/active/enabled + sector restore around render)
- input_actions/graphics_settings.dart, ui/settings/graphics_settings_screen.dart
- test/*
</content>
