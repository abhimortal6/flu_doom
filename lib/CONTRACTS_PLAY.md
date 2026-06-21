# flu_doom — Play-Simulation Contracts (Phase 2.x)

The **play simulation**: a pure-Dart port of the vanilla Doom playsim
(Chocolate Doom `info.c`, `p_mobj.c`, `p_tick.c`, `p_user.c`, `p_map.c`,
`p_maputl.c`, the spawn portion of `p_setup.c`, `p_doors/p_plats/p_floor/
p_lights.c`, `p_pspr` basics, `g_game.c` ticcmd build).

It builds strictly on `lib/INTERFACES.md` (fixed/angle math, EventQueue,
GameLoop) and `lib/CONTRACTS_WORLD.md` (Level geometry, World/Viewpoint,
TicCmd, the renderer-reads / playsim-mutates boundary). It **owns** the
`mobj_t`/thinker/player types that the world layer left as `Object?`
(`Sector.thingList`, `Sector.specialData`, `Sector.soundTarget`).

All files live under `lib/game/play/`; tests under `test/play/`. No files
outside those directories were touched.

---

## 1. File layout

```
lib/game/play/
  thinker.dart        Thinker base + ThinkerList (P_AddThinker/RemoveThinker/RunThinkers).
  actions.dart        ActionRegistry: A_* dispatch by name; unimplemented = log-once no-op stub.
  info.dart           SpriteNum enum, spriteNames[], State (state_t), MobjInfo (mobjinfo_t),
                      FF_FULLBRIGHT / FF_FRAMEMASK.
  state_num.dart      Named state indices (St.*) the engine references directly.
  info_tables.dart    states[] + mobjInfo[] data tables + Mt.* mobjtypes + doomedToMobjType map.
  mobj_flags.dart     MF_* flag bits (verbatim from p_mobj.h).
  mobj.dart           Mobj (mobj_t): position, momentum, links, state, flags; tick() delegate.
  player.dart         Player (player_t), Pspdef (pspdef_t), PlayerState, kViewHeight.
  p_maputl.dart       pointOnLineSide, boxOnLineSide, lineOpening, blockX/Y, approxDistance.
  p_map.dart          MapMove: P_CheckPosition, P_TryMove, blockmap iterators, P_SlideMove,
                      P_Set/UnsetThingPosition, R_PointInSubsector (pointInSector).
  p_mobj.dart         MobjSim: P_SetMobjState, P_SpawnMobj/RemoveMobj, P_XYMovement,
                      P_ZMovement, P_MobjThinker. ONFLOORZ/ONCEILINGZ sentinels.
  p_user.dart         PlayerSim: P_Thrust, P_CalcHeight, P_MovePlayer, P_PlayerThink.
  p_doors.dart        DoorManager: T_VerticalDoor, T_PlatRaise, T_MoveFloor, EV_VerticalDoor,
                      EV_DoFloor, P_UseLines / P_UseSpecialLine (door subset).
  p_lights.dart       LightManager: T_FireFlicker, T_LightFlash, T_StrobeFlash, T_Glow,
                      P_SpawnSpecials (light portion).
  g_build.dart        TicCmdBuilder (G_BuildTiccmd) + KeyState input struct.
  sprite_source.dart  PlaySpriteSource / MobjSprite adapter for the renderer.
  playsim.dart        PlaySim: the single object integration drives each tic.
test/play/
  playsim_test.dart   Loads real E1M1, spawns, drives a forward ticcmd (collision), runs
                      thinkers, opens a door, exercises the ticcmd builder + info tables.
```

---

## 2. Integration entrypoints (the public surface)

Construct once after `World.fromWad(...)`:

```dart
final world = World.fromWad(wad);            // E1M1 by default
final sim = PlaySim(world, skill: Skill.medium);
sim.spawnLevel();                            // P_SetupLevel (playsim portion)
```

`spawnLevel()`:
- spawns/records every `world.level.things` MapThing (`P_SpawnMapThing`),
- spawns **player 1** at DoomEd-type-1 start (`P_SpawnPlayer`); throws
  `StateError` if absent,
- attaches sector light specials (`P_SpawnSpecials` light portion),
- primes `world.viewpoint` from the player.

**Build a ticcmd from key state** (does NOT depend on the controls module):

```dart
final keys = KeyState()..forward = true..run = true..turnLeft = true;
sim.buildTiccmd(keys);     // fills world.cmd (G_BuildTiccmd)
```

**Run one 35Hz tic** (call from the GameLoop `onTic`):

```dart
sim.tic();                 // consumes world.cmd
// or sim.tic(someTicCmd); // consume an explicit cmd (demos/tests/netcmd)
```

`tic()` mirrors `G_Ticker → P_Ticker`: copies the cmd into the player, runs
`P_PlayerThink`, runs **all** thinkers (mobjs + doors/plats/floors + lights),
increments `levelTime`, then writes `world.viewpoint` (viewx/viewy/viewz/
viewangle) so the renderer sees movement. **PlaySim is the sole writer of
`world.viewpoint` and the dynamic Level fields**, per CONTRACTS_WORLD.md.

