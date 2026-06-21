# flu_doom — Roadmap

flu_doom is a pure-Dart (no FFI) port of vanilla Doom. The base
game is up and playable. This file tracks the remaining work as a public
feature roadmap. See [`README.md`](../README.md) for the full feature-status
table and the frozen `CONTRACTS_*.md` interface documents.

---

## Current state

Done (see the README for the complete table):

- Title → main menu → New Game (episode/skill) → first map.
- Faithful software renderer (BSP / segs / planes / sky / sprites / masked passes),
  plus widescreen rendering and frame interpolation.
- Player movement, thrust, view bob, collision (no tunnelling).
- Full combat: enemy AI + line-of-sight, weapons/psprites, hitscan + missiles,
  pickups, damage.
- Doors / switches / use-line specials (`P_UseLines` faithful port; manual-use +
  tagged/remote doors).
- Damaging floor sectors + secret-sector counting.
- Level flow: first map → intermission → next map with inventory carry-over.
- Player death → reborn + damage/bonus palette tint.
- SFX (DMX → s_sound → flutter_soloud) and FM music (MUS → MIDI → GENMIDI →
  Nuked-OPL3 → PCM).
- Pause (music + sim) on menu / pause.
- Touch overlay + rebindable keyboard + persisted settings; portrait/landscape.
- Bring-your-own-WAD import flow (no bundled game data).

---

## Remaining work

Each item names the vanilla C source it should be ported from.

### Screen-melt wipe
The vertical-strip screen melt between the old and new framebuffer on game-state
transitions.
- C source: `f_wipe.c` (`wipe_StartScreen`, `wipe_EndScreen`, `wipe_ScreenWipe`,
  `wipe_doMelt`), seeded by the project's existing `M_Random`.

### Attract demo loop
Title → demo1 → credits → demo2 cycle, driving the playsim from recorded demo
ticcmds. The title is currently a static TITLEPIC that waits for a keypress.
- C source: `d_main.c` (`D_AdvanceDemo`, `D_DoAdvanceDemo`, `D_PageTicker`),
  `g_game.c` (`G_DeferedPlayDemo` / `G_DoPlayDemo` / `G_ReadDemoTiccmd` /
  `demoplayback`).

### Save / load
Serialize/deserialize the playsim (mobjs, thinkers, sectors, players, specials)
and wire the already-drawn Load/Save menu items (currently inert). Persist via
files.
- C source: `p_saveg.c` (`P_ArchiveThinkers` / `P_UnArchiveThinkers` /
  `P_Archive*`), `g_game.c` (`G_DoSaveGame` / `G_DoLoadGame`), `m_menu.c`
  (`M_LoadGame` / `M_SaveGame`).

### Remaining line specials
Two parts:
- Walk-over triggers — `P_CrossSpecialLine` (no walk-over specials fire yet).
  C source: `p_spec.c` (`P_CrossSpecialLine`), called from `P_TryMove` in
  `p_map.c`.
- Switch / use sector-mover bodies — the manual-use path (already a faithful port for doors)
  currently routes the remaining sector movers to simplified stand-ins. Port the
  real bodies: `EV_DoFloor`, `EV_DoPlat`, `EV_DoCeiling`, `EV_BuildStairs`,
  `EV_DoDonut`, `EV_LightTurnOn`.
  C source: `p_floor.c`, `p_plats.c`, `p_ceilng.c`, `p_lights.c`.

### Finale end-text
The `GS_FINALE` end-text crawl (state exists; text is not yet rendered).
- C source: `f_finale.c`.

### Boss / keen special triggers
Map-end and special-action triggers tied to boss/keen death.
- C source: `p_enemy.c` (`A_BossDeath` / `A_KeenDie`), `p_spec.c`.

### More episodes / maps
The base game runs the shareware episode; extending to the full set of episodes
and maps follows the same level-flow path already in place.

### Music streaming
True real-time music streaming / authored loop points. The song is currently
rendered offline to one looped PCM buffer.

### Web target (caveat)
The web target is out of scope: fixed-point math relies on 32-bit signed integer
overflow, and JS doubles break that arithmetic. Native (AOT) targets only.
