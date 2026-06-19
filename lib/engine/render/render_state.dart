// Shared renderer state — the Dart equivalent of vanilla's r_state.h /
// r_main.c globals (centerx, projection, viewangletox[], xtoviewangle[],
// scalelight[][], zlight[][], etc.) plus the per-frame view setup
// (R_SetupFrame) and the projection-table init (R_InitTables / R_InitLightTables).
//
// One [RenderState] is created once for a given screen size and reused across
// frames; [setupFrame] is called once per frame from the camera. The sub-pass
// modules (BSP, segs, planes, things) all read/write this object — exactly as
// the C code shares file-scope globals.
//
// Faithful to Chocolate Doom r_main.c. FOV is fixed at 90 degrees.

import 'dart:typed_data';

import '../math/angle.dart';
import '../math/fixed.dart';
import '../math/tables.dart';
import '../video/palette.dart';

/// Field of view = 90 degrees. (Vanilla FIELDOFVIEW = 2048 fineangles = 90deg.)
const int kFieldOfView = 2048;

// --- Light table constants (r_main.c / r_data.c). ---
const int kLightLevels = 16; // LIGHTLEVELS
const int kLightSegShift = 4; // LIGHTSEGSHIFT (8 -> 16 for 320 width? see init)
const int kLightBright = 1; // LIGHTBRIGHT? -> we use vanilla numbers below
const int kMaxLightScale = 48; // MAXLIGHTSCALE
const int kLightScaleShift = 12; // LIGHTSCALESHIFT
const int kMaxLightZ = 128; // MAXLIGHTZ
const int kLightZShift = 20; // LIGHTZSHIFT
const int kNumColorMaps = 32; // NUMCOLORMAPS (light levels in COLORMAP)
const int kDistMap = 2; // distmap in R_InitLightTables

/// Shared per-frame + persistent renderer state.
class RenderState {
  RenderState({
    required this.screenWidth,
    required this.screenHeight,
    required this.colormap,
  })  : centerX = screenWidth ~/ 2,
        centerY = screenHeight ~/ 2,
        // 3D view occupies the FULL screen height (status bar ignored this
        // phase — see CONTRACTS_RENDER.md). viewwidth/viewheight == screen.
        viewWidth = screenWidth,
        viewHeight = screenHeight,
        viewWindowX = 0,
        viewWindowY = 0,
        centerXFrac = (screenWidth ~/ 2) << kFracBits,
        centerYFrac = (screenHeight ~/ 2) << kFracBits {
    _initTextureMapping();
    _initLightTables();
    _initClipArrays();
  }

  // --- Screen / view window geometry (R_SetViewSize / R_ExecuteSetViewSize) ---
  final int screenWidth;
  final int screenHeight;
  final int viewWidth;
  final int viewHeight;
  final int viewWindowX;
  final int viewWindowY;
  final int centerX;
  final int centerY;
  final int centerXFrac;
  final int centerYFrac;

  /// projection = centerXFrac (vanilla `projection`). Distance->scale factor.
  late final fixed_t projection = centerXFrac;

  /// finetangent index where the FOV's left/right rays sit (focallength etc).
  /// viewangletox: for each fine angle, the screen column it maps to.
  late final Int32List viewAngleToX = Int32List(kFineAngles ~/ 2);

  /// xtoviewangle: for each screen column (0..viewWidth), the view angle.
  late final Uint32List xToViewAngle = Uint32List(screenWidth + 1);

  // --- Light tables (R_InitLightTables) ---
  final Colormap colormap;

  /// scalelight[LIGHTLEVELS][MAXLIGHTSCALE] -> colormap index (0..NUMCOLORMAPS-1).
  late final List<Int32List> scaleLight;

  /// zlight[LIGHTLEVELS][MAXLIGHTZ] -> colormap index.
  late final List<Int32List> zLight;

  /// Number of colormaps (NUMCOLORMAPS) actually available for shading.
  int get numColorMaps => kNumColorMaps;

  // --- Per-frame view (R_SetupFrame) ---
  fixed_t viewX = 0;
  fixed_t viewY = 0;
  fixed_t viewZ = 0;
  angle_t viewAngle = 0;
  fixed_t viewSin = 0;
  fixed_t viewCos = 0;

