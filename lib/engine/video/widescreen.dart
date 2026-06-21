// True-widescreen render-width computation (Crispy/Woof technique).
//
// We keep SCREENHEIGHT = 200 and the VERTICAL projection identical to vanilla
// 4:3; only SCREENWIDTH widens so the HORIZONTAL field of view extends (you see
// more to the left/right) WITHOUT stretching the 4:3 image. Every width-derived
// render table is rebuilt for the chosen width (see RenderState); the per-column
// / per-span / light rasterization math is unchanged.
//
// Doom's 320x200 was displayed on a 4:3 CRT, i.e. with non-square pixels that
// are 1.2x taller than wide. So the "square-pixel" height of the view is
// 200 * 1.2 = 240 units, and a screen of device aspect A (width/height, in
// landscape) needs a render width of 240 * A to fill it with square geometry.

import 'framebuffer.dart' show kScreenWidth, kScreenHeight;

/// 4:3 baseline render width (vanilla SCREENWIDTH). Re-exported for callers.
const int kBaseWidth = kScreenWidth; // 320

/// Render height (SCREENHEIGHT) — NEVER changes for widescreen.
const int kRenderHeight = kScreenHeight; // 200

/// Doom's non-square pixel aspect (a pixel is 1.2x taller than it is wide).
const double kPixelAspect = 1.2;

/// Hard cap on the widescreen width: 21:9 (≈2.333). round(240 * 21/9) = 560.
/// Wider device aspects are clamped here to avoid a fish-eye FOV on ultrawide
/// phones. Even by construction.
const int kMaxWidescreenWidth = 560;

/// Compute the true-widescreen render width for a device of aspect
/// [deviceAspect] (= longer side / shorter side, i.e. the landscape aspect).
///
///   width = round(200 * 1.2 * deviceAspect)  -> snapped to EVEN
///         clamped to [kBaseWidth .. kMaxWidescreenWidth].
///
/// A 4:3 device (1.333) yields exactly [kBaseWidth] (320); 16:9 (1.777) yields
/// 426; anything at or beyond 21:9 is capped at [kMaxWidescreenWidth] (560).
/// Even width keeps centerx = width/2 exactly centered.
int widescreenWidthFor(double deviceAspect) {
  if (deviceAspect.isNaN || deviceAspect <= 0) return kBaseWidth;
  int w = (kRenderHeight * kPixelAspect * deviceAspect).round();
  if (w < kBaseWidth) w = kBaseWidth; // never narrower than 4:3
  if (w > kMaxWidescreenWidth) w = kMaxWidescreenWidth; // cap at 21:9
  if (w.isOdd) w += 1; // even -> symmetric centerx
  return w;
}

/// The landscape aspect (>= 1.0) of a device width x height, used to drive
/// [widescreenWidthFor]. Always the longer side over the shorter side so a
/// portrait phone still picks the widescreen width it will use when the game
/// fills the screen horizontally.
double landscapeAspect(double w, double h) {
  if (w <= 0 || h <= 0) return 4 / 3;
  final double lo = w < h ? w : h;
  final double hi = w < h ? h : w;
  return hi / lo;
}
