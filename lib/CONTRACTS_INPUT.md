# flu_doom — Input / Controls UX Layer Contracts

This document defines the **input/controls UX layer**: the on-screen overlay,
the keyboard binding system, the controls settings screen, and exactly how they
feed the foundation `EventQueue` / key-state. It builds strictly on the existing
foundation input contracts in `lib/engine/input/*` (see `INTERFACES.md` §10) and
**never touches ticcmd internals** — it produces `DoomEvent`s and a queryable
key-state set, the same data vanilla Doom's playsim consumes.

The integration agent mounts the overlay over the game view and routes events.

---

## 1. File layout

```
lib/
  input_actions/                     (NEW — the action/binding model)
    game_action.dart                 GameAction enum + ActionKeys (keycodes/labels)
    action_dispatcher.dart           ActionSink + EventQueueActionSink (-> EventQueue + key-state)
    key_bindings.dart                KeyBindings (key -> GameAction) + vanilla defaults
    action_keyboard_listener.dart    Rebindable hardware-keyboard widget
    controls_settings.dart           OverlaySettings + ControlsSettingsStore (persistence)
  ui/controls/
    overlay_button_id.dart           Stable ids for repositionable buttons
    overlay_widgets.dart             OverlayHoldButton + OverlayMovementStick primitives
    touch_controls_overlay.dart      TouchControlsOverlay (composable overlay)
    controls_preview.dart            ControlsPreviewApp / ControlsPreviewPage (standalone)
  ui/settings/
    controls_settings_screen.dart    ControlsSettingsScreen (separate route)
test/input/
    action_dispatcher_test.dart      action -> events / key-state, bindings
    overlay_widget_test.dart         overlay taps -> events, portrait/landscape/handedness
    settings_persistence_test.dart   save/load, reset, settings-screen + rebind UX
```

`pubspec.yaml`: added `shared_preferences: ^2.3.2` under `dependencies:`.

---

## 2. Action model — `input_actions/game_action.dart`

```dart
enum GameAction {
  moveForward, moveBackward, turnLeft, turnRight,
  strafeLeft, strafeRight, strafeModifier, run,
  fire, use,
  weapon1, weapon2, weapon3, weapon4, weapon5, weapon6, weapon7,
  prevWeapon, nextWeapon,
  automap, menuToggle, pause,
  confirm, menuUp, menuDown, menuLeft, menuRight,
}

abstract final class ActionKeys {
  static List<int> keysFor(GameAction a);  // Doom keycode(s) the action emits
  static String label(GameAction a);        // UI label
}
```

Default action → Doom keycode mapping (`ActionKeys.keysFor`):

| Action | DoomKey | Action | DoomKey |
|---|---|---|---|
| moveForward | upArrow | fire | rCtrl |
| moveBackward | downArrow | use | spacebar |
| turnLeft | leftArrow | weapon1..7 | '1'..'7' |
| turnRight | rightArrow | prevWeapon | minus `-` |
| strafeLeft | `,` (0x2c) | nextWeapon | equals `=` |
| strafeRight | `.` (0x2e) | automap | tab |
| strafeModifier | rAlt | menuToggle | escape |
| run | rShift | pause | pause (0xff) |
| confirm | enter | menuUp/Down/Left/Right | arrows |

`menuUp/Down/Left/Right` deliberately share keycodes with movement arrows —
vanilla uses the same physical keys and disambiguates by game state, not here.

---

## 3. Dispatch / key-state — `input_actions/action_dispatcher.dart`

```dart
abstract interface class ActionSink {
  void pressAction(GameAction a);    // begin hold
  void releaseAction(GameAction a);  // end hold
  void tapAction(GameAction a);      // momentary down+up (weapons/menu)
}

class EventQueueActionSink implements ActionSink {
  EventQueueActionSink(EventQueue queue);
  Set<int> get downKeys;             // Doom keycodes currently held (gamekeydown[])
  bool isKeyDown(int code);
  void releaseAll();                 // panic-release on focus loss / pause
}
```

> Named `EventQueueActionSink` (not `ActionDispatcher`) to avoid a name clash
> with Flutter's `ActionDispatcher` widget.

How actions reach the foundation:

- `pressAction` → posts `DoomEvent.keyDown(code)` on the `EventQueue` **and**
  records the keycode in a ref-counted key-state map.
- `releaseAction` → posts `DoomEvent.keyUp(code)` and decrements the ref-count.
- **Ref-counting** means a keycode shared by two actions (e.g. `moveForward`
  and `menuUp`, both `upArrow`) emits exactly one `keyDown` edge and only emits
  `keyUp` when the *last* holder releases — no stuck/duplicate edges.
