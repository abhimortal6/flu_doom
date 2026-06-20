# flu_doom — ROADMAP / next-session handoff

A handoff for the next integration session. Read `CLAUDE.md` (standing rules)
and the relevant `lib/CONTRACTS_*.md` before spawning anything. **The lead never
writes implementation code — delegate.**

---

## Current state

flu_doom is a pure-Dart (no FFI) pure Dart port of vanilla Doom. The base
game is up and playable on the shareware episode.

**Done** (see `README.md` for the full table and the phased `git log`,
Phase 1 → Phase 4M):

- Title → main menu → New Game (episode/skill) → E1M1 fresh.
- 1:1 software renderer (BSP / segs / planes / sky / sprites / masked passes).
- Player movement, thrust, view bob, collision (no tunnelling).
- Full combat: enemy AI + line-of-sight, weapons/psprites, hitscan + missiles,
  pickups, damage.
- Doors / switches / use-line specials (`P_UseLines` 1:1; manual-use +
  tagged/remote doors).
- Damaging floor sectors + secret-sector counting.
- Level flow E1M1 → intermission → E1M2 with inventory carry-over.
- Player death → reborn + damage/bonus palette tint.
- SFX (DMX → s_sound → flutter_soloud) and FM music (MUS → MIDI → GENMIDI →
  Nuked-OPL3 → PCM).
- Pause (music + sim) on menu / pause.
- Touch overlay + rebindable keyboard + persisted settings; portrait/landscape.

**Contracts** (frozen interfaces): `lib/INTERFACES.md`,
`lib/CONTRACTS_WORLD.md`, `lib/CONTRACTS_RENDER.md`, `lib/CONTRACTS_PLAY.md`,
`lib/CONTRACTS_COMBAT.md`, `lib/CONTRACTS_STATE.md`, `lib/CONTRACTS_INPUT.md`.

---

## Remaining work, in priority order

For each item: the vanilla C source(s) to port 1:1, and the likely
files/owners touched. Freeze a `CONTRACTS_*.md` before fanning out if an
interface is bidirectional; integration wiring is the integration agent's job.

### 1. Screen-melt WIPE — `f_wipe.c`
The `wipe_ScreenWipe` / `wipe_doMelt` vertical-strip melt between the old and new
framebuffer on `gamestate` transitions.
- **C source:** `f_wipe.c` (`wipe_StartScreen`, `wipe_EndScreen`,
  `wipe_ScreenWipe`, `wipe_doMelt`).
- **Likely files:** new `lib/engine/video/wipe.dart` (owner: a render agent);
  hook into the present path in `lib/game/doom_game.dart` (integration agent).
- A ready-to-paste subagent prompt is in **"DIRECT COMMAND FOR THE NEXT AGENT"**
  below.

### 2. Attract DEMO LOOP — `D_AdvanceDemo` + demo playback
Title → demo1 → credits → demo2 cycle, driving the playsim from recorded demo
ticcmds.
- **C source:** `d_main.c` (`D_AdvanceDemo`, `D_DoAdvanceDemo`, `D_PageTicker`),
  `g_game.c` (`G_DeferedPlayDemo` / `G_DoPlayDemo` / `G_ReadDemoTiccmd` /
  `demoplayback`).
- **Likely files:** `lib/game/state/game_state.dart` (demoscreen advance),
  `lib/game/play/playsim.dart` (feed demo ticcmds instead of live input),
  a new demo-reader (e.g. `lib/game/play/g_demo.dart`); integration in
  `doom_game.dart`. NOTE: the title is currently a static TITLEPIC that waits
  for a keypress (see the comment block in `doom_game.dart`).

### 3. SAVE / LOAD — `p_saveg.c`
Serialize/deserialize the playsim (mobjs, thinkers, sectors, players, specials)
and wire the already-drawn Load/Save menu items.
- **C source:** `p_saveg.c` (`P_ArchiveThinkers` / `P_UnArchiveThinkers` /
  `P_Archive*`), `g_game.c` (`G_DoSaveGame` / `G_DoLoadGame`), `m_menu.c`
  (`M_LoadGame` / `M_SaveGame` actions).
- **Likely files:** new `lib/game/play/p_saveg.dart` (playsim agent),
  `lib/ui/menu/menu.dart` (the `M_LOADG` / `M_SAVEG` items are drawn but inert —
  see `lib/ui/menu/menu.dart`), `lib/game/state/game_state.dart` +
  `doom_game.dart` (integration). Persist via files (not shared_preferences).

### 4. REST OF EPISODE 1 line specials
Two parts:
- **Walk-over triggers** — `P_CrossSpecialLine` (currently no walk-over specials
  fire). **C source:** `p_spec.c` (`P_CrossSpecialLine`); called from
  `P_TryMove` in `p_map.c`.
