// Doom key codes, ported from Chocolate Doom src/doomkeys.h.
//
// These are the values placed in `event_t.data1` for keydown/keyup events.
// The playsim, menu, and intermission code all compare against these.

abstract final class DoomKey {
  static const int rightArrow = 0xae;
  static const int leftArrow = 0xac;
  static const int upArrow = 0xad;
  static const int downArrow = 0xaf;
  static const int escape = 27;
  static const int enter = 13;
  static const int tab = 9;

  static const int f1 = 0x80 + 0x3b;
  static const int f2 = 0x80 + 0x3c;
  static const int f3 = 0x80 + 0x3d;
  static const int f4 = 0x80 + 0x3e;
  static const int f5 = 0x80 + 0x3f;
  static const int f6 = 0x80 + 0x40;
  static const int f7 = 0x80 + 0x41;
  static const int f8 = 0x80 + 0x42;
  static const int f9 = 0x80 + 0x43;
  static const int f10 = 0x80 + 0x44;
  static const int f11 = 0x80 + 0x57;
  static const int f12 = 0x80 + 0x58;

  static const int backspace = 0x7f;
  static const int pause = 0xff;
  static const int equals = 0x3d;
  static const int minus = 0x2d;

  static const int rShift = 0x80 + 0x36;
  static const int rCtrl = 0x80 + 0x1d;
  static const int rAlt = 0x80 + 0x38;
  static const int lAlt = rAlt;
  static const int capsLock = 0x80 + 0x3a;

  static const int home = 0x80 + 0x47;
  static const int end = 0x80 + 0x4f;
  static const int pgUp = 0x80 + 0x49;
  static const int pgDn = 0x80 + 0x51;
  static const int ins = 0x80 + 0x52;
  static const int del = 0x80 + 0x53;

  static const int spacebar = 0x20;

  /// ASCII letters/digits are their literal lowercase ASCII codes in Doom.
  static int ascii(String ch) => ch.codeUnitAt(0);
}
