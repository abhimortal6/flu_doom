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

  // --- Face state machine (st_stuff.c ST_updateFaceWidget) ---
  static const int numPainFaces = 5; // ST_NUMPAINFACES
  static const int numStraightFaces = 3; // ST_NUMSTRAIGHTFACES
  static const int faceCountMax = 5; // animation hold

  // Faces, indexed [painLevel][expression]; plus specials.
  final List<List<Patch?>> _faces = <List<Patch?>>[];
  Patch? _godFace;
  Patch? _deadFace;

  int _faceCount = 0;
  int _oldHealth = -1;

  void _loadFaces() {
    // ST_NUMPAINFACES pain levels, each with ST_NUMSTRAIGHTFACES forward +
    // turn-right + turn-left + ouch + evil-grin + rampage (vanilla packs them
    // sequentially STFST<pain><n>, STFTR<pain>0, STFTL<pain>0, STFOUCH<pain>,
    // STFEVL<pain>, STFKILL<pain>). For the static drawer we mainly need the
    // straight faces; the rest are loaded for completeness.
    for (int p = 0; p < numPainFaces; p++) {
      final List<Patch?> row = <Patch?>[];
      for (int s = 0; s < numStraightFaces; s++) {
        row.add(_gc.patch('STFST$p$s'));
      }
      row.add(_gc.patch('STFTR${p}0')); // turn right
      row.add(_gc.patch('STFTL${p}0')); // turn left
      row.add(_gc.patch('STFOUCH$p')); // ouch
      row.add(_gc.patch('STFEVL$p')); // evil grin
      row.add(_gc.patch('STFKILL$p')); // rampage
      _faces.add(row);
    }
    _godFace = _gc.patch('STFGOD0');
    _deadFace = _gc.patch('STFDEAD0');
  }

  /// Map current health to a pain level 0..4 (0 = healthiest), vanilla
  /// `ST_calcPainOffset`-ish bucketing.
  int _painLevel(int health) {
    final int h = health < 0 ? 0 : (health > 100 ? 100 : health);
    final int level = (numPainFaces - 1) - (h * numPainFaces ~/ 101);
    return level.clamp(0, numPainFaces - 1);
  }

  /// Advance the face animation one tic (ST_Ticker / ST_updateFaceWidget,
  /// simplified). Call once per game tic from the state machine's ticker. The
  /// straight-face cycle is driven by [_faceCount]; the actual glyph chosen at
  /// draw time depends on live player state (pain/attack/god/dead).
  void tick(PlayerStatus p) {
    if (_oldHealth < 0) _oldHealth = p.health;
    if (_faceCount > 0) {
      _faceCount--;
    } else {
      _faceCount = faceCountMax;
    }
    _oldHealth = p.health;
  }

  Patch? _currentFacePatch(PlayerStatus p) {
    if (p.isDead) return _deadFace;
    if (p.powerTics(PowerType.invulnerability) > 0) return _godFace;
    final int pain = _painLevel(p.health);
    final List<Patch?> row = _faces[pain];
    int col;
    if (p.damageCount > 0) {
      col = 5; // ouch
    } else if (p.attackDown) {
      col = 7; // rampage
    } else {
      col = (_faceCount ~/ 2) % numStraightFaces; // cycle straight faces
    }
    if (col >= row.length) col = 0;
    return row[col] ?? row[0];
  }

  /// Draw the full status bar overlay into [fb] for player [p].
  /// Multiplayer/deathmatch shows frags where the arsenal would be when
  /// [deathmatch] is true.
  void draw(Framebuffer fb, PlayerStatus p, {bool deathmatch = false}) {
    // Background bar.
    if (_stbar != null) _stbar.draw(fb, 0, barY);

    // Big ammo for the ready weapon (blank if the weapon uses no ammo).
    final AmmoType? at = p.readyWeaponAmmo;
    if (at != null) {
      _bigFont.drawNum(fb, ammoX, ammoY, p.ammo(at), maxDigits: 3);
    }

    // Health and armor percentages.
    _bigFont.drawPercent(fb, healthX, healthY, p.health);
    _bigFont.drawPercent(fb, armorX, armorY, p.armor);

    // Small ammo/maxammo table on the far right (clip/shell/cell/misl rows).
    const List<AmmoType> order = <AmmoType>[
      AmmoType.clip,
      AmmoType.shell,
      AmmoType.misl,
      AmmoType.cell,
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
      if (_starms != null) _starms.draw(fb, armsBgX, armsBgY);
      _drawArsenal(fb, p);
    }

    // Face.
    final Patch? face = _currentFacePatch(p);
    if (face != null) face.draw(fb, faceX, faceY);

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
      // Draw the single slot digit right-justified just past gx+digit width.
      f.drawNum(fb, gx + f.width, gy, slot, maxDigits: 1);
    }
  }

  void _drawKey(Framebuffer fb, int color, int y, PlayerStatus p) {
    // cards[]: 0..2 = cards, 3..5 = skulls. Show card icon if owned, else skull.
    final bool card = p.ownsCard(color);
    final bool skull = p.ownsCard(color + 3);
    if (!card && !skull) return;
    final int idx = card ? color : color + 3;
    if (idx < _keys.length && _keys[idx] != null) {
      _keys[idx]!.draw(fb, keyX, y);
    }
  }
}
