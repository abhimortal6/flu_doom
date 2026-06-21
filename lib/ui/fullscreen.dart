// Cross-platform fullscreen control for flu_doom.
//
// Two distinct fullscreen mechanisms, selected by platform:
//
//   * DESKTOP (macOS / Linux / Windows): true OS-level fullscreen via the
//     `window_manager` package (removes the title bar / window chrome). Toggled
//     with F11 (see ActionKeyboardListener wiring in doom_game.dart) and
//     initialized at startup in main().
//
//   * MOBILE (Android / iOS): immersive-sticky system UI mode via
//     SystemChrome.setEnabledSystemUIMode — hides the status / navigation bars
//     during gameplay. There is no "window" to fullscreen; immersive mode is the
//     equivalent.
//
//   * WEB / anything else: no-op (window_manager is desktop-only, and the engine
//     does not render correctly on web anyway — see README web section).
//
// This module ONLY removes window chrome / system bars. It does NOT touch the
// VideoView present layer: the 320x200 (or widescreen) framebuffer still
// letterboxes correctly inside whatever viewport it is given.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the current platform uses the desktop [window_manager] fullscreen
/// path (true OS fullscreen) rather than the mobile immersive path.
bool get _isDesktop {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// Whether the current platform uses the mobile immersive system-UI path.
bool get _isMobile {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Manages fullscreen state across desktop and mobile.
///
/// On desktop, [ensureInitialized] must be awaited in main() BEFORE runApp so
/// window_manager can hook the native window. On mobile / web it is a cheap
/// no-op and may be called unconditionally.
class FullscreenController {
  FullscreenController._();

  static final FullscreenController instance = FullscreenController._();

  bool _initialized = false;

  /// Tracks the desired fullscreen state (best-effort; on desktop we also query
  /// window_manager directly in [isFullscreen]).
  bool _wantFullscreen = false;

  /// Initialize the native window manager on desktop. Safe (no-op) elsewhere.
  /// Call once from main() after WidgetsFlutterBinding.ensureInitialized().
  ///
  /// [startFullscreen] requests fullscreen immediately on desktop (handy for a
  /// kiosk-style launch); defaults to false so the app opens windowed and the
  /// user toggles with F11.
  Future<void> ensureInitialized({bool startFullscreen = false}) async {
    if (_initialized) return;
    _initialized = true;

    if (_isDesktop) {
      await windowManager.ensureInitialized();
      const WindowOptions options = WindowOptions(
        title: 'flu_doom',
        titleBarStyle: TitleBarStyle.normal,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
        if (startFullscreen) {
          await setFullscreen(true);
        }
      });
    } else if (_isMobile) {
      // Mobile always launches into immersive gameplay fullscreen (status/nav
      // bars hidden); there is no windowed mode to preserve. [startFullscreen]
      // is honoured but immersive is the sensible default either way.
      await setFullscreen(true);
    }
    // Web / fuchsia: nothing to do.
  }

  /// Current fullscreen state. On desktop this queries the native window; on
  /// mobile it returns the last requested immersive state.
  Future<bool> isFullscreen() async {
    if (_isDesktop) {
      try {
        return await windowManager.isFullScreen();
      } catch (_) {
        return _wantFullscreen;
      }
    }
    return _wantFullscreen;
  }

  /// Set fullscreen on/off for the current platform.
  Future<void> setFullscreen(bool value) async {
    _wantFullscreen = value;
    if (_isDesktop) {
      try {
        await windowManager.setFullScreen(value);
      } catch (_) {
        // window_manager not ready / unsupported — ignore.
      }
    } else if (_isMobile) {
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
    // Web / fuchsia: no-op.
  }

  /// Toggle fullscreen. Returns the new state (best-effort).
  Future<bool> toggle() async {
    final bool now = await isFullscreen();
    await setFullscreen(!now);
    return !now;
  }
}