**Renderer sprite feed:** `sim.spriteSource.sprites` yields one `MobjSprite`
per live mobj (x/y/z/angle/sprite/frame/fullBright/baseFrame/flags/sector).

### KeyState input contract (what the controls layer must provide)

`KeyState` is a plain bag of booleans + two ints the integration fills each tic
from the foundation `EventQueue` / `DoomKey` state:

| field            | meaning                                              |
|------------------|------------------------------------------------------|
| `forward/backward` | walk thrust                                        |
| `turnLeft/turnRight` | yaw (or strafe if `strafeModifier`)              |
| `strafeLeft/strafeRight` | strafe thrust                                |
| `run`            | speed (run) modifier                                 |
| `strafeModifier` | turn keys become strafe                              |
| `use` / `attack` | BT_USE / BT_ATTACK                                   |
| `analogTurn`     | mouse/touch-look turn delta (vanilla `mousex` units; builder applies `angleturn -= mousex*0x8`) |
| `analogForward`  | analog stick forward/back, 16.16 fixed in [-FRACUNIT, FRACUNIT] (+ = forward); `FixedMul(forwardmove[tier])`, summed then clamped to MAXPLMOVE |
| `analogSide`     | analog stick strafe, 16.16 fixed in [-FRACUNIT, FRACUNIT] (+ = strafe right) |
| `analogRun`      | analog stick at full deflection → run tier for the analog contribution |
| `weapon`         | requested slot 1..8, 0 = no change                   |

