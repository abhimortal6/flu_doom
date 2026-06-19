// Automap (am_map.c port): draws the level line geometry as a top-down map,
// with two-sided / secret / unseen colouring, a player arrow, grid, and
// pan/zoom. Draws directly into the indexed [Framebuffer] using Bresenham
// lines (AM_drawFline) rather than Flutter widgets.
//
// Colours are vanilla palette indices (am_map.c WALLCOLORS etc.). The map
// reads geometry from the shared [Level] and the camera from [Viewpoint]; it
// never mutates either.

import '../../engine/math/fixed.dart';
import '../../engine/video/framebuffer.dart';
import '../../engine/input/doomkeys.dart';
import '../../engine/input/event.dart';
import '../../game/world/defs.dart';
import '../../game/world/level.dart';
import '../../game/world/world.dart';

/// Vanilla automap colour indices (am_map.c).
abstract final class AutomapColor {
  static const int background = 0; // BLACK
  static const int wall = 23; // WALLCOLORS (one-sided) — red range
  static const int twoSidedFloorDiff = 55; // FDWALLCOLORS (floor height diff)
  static const int twoSidedCeilDiff = 215; // CDWALLCOLORS (ceiling diff)
  static const int twoSidedSame = 96; // TSWALLCOLORS (no height change) — grey
  static const int secret = 252; // SECRETWALLCOLORS (same as wall in vanilla)
  static const int grid = 104; // GRIDCOLORS
  static const int player = 4; // WHITE / PLAYERCOLORS area
  static const int unseen = 100; // not-yet-mapped (only with cheat allmap)
}

/// Automap state + drawer + responder.
class Automap {
  Automap();

  /// Whether the automap is currently active (toggled by Tab).
  bool active = false;

  /// Whether to overlay grid lines.
  bool grid = false;

  /// Whether to show every line regardless of "mapped" flags (IDDT-style /
  /// reveal-all). Tests use this to force full geometry.
  bool revealAll = true;

  // View centre in map coordinates (fixed_t) and scale (map units per pixel,
  // as a multiplier we apply directly). We keep a simple float-ish scale.
  double _scale = 0; // pixels per map unit
  int _mx = 0; // centre x (fixed_t)
  int _my = 0; // centre y (fixed_t)
  bool _followPlayer = true;

  // Map bounds (fixed_t), computed on first open.
  int _minX = 0, _maxX = 0, _minY = 0, _maxY = 0;
  bool _boundsValid = false;

  // Pan/zoom step constants (am_map.c F_PANINC / M_ZOOMIN / M_ZOOMOUT scaled).
  static const double _zoomIn = 1.0 / 0.96875; // M_ZOOMOUT inverse ~ 1.03
  static const double _zoomOut = 0.96875;
  static const int _panStep = 8 * kFracUnit; // map units per pan key-tic

  /// Map drawing viewport (full screen minus the status bar by default).
  int viewWidth = kScreenWidth;
  int viewHeight = kScreenHeight - 32; // leave room for status bar

  /// Compute map bounds from the level vertexes (AM_findMinMaxBoundaries).
  void _computeBounds(Level level) {
    if (level.vertexes.isEmpty) {
      _minX = _minY = -kFracUnit;
      _maxX = _maxY = kFracUnit;
    } else {
      _minX = _maxX = level.vertexes.first.x;
      _minY = _maxY = level.vertexes.first.y;
      for (final Vertex v in level.vertexes) {
        if (v.x < _minX) _minX = v.x;
        if (v.x > _maxX) _maxX = v.x;
        if (v.y < _minY) _minY = v.y;
        if (v.y > _maxY) _maxY = v.y;
      }
    }
    _boundsValid = true;
  }

  /// Fit the whole map into the viewport and centre it (AM_initVariables).
  void _fit(Level level) {
    if (!_boundsValid) _computeBounds(level);
    final int w = (_maxX - _minX).abs();
    final int h = (_maxY - _minY).abs();
    final double sx = w == 0 ? 1 : viewWidth / (w / kFracUnit);
    final double sy = h == 0 ? 1 : viewHeight / (h / kFracUnit);
    _scale = (sx < sy ? sx : sy) * 0.9; // 10% margin
    if (_scale <= 0) _scale = 0.01;
    _mx = (_minX + _maxX) ~/ 2;
    _my = (_minY + _maxY) ~/ 2;
  }

