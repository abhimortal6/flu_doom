// Game loop driving Doom's 35Hz tic logic and frame rendering.
//
// Vanilla Doom runs game logic at a fixed TICRATE of 35 tics/second
// (src/i_timer.h). The renderer can draw more often (interpolation is not
// done in vanilla). We use a Flutter Ticker to get per-frame callbacks, derive
// elapsed wall-clock time, and run as many 35Hz tics as are due (with a cap to
// avoid spiral-of-death after a stall). After ticking we invoke the render
// hook once per frame.

import 'package:flutter/scheduler.dart';

/// Doom tic rate (TICRATE).
const int kTicRate = 35;

/// Microseconds per tic.
const int kMicrosPerTic = 1000000 ~/ kTicRate;

/// A function that advances the playsim by exactly one tic (Doom's TryRunTics
/// -> G_Ticker). Implemented by the game/playsim module.
typedef TicHook = void Function(int gametic);

/// A function that renders one frame. Called once per Ticker frame after any
/// due tics have run. Implemented by the renderer / video module.
typedef RenderHook = void Function();

/// Drives tics and frames. Owns timing; does not own game state.
class GameLoop {
  GameLoop({
    required TickerProvider vsync,
    required this.onTic,
    required this.onRender,
    this.maxTicsPerFrame = 5,
  }) {
    _ticker = vsync.createTicker(_onFrame);
  }

  /// Called once per game tic (35Hz). Receives the current [gametic] count.
  final TicHook onTic;

  /// Called once per rendered frame.
  final RenderHook onRender;

  /// Cap on tics processed per frame, preventing runaway catch-up.
  final int maxTicsPerFrame;

  late final Ticker _ticker;

  int _gametic = 0;
  Duration _lastElapsed = Duration.zero;
  int _accumulatorMicros = 0;

  // FPS / debug metrics.
  int _frameCount = 0;
  double _fps = 0;
  int _fpsWindowMicros = 0;

  /// Total tics processed since start.
  int get gametic => _gametic;

  /// Most recent measured frames-per-second.
  double get fps => _fps;

  /// Inter-tic fraction in 16.16 fixed-point, clamped to [0, FRACUNIT].
  ///
  /// After the per-frame tic loop, [_accumulatorMicros] holds the wall-clock
  /// time elapsed since the last 35Hz tic (always < kMicrosPerTic). Dividing by
  /// the tic duration gives the Crispy/Woof `fractionaltic` the renderer uses to
  /// blend the previous tic's positions toward the current tic's. RENDER-ONLY:
  /// the simulation is unaffected.
  int get subTicFrac16 {
    int f = (_accumulatorMicros << 16) ~/ kMicrosPerTic;
    if (f < 0) f = 0;
    if (f > 0x10000) f = 0x10000; // clamp to FRACUNIT
    return f;
  }

  /// Whether the loop is currently running.
  bool get isRunning => _ticker.isActive;

  /// Start the loop.
  void start() {
    if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  /// Stop the loop.
  void stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _onFrame(Duration elapsed) {
    // Delta since last frame.
    final int deltaMicros = _lastElapsed == Duration.zero
        ? 0
        : (elapsed - _lastElapsed).inMicroseconds;
    _lastElapsed = elapsed;

    _accumulatorMicros += deltaMicros;

    int ticsThisFrame = 0;
    while (_accumulatorMicros >= kMicrosPerTic &&
        ticsThisFrame < maxTicsPerFrame) {
      onTic(_gametic);
      _gametic++;
      _accumulatorMicros -= kMicrosPerTic;
      ticsThisFrame++;
    }
    // If we hit the cap (long stall), drop the backlog to stay real-time.
    if (ticsThisFrame >= maxTicsPerFrame) {
      _accumulatorMicros = 0;
    }

    onRender();

    // FPS measurement over a ~0.5s window.
    _frameCount++;
    _fpsWindowMicros += deltaMicros;
    if (_fpsWindowMicros >= 500000) {
      _fps = _frameCount * 1000000.0 / _fpsWindowMicros;
      _frameCount = 0;
      _fpsWindowMicros = 0;
    }
  }

  /// Dispose the underlying ticker.
  void dispose() {
    _ticker.dispose();
  }
}