  /// extralight (weapon flash); 0 unless playsim adds it. Affects light index.
  int extraLight = 0;

  // --- Clip / occlusion arrays shared by BSP, segs, planes ---
  /// ceilingclip[x] / floorclip[x]: the current vertical clip bounds per column
  /// used by visplanes (R_MapPlane reads these via the plane's top/bottom).
  /// floorclip is the lowest pixel a wall has drawn to (bottom clip), ceilingclip
  /// the highest. Initialized per frame.
  late final Int16List ceilingClip = Int16List(screenWidth);
  late final Int16List floorClip = Int16List(screenWidth);

  void _initTextureMapping() {
    // R_InitTextureMapping, faithful to r_main.c.
    // focallength = FixedDiv(centerxfrac, finetangent[FINEANGLES/4 + FIELDOFVIEW/2])
    final int fovHalf = kFieldOfView ~/ 2;
    final int focalIndex = kFineAngles ~/ 4 + fovHalf;
    final fixed_t focalLength =
        fixedDiv(centerXFrac, finetangent[focalIndex]);

    // For each fine angle in [0, FINEANGLES/2), compute the screen column.
    for (int i = 0; i < kFineAngles ~/ 2; i++) {
      int t;
      final fixed_t tan = finetangent[i];
      if (tan > fracUnitMul(2, focalLength)) {
        t = -1;
      } else if (tan < -fracUnitMul(2, focalLength)) {
        t = viewWidth + 1;
      } else {
        t = fixedMul(tan, focalLength);
        t = (centerXFrac - t + kFracUnit - 1) >> kFracBits;
        if (t < -1) {
          t = -1;
        } else if (t > viewWidth + 1) {
          t = viewWidth + 1;
        }
      }
      viewAngleToX[i] = t;
    }

    // Scan viewangletox[] to fill xtoviewangle[].
    for (int x = 0; x <= viewWidth; x++) {
      int i = 0;
      while (i < kFineAngles ~/ 2 && viewAngleToX[i] > x) {
        i++;
      }
      // xtoviewangle[x] = (i<<ANGLETOFINESHIFT) - ANG90
      xToViewAngle[x] =
          normAngle((i << kAngleToFineShift) - kAng90);
    }

    // Clamp viewangletox values to [0, viewwidth] (vanilla post-pass).
    for (int i = 0; i < kFineAngles ~/ 2; i++) {
      if (viewAngleToX[i] == -1) {
        viewAngleToX[i] = 0;
      } else if (viewAngleToX[i] == viewWidth + 1) {
        viewAngleToX[i] = viewWidth;
      }
    }
  }

  // (a * focalLength*2) helper kept readable.
  int fracUnitMul(int n, int v) => n * v;

  void _initLightTables() {
    // R_InitLightTables, faithful to r_main.c.
    final int numMaps = colormap.numMaps >= kNumColorMaps
        ? kNumColorMaps
        : colormap.numMaps;
    scaleLight = List<Int32List>.generate(
        kLightLevels, (_) => Int32List(kMaxLightScale));
    zLight =
        List<Int32List>.generate(kLightLevels, (_) => Int32List(kMaxLightZ));

    // zlight (distance-based).
    for (int i = 0; i < kLightLevels; i++) {
      final int startMap = ((kLightLevels - 1 - i) * 2) * numMaps ~/ kLightLevels;
      for (int j = 0; j < kMaxLightZ; j++) {
        // scale = FixedDiv(SCREENWIDTH/2*FRACUNIT, (j+1)<<LIGHTZSHIFT)>>LIGHTSCALESHIFT
        int scale = fixedDiv(
            (screenWidth ~/ 2) * kFracUnit, (j + 1) << kLightZShift);
        scale >>= kLightScaleShift;
        int level = startMap - scale ~/ kDistMap;
        if (level < 0) level = 0;
        if (level >= numMaps) level = numMaps - 1;
        zLight[i][j] = level;
      }
    }
    // scalelight (R_ExecuteSetViewSize portion).
    for (int i = 0; i < kLightLevels; i++) {
      final int startMap = ((kLightLevels - 1 - i) * 2) * numMaps ~/ kLightLevels;
      for (int j = 0; j < kMaxLightScale; j++) {
        int level = startMap - (j * screenWidth ~/ 320) ~/ kDistMap;
        if (level < 0) level = 0;
        if (level >= numMaps) level = numMaps - 1;
        scaleLight[i][j] = level;
      }
    }
  }

