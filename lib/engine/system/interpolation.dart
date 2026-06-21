// Frame interpolation (Crispy/Woof "uncapped framerate" smooth motion) — the
// RENDER-ONLY state + math. The 35Hz simulation stays byte-identical; only what
// the renderer draws is linearly interpolated between the previous tic and the
// current tic by a per-frame fractional factor.
//
// CRITICAL INVARIANT: nothing here feeds back into the sim. The sim writes the
// real 35Hz `old*`/current fields; this module only blends them at render time.
// At [renderFrac] == FRACUNIT (interpolation OFF, paused/menu, or old==new) every
// lerp returns the CURRENT value exactly, so the rendered frame is byte-identical
// to the non-interpolated path (the render golden holds).
//
// Reference: Crispy Doom r_main.c R_InterpolateView / R_RestoreInterpolations and
// the fractionaltic handling; Woof i_video.c.

import '../math/angle.dart';
import '../math/fixed.dart';

/// Shared, render-only interpolation state. Owned by [World] so both the play
/// simulation (which sets [active]) and the render path (which reads
/// [renderFrac]) reach the same instance. The integration layer (doom_game)
/// refreshes [frac]/[active]/[enabled] once per frame BEFORE rendering.
class InterpolationState {
  /// The 'Smooth motion' graphics toggle. Default ON. When false the renderer
  /// always draws CURRENT positions (renderFrac == FRACUNIT) — exactly today's
  /// behaviour and the render-golden path.
  bool enabled = true;

  /// Inter-tic fraction in 16.16 fixed-point, in [0, FRACUNIT]. The wall-clock
  /// time elapsed since the last 35Hz tic divided by one tic's duration.
  /// Computed by the game loop and copied in by the integration each frame.
  fixed_t frac = 0;

  /// True only while the simulation is ADVANCING (active gameplay). When the sim
  /// is frozen (paused / menu / title), interpolation is disabled for that frame
  /// so the view does not jitter between two identical tics (Crispy freezes the
  /// interpolated view while paused).
  bool active = false;

  /// The effective fraction the renderer interpolates with: the live [frac] only
  /// when interpolation is enabled AND the sim is advancing; otherwise FRACUNIT
  /// ("draw the current tic exactly"). FRACUNIT makes every [lerpFixed] /
  /// [lerpAngle] return the NEW value, i.e. byte-identical to no interpolation.
  fixed_t get renderFrac => (enabled && active) ? frac : kFracUnit;

  /// Whether the renderer should actually blend this frame (a tiny optimisation
  /// + the guard that keeps the golden path untouched).
  bool get interpolating => renderFrac != kFracUnit;
}

/// Fixed-point linear interpolation: a + (b - a) * frac, all 16.16.
/// At frac == 0 returns a; at frac == FRACUNIT returns b exactly.
fixed_t lerpFixed(fixed_t a, fixed_t b, fixed_t frac) =>
    toInt32(a + fixedMul(toInt32(b - a), frac));

/// Angle (BAM) interpolation that handles wrap-around correctly by interpolating
/// the SIGNED delta. `(int32)(b - a)` is the shortest signed step from a to b
/// (e.g. a just below 0xFFFFFFFF -> b just above 0 yields a small positive
/// delta, not a near-full-circle backspin). result = a + delta * frac.
///
/// At frac == FRACUNIT returns b exactly (a + (b - a) == b mod 2^32).
angle_t lerpAngle(angle_t a, angle_t b, fixed_t frac) {
  // Signed 32-bit delta = shortest path from a to b.
  final int delta = toInt32(b - a);
  final int step = fixedMul(delta, frac);
  return normAngle(a + step);
}
