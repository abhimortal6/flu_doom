// Shared renderer state — a faithful Dart port of vanilla Doom's
// r_main.c globals + r_state.h, and the per-frame view setup (R_SetupFrame).
//
// Ported from Chocolate Doom (commit 353cf500), src/doom/r_main.c.
// FOV is fixed at 90 degrees (FIELDOFVIEW = 2048 fineangles). The view occupies
// the FULL screen (no status-bar inset in this engine: setblocks == 11).
//
// IMPORTANT FAITHFULNESS NOTES (these were the source of prior bugs):
//   * finesine[] has 5*FINEANGLES/4 = 10240 entries and finetangent[] has
//     FINEANGLES/2 = 4096 entries. Vanilla indexes them with
//     `(angle) >> ANGLETOFINESHIFT` WITHOUT masking — the index can legally
//     exceed FINEANGLES (up to ~10240 for finesine). We MUST NOT mask with
//     kFineMask here, or scale/texture math is corrupted at certain view
//     angles (the "smear while turning" artifact). We replicate vanilla's
//     unmasked shift exactly.
//   * angle_t is unsigned 32-bit; we keep values masked to 32 bits via & on the
//     shift result so the >>19 yields the same index C's unsigned shift does.

import 'dart:typed_data';

import '../math/angle.dart';
import '../math/fixed.dart';
import '../math/tables.dart';
import '../video/palette.dart';

/// Field of view = 90 degrees. (Vanilla FIELDOFVIEW = 2048 fineangles.)
const int kFieldOfView = 2048;

// --- Light table constants (r_main.c). ---
const int kLightLevels = 16; // LIGHTLEVELS
const int kLightSegShift = 4; // LIGHTSEGSHIFT
const int kMaxLightScale = 48; // MAXLIGHTSCALE
const int kLightScaleShift = 12; // LIGHTSCALESHIFT
const int kMaxLightZ = 128; // MAXLIGHTZ
const int kLightZShift = 20; // LIGHTZSHIFT
const int kNumColorMaps = 32; // NUMCOLORMAPS
const int kDistMap = 2; // DISTMAP

/// ANGLETOFINESHIFT, but applied to a 32-bit-masked angle WITHOUT a fine mask.
/// This is the exact vanilla `(angle) >> ANGLETOFINESHIFT` for an unsigned
/// 32-bit angle: produces an index in [0, FINEANGLES) for finesine/finecosine
/// (0..8191) and [0, FINEANGLES/2) for finetangent when the caller has biased
/// the angle accordingly. Used by R_ScaleFromGlobalAngle / R_RenderSegLoop /
/// R_MapPlane where the bias can push the index past FINEANGLES (legal: the
/// finesine table is 10240 long).
int fineShift(int angle) => (angle & 0xFFFFFFFF) >> kAngleToFineShift;

/// Shared per-frame + persistent renderer state.
class RenderState {
  RenderState({
    required this.screenWidth,
    required this.screenHeight,
    required this.colormap,
  })  : centerX = screenWidth ~/ 2,
        centerY = screenHeight ~/ 2,
        viewWidth = screenWidth,
        viewHeight = screenHeight,
        centerXFrac = (screenWidth ~/ 2) << kFracBits,
        centerYFrac = (screenHeight ~/ 2) << kFracBits {
    _initTextureMapping();
    _initLightTables();
  }

  // --- Screen / view window geometry (R_ExecuteSetViewSize, setblocks==11) ---
  final int screenWidth;
  final int screenHeight;
  final int viewWidth;
  final int viewHeight;
  final int centerX;
  final int centerY;
  final int centerXFrac;
  final int centerYFrac;

  /// projection = centerxfrac. (r_main.c)
  late final fixed_t projection = centerXFrac;

  /// pspritescale = FRACUNIT*viewwidth/SCREENWIDTH; here viewwidth==SCREENWIDTH.
  late final fixed_t pspriteScale = (kFracUnit * viewWidth) ~/ screenWidth;
  late final fixed_t pspriteIScale = (kFracUnit * screenWidth) ~/ viewWidth;

