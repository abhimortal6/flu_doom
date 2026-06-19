# flu_doom — Stable Public Interfaces (Phase 1)

This document defines the **stable public contracts** that all later modules
build against. Parallel agents should code to these signatures. The foundation
is a pure-Dart (no FFI) port of vanilla Doom (Chocolate Doom / doomgeneric),
targeting **Dart native (AOT) integer semantics**.

> Fixed-point math relies on 32-bit signed overflow. We do the math in Dart's
> 64-bit ints and mask back to signed 32-bit via `toInt32`. **Web is out of
> scope** for this phase.

---

## 1. Module layout (`lib/`)

```
lib/
  main.dart                     App entry; WidgetsApp -> DoomGame.
  INTERFACES.md                 This file.
  engine/
    math/
      fixed.dart                fixed_t, FixedMul/FixedDiv, conversions.
      angle.dart                angle_t, BAM consts, trig lookups, SlopeDiv.
      tables.dart               GENERATED finesine/finecosine/finetangent/tantoangle.
    wad/
      wad.dart                  WadFile, Lump, WadException.
    video/
      palette.dart              Palette (PLAYPAL->ARGB), Colormap (COLORMAP).
      framebuffer.dart          Framebuffer (320x200 indexed) + toImage().
      patch.dart                Patch (Doom picture format) decode + draw().
      video_view.dart           VideoView widget, ScaleMode.
    input/
      doomkeys.dart             DoomKey constants.
      event.dart                DoomEvent, EventType, EventQueue.
      keyboard.dart             DoomKeyboardListener, mapLogicalKey().
    system/
      gameloop.dart             GameLoop (35Hz tic + render hooks).
  game/
    doom_game.dart              Phase-1 vertical slice widget.
  ui/
    debug_overlay.dart          FPS/tic overlay.
    touch_overlay.dart          On-screen button stub.
```

---

## 2. Fixed-point math — `engine/math/fixed.dart`

```dart
const int kFracBits = 16;          // FRACBITS
const int kFracUnit = 1 << 16;     // FRACUNIT (65536)
const int kInt32Max = 0x7FFFFFFF;
const int kInt32Min = -0x80000000;

typedef fixed_t = int;             // 16.16, kept in signed-32-bit range

int toInt32(int v);                // mask+sign-extend to signed 32-bit
int intToFixed(int v);             // v << 16 (then toInt32)
int fixedToInt(int v);             // v >> 16 (arithmetic)

int fixedMul(int a, int b);        // ((a*b) >> 16) -> toInt32   (FixedMul)
int fixedDiv(int a, int b);        // overflow-guarded (a<<16)/b (FixedDiv)
```

`fixedDiv` reproduces vanilla's guard exactly:
`if ((a.abs() >> 14) >= b.abs()) return (a^b)<0 ? INT_MIN : INT_MAX;`

---

## 3. Angles & trig — `engine/math/angle.dart`, `engine/math/tables.dart`

```dart
typedef angle_t = int;             // unsigned 32-bit BAM angle (full circle 2^32)

const int kFineAngles = 8192;      // FINEANGLES
const int kFineMask   = 8191;      // FINEMASK
const int kAngleToFineShift = 19;  // ANGLETOFINESHIFT

const int kAng45  = 0x20000000;
const int kAng90  = 0x40000000;
const int kAng180 = 0x80000000;
const int kAng270 = 0xC0000000;
const int kAngMax = 0xFFFFFFFF;
const int kAng1   = kAng45 ~/ 45;

const int kSlopeRange = 2048;      // SLOPERANGE
const int kSlopeBits  = 11;        // SLOPEBITS

int normAngle(int a);                       // a & 0xFFFFFFFF
int angleToFineIndex(int angle);            // (angle >> 19) & 8191
int sineOf(int angle);                      // finesine[idx]      (fixed_t)
int cosineOf(int angle);                    // finecosine analog  (fixed_t)
int tangentOf(int fineIndex);               // finetangent[idx]   (fixed_t)
int slopeDiv(int num, int den);             // SlopeDiv -> tantoangle index

// Raw tables (engine/math/tables.dart) — verbatim from Chocolate Doom tables.c:
Int32List  finesine;     // 10240 entries (FINEANGLES*5/4), 16.16
Int32List  finecosine;   // sublistView of finesine at +2048
Int32List  finetangent;  // 4096 entries, 16.16
Uint32List tantoangle;   // 2049 entries (SLOPERANGE+1), angle_t
```

