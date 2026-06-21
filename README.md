# flu_doom

**flu_doom** is a from-scratch, **pure-Dart (NO FFI)** port of the
vanilla Doom engine, running as a **Flutter app**. The software renderer, play
simulation (BSP, mobjs/thinkers, physics, collision, combat), WAD loading,
16.16 fixed-point and BAM-angle math, the DMX sound dispatch, and the full FM
music path (WAD MUS → MIDI → GENMIDI → Nuked-OPL3 → PCM) are all faithfully
ported **into Dart** from [Chocolate Doom](https://github.com/chocolate-doom/chocolate-doom)
(GPLv2) and [Nuked-OPL3](https://github.com/nukeykt/Nuked-OPL3) (LGPL). There is
no native Doom binary and no FFI binding — the engine *is* the Dart code.

Flutter provides the shell around that pure-Dart engine: the engine's 320×200
indexed framebuffer is converted to a `dart:ui` image each frame, the game loop
runs off a `Ticker`/vsync, and input, menus and on-screen controls are Flutter
widgets. The only native dependency is **`flutter_soloud`**, used purely as the
low-latency audio backend that plays PCM/WAV buffers flu_doom synthesizes itself
in Dart (it does not generate any game audio).

> The engine relies on 32-bit signed integer overflow for fixed-point math. It
> targets **Dart native (AOT) integer semantics** (macOS / iOS / Android). The
> **web target is out of scope** (JS doubles break the fixed-point arithmetic).

---

## Development

This project was **designed and implemented entirely by Claude Opus 4.8 using
[Claude Code](https://claude.com/claude-code)** (Anthropic's agentic CLI). Every
line of the engine, audio, rendering, mobile controls, and tooling was written
by the model; the human author directed product decisions and testing.

It was built across a single Claude Code development session spanning roughly
**2 days of wall-clock time (2026-06-19 to 2026-06-21, ~50 hours)**. That figure
is wall-clock span, not continuous compute time.

---

## Bring your own WAD

**flu_doom ships NO game data.** It contains no maps, textures, sounds, or music —
only the engine. On first run the app opens an **in-app import screen** and asks
you to supply a Doom-format **IWAD** from your device; the file is copied into
the app's documents directory and loaded on every subsequent launch.

You can use any vanilla-compatible IWAD:

- **Freedoom** — a free, BSD-licensed, vanilla-compatible IWAD. Download
  `freedoom1.wad` (Phase 1) or `freedoom2.wad` (Phase 2) from
  <https://freedoom.github.io/> and import it. This is the recommended way to
  run flu_doom with no proprietary data.
- **Retail / shareware Doom** — your own legally-obtained `doom.wad`,
  `doom1.wad` (shareware), `doom2.wad`, etc. also load.

flu_doom does not redistribute Freedoom or any commercial WAD; you provide the
game data yourself.

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

**Native build dependency — CMake:** the `flutter_soloud` audio plugin builds a
native backend with CMake. If you don't have it:

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
flutter test       # render / play / state / sound suites
flutter analyze    # lint (flutter_lints)
```

---

## Feature status

| Done | Deferred / TODO |
|------|------------------|
| Title screen → main menu → New Game (episode/skill) → first map | Attract **demo loop** (`D_AdvanceDemo` + demo playback ticcmds) |
| Faithful software renderer: BSP, walls, flats/planes, sky, sprites, masked passes | **Save / load** (`p_saveg.c`; Load/Save menu items draw but are inert) |
| **Widescreen** rendering + **frame interpolation** (smooth motion above 35 Hz) | Walk-over **line specials** (`P_CrossSpecialLine`) |
| Player move / thrust / view bob / **collision** (no tunnelling) | Unported switch `EV_` bodies (`EV_DoFloor`/`EV_DoPlat`/`EV_DoCeiling`/`EV_BuildStairs`/`EV_DoDonut`/`EV_LightTurnOn`) |
| Full **combat**: enemy AI + line-of-sight, weapons/psprites, hitscan + missiles, pickups, damage | **Finale end-text** crawl (GS_FINALE state exists; text not rendered) |
| **Doors / switches / use-specials** (`P_UseLines` faithful port, manual + tagged/remote) | **Boss / keen** special triggers |
| **Damaging floor sectors** + secret-sector counting | Screen-melt **wipe** on state transitions |
| **Level flow**: first map → intermission → next with inventory carry-over | True real-time **music streaming** / authored loop points (song is rendered offline to one looped PCM buffer) |
| Player **death → reborn** + damage/bonus **palette tint** | **Web target** (fixed-point JS int issue) |
| **SFX** (DMX decode → s_sound port → flutter_soloud) | |
| **FM music**: WAD MUS → MIDI → GENMIDI → Nuked-OPL3 → PCM | |
| **Pause** (music + sim) on menu / pause | |
| **Mobile touch controls** + on-screen control customization | |
| **Graphics options** screen; portrait / landscape layouts | |
| **Input**: touch overlay + rebindable hardware keyboard, persisted settings | |
| **Bring-your-own-WAD** import flow (no bundled game data) | |

---

## Architecture / module map

The codebase is layered. Lower layers never depend on higher ones; modules code
against the frozen `CONTRACTS_*.md` interface documents, not each other's
implementations.

```
lib/
  main.dart                       App entry: MaterialApp -> DoomGame.
  game/doom_game.dart             Integration: wires every subsystem into the loop.
  game/wad_store.dart             Imported-IWAD location/copy/load (bring-your-own-WAD).

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
    hud/        status_bar, hud, fonts, patch_draw, graphics_cache
    menu/       menu              m_menu (main/episode/skill/options).
    automap/    automap           am_map.
    controls/   touch_controls_overlay, overlay_widgets, ...   on-screen controls.
    settings/   controls_settings_screen   key-binding / overlay settings route.
    wad_import/ first-run WAD-import UI (bring-your-own-WAD).

  input_actions/                  GameAction model, key bindings, persistence.
```

### Contract documents (frozen interfaces)

| File | Governs |
|------|---------|
| `lib/INTERFACES.md` | Phase-1 foundation: fixed/angle math, WAD, palette/framebuffer/patch, events, game loop |
| `lib/CONTRACTS_WORLD.md` | Shared world data layer: geometry structs, `Level.load`, `World`/`Viewpoint`, `TicCmd` |
| `lib/CONTRACTS_RENDER.md` | Software renderer: BSP, segs, planes, things, draw, `SpriteSource` |
| `lib/CONTRACTS_PLAY.md` | Play simulation: mobj/thinker/player, physics, collision, doors/plats/floors/lights |
| `lib/CONTRACTS_COMBAT.md` | Combat: damage, hitscan/missiles, enemy AI, weapon psprites, pickups |
| `lib/CONTRACTS_STATE.md` | Game-state machine + UI: `g_game`, status bar, HUD, automap, menu, intermission |
| `lib/CONTRACTS_INPUT.md` | Input / controls UX: touch overlay, rebindable keyboard, settings persistence |
| `lib/CONTRACTS_INTERP.md` | Frame interpolation: smoothing motion above the 35 Hz tic |
| `lib/CONTRACTS_WIPE.md` | Screen-melt wipe module (`f_wipe.c`) interface |
| `CONTRACTS_WIDESCREEN.md` | Widescreen rendering geometry |

---

## License

flu_doom is licensed under the **GNU General Public License, version 2 (GPLv2)** —
see [`LICENSE`](LICENSE) for the full text. Because the engine is a derivative
port of Chocolate Doom (GPLv2), the project as a whole is GPLv2.

Third-party attributions — Chocolate Doom, Nuked-OPL3, Freedoom, `flutter_soloud`,
and the other Flutter/Dart packages — are listed in [`NOTICE`](NOTICE).

Contributions: see [`CONTRIBUTING.md`](CONTRIBUTING.md).

### Trademark disclaimer

**DOOM is a trademark of id Software LLC**, a ZeniMax Media / Microsoft company.
flu_doom is an **independent, unofficial reimplementation** and is **not
affiliated with, authorized by, or endorsed by** id Software, ZeniMax, or
Microsoft. The GPLv2 covers the source code only and grants no trademark
rights — **do not distribute this software under the "Doom" name.**
