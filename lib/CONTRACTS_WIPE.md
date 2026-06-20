# flu_doom — Screen-Melt Wipe Contract

Stable contract for the **screen-melt wipe** (`f_wipe.c`) and its present-path
integration. The wipe is the classic Doom effect: on a game-state transition the
OLD screen melts downward in vertical strips, revealing the NEW screen.

pure Dart port of Chocolate Doom `src/doom/f_wipe.c` (the MELT wipe:
`wipe_initMelt` / `wipe_doMelt` / `wipe_exitMelt`, plus the `wipe_StartScreen` /
`wipe_EndScreen` capture and the `wipe_ScreenWipe` driver) and the `D_Display` /
`D_RunFrame` driving logic in `d_main.c`. Operates on the 320x200 8-bit indexed
`Framebuffer` (`lib/engine/video/framebuffer.dart`).

---

## 0. Files

```
lib/engine/video/wipe.dart        WipeMelt — the melt (this contract).
lib/game/doom_game.dart           Present-path hook (D_Display/D_RunFrame logic).
test/video/wipe_test.dart         Behavioural unit tests.
```

`lib/game/state/game_state.dart` is **unchanged**: its `gamestate` field is
already public, so `doom_game` reads it directly to detect transitions. No
transition signal needed to be added.

---

## 1. WipeMelt API (`lib/engine/video/wipe.dart`)

```dart
class WipeMelt {
  /// wipe_StartScreen + wipe_EndScreen + wipe_initMelt.
  /// startBytes = OLD (already-presented) 320x200 indexed screen.
  /// endBytes   = NEW 320x200 indexed screen. Both copied defensively.
  /// Seeds per-column offsets from mRandom (the COSMETIC stream, NOT pRandom),
  /// exactly as vanilla. The live buffer starts == the OLD screen.
  factory WipeMelt.start(Uint8List startBytes, Uint8List endBytes);

  /// wipe_doMelt: advance the melt by [ticks] tics (default 1 = one 35Hz tic).
  /// Returns true once complete; idempotent no-op after that. Updates the live
  /// (compose-source) buffer.
  bool update([int ticks = 1]);

  /// Write the current melted frame (row-major 320x200) into [out].pixels.
  void compose(Framebuffer out);

  bool       get isComplete;     // true once the melt has fully finished.
  Int32List  get columnOffsets;  // per-column y[] offsets (copy), for tests.
  Uint8List  get currentBytes;   // live row-major frame bytes, for tests.
}
```

Driver-order contract (mirrors `wipe_ScreenWipe`):

1. `WipeMelt.start(old, new)` — captures both screens, runs `wipe_initMelt`.
   The first `compose` after this is **~all-OLD** (the live buffer is the copied
   start screen verbatim).
2. Each tic: `update()` advances the melt; `compose(fb)` presents the current
   frame. NEW pixels only ever increase (columns melt **downward**, revealing
   NEW from the **top** of each column).
3. When `update()` returns `true` (== `isComplete`) the frame is **~all-NEW**
   and the wipe is done (`wipe_exitMelt` has effectively run — Dart GC reclaims
   the buffers).

Determinism: `clearRandom()` then `WipeMelt.start(...)` yields identical column
offsets and identical melt frames across runs (vanilla `M_Random` table stream).

Duration: ~1s at 35fps; vanilla completes in well under 200 tics.

### Fidelity to f_wipe.c (deviations, all behaviour-preserving)

- The C packs two 8-bit pixels into one `dpixel_t` (32-bit) and halves `width`,
  so a "column" is a 2-pixel-wide strip. We keep raw bytes and a
  `kScreenWidth/2` column count, copying **2 bytes per dpixel step**. The
  column/byte math (the `y[]` init recurrence, the column-major transform, the
  `dy` velocity ramp `dy = (y[i] < 16) ? y[i]+1 : 8`) is identical.
- `wipe_shittyColMajorXform` is replicated exactly (start/end source buffers are
  stored column-major; the live `wipe_scr` stays row-major, as vanilla).
- Melt init uses `mRandom` (cosmetic stream), **not** `pRandom` — exactly as
  vanilla's `f_wipe.c` (which calls `M_Random`).
- **Loop host differs**: vanilla runs the melt in a *blocking* loop inside
  `D_RunFrame` (sleeping until a tic elapses, then `wipe_ScreenWipe(..., tics)`).
  We drive it across **Ticker frames** (one `update()` == one tic per rendered
  frame) so the Flutter event loop stays live. The per-tic math is identical;
  only the host loop (frames vs a blocking while) changed.

---

## 2. Present-path integration (`doom_game.dart`)

State added to `_DoomGameState`:

```dart
GameStateType? _wipegamestate;  // last *presented* gamestate (d_main wipegamestate)
WipeMelt?      _wipe;           // active melt, or null when not wiping
```

`_wipegamestate` is seeded at boot to the boot state (`GS_DEMOSCREEN`) so no
spurious wipe fires before the first real transition.

### Transition detection + START-screen capture (`_onRender`, the D_Display logic)

Each frame, before normal rendering:

1. **If a melt is active** (`_wipe != null`): `update()` one tic, `compose` into
   `_fb`, present. On completion clear `_wipe` and set
   `_wipegamestate = gs.gamestate` so normal rendering resumes next frame.
2. **Else if `gs.gamestate != _wipegamestate`** (a transition that should wipe —
   title↔level, level→intermission, intermission→next level, level→finale):
   - `_fb.pixels` still holds the **previously-presented frame** → snapshot it as
     the wipe **START** screen.
   - `gs.render(_fb)` draws the NEW screen → snapshot as the **END** screen.
   - `WipeMelt.start(start, end)`, `compose` the all-OLD first frame, present.
3. **Else**: normal `gs.render(_fb)` + present.

Keeping the previous frame correct is automatic: `_fb` is only mutated by
`gs.render` / `compose`, and `_present()` snapshots `_fb.pixels` synchronously
(via `toRgba`) before any `await`, so the live buffer always equals the last
presented frame at transition-detection time.

### Freezing game logic during the wipe (`_onTic`, the D_RunFrame freeze)

While `_wipe != null`, `_onTic` returns early — the playsim does **not** tic and
`gs.ticker` is not called. This mirrors vanilla blocking in `D_RunFrame` until
`wipe_ScreenWipe` reports done before resuming `TryRunTics`. Input events stay
queued and are drained once the wipe completes.

---

## 3. Verification

- `flutter analyze lib test` → clean (No issues found).
- `flutter test` → all pass (incl. `test/video/wipe_test.dart`: all-OLD first
  frame; monotonic NEW-pixel progress; per-column top-down reveal; completion
  with all-NEW frame in < 200 tics; idempotent done; column offsets match the
  vanilla `wipe_initMelt` recurrence; determinism under `clearRandom`).
- `flutter build macos --debug` → builds; app launches and runs stably with the
  hook wired.
- Visual proof: a mid-melt frame composed by the production `WipeMelt` (real
  PLAYPAL palette) shows the OLD horizontal bands sliding downward in irregular
  per-column strips, revealing the NEW screen from the top — the correct melt.

---

## 4. Out of scope / not touched

- The `wipe_ColorXForm` wipe (the other `f_wipe.c` mode) is not ported — vanilla
  Doom always uses the MELT wipe (`wipe_Melt`).
- Renderer 3D internals, world, play-sim, controls, audio: unchanged.
- `game_state.dart`: unchanged (existing public `gamestate` suffices).