  /// viewangletox[FINEANGLES/2]: for each fine angle, the screen column.
  late final Int32List viewAngleToX = Int32List(kFineAngles ~/ 2);

  /// xtoviewangle[SCREENWIDTH+1]: for each screen column, the view angle.
  late final Uint32List xToViewAngle = Uint32List(screenWidth + 1);

  /// clipangle = xtoviewangle[0]. (r_main.c)
  late angle_t clipAngle;

  // --- Light tables (R_InitLightTables / R_ExecuteSetViewSize) ---
  final Colormap colormap;

  /// scalelight[LIGHTLEVELS][MAXLIGHTSCALE] -> colormap index.
  late final List<Int32List> scaleLight;

  /// zlight[LIGHTLEVELS][MAXLIGHTZ] -> colormap index.
  late final List<Int32List> zLight;

  // --- Per-frame view (R_SetupFrame) ---
  fixed_t viewX = 0;
  fixed_t viewY = 0;
  fixed_t viewZ = 0;
  angle_t viewAngle = 0;
  fixed_t viewSin = 0;
  fixed_t viewCos = 0;

  /// extralight (weapon flash); 0 unless playsim adds it.
  int extraLight = 0;

  // --- Clip / occlusion arrays (r_plane.c). ---
  /// floorclip starts SCREENHEIGHT (viewheight); ceilingclip starts -1.
  late final Int16List ceilingClip = Int16List(screenWidth);
  late final Int16List floorClip = Int16List(screenWidth);

  /// negonearray / screenheightarray (r_things.c) — constant sprite clips.
  late final Int16List negOneArray = () {
    final a = Int16List(screenWidth);
    for (int i = 0; i < screenWidth; i++) {
      a[i] = -1;
    }
    return a;
  }();
  late final Int16List screenHeightArray = () {
    final a = Int16List(screenWidth);
    for (int i = 0; i < screenWidth; i++) {
      a[i] = viewHeight;
    }
    return a;
  }();

  void _initTextureMapping() {
    // R_InitTextureMapping, faithful to r_main.c.
    // focallength = FixedDiv(centerxfrac, finetangent[FINEANGLES/4+FIELDOFVIEW/2])
    final fixed_t focalLength =
        fixedDiv(centerXFrac, finetangent[kFineAngles ~/ 4 + kFieldOfView ~/ 2]);

    for (int i = 0; i < kFineAngles ~/ 2; i++) {
      int t;
      if (finetangent[i] > kFracUnit * 2) {
        t = -1;
      } else if (finetangent[i] < -kFracUnit * 2) {
        t = viewWidth + 1;
      } else {
        t = fixedMul(finetangent[i], focalLength);
        t = (centerXFrac - t + kFracUnit - 1) >> kFracBits;
        if (t < -1) {
          t = -1;
        } else if (t > viewWidth + 1) {
          t = viewWidth + 1;
        }
      }
      viewAngleToX[i] = t;
    }

    // Scan viewangletox[] to generate xtoviewangle[] — VANILLA ORDER: this
    // runs BEFORE the fencepost clamp below (the unclamped -1 / viewwidth+1
    // sentinels are what make the `while (viewangletox[i]>x) i++` loop stop at
    // the right place; clamping first shifts the boundary by a fine-angle).
    for (int x = 0; x <= viewWidth; x++) {
      int i = 0;
      while (viewAngleToX[i] > x) {
        i++;
      }
      xToViewAngle[x] = normAngle((i << kAngleToFineShift) - kAng90);
    }

    // Take out the fencepost cases from viewangletox.
    for (int i = 0; i < kFineAngles ~/ 2; i++) {
      if (viewAngleToX[i] == -1) {
        viewAngleToX[i] = 0;
      } else if (viewAngleToX[i] == viewWidth + 1) {
        viewAngleToX[i] = viewWidth;
      }
    }

    clipAngle = xToViewAngle[0];
  }

