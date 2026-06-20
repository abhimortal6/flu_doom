# flu_doom — Game-State + UI Contracts (Phase 2 / state subsystem)

This document is the **stable contract** for the GAME-STATE and UI subsystems
(`g_game`, `st_stuff`, `hu_stuff`, `am_map`, `m_menu`, `wi_stuff`). The
integration layer wires these to the real renderer and play-simulation through
the **injected interfaces** below. This layer builds strictly on the Phase-1
foundation (`lib/INTERFACES.md`: Framebuffer, Patch, Palette, EventQueue,
DoomEvent, GameLoop, WadFile) and the Phase-2 world layer
(`lib/CONTRACTS_WORLD.md`: World, Level, Viewpoint). It owns **no** play-sim or
renderer concrete types — everything it cannot own is injected.

Faithful port of Chocolate Doom `g_game.c`/`d_main.c` dispatch, `st_stuff.c`,
`hu_stuff.c`, `am_map.c`, `m_menu.c`, `wi_stuff.c`. Rendered into the 320x200
indexed `Framebuffer` using the foundation `Patch` decoder + WAD lumps (NOT
Flutter widgets).

---

## 0. File layout (this layer)

```
lib/
  CONTRACTS_STATE.md                 This file.
  game/state/
    interfaces.dart                  Injected interfaces (WorldView, PlayerStatus,
                                     IntermissionStats) + AmmoType/PowerType enums.
    dummy_player_status.dart         DummyPlayerStatus (mutable test/boot impl).
    game_state.dart                  GameState machine (gamestate enum, gameaction,
                                     G_Ticker/G_Responder, D_Display dispatch).
    intermission.dart                Intermission (wi_stuff) screen + flow.
  ui/hud/
    graphics_cache.dart              GraphicsCache: decode+cache Patches by lump.
    fonts.dart                       NumberFont (STTNUM/STYSNUM/STGNUM/WINUM),
                                     HudFont (STCFN).
    status_bar.dart                  StatusBar (st_stuff): STBAR + numbers + face.
    hud.dart                         Hud (hu_stuff): message line + fullscreen HUD.
  ui/menu/
    menu.dart                        MenuController (m_menu): main/episode/skill/options.
  ui/automap/
    automap.dart                     Automap (am_map): AM_Drawer + AM_Responder.
test/state/
    status_bar_test.dart, hud_test.dart, automap_test.dart,
    menu_test.dart, game_state_test.dart
```

---

## 1. Injected interfaces (the seam to renderer + playsim)

Defined in `lib/game/state/interfaces.dart`. The integration layer supplies
implementations; this layer never imports playsim/renderer concrete types.

### WorldView — the 3D-scene render hook
```dart
typedef WorldView = void Function(Framebuffer fb);
```
Called by `GameState.render` when `gamestate == GameStateType.level` and the
automap is **not** active. It must draw the 3D player view (R_RenderPlayerView)
into the 320x200 `fb`. The status bar / HUD are overlaid afterward by this
layer, so `WorldView` may write the whole buffer.

### PlayerStatus — read-only HUD values (st_stuff / hu_stuff source)
```dart
enum AmmoType { clip, shell, cell, misl }            // ammotype_t order
enum PowerType { invulnerability, strength, infrared }

abstract interface class PlayerStatus {
  int     get health;                  // player.health
  int     get armor;                   // player.armorpoints
  int     get armorType;               // 0 none / 1 green / 2 blue
  int     get readyWeapon;             // 0..8 weapon slot
  bool    ownsWeapon(int slot);        // weaponowned[slot]
  int     ammo(AmmoType type);         // player.ammo[type]
  int     maxAmmo(AmmoType type);      // player.maxammo[type]
  AmmoType? get readyWeaponAmmo;       // ammo the ready weapon uses (null=fist/saw)
  bool    ownsCard(int index);         // cards[0..2]=cards, [3..5]=skulls
  int     get fragCount;               // deathmatch frags (0 in SP)
  int     powerTics(PowerType power);  // player.powers[power]; 0=inactive
  int     get damageCount;             // player.damagecount (pain face)
  int     get bonusCount;              // player.bonuscount (palette hook)
  bool    get attackDown;              // firing (face)
  bool    get isDead;                  // health <= 0 (STFDEAD0)
}
```
A mutable `DummyPlayerStatus` implements this for tests and the boot/title
screen before the playsim is wired. Integration provides a real adapter over
`player_t`.

### IntermissionStats — end-of-level stats (wi_stuff source)
```dart
class IntermissionStats {
  IntermissionStats({episode, lastMap, nextMap, killCount, totalKills,
    itemCount, totalItems, secretCount, totalSecrets,
    levelTimeSeconds, parTimeSeconds});
  // all final ints; 0-based episode/map indices.
}
```
Supplied lazily via `GameStateConfig.statsProvider` (a
`IntermissionStats Function()`), called when a level completes. Integration
builds this from the playsim's `wbstartstruct_t`.