- `tapAction` posts a clean `keyDown`+`keyUp` pair without touching ref-counts.
- `downKeys` / `isKeyDown` expose the live held-key set for a future
  `G_BuildTiccmd` (mirrors vanilla `gamekeydown[]`). Consumers may use **either**
  the drained events **or** the key-state set; both are kept consistent.

The game loop continues to drain the queue per tic via `queue.popEvent()` /
`queue.drain()` exactly as documented in `INTERFACES.md` §10 — this layer only
*posts*.

---

## 4. Keyboard bindings — `input_actions/key_bindings.dart`

```dart
class KeyBindings {
  KeyBindings(Map<int, GameAction> bindings);           // keyId -> action
  factory KeyBindings.defaults();                        // vanilla-style
  factory KeyBindings.fromJson(Map<String,dynamic> j);
  Map<String,String> toJson();                           // keyId(str)->action.name

  GameAction? actionFor(LogicalKeyboardKey key);
  List<int> keysFor(GameAction action);                  // all keyIds for action
  void bind(LogicalKeyboardKey key, GameAction action);
  void unbind(LogicalKeyboardKey key);
  void clearAction(GameAction action);
}
```

Bindings are keyed by `LogicalKeyboardKey.keyId` (stable int) for trivial
serialization. Multiple keys → one action allowed; one key → at most one action.

Default bindings (vanilla-style, fully rebindable):
arrows + **WASD** (W/S forward/back, A/D strafe, ←/→ turn), **Ctrl** fire,
**Space** use, **Shift** run, **Alt** strafe-modifier, **`,`/`.`** strafe,
**1–7** weapons, **`-`/`=`** prev/next weapon, **Tab** automap, **Esc** menu,
**Enter/NumpadEnter** confirm, **Pause** pause.

### Rebindable listener — `action_keyboard_listener.dart`

```dart
class ActionKeyboardListener extends StatefulWidget {
  const ActionKeyboardListener({
    required KeyBindings bindings,   // live-updatable
    required ActionSink sink,
    required Widget child,
    bool autofocus = true,
    bool enabled = true,             // set false while a rebind capture is open
  });
}
```

Resolves each hardware key through `bindings` → `GameAction` → `sink`. This is
the rebindable replacement for the foundation's fixed `DoomKeyboardListener`;
wrap the game view in it instead (or alongside) to get rebindable keys.

---

## 5. Overlay — `ui/controls/touch_controls_overlay.dart`

```dart
class TouchControlsOverlay extends StatefulWidget {
  const TouchControlsOverlay({ required ActionSink sink,
                               OverlaySettings settings = const OverlaySettings() });
  TouchControlsOverlay.forQueue({ required EventQueue queue,
                                  OverlaySettings settings = const OverlaySettings() });
}
```

Self-contained, drop into a `Stack` over the game view. Returns a
`Positioned.fill` so it overlays without consuming layout. Emits the **same**
`GameAction`s as the keyboard via the supplied `ActionSink`. Honors
`OverlaySettings` (visibility, opacity, scale, handedness). When
`settings.visible == false` it renders `SizedBox.shrink()` (no hit targets).

Clusters:
- **Movement stick** (`OverlayMovementStick`): 8-direction analog stick with a
  deadzone; resolves the drag vector into up to two simultaneous
  forward/back + turn/strafe actions (diagonals). A local **STR** toggle button
  switches left/right between turn and strafe.
- **Primary actions**: USE + FIRE (hold buttons → press/release).
- **Secondary actions**: prev/next weapon (momentary taps), RUN (hold), STR
  (local toggle).
- **Utility**: MENU / MAP / PAUSE (momentary taps).

Buttons expose `semanticLabel`s (`FIRE`, `USE`, `MENU`, `MAP`, `W+`, `W-`, …)
used by tests and accessibility.

### Orientation & handedness layout

Driven by `LayoutBuilder` (orientation = `maxWidth >= maxHeight`):

- **Right-handed (default):** movement stick **bottom-left**, action clusters
  **bottom-right** (secondary stacked above primary), utility **top-right**.
- **Left-handed:** the above is mirrored — movement **bottom-right**, actions
  **bottom-left**, utility **top-left**.
- **Portrait:** buttons auto-scale to ~0.9× to leave thumb room; the secondary
  cluster `Wrap`s if width is tight. Everything stays inside `SafeArea`.
