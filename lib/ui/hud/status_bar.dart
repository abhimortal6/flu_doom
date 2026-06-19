// Status bar (st_stuff.c port): the STBAR overlay with health/armor/ammo, the
// big ammo readout, the arsenal (STARMS), keycards, frag count, and the
// animated face (STFST/STFB/STFOUCH/STFEVL/STFKILL/STFGOD/STFDEAD).
//
// Layout constants are taken verbatim from Chocolate Doom st_stuff.c (the
// ST_*X / ST_*Y #defines). The bar occupies the bottom 32 rows (y 168..199) of
// the 320x200 screen. Values are read through the injected [PlayerStatus].

import '../../engine/video/framebuffer.dart';
import '../../engine/video/patch.dart';
import '../../game/state/interfaces.dart';
import 'fonts.dart';
import 'graphics_cache.dart';
import 'patch_draw.dart';

/// Status bar drawer + face state machine.
class StatusBar {
  StatusBar(this._gc) {
    _bigFont = NumberFont.big(_gc);
    _smallFont = NumberFont.smallYellow(_gc);
    _greyFont = NumberFont.grey(_gc);
    _stbar = _gc.patch('STBAR');
    _starms = _gc.patch('STARMS');
    for (int i = 0; i < 6; i++) {
      _keys.add(_gc.patch('STKEYS$i'));
    }
    _loadFaces();
  }

  final GraphicsCache _gc;
  late final NumberFont _bigFont;
  late final NumberFont _smallFont;
  late final NumberFont _greyFont;

  // The background bar and arsenal frame.
  late final Patch? _stbar;
  late final Patch? _starms;

  // Key card icons (STKEYS0..5).
  final List<Patch?> _keys = <Patch?>[];

  // --- Layout constants (st_stuff.c) ---
  /// Y of the top of the status bar (ST_Y = SCREENHEIGHT - ST_HEIGHT, 200-32).
  static const int barY = 168;
  static const int barHeight = 32;

  // Big ammo number (right edge x), health, armor.
  static const int ammoX = 44;
  static const int ammoY = 171;
  static const int healthX = 90;
  static const int healthY = 171;
  static const int armorX = 221;
  static const int armorY = 171;

  // Small ammo / maxammo columns (ST_AMMOX/MAXAMMOX).
  static const int smallAmmoX = 288;
  static const int smallMaxAmmoX = 314;
  static const int ammoRow0Y = 173; // ST_AMMO0Y
  static const int ammoRowStep = 6; // ST_AMMODELTA

  // Arsenal frame + numbers (ST_ARMSX/Y, ST_ARMSXSPACE/YSPACE).
  static const int armsX = 111;
  static const int armsY = 172;
  static const int armsXSpace = 12;
  static const int armsYSpace = 10;
  static const int armsBgX = 104; // STARMS background origin
  static const int armsBgY = 168;

  // Face (ST_FACESX/Y) and frag count.
  static const int faceX = 143;
  static const int faceY = 168;
  static const int fragsX = 138;
  static const int fragsY = 171;

  // Keys (ST_KEY0X.. column on the right).
  static const int keyX = 239;
  static const int key0Y = 171;
  static const int key1Y = 181;
  static const int key2Y = 191;

  // --- Face state machine (st_stuff.c ST_updateFaceWidget / ST_calcPainOffset),
  //     ported faithfully from Chocolate Doom st_stuff.c. ---
  static const int kTicRate = 35; // TICRATE
  static const int stNumPainFaces = 5; // ST_NUMPAINFACES
  static const int stNumStraightFaces = 3; // ST_NUMSTRAIGHTFACES
  static const int stNumTurnFaces = 2; // ST_NUMTURNFACES
  static const int stNumSpecialFaces = 3; // ST_NUMSPECIALFACES
  static const int stFaceStride =
      stNumStraightFaces + stNumTurnFaces + stNumSpecialFaces; // 8
  static const int stNumExtraFaces = 2; // ST_NUMEXTRAFACES
  static const int stNumFaces =
      stFaceStride * stNumPainFaces + stNumExtraFaces; // 42
  static const int stTurnOffset = stNumStraightFaces; // 3
  static const int stOuchOffset = stTurnOffset + stNumTurnFaces; // 5
  static const int stEvilGrinOffset = stOuchOffset + 1; // 6
  static const int stRampageOffset = stEvilGrinOffset + 1; // 7
  static const int stGodFace = stNumPainFaces * stFaceStride; // 40
  static const int stDeadFace = stGodFace + 1; // 41
  static const int stEvilGrinCount = 2 * kTicRate; // ST_EVILGRINCOUNT
  static const int stStraightFaceCount = kTicRate ~/ 2; // ST_STRAIGHTFACECOUNT
  static const int stTurnCount = 1 * kTicRate; // ST_TURNCOUNT
  static const int stOuchCount = 1 * kTicRate; // ST_OUCHCOUNT
  static const int stRampageDelay = 2 * kTicRate; // ST_RAMPAGEDELAY
  static const int stMuchPain = 20; // ST_MUCHPAIN