---

## 2. Game-state machine entrypoints (what the integration loop calls)

`GameState` is constructed once with a `GameStateConfig`:
```dart
GameStateConfig({
  required WadFile wad,                 // graphics lumps
  required World world,                 // geometry + viewpoint (read for automap)
  required PlayerStatus playerStatus,   // HUD source
  required WorldView worldView,         // 3D-scene render hook
  void Function(int episode,int skill)? onStartNewGame, // menu -> G_InitNew
  void Function()? onAdvanceLevel,      // intermission done -> next level load
  IntermissionStats Function()? statsProvider,
});
final gs = GameState(config);
```

The Phase-1 `GameLoop(onTic, onRender)` wires to:

- **`onTic` -> `gs.ticker(List<DoomEvent> events)`** — call once per 35Hz tic,
  AFTER the playsim has advanced this tic. Pass the events drained from the
  `EventQueue` this tic (`queue.drain()`). `ticker`:
  1. routes each event through `responder` (G_Responder),
  2. consumes the pending `GameAction` (newGame/completed/worldDone/victory),
  3. ticks the active state (status-bar face anim + HUD timers in GS_LEVEL;
     stat count-up in GS_INTERMISSION; menu cursor always),
  4. bumps `gs.gametic`.

- **`onRender` -> `gs.render(Framebuffer fb)`** — the D_Display equivalent.
  Dispatches on `gamestate`:
  - `level`: automap.draw OR `worldView(fb)`, then status bar + HUD overlay,
    then pause graphic;
  - `intermission`: `intermission.draw(fb)`;
  - `finale`: finale background (CREDIT placeholder);
  - `demoScreen`: TITLEPIC.
  The menu (`M_Drawer`) is drawn last, on top of every state.
  The caller then does `fb.toImage(palette)` for display (Phase-1 contract).

State enums:
```dart
enum GameStateType { level, intermission, finale, demoScreen }  // gamestate_t
enum GameAction { nothing, newGame, loadLevel, completed, worldDone, victory }
```

Lifecycle helpers the integration / playsim may call directly:
`gs.enterLevel()`, `gs.enterDemoScreen()`, `gs.completeLevel()`,
`gs.triggerVictory()`. Public fields: `gamestate`, `gametic`, `paused`, plus
the owned subsystems `statusBar`, `hud`, `automap`, `menu`, `intermission`.

The machine boots in `demoScreen`. Selecting New Game from the menu fires
`onStartNewGame(episode, skill)` then defers `ga_newgame`, which `ticker`
resolves into `enterLevel()`. When the playsim signals level completion it calls
`gs.completeLevel()`; `ticker` then enters `intermission` and pulls stats from
`statsProvider`. Advancing past the intermission fires `onAdvanceLevel()` and
returns to `level`.

---

## 3. Input routing (G_Responder priority)

`gs.responder(DoomEvent)` (called for each event by `ticker`) routes by:
1. **Menu active** -> `MenuController.responder` (M_Responder) wins everything.
2. **ESC keyDown** (menu inactive) -> opens the menu.
3. By state:
   - `level`: Pause key toggles `paused`; then `Automap.responder`
     (Tab toggle + +/-/arrows/f/g). If unconsumed, returns `false` so the
     input/playsim agent's `G_BuildTiccmd` can use the event.
   - `intermission`: `Intermission.responder` (key snaps count-up to final,
     next key advances).
   - `finale`: any key returns to the demo screen.
   - `demoScreen`: any key opens the menu.

Returns `true` when consumed. Unconsumed level events are the playsim's to turn
into a `TicCmd` (this layer does not build tic commands).

---

## 4. Subsystem notes & fidelity

- **Status bar** (`status_bar.dart`): draws STBAR at y=168 (bottom 32 rows),
  big red font (STTNUM/STTPRCNT/STTMINUS) for ammo/health/armor, small yellow
  (STYSNUM) for the ammo table + owned arsenal slots, grey (STGNUM) for unowned
  arsenal slots, STARMS frame, STKEYS icons, and the animated face. Layout
  constants are the vanilla st_stuff.c `ST_*X/Y` values. Frag count replaces the
  arsenal when `draw(..., deathmatch: true)`.
- **Face state machine**: `tick(PlayerStatus)` drives a simplified
  ST_updateFaceWidget — pain-level bucketing (5 levels), straight-face cycle,
  ouch/rampage on damage/attack, god face on invulnerability, STFDEAD0 on death.
  The exact turn-toward-damage-source and evil-grin-on-pickup cues are
  **simplified** (no damage-source direction; no pickup grin) — see Stubs.