  void _initLightTables() {
    // R_InitLightTables (zlight) + R_ExecuteSetViewSize (scalelight).
    final int numMaps =
        colormap.numMaps >= kNumColorMaps ? kNumColorMaps : colormap.numMaps;
    scaleLight = List<Int32List>.generate(
        kLightLevels, (_) => Int32List(kMaxLightScale));
    zLight =
        List<Int32List>.generate(kLightLevels, (_) => Int32List(kMaxLightZ));

    for (int i = 0; i < kLightLevels; i++) {
      final int startMap =
          ((kLightLevels - 1 - i) * 2) * numMaps ~/ kLightLevels;
      for (int j = 0; j < kMaxLightZ; j++) {
        int scale =
            fixedDiv((screenWidth ~/ 2) * kFracUnit, (j + 1) << kLightZShift);
        scale >>= kLightScaleShift;
        int level = startMap - scale ~/ kDistMap;
        if (level < 0) level = 0;
        if (level >= numMaps) level = numMaps - 1;
        zLight[i][j] = level;
      }
    }
    for (int i = 0; i < kLightLevels; i++) {
      final int startMap =
          ((kLightLevels - 1 - i) * 2) * numMaps ~/ kLightLevels;
      for (int j = 0; j < kMaxLightScale; j++) {
        // level = startmap - j*SCREENWIDTH/viewwidth/DISTMAP; viewwidth==SW.
        int level = startMap - (j * screenWidth ~/ viewWidth) ~/ kDistMap;
        if (level < 0) level = 0;
        if (level >= numMaps) level = numMaps - 1;
        scaleLight[i][j] = level;
      }
    }
  }

  /// R_SetupFrame: copy the camera in, precompute view sin/cos. Note: the clip
  /// arrays are reset by R_ClearPlanes (PlaneRenderer.clearPlanes), exactly as
  /// vanilla — NOT here.
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
    viewSin = finesine[fineShift(viewAngle)];
    viewCos = finecosine[fineShift(viewAngle)];
  }

  /// R_PointToAngle: faithful to r_main.c.
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
      if (y >= 0) {
        if (x > y) {
          return tantoangle[slopeDiv(y, x)]; // octant 0
        } else {
          return normAngle(kAng90 - 1 - tantoangle[slopeDiv(x, y)]); // octant 1
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(-tantoangle[slopeDiv(y, x)]); // octant 8
        } else {
          return normAngle(kAng270 + tantoangle[slopeDiv(x, y)]); // octant 7
        }
      }
    } else {
      x = -x;
      if (y >= 0) {
        if (x > y) {
          return normAngle(kAng180 - 1 - tantoangle[slopeDiv(y, x)]); // oct 3
        } else {
          return normAngle(kAng90 + tantoangle[slopeDiv(x, y)]); // octant 2
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(kAng180 + tantoangle[slopeDiv(y, x)]); // octant 4
        } else {
          return normAngle(kAng270 - 1 - tantoangle[slopeDiv(x, y)]); // oct 5
        }
      }
    }
  }

  /// R_PointToDist: faithful to r_main.c.
  fixed_t pointToDist(fixed_t x, fixed_t y) {
    int dx = (toInt32(x - viewX)).abs();
    int dy = (toInt32(y - viewY)).abs();

    if (dy > dx) {
      final int t = dx;
      dx = dy;
      dy = t;
    }
    // Fix crashes in udm1.wad (vanilla guard).
    final int frac = dx != 0 ? fixedDiv(dy, dx) : 0;
    // angle = (tantoangle[frac>>DBITS]+ANG90) >> ANGLETOFINESHIFT
    final int angle =
        fineShift(normAngle(tantoangle[frac >> _dbits] + kAng90));
    final fixed_t dist = fixedDiv(dx, finesine[angle]);
    return dist;
  }

  // DBITS = FRACBITS - SLOPEBITS.
  static const int _dbits = kFracBits - kSlopeBits;
}