  /// Open the automap for [level], centring on the player at [viewpoint].
  void open(World world) {
    active = true;
    _computeBounds(world.level);
    _fit(world.level);
    _recenterOnPlayer(world);
  }

  /// Centre on the player when following, but only if the viewpoint lies inside
  /// the map bounds. Before the playsim has set a viewpoint it is (0,0), which
  /// may be far outside the level; in that case we keep the map centre so the
  /// whole level stays framed.
  void _recenterOnPlayer(World world) {
    if (!_followPlayer) return;
    final int vx = world.viewpoint.x;
    final int vy = world.viewpoint.y;
    if (vx >= _minX && vx <= _maxX && vy >= _minY && vy <= _maxY) {
      _mx = vx;
      _my = vy;
    }
  }

  /// Close the automap.
  void close() {
    active = false;
  }

  /// Project a map-space fixed_t point to integer framebuffer pixel coords.
  /// Y is flipped (map +y is up; screen +y is down).
  void _project(int mxFixed, int myFixed, List<int> out) {
    final double dx = (mxFixed - _mx) / kFracUnit;
    final double dy = (myFixed - _my) / kFracUnit;
    out[0] = (viewWidth / 2 + dx * _scale).round();
    out[1] = (viewHeight / 2 - dy * _scale).round();
  }

  final List<int> _p1 = <int>[0, 0];
  final List<int> _p2 = <int>[0, 0];

  /// Number of lines actually plotted in the last [draw] call (for tests).
  int linesDrawn = 0;

  /// Draw the automap into [fb] for the given [world]. The caller must have
  /// called [open] first (or [draw] auto-fits if bounds are stale).
  void draw(Framebuffer fb, World world) {
    final Level level = world.level;
    if (!_boundsValid) {
      _computeBounds(level);
      _fit(level);
    }
    _recenterOnPlayer(world);

    // Background: clear the map viewport.
    for (int y = 0; y < viewHeight; y++) {
      final int row = y * fb.width;
      for (int x = 0; x < viewWidth; x++) {
        fb.pixels[row + x] = AutomapColor.background;
      }
    }

    if (grid) _drawGrid(fb);

    linesDrawn = 0;
    for (final Line line in level.lines) {
      // Visibility: vanilla hides ML_DONTDRAW unless mapped/allmap.
      final bool mapped = (line.flags & mlMapped) != 0;
      if (!revealAll) {
        if ((line.flags & mlDontDraw) != 0) continue;
        if (!mapped) continue;
      }
      final int color = _colorForLine(line);
      _project(line.v1.x, line.v1.y, _p1);
      _project(line.v2.x, line.v2.y, _p2);
      if (_drawClippedLine(fb, _p1[0], _p1[1], _p2[0], _p2[1], color)) {
        linesDrawn++;
      }
    }

    _drawPlayerArrow(fb, world);
  }

  int _colorForLine(Line line) {
    if ((line.flags & mlSecret) != 0) return AutomapColor.secret;
    if (line.backSector == null) return AutomapColor.wall; // one-sided
    // Two-sided: colour by what changes (floor vs ceiling vs none).
    final Sector? back = line.backSector;
    final Sector front = line.frontSector;
    if (back != null) {
      if (back.floorHeight != front.floorHeight) {
        return AutomapColor.twoSidedFloorDiff;
      }
      if (back.ceilingHeight != front.ceilingHeight) {
        return AutomapColor.twoSidedCeilDiff;
      }
    }
    return AutomapColor.twoSidedSame;
  }

  void _drawGrid(Framebuffer fb) {
    // Draw vertical + horizontal grid lines spaced at 128 map units.
    const int step = 128;
    final double pxStep = step * _scale;
    if (pxStep < 4) return; // too dense to be useful
    for (double x = (viewWidth / 2) % pxStep; x < viewWidth; x += pxStep) {
      final int ix = x.round();
      for (int y = 0; y < viewHeight; y++) {
        fb.pixels[y * fb.width + ix] = AutomapColor.grid;
      }
    }
    for (double y = (viewHeight / 2) % pxStep; y < viewHeight; y += pxStep) {
      final int iy = y.round();
      final int row = iy * fb.width;
      for (int x = 0; x < viewWidth; x++) {
        fb.pixels[row + x] = AutomapColor.grid;
      }
    }
  }