- **HUD** (`hud.dart`): top-left message line (HU_MSGTIMEOUT = 4*TICRATE),
  STCFN font, optional fullscreen readout when the status bar is hidden.
- **Automap** (`automap.dart`): Bresenham line geometry from `Level.lines`,
  coloured one-sided/two-sided(floor vs ceiling diff)/secret/grid/player-arrow.
  Auto-fits the level to the viewport (above the status bar). Follows the player
  when the viewpoint is inside the map bounds; otherwise keeps the level framed
  (the playsim has not set a viewpoint yet at boot). Pan/zoom/grid/follow via
  AM_Responder. `linesDrawn` exposes the plotted-line count for tests.
- **Menu** (`menu.dart`): main (M_DOOM) -> episode (M_EPISOD) -> skill (M_SKILL)
  -> `onNewGame(episode, skill)`. Options menu present with vanilla item
  graphics; M_SKULL1/2 animated cursor. Arrow/Enter/Esc/Backspace navigation.
- **Intermission** (`intermission.dart`): WIMAP0 background, "finished" title,
  Kills/Items/Secrets percentages (WINUM font) counted up, Time/Par MM:SS, then
  waits for a key. **Partial**: the staggered per-stat sound-timed animation and
  the map-traversal "you are here" splat animation are reduced to a single
  count-up; net/deathmatch tables are not drawn (single-player only).

---

## 5. Stubbed / partial (and why)

- **Options menu actions** are inert (no-op `onSelect`): sound volume, detail,
  messages, screen size, mouse sensitivity, save/load are owned by other agents
  (`lib/ui/settings/`, `lib/ui/controls/`) or systems not yet built. Their item
  graphics are drawn for layout fidelity.
- **Finale** draws CREDIT as a placeholder background; the scrolling end-text
  and cast call are not implemented (low priority; episode-1 shareware uses a
  text screen).
- **Demo playback** (the actual `.lmp` demo loop on the title screen) is not
  implemented — `demoScreen` just shows TITLEPIC and routes any key to the menu.
- **Palette tinting** (damage/bonus/radsuit) is not applied here; `bonusCount`/
  `damageCount` are exposed via `PlayerStatus` so the integration layer can pick
  a `Palette` (Phase-1 exposes palette 0 only).
- **Face cues**: damage-direction turn faces and the pickup evil-grin are
  simplified to forward/ouch/rampage selection.
- All three episodes are listed AND selectable in the episode menu
  (`MenuController(shareware: false)`, the default): each fires
  `onNewGame(episode, skill)`. `G_InitNew` (`PlaySim.newGame`) decides what to
  load and falls back to E1M1 if the chosen episode's map lump is absent from
  the loaded WAD (doom1.wad ships episode 1 only), so a new game always starts.
  Passing `MenuController(shareware: true)` restores the vanilla `M_Episode`
  shareware branch instead: episodes > 1 pop the `SWSTRING` message box.

---

## 6. Dependencies needed from other layers / integration

- A `Palette` (Phase-1) at display time: integration calls `fb.toImage(palette)`
  after `gs.render(fb)`. Damage/bonus tint palette selection (if desired) is the
  integration layer's call using `PlayerStatus.damageCount/bonusCount`.
- The playsim must call `gs.completeLevel()` on exit and provide `statsProvider`
  / `onAdvanceLevel` / `onStartNewGame`.
- The renderer must implement `WorldView`.
- No new pubspec dependencies were added by this layer.

---

## 7. Verification status

- `flutter analyze lib/game/state lib/ui/hud lib/ui/menu lib/ui/automap test/state`
  -> **clean (No issues found)**.
- `flutter test test/state` -> **all pass**:
  - status bar: lumps load; ST_Drawer fills the bottom 32 rows and leaves the
    3D-view region untouched; dead face differs from alive.
  - hud: STCFN font loads; message posts/draws/times out.
  - automap: E1M1 draws > 100 lines / > 500 pixels; Tab toggles, pan/zoom
    consumed.
  - menu: M_DOOM + items + skull load; arrow navigation changes selection;
    New Game -> episode -> skill -> `onNewGame(0, 2)`; Esc/Backspace navigate.
  - game_state: boots to demoScreen; ESC opens menu; GS_LEVEL render calls
    WorldView + overlays status bar; completeLevel -> intermission -> advance
    fires `onAdvanceLevel`; Tab toggles automap which replaces the 3D view.

---

## 8. Files this layer did NOT touch

`lib/main.dart`, `lib/game/doom_game.dart`, `lib/INTERFACES.md`,
`lib/CONTRACTS_WORLD.md`, `lib/game/world/*`, `pubspec.yaml`,
`lib/ui/controls/`, `lib/ui/settings/`, `lib/game/play/`, `lib/engine/render/`.
Built purely on the existing public foundation + world APIs.
