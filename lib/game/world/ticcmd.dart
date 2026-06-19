// tic_cmd, ported faithfully from Chocolate Doom src/d_ticcmd.h.
//
// A ticcmd_t is the complete set of player intentions for a single 35Hz tic.
// It is the bridge between input (which builds it via G_BuildTiccmd) and the
// play simulation (which consumes it in P_PlayerThink). Pure data.
//
// Field sizes in vanilla:
//   signed char  forwardmove;   // *2048 for move
//   signed char  sidemove;      // *2048 for move
//   short        angleturn;     // <<16 for view angle delta
//   short        consistancy;   // checks for net game
//   byte         chatchar;
//   byte         buttons;
//   byte         buttons2;      // (Strife / unused in Doom; kept for parity)
//   int          inventory;     // (Strife; kept for parity, unused in Doom)
//
// We keep the same field names (Dart camelCase where it matters) and the same
// semantics. Values are plain Dart ints; callers are responsible for keeping
// them in the vanilla byte/short ranges if bit-exact net consistancy matters.

/// A single tic's worth of player commands. Vanilla `ticcmd_t`.
class TicCmd {
  TicCmd();

  /// Forward/backward thrust (signed). Vanilla `forwardmove`; multiplied by
  /// 2048 (>>8 of FRACUNIT) when applied to player momentum.
  int forwardMove = 0;

  /// Strafe thrust (signed). Vanilla `sidemove`.
  int sideMove = 0;

  /// View angle delta for this tic (signed short). Applied as
  /// `player->angle += cmd->angleturn << 16`. Vanilla `angleturn`.
  int angleTurn = 0;

  /// Net-game consistency check value. Vanilla `consistancy` (sic).
  int consistancy = 0;

  /// Pending chat character. Vanilla `chatchar`.
  int chatChar = 0;

  /// Action button bitfield (BT_*). Vanilla `buttons`.
  int buttons = 0;

  /// Secondary button bitfield (used by Strife; unused in Doom, kept for
  /// struct parity). Vanilla `buttons2`.
  int buttons2 = 0;

  /// Inventory action (Strife; unused in Doom, kept for parity). Vanilla
  /// `inventory`.
  int inventory = 0;

  /// Reset all fields to zero (cheaper than reallocating each tic).
  void clear() {
    forwardMove = 0;
    sideMove = 0;
    angleTurn = 0;
    consistancy = 0;
    chatChar = 0;
    buttons = 0;
    buttons2 = 0;
    inventory = 0;
  }

  /// Copy [other] into this command in place.
  void copyFrom(TicCmd other) {
    forwardMove = other.forwardMove;
    sideMove = other.sideMove;
    angleTurn = other.angleTurn;
    consistancy = other.consistancy;
    chatChar = other.chatChar;
    buttons = other.buttons;
    buttons2 = other.buttons2;
    inventory = other.inventory;
  }
}

// --- Button bits (BT_*), from d_event.h ---

/// Press "use" button.
const int btAttack = 1;
/// Press "fire" button.
const int btUse = 2;

/// Flag: weapon change is requested; the new weapon is in the masked field.
const int btChangeWeapon = 4;

/// Mask to extract the weapon number from [TicCmd.buttons].
const int btWeaponMask = 8 + 16 + 32;

/// Shift to extract the weapon number from [TicCmd.buttons].
const int btWeaponShift = 3;

/// Special-event flags (top bits of [TicCmd.buttons]). BTS_*.
const int btSpecial = 128;
const int btSpecialMask = 3;

/// BTS_*: pause game.
const int btsPause = 1;
/// BTS_*: save game.
const int btsSaveGame = 2;

/// Mask/shift to pick a save slot from the special button. BTS_SAVEMASK/SHIFT.
const int btsSaveMask = 4 + 8 + 16;
const int btsSaveShift = 2;
