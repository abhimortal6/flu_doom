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

  /// Look sensitivity multiplier (1.0 = baseline mouse-like feel). Configured
  /// from [OverlaySettings.lookSensitivity] by the mount layer.
  double lookSensitivity = 1.0;

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
  /// equivalent and clear it. The scaling mirrors g_game.c:
  ///   `mousex = rawDelta * (mouseSensitivity + 5) / 10`
  /// with [lookSensitivity] standing in for the user sensitivity (baseline
  /// 1.0 ≈ Doom default mouseSensitivity 5 -> factor 1.0). The builder then
  /// applies `angleturn -= mousex * 0x8` exactly as vanilla mouse-look does.
  ///
  /// Returns an integer `mousex`-like value (truncated toward zero like the C
  /// integer arithmetic).
  int takeMouseX() {
    final double raw = takeLookDeltaX();
    if (raw == 0.0) return 0;
    final double scaled = raw * lookSensitivity;
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