  // Flat face table (vanilla `faces[ST_NUMFACES]`).
  final List<Patch?> _faces = <Patch?>[];

  // ST_updateFaceWidget persistent state.
  int _faceIndex = 0; // st_faceindex
  int _faceCount = 0; // st_facecount
  int _priority = 0; // priority
  int _lastAttackDown = -1; // lastattackdown
  int _oldHealth = -1; // st_oldhealth
  bool _started = false;

  // M_Random for the face (vanilla rndtable + a private index distinct from
  // P_Random). ST_updateFaceWidget uses M_Random.
  int _rndIndex = 0;
  int _mRandom() {
    _rndIndex = (_rndIndex + 1) & 0xff;
    return _rndTable[_rndIndex];
  }

  void _loadFaces() {
    // Exactly ST_loadGraphics' face loop:
    //   for (i=0;i<ST_NUMPAINFACES;i++) {
    //     for (j=0;j<ST_NUMSTRAIGHTFACES;j++) faces[fn++]=STFST i j;
    //     faces[fn++]=STFTR i 0;  // turn right
    //     faces[fn++]=STFTL i 0;  // turn left
    //     faces[fn++]=STFOUCH i;  // ouch
    //     faces[fn++]=STFEVL i;   // evil grin
    //     faces[fn++]=STFKILL i;  // pissed off
    //   }
    //   faces[fn++]=STFGOD0; faces[fn++]=STFDEAD0;
    for (int i = 0; i < stNumPainFaces; i++) {
      for (int j = 0; j < stNumStraightFaces; j++) {
        _faces.add(_gc.patch('STFST$i$j'));
      }
      _faces.add(_gc.patch('STFTR${i}0'));
      _faces.add(_gc.patch('STFTL${i}0'));
      _faces.add(_gc.patch('STFOUCH$i'));
      _faces.add(_gc.patch('STFEVL$i'));
      _faces.add(_gc.patch('STFKILL$i'));
    }
    _faces.add(_gc.patch('STFGOD0'));
    _faces.add(_gc.patch('STFDEAD0'));
  }

  /// ST_calcPainOffset. Caches on health like vanilla.
  int _lastCalc = 0;
  int _oldCalcHealth = -1;
  int _calcPainOffset(int health) {
    final int h = health > 100 ? 100 : health;
    if (h != _oldCalcHealth) {
      _lastCalc =
          stFaceStride * ((100 - h) * stNumPainFaces ~/ 101);
      _oldCalcHealth = h;
    }
    return _lastCalc;
  }