- **Landscape:** full `settings.scale`; clusters hug the bottom corners where
  thumbs rest. Verified by widget tests at 800×1400 (portrait) and 1400×800
  (landscape) plus a left-handed render test.

### Repositionable buttons — `ui/controls/overlay_button_id.dart`

`OverlayButtonId` provides stable string ids (`movementStick`, `fire`, `use`,
`run`, `automap`, `menu`, `prevWeapon`, `nextWeapon`). `OverlaySettings.positions`
maps these ids → fractional `ButtonPosition` overrides for drag-to-reposition.
(The model + persistence are wired; the default overlay uses corner clusters and
ignores empty overrides.)

---

## 6. Settings + persistence — `input_actions/controls_settings.dart`

```dart
enum HandedLayout { right, left }
class ButtonPosition { final double dx, dy; }   // 0..1 fractional

class OverlaySettings {
  const OverlaySettings({ bool visible = true, double opacity = 0.45,
    double scale = 1.0, HandedLayout handed = HandedLayout.right,
    Map<String, ButtonPosition> positions = const {} });
  OverlaySettings copyWith({...});
  Map<String,dynamic> toJson(); factory OverlaySettings.fromJson(...);
  factory OverlaySettings.defaults();
}

class ControlsSettingsStore {
  static Future<ControlsSettingsStore> open();   // SharedPreferences-backed
  OverlaySettings loadOverlay();  Future<void> saveOverlay(OverlaySettings);
  KeyBindings     loadBindings(); Future<void> saveBindings(KeyBindings);
  Future<void> resetToDefaults();
}
```

**Persistence keys** (shared_preferences, JSON-encoded strings):
- `flu_doom.controls.overlay`  → `OverlaySettings` JSON
- `flu_doom.controls.bindings` → `KeyBindings` JSON (`keyId` → `action.name`)

Missing or corrupt values fall back to defaults (never throw). Defaults:
overlay visible, opacity `0.45`, scale `1.0`, right-handed, vanilla bindings.

---

## 7. Settings screen — `ui/settings/controls_settings_screen.dart`

```dart
class ControlsSettingsScreen extends StatefulWidget {
  const ControlsSettingsScreen({
    required ControlsSettingsStore store,
    void Function(OverlaySettings, KeyBindings)? onChanged,  // live-apply hook
  });
}
```

A **separate route** (push via `MaterialPageRoute`). Two sections:

1. **On-screen Controls** — show/hide switch, opacity slider, size slider,
   left/right handedness segmented control.
2. **Keyboard Bindings** — one row per `GameAction`; tap opens a modal
   **key-capture dialog** ("Press a key…", Esc cancels) that captures the next
   physical key and rebinds it (clearing the action's previous keys).

An app-bar **RESET** button calls `resetToDefaults()`. Every change persists
immediately and fires `onChanged` so the shell can live-apply.

**Orientation:** single scrolling column in portrait; two side-by-side columns
(overlay | bindings), each independently scrollable, in landscape.

---

## 8. Standalone preview & verification

`ui/controls/controls_preview.dart` exports `ControlsPreviewApp` — runnable in
isolation:

```dart
import 'package:flu_doom/ui/controls/controls_preview.dart';
void main() => runApp(const ControlsPreviewApp());
```

It composes `TouchControlsOverlay` over a placeholder game view, wires hardware
keys through `ActionKeyboardListener`, shows a live event log (drain on "Pump"),
and a **Settings** button opening `ControlsSettingsScreen`.

Verified: `flutter analyze` clean (whole project), `flutter test` green (53
tests, incl. 20 in `test/input/`). The rebind test drives the real Flutter
focus/key pipeline (`sendKeyEvent`) — the same path used for macOS hardware
keyboard input.

---

## 9. Integration checklist (for the integration agent)

1. Create one `EventQueueActionSink(gameQueue)` over the existing game
   `EventQueue` (or use `TouchControlsOverlay.forQueue`).
2. Wrap the game view in `ActionKeyboardListener(bindings, sink, child: …)` for
   rebindable hardware keys (replaces/augments `DoomKeyboardListener`).
3. Stack `TouchControlsOverlay(sink: sink, settings: overlaySettings)` over the
   `VideoView`.
4. Load settings once at startup via `ControlsSettingsStore.open()`; pass
   `onChanged` from `ControlsSettingsScreen` to update `bindings`/`settings`
   live (rebuild the listener + overlay).
5. Call `sink.releaseAll()` on app pause / focus loss to avoid stuck keys.
6. The playsim consumes either the drained `DoomEvent`s (existing per-tic drain)
   or `sink.downKeys` — both stay consistent.
```
