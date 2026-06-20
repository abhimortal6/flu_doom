# flu_doom

**flu_doom** is a from-scratch, **pure-Dart (NO FFI)** pure Dart port of vanilla
Doom — the software renderer, play simulation, sound (DMX SFX) and FM music
(Nuked-OPL3) — ported faithfully from [Chocolate Doom](https://github.com/chocolate-doom/chocolate-doom)
(GPLv2) and Nuked-OPL3 to Flutter. It boots to the title screen, opens the main
menu, starts a New Game and plays through the bundled IWAD's first episode
(E1M1 onward):
full software-rendered 3D, player movement and collision, enemy AI, weapons,
hitscan/missiles, pickups, doors/switches, intermissions, sound and music — all
in Dart, with no native game code.

> The engine relies on 32-bit signed integer overflow for fixed-point math. It
> targets **Dart native (AOT) integer semantics** (macOS / iOS / Android). The
> **web target is out of scope** (JS doubles break the fixed-point arithmetic).

---

## Build & run

```sh
flutter pub get

# Dev target (this project develops and verifies on macOS release):
flutter run -d macos --release

# Ship targets:
flutter run -d ios --release
flutter run -d android --release
```

**IMPORTANT — native build dependency:** the `flutter_soloud` audio plugin builds
a native backend with CMake. If you don't have it:

```sh
brew install cmake
```

**macOS release-relaunch quirk:** a macOS `--release` relaunch can run a stale
AOT snapshot, so a behavior-level change may not appear. When a change *must* be
visible, do a clean rebuild first:

```sh
flutter clean && flutter run -d macos --release
```

Tests and lint:

```sh
flutter test       # unit + golden-ish render/play/state/sound suites
flutter analyze    # lint (flutter_lints)
```

---

## Feature status

| Done | Deferred / TODO |
|------|------------------|
| Title screen → main menu → New Game (episode/skill) → E1M1 | Screen-melt **wipe** (`f_wipe.c`) on state transitions |
| 1:1 software renderer: BSP, walls, flats/planes, sky, sprites, masked passes | Attract **demo loop** (`D_AdvanceDemo` + demo playback ticcmds) |
| Player move / thrust / view bob / **collision** (no tunnelling) | **Save / load** (`p_saveg.c`; Load/Save menu items are drawn but inert) |
| Full **combat**: enemy AI + line-of-sight, weapons/psprites, hitscan + missiles, pickups, damage | Walk-over **line specials** (`P_CrossSpecialLine`) |
| **Doors / switches / use-specials** (`P_UseLines` 1:1, manual-use + tagged/remote doors) | Unported switch `EV_` bodies: `EV_DoFloor`/`EV_DoPlat`/`EV_DoCeiling`/`EV_BuildStairs`/`EV_DoDonut`/`EV_LightTurnOn` |
| **Damaging floor sectors** + secret-sector counting | **Finale end-text** (GS_FINALE state exists; the crawl/end text is not rendered) |
| **Level flow**: E1M1 → intermission → E1M2 with inventory carry-over | **Boss / keen** special triggers |
| Player **death → reborn** + damage/bonus **palette tint** | **Web target** (fixed-point JS int issue) |
| **SFX** (DMX decode → s_sound port → flutter_soloud) | True real-time **music streaming** / authored loop points (song is rendered offline to one looped PCM buffer) |
| **FM music**: WAD MUS → MIDI → GENMIDI → Nuked-OPL3 → PCM | |
| **Pause** (music + sim) on menu / pause | |
| **Input**: touch overlay + rebindable hardware keyboard + settings screen (persisted) | |
| Portrait / landscape layouts | |

---

## Architecture / module map

The codebase is layered. Lower layers never depend on higher ones; parallel
agents code against the frozen `CONTRACTS_*.md` interfaces, not each other's
implementations.

```
lib/
  main.dart                       App entry: MaterialApp -> DoomGame.
  game/doom_game.dart             Integration: wires every subsystem into the loop.

  engine/                         Pure-Dart engine (no game-specific knowledge)
    math/   fixed, angle, tables  16.16 fixed-point + BAM angles + trig LUTs.
    wad/    wad                    WAD/lump reader.
    video/  framebuffer, palette, patch, video_view   320x200 indexed FB -> ARGB.
    render/ renderer, bsp, segs, planes, things, draw, render_state   software renderer.
    input/  doomkeys, event, keyboard   DoomEvent / EventQueue / key mapping.
    sound/  dmx, s_sound hook, audio_engine, opl3, opl_player, mus2mid, midifile, genmidi, music
    system/ gameloop              35Hz tic + render hooks.
    data/   textures              PNAMES/TEXTURE1/flats/sprites.

  game/
    world/  defs, level, world, ticcmd   Shared geometry + World/Viewpoint + TicCmd.
    play/   thinker, mobj, player, p_mobj, p_user, p_map, p_maputl, p_enemy,
            p_sight, p_pspr, p_shoot, p_inter, p_doors, p_switch, p_lights,
            p_spec, spawn, info(_tables), state_num, sounds, p_random, playsim
    state/  game_state, intermission, level_flow, interfaces   gamestate machine.
    integration/  *_adapter, key_state_bridge   injected-interface adapters.

  ui/
    hud/      status_bar, hud, fonts, patch_draw, graphics_cache
    menu/     menu              m_menu (main/episode/skill/options).
    automap/  automap           am_map.
    controls/ touch_controls_overlay, overlay_widgets, ...   on-screen controls.
    settings/ controls_settings_screen   key-binding / overlay settings route.

  input_actions/                  GameAction model, key bindings, persistence.
```

### Contract documents (frozen interfaces)

| File | Governs |
|------|---------|
| `lib/INTERFACES.md` | Phase-1 foundation: fixed/angle math, WAD, palette/framebuffer/patch, events, game loop |
| `lib/CONTRACTS_WORLD.md` | Shared world data layer: geometry structs, `Level.load`, `World`/`Viewpoint`, `TicCmd`; renderer-reads / playsim-mutates boundary |
| `lib/CONTRACTS_RENDER.md` | Software renderer: BSP, segs, planes, things, draw, `SpriteSource` |
| `lib/CONTRACTS_PLAY.md` | Play simulation: mobj/thinker/player, physics, collision, doors/plats/floors/lights, ticcmd build |
| `lib/CONTRACTS_COMBAT.md` | Combat wave: damage, hitscan/missiles, enemy AI, weapon psprites, pickups; the `info.c`/`d_items.c` data tables |
| `lib/CONTRACTS_STATE.md` | Game-state machine + UI: `g_game`, status bar, HUD, automap, menu, intermission (injected `WorldView`/`PlayerStatus`) |
| `lib/CONTRACTS_INPUT.md` | Input / controls UX: touch overlay, rebindable keyboard, settings persistence |

---

## Licensing / credits

- **Code** is a port of **Chocolate Doom** (GPLv2) and **Nuked-OPL3**.
  Accordingly, **this project is licensed under the GNU GPL v2**.
- **Game data** is **Freedoom Phase 1** (`assets/freedoom1.wad`,
  [freedoom.github.io](https://freedoom.github.io/)) — a **BSD-licensed**,
  vanilla-compatible drop-in IWAD (ExMy maps, standard texture/sprite/sound/music
  lump names). It is the only IWAD bundled with the app, so **the app is freely
  redistributable**. (Freedoom Phase 1 actually has 4 episodes; the in-game menu
  currently exposes 3 — episode 4 is not yet selectable. Note its E1M1 is a
  different, larger map than shareware Doom's.)
- The shareware **`doom1.wad`** (© id Software) is **retained in `assets/` only
  as a test fixture**: the test suite asserts shareware-Doom-specific map data
  (E1M1 geometry, the `STARTAN3`/`FLOOR4_8`/`PLAYA1` lumps, player start, etc.),
  so it loads `doom1.wad` directly from the filesystem via `File(...)`. It is
  **not** declared as a Flutter asset and is **not** bundled in the app.
- **Dependencies**: `flutter_soloud` (low-latency audio backend) and
  `shared_preferences` (settings persistence) are used under their own licenses.
- The C reference sources used for the port live in `reference/`,
  which is **gitignored** and not redistributed.
