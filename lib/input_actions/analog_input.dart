// Analog input channel for the PUBG-style touch controls.
//
// The discrete GameAction -> Doom-keycode path (action_dispatcher.dart) only
// carries on/off key state, which is enough for buttons but NOT for an analog
// movement stick or a drag-to-look "camera". This holder is the side channel
// the touch layer WRITES and the play-sim bridge (key_state_bridge.dart) READS
// each tic, so analog magnitudes reach G_BuildTiccmd faithfully.
//
// Semantics mirror vanilla g_game.c's joystick + mouse inputs:
//   * [forwardMove] / [sideMove] are normalized stick deflection in [-1, 1].
//     Forward is +1 (push up), strafe-right is +1 (push right). These map to
//     `joyymove`/`joyxmove` (scaled to FRACUNIT) in the builder.
//   * [run] is true at/near full deflection (the run speed tier).
//   * [lookDeltaX] is the ACCUMULATED horizontal drag distance (in logical
//     pixels) for the current tic — the analog of vanilla `mousex` before the
//     `mousex = ev->data2*(mouseSensitivity+5)/10` scaling. The bridge converts
//     it to an angleturn delta and then CLEARS it (`mousex = 0` each tic).
//
// Keyboard is unaffected: when no touch input is present, all fields stay at
// their zero defaults and the builder produces byte-identical ticcmds.

import 'dart:math' as math;

/// Base drag-to-look gain: how many vanilla `mousex` units one logical pixel of
/// finger travel is worth, BEFORE the user [lookSensitivity] multiplier.
///
/// WHY THIS EXISTS (root-cause fix for "look turn far too slow"):
/// Vanilla's `mousex = data2*(mouseSensitivity+5)/10` consumes *raw mouse
/// counts* — a real mouse emits thousands of counts per swipe. A finger drag,
/// by contrast, is measured in coarse *logical pixels*: a whole-screen swipe is
/// only a few hundred logical px, and it arrives spread across 3-4 of the 35Hz
/// tics, so per-tic travel is ~15-30 px. Feeding that 1:1 into `mousex`
/// (`mousex = px`) made even the 4x slider crawl. This constant amplifies
/// finger-px into mouse-count-like units so sensitivity 1.0 already feels brisk.
///
/// Tuning: `angleturn = px * kLookBaseGain * lookSensitivity * 8` (the *8 is
/// vanilla `angleturn -= mousex*0x8`). A full 360° turn is 0x4000 (16384) of
/// summed angleturn. With kLookBaseGain = 6.0 at the default sensitivity 2.0:
///   * a moderate ~50px/tic swipe -> mousex 600 -> angleturn 4800 (~105°/tic),
///     so a normal swipe sweeps the view briskly (PUBG-like);
///   * at the MAX slider (8.0x) -> mousex 2400 -> angleturn 19200/tic, a very
///     fast ceiling the user can dial back if they want.
/// This is the ONE knob to nudge if the on-device feel needs more/less: raise
/// for faster, lower for slower. The slider (lookSensitivity, 0.5x..8x)
/// multiplies it (default 2.0x).
const double kLookBaseGain = 6.0;

/// Mutable analog input bag shared between the touch overlay (writer) and the
/// per-tic key-state bridge (reader). Not threaded; all access is on the UI /
/// game-loop thread.
class AnalogInput {
  AnalogInput();

  /// Normalized forward/back stick deflection in [-1, 1] (+1 = forward/up).
  double forwardMove = 0.0;

  /// Normalized strafe stick deflection in [-1, 1] (+1 = strafe right).
  double sideMove = 0.0;

  /// True when the stick is at/near full deflection: selects the run tier.
  bool run = false;

  /// Accumulated horizontal look-drag this tic, in logical pixels. Positive =
  /// drag right (turn right / clockwise). Reset each tic by [takeLookDeltaX].
  double lookDeltaX = 0.0;

  /// Look sensitivity multiplier (2.0 = baseline brisk feel). Configured
  /// from [OverlaySettings.lookSensitivity] by the mount layer.
  double lookSensitivity = 2.0;

  /// Set the movement stick vector. [fwd] and [side] are normalized in [-1, 1]
  /// (+fwd = forward, +side = strafe right). [running] marks the run tier.
  void setStick(double fwd, double side, {required bool running}) {
    forwardMove = fwd.clamp(-1.0, 1.0).toDouble();
    sideMove = side.clamp(-1.0, 1.0).toDouble();
    run = running;
  }

  /// Clear the movement stick (finger lifted).
  void clearStick() {
    forwardMove = 0.0;
    sideMove = 0.0;
    run = false;
  }

  /// Accumulate a horizontal look-drag delta (logical pixels) for this tic.
  void addLookDelta(double dx) {
    lookDeltaX += dx;
  }

  /// Read and CLEAR the accumulated look delta (vanilla consumes mousex once
  /// per tic then zeroes it).
  double takeLookDeltaX() {
    final double v = lookDeltaX;
    lookDeltaX = 0.0;
    return v;
  }

  /// Reset everything (panic release on focus loss / settings open).
  void reset() {
    clearStick();
    lookDeltaX = 0.0;
  }

  /// True if any analog input is currently active (used to decide whether to
  /// touch the analog ticcmd path at all).
  bool get isActive =>
      forwardMove != 0.0 ||
      sideMove != 0.0 ||
      lookDeltaX != 0.0;

  /// Convert the accumulated look delta into a raw vanilla-style `mousex`
  /// equivalent and clear it. Touch-adapted scaling:
  ///   `mousex = rawLogicalPx * kLookBaseGain * lookSensitivity`
  /// where [kLookBaseGain] bridges coarse finger-logical-pixels into the
  /// mouse-count-like units vanilla's `mousex` expects (see kLookBaseGain), and
  /// [lookSensitivity] is the user slider (2.0 = default brisk feel). The
  /// builder then applies `angleturn -= mousex * 0x8` exactly as vanilla
  /// mouse-look does.
  ///
  /// NOTE on truncation: we scale BEFORE truncating, so the base-gain
  /// amplification happens first — a small per-event/per-tic px count can no
  /// longer round to zero the way a bare `px * (sens<1)` could.
  ///
  /// Returns an integer `mousex`-like value (truncated toward zero like the C
  /// integer arithmetic).
  int takeMouseX() {
    final double raw = takeLookDeltaX();
    if (raw == 0.0) return 0;
    final double scaled = raw * kLookBaseGain * lookSensitivity;
    // Truncate toward zero (C integer cast semantics).
    return scaled.truncate();
  }

  /// Returns the normalized [forwardMove] clamped and quantized to a
  /// FRACUNIT-scaled fixed value in [-FRACUNIT, FRACUNIT], like vanilla
  /// `joyymove` after sensitivity scaling. Sign convention matches the stick
  /// (+1 forward).
  int forwardFixed(int fracUnit) =>
      (forwardMove.clamp(-1.0, 1.0) * fracUnit).round();

  /// Same as [forwardFixed] for the strafe axis (+1 strafe right).
  int sideFixed(int fracUnit) =>
      (sideMove.clamp(-1.0, 1.0) * fracUnit).round();

  /// Magnitude of the current stick deflection (0..~1.41 for diagonals,
  /// usually clamped to 1.0 by the caller).
  double get magnitude => math.sqrt(forwardMove * forwardMove + sideMove * sideMove);
}