Verified known values: `finesine[0]=25, [1]=75, [2]=125`;
`finetangent[0]=-170910304, [4095]=170910304`;
`tantoangle[1]=333772, [2048]=0x20000000 (ANG45)`.

---

## 4. WAD — `engine/wad/wad.dart`

```dart
class Lump {
  final String name;     // uppercased, <=8 chars
  final int position;    // byte offset of data in WAD
  final int size;        // bytes
  final int index;       // global lump number
  Uint8List get bytes;   // zero-copy view of lump data
  ByteData  get data;    // zero-copy ByteData view
}

class WadException implements Exception { final String message; }

class WadFile {
  final String identification;     // "IWAD" | "PWAD"
  final List<Lump> lumps;          // directory order
  int  get numLumps;
  bool get isIwad;

  static WadFile fromBytes(Uint8List bytes);

  Lump? lumpByName(String name);   // case-insensitive; LAST match (PWAD override)
  Lump  getLump(String name);      // throws WadException if missing
  bool  hasLump(String name);
  Lump  lumpByIndex(int index);
  int   lumpNumForName(String name); // -1 if missing (for namespace marker scan)
}
```

WAD format: 12-byte header (`id[4]`, int32 `numLumps`, int32 `infoTableOfs`),
then 16-byte directory entries (int32 `filepos`, int32 `size`, char `name[8]`),
all little-endian.

---

## 5. Palette & Colormap — `engine/video/palette.dart`

```dart
class Palette {
  final Uint32List argb;                 // 256 entries, 0xFFRRGGBB
  Palette(Uint32List argb);
  factory Palette.fromPlaypal(Uint8List playpal, {int paletteIndex = 0});
  factory Palette.fromWad(WadFile wad);  // palette 0 from PLAYPAL
  static const int paletteCount = 14;
}

class Colormap {
  final Uint8List maps;                  // numMaps * 256 bytes
  final int numMaps;                     // typically 34
  int       remap(int mapIndex, int paletteIndex);
  Uint8List mapAt(int mapIndex);         // zero-copy 256-byte view
  factory Colormap.fromLump(Uint8List colormap);
  factory Colormap.fromWad(WadFile wad);
}
```

PLAYPAL = 14 palettes × 256 × RGB. COLORMAP = N × 256 index-remap tables.

---

## 6. Framebuffer — `engine/video/framebuffer.dart`

```dart
const int kScreenWidth  = 320;   // SCREENWIDTH
const int kScreenHeight = 200;   // SCREENHEIGHT

class Framebuffer {
  Framebuffer({int width = 320, int height = 200});
  final int width, height;
  final Uint8List pixels;          // indexed; index = y*width + x. Renderers write here.

  void clear([int color = 0]);
  void setPixel(int x, int y, int colorIndex);
  int  getPixel(int x, int y);

  Uint8List toRgba(Palette palette);          // reusable internal RGBA8888 buffer
  Future<ui.Image> toImage(Palette palette);  // decode to ui.Image (RGBA8888)
}
```

**Renderer contract:** write palette indices into `pixels` (row-major). Call
`toImage(palette)` once per frame to obtain a `ui.Image` for display.

---

## 7. Patch (Doom picture) — `engine/video/patch.dart`

```dart
class Patch {
  final int width, height, leftOffset, topOffset;
  factory Patch.fromBytes(Uint8List bytes);
  void draw(Framebuffer fb, int x, int y);  // V_DrawPatch-style, transparency-aware, clipped
}
```