  void _initClipArrays() {
    // Filled per-frame in setupFrame; allocate above.
  }

  /// R_SetupFrame: copy the camera in and precompute view sin/cos. Resets the
  /// per-frame occlusion arrays.
  void setupFrame({
    required fixed_t x,
    required fixed_t y,
    required fixed_t z,
    required angle_t angle,
    int extraLight = 0,
  }) {
    viewX = x;
    viewY = y;
    viewZ = z;
    viewAngle = normAngle(angle);
    this.extraLight = extraLight;
    final int fineIdx = angleToFineIndex(viewAngle);
    viewSin = finesine[fineIdx];
    viewCos = finecosine[fineIdx];
    // ceilingclip = -1 (top), floorclip = viewheight (bottom): nothing drawn.
    for (int xx = 0; xx < screenWidth; xx++) {
      ceilingClip[xx] = -1;
      floorClip[xx] = viewHeight;
    }
  }

  /// R_PointToAngle: angle from the viewpoint to (x, y). Faithful to r_main.c.
  angle_t pointToAngle(fixed_t x, fixed_t y) {
    return _pointToAngleFrom(viewX, viewY, x, y);
  }

  /// R_PointToAngle2: angle from (x1,y1) to (x2,y2).
  angle_t pointToAngle2(fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2) {
    return _pointToAngleFrom(x1, y1, x2, y2);
  }

  static angle_t _pointToAngleFrom(
      fixed_t vx, fixed_t vy, fixed_t x, fixed_t y) {
    x = toInt32(x - vx);
    y = toInt32(y - vy);

    if (x == 0 && y == 0) return 0;

    if (x >= 0) {
      // x >=0
      if (y >= 0) {
        if (x > y) {
          // octant 0
          return tantoangle[slopeDiv(y, x)];
        } else {
          // octant 1
          return normAngle(kAng90 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      } else {
        // y < 0
        y = -y;
        if (x > y) {
          // octant 8
          return normAngle(-tantoangle[slopeDiv(y, x)]);
        } else {
          // octant 7
          return normAngle(kAng270 + tantoangle[slopeDiv(x, y)]);
        }
      }
    } else {
      // x < 0
      x = -x;
      if (y >= 0) {
        if (x > y) {
          // octant 3
          return normAngle(kAng180 - 1 - tantoangle[slopeDiv(y, x)]);
        } else {
          // octant 2
          return normAngle(kAng90 + tantoangle[slopeDiv(x, y)]);
        }
      } else {
        // y < 0
        y = -y;
        if (x > y) {
          // octant 4
          return normAngle(kAng180 + tantoangle[slopeDiv(y, x)]);
        } else {
          // octant 5
          return normAngle(kAng270 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      }
    }
  }

  /// R_PointToDist: distance from the viewpoint to (x, y). Faithful to r_main.c.
  fixed_t pointToDist(fixed_t x, fixed_t y) {
    int dx = (toInt32(x - viewX)).abs();
    int dy = (toInt32(y - viewY)).abs();

    if (dy > dx) {
      final int t = dx;
      dx = dy;
      dy = t;
    }
    if (dx == 0) return 0;
    // angle = (tantoangle[ FixedDiv(dy,dx)>>DBITS ] + ANG90) >> ANGLETOFINESHIFT
    final int frac = fixedDiv(dy, dx);
    final int idx = (frac >> _dbits);
    final angle_t a =
        normAngle(tantoangle[idx & (kSlopeRange)] + kAng90);
    final int fineIdx = (a >> kAngleToFineShift) & kFineMask;
    final fixed_t dist = fixedDiv(dx, finesine[fineIdx]);
    return dist;
  }

  // DBITS = FRACBITS - SLOPEBITS.
  static const int _dbits = kFracBits - kSlopeBits;
}
