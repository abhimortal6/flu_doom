// Integration bridge: builds the play-sim's [KeyState] (the G_BuildTiccmd
// input bag) from the controls layer's live key-state.
//
// The controls layer ([EventQueueActionSink]) maintains a ref-counted set of
// held Doom keycodes (`downKeys` / `isKeyDown`) — vanilla's gamekeydown[]. This
// bridge reads those keycodes (by [DoomKey] code) and fills a [KeyState] each
// tic. It uses the SAME default keycodes the action layer emits
// (ActionKeys.keysFor), so it follows the player's intent regardless of which
// physical key (arrows / WASD / touch) produced it.

import 'package:flutter/foundation.dart' show debugPrint;

import '../../engine/input/doomkeys.dart';
import '../../engine/math/fixed.dart';
import '../../input_actions/action_dispatcher.dart';
import '../../input_actions/analog_input.dart';
import '../play/g_build.dart';

/// Translates the controls layer's held-key set into a play-sim [KeyState].
class KeyStateBridge {
  KeyStateBridge(this.sink, {AnalogInput? analog})
      : analog = analog ?? AnalogInput();

  final EventQueueActionSink sink;

  /// Analog side channel written by the touch overlay (movement stick + look
  /// drag). When no touch input is present every field is zero, so the keyboard
  /// path is byte-identical to before. Defaults to a fresh (idle) instance so
  /// keyboard-only callers (and tests) need not supply one.
  final AnalogInput analog;

  final KeyState _keys = KeyState();

  // Doom keycodes for strafe (comma/period), as emitted by the action layer.
  static const int _kStrafeLeft = 0x2c; // ','
  static const int _kStrafeRight = 0x2e; // '.'

  /// Read the current held-key set and return a freshly-filled [KeyState].
  KeyState build() {
    _keys.clear();
    bool down(int code) => sink.isKeyDown(code);

    _keys.forward = down(DoomKey.upArrow);
    _keys.backward = down(DoomKey.downArrow);
    _keys.turnLeft = down(DoomKey.leftArrow);
    _keys.turnRight = down(DoomKey.rightArrow);
    _keys.strafeLeft = down(_kStrafeLeft);
    _keys.strafeRight = down(_kStrafeRight);
    _keys.run = down(DoomKey.rShift);
    _keys.strafeModifier = down(DoomKey.rAlt);
    _keys.use = down(DoomKey.spacebar);
    _keys.attack = down(DoomKey.rCtrl);

    // Weapon select (1..7); first pressed wins. Vanilla direct select.
    for (int slot = 1; slot <= 7; slot++) {
      if (down(0x30 + slot)) {
        _keys.weapon = slot;
        break;
      }
    }

    // Touch weapon cycling: carry the prev/next request as flags. The play-sim
    // ([PlaySim.buildTiccmd]) resolves these against the live inventory into a
    // concrete weapon slot before the cmd is built. We do NOT resolve here (the
    // bridge has no player). Direct 1..7 select above takes precedence: if a
    // number key is also down this tic, leave the cycle flags off.
    if (_keys.weapon == 0) {
      _keys.prevWeapon = down(DoomKey.minus);
      _keys.nextWeapon = down(DoomKey.equals);
    }

    // Per-tic confirmation that a momentary tap survived to be sampled. Logs
    // only on the tics where USE / weapon-cycle keys are observed down, so it
    // stays quiet during normal play. grep `adb logcat` for `[touch]`.
    if (kTouchInputDebugLog) {
      if (_keys.use) debugPrint('[touch] tic sampled USE down');
      if (down(DoomKey.minus)) debugPrint('[touch] tic sampled PREV weapon');
      if (down(DoomKey.equals)) debugPrint('[touch] tic sampled NEXT weapon');
      if (_keys.weapon != 0) {
        debugPrint('[touch] tic sampled weapon slot ${_keys.weapon}');
      }
    }

    // Analog channel (touch movement stick + drag-to-look). FRACUNIT-scaled
    // deflection for the stick; mousex-equivalent for the look. The look delta
    // is consumed (cleared) here so it is applied exactly once per tic, like
    // vanilla `mousex = 0`.
    _keys.analogForward = analog.forwardFixed(kFracUnit);
    _keys.analogSide = analog.sideFixed(kFracUnit);
    _keys.analogRun = analog.run;
    _keys.analogTurn = analog.takeMouseX();

    return _keys;
  }
}
