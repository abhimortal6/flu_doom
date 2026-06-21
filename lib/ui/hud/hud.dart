// Heads-up display (hu_stuff.c port): the player message line at the top of
// the screen and an optional fullscreen status overlay (health/ammo) used when
// the status bar is hidden (vanilla "fullscreen HUD", screenblocks 11+).
//
// Messages are posted via [postMessage] (HU_PlayerMessage equivalent) and hold
// for HU_MSGTIMEOUT tics before fading. The HUD font is the STCFN set.

import '../../engine/video/framebuffer.dart';
import '../../game/state/interfaces.dart';
import 'fonts.dart';
import 'graphics_cache.dart';

/// HUD / message subsystem.
class Hud {
  Hud(GraphicsCache gc) : font = HudFont.stcfn(gc);

  /// The HUD text font.
  final HudFont font;

  /// Message hold time in tics (HU_MSGTIMEOUT = 4 * TICRATE).
  static const int messageTimeout = 4 * 35;

  /// Top-left of the message line (vanilla HU_MSGX/HU_MSGY = 0, 0).
  static const int messageX = 0;
  static const int messageY = 0;

  String _message = '';
  int _messageTics = 0;

  /// Whether a message is currently visible.
  bool get hasMessage => _messageTics > 0 && _message.isNotEmpty;

  /// The current message text (empty if none).
  String get message => _message;

  /// Post a player message (HU_PlayerMessage). It displays for
  /// [messageTimeout] tics.
  void postMessage(String text) {
    _message = text;
    _messageTics = messageTimeout;
  }

  /// Clear any active message immediately.
  void clearMessage() {
    _message = '';
    _messageTics = 0;
  }

  /// Advance one tic (HU_Ticker): count down the message timer.
  void tick() {
    if (_messageTics > 0) {
      _messageTics--;
      if (_messageTics == 0) _message = '';
    }
  }

  /// Draw the HUD overlays (HU_Drawer). Draws the message line if active. When
  /// [fullscreen] is true and a [player] is supplied, also draws a minimal
  /// fullscreen readout (health / ammo) in the corners, as the vanilla
  /// fullscreen HUD does when the status bar is hidden.
  void draw(Framebuffer fb, {PlayerStatus? player, bool fullscreen = false}) {
    // Centre the 320-wide HUD on a wider (widescreen) framebuffer. 0 at 320.
    final int ox = (fb.width - kScreenWidth) ~/ 2;
    if (hasMessage) {
      font.draw(fb, ox + messageX, messageY, _message);
    }
    if (fullscreen && player != null) {
      _drawFullscreen(fb, player, ox);
    }
  }

  void _drawFullscreen(Framebuffer fb, PlayerStatus p, int ox) {
    // Bottom-left: health. Bottom-right: ready ammo. (Doom uses big red
    // numbers here; we render with the HUD font for a dependency-light layout.)
    // Anchored to the centred 320-wide band so widescreen keeps the corners.
    final int y = kScreenHeight - font.height - 2;
    font.draw(fb, ox + 2, y, '${p.health}%');
    final AmmoType? at = p.readyWeaponAmmo;
    if (at != null) {
      final String ammoStr = '${p.ammo(at)}';
      final int w = font.widthOf(ammoStr);
      font.draw(fb, ox + kScreenWidth - w - 2, y, ammoStr);
    }
  }
}