Patch header: int16 `width,height,leftoffset,topoffset`, then uint32
`columnofs[width]`. Each column = posts of `(topdelta, length, pad, pixels[length], pad)`
terminated by `topdelta == 0xFF`.

---

## 8. Video widget — `engine/video/video_view.dart`

```dart
enum ScaleMode { fit, integer, fill }   // auto-fit/letterbox | integer multiple | stretch

class VideoView extends StatelessWidget {
  const VideoView({
    Key? key,
    required ui.Image? image,
    ScaleMode scaleMode = ScaleMode.fit,
    bool pixelAspectCorrection = false,  // 4:3 correction (height * 1.2)
    Color backgroundColor = const Color(0xFF000000),
  });
}
```

Nearest-neighbour (`FilterQuality.none`); auto-scales preserving aspect with
letterboxing; works in portrait and landscape.

---

## 9. Game loop — `engine/system/gameloop.dart`

```dart
const int kTicRate = 35;                       // TICRATE
const int kMicrosPerTic = 1000000 ~/ 35;

typedef TicHook    = void Function(int gametic);  // advance playsim one tic (G_Ticker)
typedef RenderHook = void Function();             // render one frame

class GameLoop {
  GameLoop({
    required TickerProvider vsync,
    required TicHook onTic,
    required RenderHook onRender,
    int maxTicsPerFrame = 5,
  });
  int    get gametic;
  double get fps;
  bool   get isRunning;
  void start();
  void stop();
  void dispose();
}
```

Fixed-timestep accumulator: runs as many 35Hz tics as are due per frame
(capped by `maxTicsPerFrame`), then calls `onRender` once. **Playsim plugs in
via `onTic`; the renderer via `onRender`.**

---

## 10. Input — `engine/input/{doomkeys,event,keyboard}.dart`

```dart
// doomkeys.dart — Doom keycodes (event.data1 values)
abstract final class DoomKey {
  static const int rightArrow, leftArrow, upArrow, downArrow, escape, enter,
      tab, spacebar, backspace, rCtrl, rShift, rAlt, f1..f12, /* ... */;
  static int ascii(String ch);   // literal lowercase ASCII for letters/digits
}

// event.dart
enum EventType { keyDown, keyUp, mouse, joystick, quit }

class DoomEvent {
  const DoomEvent(EventType type, {int data1, int data2, int data3});
  const DoomEvent.keyDown(int key);   // data1 = DoomKey code
  const DoomEvent.keyUp(int key);
  final EventType type;
  final int data1, data2, data3;
}

class EventQueue {                     // ring buffer (MAXEVENTS=64)
  EventQueue({int capacity = 64});
  void postEvent(DoomEvent e);         // D_PostEvent (sources call this)
  DoomEvent? popEvent();               // D_PopEvent  (game loop drains)
  bool get isEmpty;
  List<DoomEvent> drain();             // pop all in order
}

// keyboard.dart
int? mapLogicalKey(LogicalKeyboardKey key);   // Flutter key -> Doom code (null if unmapped)
class DoomKeyboardListener extends StatefulWidget {
  const DoomKeyboardListener({required EventQueue queue, required Widget child, bool autofocus = true});
}
```

**Input contract:** all sources (hardware keyboard via `DoomKeyboardListener`,
touch via `TouchOverlay`) call `queue.postEvent(...)`. The game loop drains the
queue once per tic inside `onTic` (mirrors vanilla's per-tic event drain).

---

## Assumptions / deviations from vanilla

- 64-bit math masked to signed 32-bit instead of native C overflow.
- `EventQueue` drops the oldest event when full (vanilla overwrites); behaviour
  matters only under pathological flooding.
- `GameLoop` uses a wall-clock accumulator on a Flutter `Ticker` rather than
  `I_GetTime`; tic cadence is identical (35Hz) but frames may render between
  tics (vanilla renders once per tic). No interpolation yet.
- Only palette 0 of PLAYPAL is exposed this phase (no damage/bonus tints).
- `ScaleMode` + optional 4:3 pixel-aspect correction are extensions beyond
  vanilla's fixed scaling, per product requirement.