> **Note:** `analogTurn`'s scaling changed from "raw angleturn units" to the
> vanilla `mousex`-equivalent (the builder now does `angleturn -= analogTurn*0x8`,
> matching g_game.c's mouse-look path). The touch drag-to-look feeds a scaled
> `mousex` via `AnalogInput.takeMouseX()`. Analog fields default to zero, so a
> keyboard-only `KeyState` produces byte-identical ticcmds to before.

These map 1:1 to vanilla key bindings. The builder keeps the only cross-tic
state vanilla does (`turnHeld` for turn acceleration).

---

## 3. Type summary (mobj / player)

- **Mobj** (`mobj_t`): `x,y,z` (fixed_t), `angle` (angle_t), `momX/Y/Z`,
  `radius,height,floorZ,ceilingZ`, `sprite/frame/stateIndex/tics`, `type`,
  `flags`, `health`, AI fields (`moveDir,moveCount,reactionTime,threshold,
  lastLook,target,tracer`), `spawnPoint`, intrusive sector links
  (`sNext/sPrev/subsectorSector`) and blockmap links (`bNext/bPrev/blockIndex`),
  and a `player` back-reference (`Object?`, cast to `Player`). It is a
  `Thinker`; `tick()` delegates to the `thinkFn` (P_MobjThinker) the sim
  assigns at spawn.
- **Player** (`player_t`): `mo`, `playerState`, `cmd`, `viewHeight`,
  `deltaViewHeight`, `bob`, `viewZ`, `health`, armor, counters, tint counters,
  `psprites[2]` (`Pspdef` weapon + flash), button latches.
- **Thinker / ThinkerList**: circular doubly-linked list with a sentinel;
  `add` (P_AddThinker), `remove` (mark removed; unlinked safely during the
  run pass), `runThinkers` (P_RunThinkers). `Object?` cross-refs from the world
  layer (`thingList`, `specialData`) hold `Mobj` / plane-thinker instances.

---

## 4. What is stubbed / deferred (explicitly LATER waves)

- **Enemy AI A_* functions** (A_Look, A_Chase, A_FaceTarget, all attacks):
  recorded by name in `states[]`; resolve to **log-once no-op stubs** via
  `ActionRegistry`. Monster idle "spawn" states are faithful; full walk/attack/
  death chains are not transcribed (filled with an inert placeholder state).
- **Weapons / firing** (A_WeaponReady, A_FirePistol, A_Refire, P_FireWeapon,
  bobbing of the weapon psprite): psprite *state* is set up at spawn but firing
  behaviour is stubbed. `player.attackDown` latch is tracked for later wiring.
- **Pickups / items**: `MapMove.onTouchSpecial` hook fires on contact with an
  `MF_SPECIAL` thing, but `P_TouchSpecialThing` (giving ammo/health/keys) is
  not implemented; pickups remain in the world.
- **Damage / death / pain**: no `P_DamageMobj`, no health loss, no respawn;
  damage/bonus tint counters decay but are not raised.
- **Switches / full line-special catalogue**: `P_UseSpecialLine` is now the
  FULL vanilla p_switch.c manual-use switch (ported faithfully). It handles all
  manual-door specials (1,26,27,28,31,32,33,34,117,118 → EV_VerticalDoor, incl.
  key-card lock checks), tagged/remote doors (29,42,50,61,63,103,111-116,
  99/133-137 → EV_DoDoor / EV_DoLockedDoor), the level-exit switches (11/51 via
  an injected exit hook), and the switch-texture swap + button timer
  (`p_switch.dart`: P_ChangeSwitchTexture / P_StartButton / alphSwitchList /
  the BUTTONTIME countdown run from the tic). `P_UseLines` + `PTR_UseTraverse`
  are the faithful raycast over the shared `P_PathTraverse` (PT_ADDLINES), not a
  hand-rolled blockmap scan — they stop at the first usable special or the first
  blocking line. The floor/plat/ceiling/stairs SWITCH specials
  (7,9,14,15,18,20,21,23,41,45,49,55,60,62,64-71,101,102,122,123,127,131,132,
  138-140) are recognized by case but their EV_ bodies are NOT ported
  (EV_DoFloor/EV_DoPlat/EV_DoCeiling/EV_BuildStairs/EV_DoDonut/EV_LightTurnOn);
  they return false so the switch texture does not swap (vanilla only swaps on a
  true return). None of those are USE specials on E1M1 (whose only USE specials
  are 1 and 11). The pre-existing simplified `evDoFloor` mover remains for
  future wiring.
- **Sound propagation, intercepts/aiming (P_AimLineAttack), teleporters**:
  not implemented. `crossedSpecials` records crossed special lines after a
  successful move for a later wave to trigger (walkover specials).
- **Full info.c tables**: the slice ports the player + weapon (fist/pistol) +
  blood/puff/teleport-fog state chains faithfully (correct vanilla indices),
  plus an idle "spawn" state and a complete `mobjinfo` row for **every
  placeable DoomEd number** so `P_SpawnMapThing` resolves all map things. The
  ~960-entry full enemy/weapon state table is intentionally bounded for this
  slice; the framework (State/MobjInfo/ActionRegistry/P_SetMobjState) is
  complete so the remaining rows drop in without code changes.

---

## 5. Deviations from vanilla

- Vanilla file-scope globals (`tmthing`, `tmbbox`, `opentop`, `blocklinks`,
  `thinkercap`) become instance fields on `MapMove` / `ThinkerList` / a shared
  `opening` scratch object — same semantics, no statics.
- `P_HitSlideLine`'s general (non-axis-aligned) case projects momentum onto the
  line direction with a double dot-product instead of vanilla's angle-table
  reflection. Axis-aligned walls (the common case) use the exact vanilla fast
  path; the result for player sliding is equivalent in behaviour.
- `P_SetMobjState` recursion guard: vanilla loops on zero-tic states; we do the
  same with a `do/while (tics == 0)`.
- Thinker removal: vanilla marks `function = -1` and frees at end-of-pass; we
  use a `removed` flag unlinked during `runThinkers` (and skipped by iterators).
- `MapThing` angle → BAM uses `ANG45 * (deg/45)` (snaps to 45°), matching
  vanilla `P_SpawnMapThing`.

---

## 6. SpriteSource adapter (renderer integration)

No `lib/.../CONTRACTS_RENDER.md` / abstract `SpriteSource` existed in the tree
when this layer was finished (the renderer agent runs concurrently). To avoid
blocking, `sprite_source.dart` provides a self-contained
`PlaySpriteSource`/`MobjSprite` view whose fields already match the documented
renderer needs: `x, y, z` (fixed_t), `angle` (angle_t), `sprite` (SpriteNum),
`frame` (with FF_FULLBRIGHT) + `baseFrame`/`fullBright`, `flags`, `sector`.

**Integration wiring when the renderer publishes its contract:**
- If the renderer defines `abstract class SpriteSource` with these getters,
  make `PlaySpriteSource implement SpriteSource` (field set already matches) or
  wrap it in a thin adapter — no playsim changes required.
- The renderer reads `sim.spriteSource.sprites` once per frame after the tic.

---

## 7. Dependencies / requests to other layers

- No new pubspec dependencies are required.
- No changes were needed to `lib/INTERFACES.md`, `lib/CONTRACTS_WORLD.md`,
  `lib/game/world/*`, `lib/main.dart`, `lib/game/doom_game.dart`, or
  `pubspec.yaml`.
- **Integration note:** `doom_game.dart` should construct `PlaySim(world)`,
  call `spawnLevel()` once, then per GameLoop `onTic` call `sim.buildTiccmd(...)`
  (from live key state) and `sim.tic()`; the renderer's `onRender` reads
  `world.viewpoint` and `sim.spriteSource`.

---

## 8. Verification status

- `flutter analyze lib/game/play test/play` → **clean (no issues)**.
- `flutter test test/world test/play` → **all pass** (31 tests). The play
  suite loads real `assets/doom1.wad` E1M1 and asserts:
  - player 1 spawns at (1056, -3616), angle ANG90, z == sector floor, health 100;
  - map things spawn into the thinker list and the sprite source exposes them;
  - a forward ticcmd advances the player (>64 units) then is blocked by a wall
    (collision holds it — no tunnelling);
  - the thinker list runs 70 tics without error, all mobjs keep valid sectors;
  - `EV_VerticalDoor` on E1M1 door line 151 raises its sector ceiling over 35 tics;
  - `P_UseLines` runs cleanly; the ticcmd builder + info tables behave.