  /// ST_updateFaceWidget — strict port. Called once per tic from
  /// [tick]. We lack the attacker direction (needs the attacker mobj), so the
  /// "turn toward damage source" branch falls back to the random look cycle;
  /// every other branch (priority ladder, evil grin on weapon pickup proxy,
  /// rampage, god, dead, ouch, straight-face look-left/right/forward random
  /// cycle) is faithful, giving the vanilla cadence (not a per-tic flicker).
  void _updateFaceWidget(PlayerStatus p) {
    final int health = p.health;
    if (!_started) {
      _oldHealth = health;
      _started = true;
    }

    bool doEvilGrin = false; // we have no weapon-pickup signal; stays false

    if (_priority < 10) {
      // dead
      if (health <= 0) {
        _priority = 9;
        _faceIndex = stDeadFace;
        _faceCount = 1;
      }
    }

    if (_priority < 9) {
      if (p.bonusCount != 0) {
        // picking up a bonus -> evil grin (vanilla checks weaponowned changes;
        // bonuscount is the closest available pickup cue).
        doEvilGrin = true;
      }
      if (doEvilGrin) {
        _priority = 8;
        _faceCount = stEvilGrinCount;
        _faceIndex = _calcPainOffset(health) + stEvilGrinOffset;
      }
    }

    if (_priority < 8) {
      if (p.damageCount != 0 && _oldHealth - health > stMuchPain) {
        // ouch! (took a lot of damage)
        _priority = 7;
        _faceCount = stTurnCount;
        _faceIndex = _calcPainOffset(health) + stOuchOffset;
      } else if (p.damageCount != 0) {
        // being hurt: look toward the attacker. Without the attacker angle we
        // pick a random turn (vanilla turns toward the damage direction).
        _priority = 7;
        _faceCount = stTurnCount;
        final int r = _mRandom();
        final int dir = r < 128 ? 0 : 1;
        _faceIndex =
            _calcPainOffset(health) + stTurnOffset + dir;
      }
    }

    if (_priority < 7) {
      // getting hurt because of your own damn stupidity / rampage
      if (p.attackDown) {
        if (_lastAttackDown == -1) {
          _lastAttackDown = stRampageDelay;
        } else if (--_lastAttackDown == 0) {
          _priority = 5;
          _faceIndex = _calcPainOffset(health) + stRampageOffset;
          _faceCount = 1;
          _lastAttackDown = 1;
        }
      } else {
        _lastAttackDown = -1;
      }
    }

    if (_priority < 6) {
      // invulnerability
      if (p.powerTics(PowerType.invulnerability) != 0) {
        _priority = 4;
        _faceIndex = stGodFace;
        _faceCount = 1;
      }
    }

    // look left or right or straight ahead (the idle random cycle)
    if (_faceCount == 0) {
      final int r = _mRandom();
      _faceIndex = _calcPainOffset(health) + (r % 3);
      _faceCount = stStraightFaceCount;
      _priority = 0;
    }

    _faceCount--;
    _oldHealth = health;
  }

  /// ST_Ticker (face portion). Call once per game tic.
  void tick(PlayerStatus p) {
    _updateFaceWidget(p);
  }

  Patch? _currentFacePatch() {
    int idx = _faceIndex;
    if (idx < 0) idx = 0;
    if (idx >= _faces.length) idx = 0;
    return _faces[idx] ?? (_faces.isNotEmpty ? _faces[0] : null);
  }

  // M_Random rndtable (vanilla m_random.c) — 256 bytes.
  static const List<int> _rndTable = <int>[
    0, 8, 109, 220, 222, 241, 149, 107, 75, 248, 254, 140, 16, 66, //
    74, 21, 211, 47, 80, 242, 154, 27, 205, 128, 161, 89, 77, 36, //
    95, 110, 85, 48, 212, 140, 211, 249, 22, 79, 200, 50, 28, 188, //
    52, 140, 202, 120, 68, 145, 62, 70, 184, 190, 91, 197, 152, 224, //
    149, 104, 25, 178, 252, 182, 202, 182, 141, 197, 4, 81, 181, 242, //
    145, 42, 39, 227, 156, 198, 225, 193, 219, 93, 122, 175, 249, 0, //
    175, 143, 70, 239, 46, 246, 163, 53, 163, 109, 168, 135, 2, 235, //
    25, 92, 20, 145, 138, 77, 69, 166, 78, 176, 173, 212, 166, 113, //
    94, 161, 41, 50, 239, 49, 111, 164, 70, 60, 2, 37, 171, 75, //
    136, 156, 11, 56, 42, 146, 138, 229, 73, 146, 77, 61, 98, 196, //
    135, 106, 63, 197, 195, 86, 96, 203, 113, 101, 170, 247, 181, 113, //
    80, 250, 108, 7, 255, 237, 129, 226, 79, 107, 112, 166, 103, 241, //
    24, 223, 239, 120, 198, 58, 60, 82, 128, 3, 184, 66, 143, 224, //
    145, 224, 81, 206, 163, 45, 63, 90, 168, 114, 59, 33, 159, 95, //
    28, 139, 123, 98, 125, 196, 15, 70, 194, 253, 54, 14, 109, 226, //
    71, 17, 161, 93, 186, 87, 244, 138, 20, 52, 123, 251, 26, 36, //
    17, 46, 52, 231, 232, 76, 31, 221, 84, 37, 216, 165, 212, 106, //
    197, 242, 98, 43, 39, 175, 254, 145, 190, 84, 118, 222, 187, 136, //
    120, 163, 236, 249
  ];

