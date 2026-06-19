// Integration bridge: builds the play-sim's [KeyState] (the G_BuildTiccmd
// input bag) from the controls layer's live key-state.
//
// The controls layer ([EventQueueActionSink]) maintains a ref-counted set of
// held Doom keycodes (`downKeys` / `isKeyDown`) — vanilla's gamekeydown[]. This
// bridge reads those keycodes (by [DoomKey] code) and fills a [KeyState] each
// tic. It uses the SAME default keycodes the action layer emits
// (ActionKeys.keysFor), so it follows the player's intent regardless of which
// physical key (arrows / WASD / touch) produced it.

import '../../engine/input/doomkeys.dart';
import '../../input_actions/action_dispatcher.dart';
import '../play/g_build.dart';

/// Translates the controls layer's held-key set into a play-sim [KeyState].
class KeyStateBridge {
  KeyStateBridge(this.sink);

  final EventQueueActionSink sink;

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

    // Weapon select (1..7); first pressed wins.
    for (int slot = 1; slot <= 7; slot++) {
      if (down(0x30 + slot)) {
        _keys.weapon = slot;
        break;
      }
    }

    return _keys;
  }
}