  void _drawPlayerArrow(Framebuffer fb, World world) {
    _project(world.viewpoint.x, world.viewpoint.y, _p1);
    final int cx = _p1[0];
    final int cy = _p1[1];
    // A simple arrow: a short line in the facing direction plus barbs.
    final double ang = world.viewpoint.angle / 4294967296.0 * 2 * 3.141592653589793;
    const double len = 8;
    final int tx = (cx + len * _cosApprox(ang)).round();
    final int ty = (cy - len * _sinApprox(ang)).round();
    _drawClippedLine(fb, cx, cy, tx, ty, AutomapColor.player);
    // Barbs.
    final int bx1 = (tx - 4 * _cosApprox(ang - 0.5)).round();
    final int by1 = (ty + 4 * _sinApprox(ang - 0.5)).round();
    final int bx2 = (tx - 4 * _cosApprox(ang + 0.5)).round();
    final int by2 = (ty + 4 * _sinApprox(ang + 0.5)).round();
    _drawClippedLine(fb, tx, ty, bx1, by1, AutomapColor.player);
    _drawClippedLine(fb, tx, ty, bx2, by2, AutomapColor.player);
  }

  // Lightweight trig (the BAM tables are angle->fixed; for the arrow a double
  // approximation is plenty and avoids importing the angle module just here).
  double _cosApprox(double r) => _seriesCos(r);
  double _sinApprox(double r) => _seriesCos(r - 1.5707963267948966);
  double _seriesCos(double x) {
    // Normalise to [-pi, pi].
    const double twoPi = 6.283185307179586;
    x = x % twoPi;
    if (x > 3.141592653589793) x -= twoPi;
    if (x < -3.141592653589793) x += twoPi;
    final double x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
  }

  /// Bresenham line clipped to the map viewport. Returns true if any pixel was
  /// plotted.
  bool _drawClippedLine(
      Framebuffer fb, int x0, int y0, int x1, int y1, int color) {
    bool plotted = false;
    int dx = (x1 - x0).abs();
    int dy = (y1 - y0).abs();
    final int sx = x0 < x1 ? 1 : -1;
    final int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;
    int x = x0;
    int y = y0;
    final int w = viewWidth;
    final int h = viewHeight;
    final int fbw = fb.width;
    while (true) {
      if (x >= 0 && x < w && y >= 0 && y < h) {
        fb.pixels[y * fbw + x] = color;
        plotted = true;
      }
      if (x == x1 && y == y1) break;
      final int e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x += sx;
      }
      if (e2 < dx) {
        err += dx;
        y += sy;
      }
    }
    return plotted;
  }

  /// Handle an input event (AM_Responder). Returns true if consumed.
  ///
  /// Bindings (vanilla defaults): Tab toggles; +/- zoom; arrows pan (disabling
  /// follow mode); 'f' toggles follow; 'g' toggles grid. The state machine
  /// calls this only while a level is active.
  bool responder(DoomEvent ev) {
    if (ev.type != EventType.keyDown) return false;
    final int key = ev.data1;
    if (key == DoomKey.tab) {
      active = !active;
      return true;
    }
    if (!active) return false;
    if (key == _kPlus || key == DoomKey.equals) {
      _scale *= _zoomIn;
      return true;
    }
    if (key == _kMinus || key == DoomKey.minus) {
      _scale *= _zoomOut;
      return true;
    }
    switch (key) {
      case DoomKey.upArrow:
        _followPlayer = false;
        _my += _panStep;
        return true;
      case DoomKey.downArrow:
        _followPlayer = false;
        _my -= _panStep;
        return true;
      case DoomKey.leftArrow:
        _followPlayer = false;
        _mx -= _panStep;
        return true;
      case DoomKey.rightArrow:
        _followPlayer = false;
        _mx += _panStep;
        return true;
    }
    if (key == _kF) {
      _followPlayer = !_followPlayer;
      return true;
    }
    if (key == _kG) {
      grid = !grid;
      return true;
    }
    return false;
  }

  static final int _kPlus = '+'.codeUnitAt(0);
  static final int _kMinus = '-'.codeUnitAt(0);
  static final int _kF = 'f'.codeUnitAt(0);
  static final int _kG = 'g'.codeUnitAt(0);
}