- **Unported switch `EV_` bodies** — the manual-use/switch path
  (`P_UseSpecialLine`, already 1:1 for doors in `lib/game/play/p_doors.dart` /
  `p_switch.dart`) currently routes the remaining sector movers to simplified
  stand-ins. Port the real bodies: `EV_DoFloor`, `EV_DoPlat`, `EV_DoCeiling`,
  `EV_BuildStairs`, `EV_DoDonut`, `EV_LightTurnOn`.
  **C source:** `p_floor.c` (`EV_DoFloor` / `EV_BuildStairs` / `EV_DoDonut`),
  `p_plats.c` (`EV_DoPlat`), `p_ceilng.c` (`EV_DoCeiling`), `p_lights.c`
  (`EV_LightTurnOn`).
- **Likely files:** `lib/game/play/p_spec.dart` (cross-line dispatch),
  new `p_floor.dart` / `p_plats.dart` / `p_ceilng.dart`, additions to
  `p_lights.dart`; `p_switch.dart` / `p_doors.dart` route into them; the playsim
  thinker loop runs the new movers. Freeze a small contract for the new
  mover/thinker types before fanning these out in parallel.

---

## DIRECT COMMAND FOR THE NEXT AGENT — screen-melt WIPE

> Paste the block below into a single subagent spawn (one implementation agent).
> It follows all `CLAUDE.md` conventions. The lead does NOT implement it — the
> lead spawns this agent, then verifies (read-only `flutter analyze` +
> `flutter test` + screenshots on macOS release) before committing.

```
TASK: Implement vanilla Doom's screen-melt WIPE (f_wipe.c), pure-Dart, no FFI,
as a faithful Dart port. Do NOT paraphrase or "clean up" the C.

REFERENCE (gitignored, read it — do not work from memory):
  reference/chocolate-doom/src/f_wipe.c  (and f_wipe.h)
Port: wipe_StartScreen, wipe_EndScreen, wipe_initMelt,
wipe_doMelt (the per-column y-offset melt with the randomized starting
y[] and the speed ramp), and the wipe_ScreenWipe dispatcher. Preserve the
exact integer/fixed arithmetic and the M_Random-equivalent column seeding.
Use the project's existing p_random / M_Random source for the seeding RNG
(do not invent a new RNG); match vanilla's wipe column init exactly.

FILES YOU OWN (strictly disjoint — touch ONLY these):
  - lib/engine/video/wipe.dart          (NEW — the wipe module)
  - test/render/wipe_test.dart          (NEW — see TEST below)
  - lib/CONTRACTS_WIPE.md               (NEW — write your own contract)
Do NOT edit doom_game.dart, main.dart, pubspec.yaml, or any other agent's
files. If you need a present-path hook, DOCUMENT the required integration in
CONTRACTS_WIPE.md for the integration agent to wire later (the lead will run a
separate integration step):
  - Hook point: lib/game/doom_game.dart present path (where fb.toImage(palette)
    is handed to VideoView). On a gamestate transition the integration agent
    captures the START framebuffer (old screen) and END framebuffer (new
    screen) and drives wipe.dart frame-by-frame (35Hz) until the melt completes,
    presenting the intermediate buffer each frame instead of the live one.

CONTRACT (CONTRACTS_WIPE.md) must specify, at minimum:
  - The public API: e.g. Wipe.start(Framebuffer from, Framebuffer to),
    bool Wipe.tick(int ticDuration) -> returns true when the melt is done,
    and the buffer the present path should display while a wipe is active.
  - That wipe.dart only READS two framebuffers and WRITES an output buffer; it
    mutates no game state.
  - The exact integration hook above (for the integration agent).

WORK ON: 320x200 indexed framebuffers (lib/engine/video/framebuffer.dart),
matching vanilla's column-wise melt over the 320-wide screen.

TEST (test/render/wipe_test.dart):
  - Construct two distinct framebuffers (e.g. all-index-A vs all-index-B).
  - Start a wipe; assert tick() returns false until the melt finishes and true
    at completion; assert the output is pure "from" before the first tick and
    pure "to" after completion; assert at least one mid-wipe frame is a genuine
    mix of both (some columns still showing "from", some showing "to") — i.e.
    verify the melt IN MOTION, not one static frame.

VERIFY before you report complete:
  - flutter analyze lib/engine/video/wipe.dart test/render/wipe_test.dart -> clean
  - flutter test test/render/wipe_test.dart -> all pass
  - Confirm it builds on macOS release.

REPORT: the files you wrote, the public API you froze in CONTRACTS_WIPE.md, the
exact integration hook the integration agent must wire in doom_game.dart, and
any deviation from f_wipe.c (there should be none — flag honestly if there is).
DO NOT commit; the lead commits after read-only verification.
```