  /// Draw the full status bar overlay into [fb] for player [p].
  /// Multiplayer/deathmatch shows frags where the arsenal would be when
  /// [deathmatch] is true.
  void draw(Framebuffer fb, PlayerStatus p, {bool deathmatch = false}) {
    // Background bar.
    if (_stbar != null) _stbar.drawV(fb, 0, barY);

    // Big ammo for the ready weapon (blank if the weapon uses no ammo).
    final AmmoType? at = p.readyWeaponAmmo;
    if (at != null) {
      _bigFont.drawNum(fb, ammoX, ammoY, p.ammo(at), maxDigits: 3);
    }

    // Health and armor percentages.
    _bigFont.drawPercent(fb, healthX, healthY, p.health);
    _bigFont.drawPercent(fb, armorX, armorY, p.armor);

    // Small ammo/maxammo table on the far right. Vanilla row order matches the
    // ammotype_t enum: clip, shell, cell, misl (rows at Y 173/179/185/191).
    const List<AmmoType> order = <AmmoType>[
      AmmoType.clip,
      AmmoType.shell,
      AmmoType.cell,
      AmmoType.misl,
    ];
    for (int i = 0; i < order.length; i++) {
      final int rowY = ammoRow0Y + i * ammoRowStep;
      _smallFont.drawNum(fb, smallAmmoX, rowY, p.ammo(order[i]), maxDigits: 3);
      _smallFont.drawNum(fb, smallMaxAmmoX, rowY, p.maxAmmo(order[i]),
          maxDigits: 3);
    }

    if (deathmatch) {
      // Frag count where the arsenal sits.
      _bigFont.drawNum(fb, fragsX, fragsY, p.fragCount, maxDigits: 2);
    } else {
      // Arsenal frame + weapon numbers (weapons 2..7 shown in a 3x2 grid).
      if (_starms != null) _starms.drawV(fb, armsBgX, armsBgY);
      _drawArsenal(fb, p);
    }

    // Face.
    final Patch? face = _currentFacePatch();
    if (face != null) face.drawV(fb, faceX, faceY);

    // Keycards (blue/yellow/red). Vanilla shows skull OR card in one slot;
    // we show whichever the player owns, card taking precedence.
    _drawKey(fb, 0, key0Y, p); // blue
    _drawKey(fb, 1, key1Y, p); // yellow
    _drawKey(fb, 2, key2Y, p); // red
  }

  void _drawArsenal(Framebuffer fb, PlayerStatus p) {
    // STARMS shows weapon slots 2..7 in a 3-wide, 2-tall grid (vanilla
    // arms[6]). Slot numbers are 2..7; ownership picks bright vs grey glyph.
    for (int i = 0; i < 6; i++) {
      final int slot = i + 2;
      final int col = i % 3;
      final int rowIdx = i ~/ 3;
      final int gx = armsX + col * armsXSpace;
      final int gy = armsY + rowIdx * armsYSpace;
      final NumberFont f = p.ownsWeapon(slot) ? _smallFont : _greyFont;
      // Vanilla w_arms[i] is right-justified at ST_ARMSX + col*XSPACE
      // (STlib_drawNum: rightmost digit's right edge == n->x).
      f.drawNum(fb, gx, gy, slot, maxDigits: 1);
    }
  }

  void _drawKey(Framebuffer fb, int color, int y, PlayerStatus p) {
    // cards[]: 0..2 = cards, 3..5 = skulls. Show card icon if owned, else skull.
    final bool card = p.ownsCard(color);
    final bool skull = p.ownsCard(color + 3);
    if (!card && !skull) return;
    final int idx = card ? color : color + 3;
    if (idx < _keys.length && _keys[idx] != null) {
      _keys[idx]!.drawV(fb, keyX, y);
    }
  }
}
