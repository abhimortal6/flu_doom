// Intermission screen (wi_stuff.c port): the level-completion stats screen
// shown between levels. Draws the WIMAP0 background, "level finished" title,
// and Kills/Items/Secrets/Time/Par counters using the WINUM percent font.
//
// This is a faithful-but-compact port: it implements the SCREEN and the FLOW
// (count-up of stats, then wait for a key to advance). The full per-stat
// staggered tic-by-tic animation and the deathmatch/net tables are documented
// as partial in CONTRACTS_STATE.md.

import '../../engine/input/event.dart';
import '../../engine/video/framebuffer.dart';
import '../../engine/video/patch.dart';
import '../../ui/hud/fonts.dart';
import '../../ui/hud/graphics_cache.dart';
import 'interfaces.dart';

/// Phases of the intermission count-up (WI's `state`).
enum IntermissionPhase { statCount, showStats, done }

/// The intermission (WI) screen + ticker.
class Intermission {
  Intermission(this._gc) {
    _percentFont = _winumFont();
  }

  final GraphicsCache _gc;
  late final NumberFont _percentFont;

  IntermissionStats? _stats;
  IntermissionPhase phase = IntermissionPhase.done;

  // Displayed (animated) counts; ramp up toward the real totals.
  int _killPct = 0;
  int _itemPct = 0;
  int _secretPct = 0;
  bool _finished = false;

  /// Fired when the player advances past the intermission (WI_End ->
  /// G_WorldDone). The state machine wires this to load the next level.
  void Function()? onComplete;

  /// True while the intermission is showing.
  bool get active => phase != IntermissionPhase.done;

  NumberFont _winumFont() {
    // WINUM0..9 are the big white percent digits used on the WI screen.
    return NumberFont(
      digits: List<Patch?>.generate(10, (int i) => _gc.patch('WINUM$i')),
      percent: _gc.patch('WIPCNT'),
      minus: _gc.patch('WIMINUS'),
    );
  }

  /// Begin the intermission for [stats] (WI_Start).
  void start(IntermissionStats stats) {
    _stats = stats;
    phase = IntermissionPhase.statCount;
    _killPct = 0;
    _itemPct = 0;
    _secretPct = 0;
    _finished = false;
  }

  int _pct(int got, int total) => total <= 0 ? 100 : (got * 100 ~/ total);

  /// Advance one tic (WI_Ticker). Counts the stats up, then waits for input.
  void tick() {
    final IntermissionStats? s = _stats;
    if (s == null || phase == IntermissionPhase.done) return;
    if (phase == IntermissionPhase.statCount) {
      // Ramp each percentage up by a few points per tic.
      final int tk = _pct(s.killCount, s.totalKills);
      final int ti = _pct(s.itemCount, s.totalItems);
      final int ts = _pct(s.secretCount, s.totalSecrets);
      bool moved = false;
      if (_killPct < tk) {
        _killPct = (_killPct + 2).clamp(0, tk);
        moved = true;
      }
      if (_itemPct < ti) {
        _itemPct = (_itemPct + 2).clamp(0, ti);
        moved = true;
      }
      if (_secretPct < ts) {
        _secretPct = (_secretPct + 2).clamp(0, ts);
        moved = true;
      }
      if (!moved) {
        phase = IntermissionPhase.showStats;
      }
    }
  }

  /// Handle input (WI_checkForAccelerate): any attack/use/enter ends the
  /// screen. Returns true if consumed.
  bool responder(DoomEvent ev) {
    if (ev.type != EventType.keyDown) return false;
    if (phase == IntermissionPhase.done) return false;
    // Pressing during count-up snaps to final; pressing on the stats advances.
    final IntermissionStats? s = _stats;
    if (phase == IntermissionPhase.statCount && s != null) {
      _killPct = _pct(s.killCount, s.totalKills);
      _itemPct = _pct(s.itemCount, s.totalItems);
      _secretPct = _pct(s.secretCount, s.totalSecrets);
      phase = IntermissionPhase.showStats;
      return true;
    }
    if (phase == IntermissionPhase.showStats && !_finished) {
      _finished = true;
      phase = IntermissionPhase.done;
      onComplete?.call();
      return true;
    }
    return false;
  }

  /// Draw the intermission (WI_Drawer).
  void draw(Framebuffer fb) {
    final IntermissionStats? s = _stats;
    if (s == null) return;
    // Centre the 320-wide intermission on a wider (widescreen) framebuffer.
    final int ox = (fb.width - kScreenWidth) ~/ 2;
    // Background (WIMAP0 for episode 1). Black-fill the side strips first.
    if (ox > 0) fb.clear(0);
    if (_gc.has('WIMAP0')) {
      _gc.draw(fb, 'WIMAP0', ox + 0, 0);
    } else {
      fb.clear(0);
    }

    // "finished" / "entering" titles. Centre on the full screen width.
    _gc.draw(fb, 'WIF', (fb.width - (_gc.patch('WIF')?.width ?? 0)) ~/ 2, 14);

    // Stat rows: Kills / Items / Secrets / Time, vanilla SP_STATSX/Y layout.
    const int statsX = 280;
    const int statsY = 50;
    const int rowH = 18;
    _gc.draw(fb, 'WIOSTK', ox + 50, statsY); // "Kills"
    _percentFont.drawPercent(fb, ox + statsX, statsY, _killPct);
    _gc.draw(fb, 'WIOSTI', ox + 50, statsY + rowH); // "Items"
    _percentFont.drawPercent(fb, ox + statsX, statsY + rowH, _itemPct);
    _gc.draw(fb, 'WISCRT2', ox + 50, statsY + rowH * 2); // "Secret"
    _percentFont.drawPercent(fb, ox + statsX, statsY + rowH * 2, _secretPct);

    // Time / Par at the bottom (WITIME / WIPAR).
    const int timeY = 160;
    _gc.draw(fb, 'WITIME', ox + 16, timeY);
    _drawTime(fb, ox + 90, timeY, s.levelTimeSeconds);
    _gc.draw(fb, 'WIPAR', ox + 180, timeY);
    _drawTime(fb, ox + 248, timeY, s.parTimeSeconds);
  }

  void _drawTime(Framebuffer fb, int x, int y, int seconds) {
    if (seconds < 0) return;
    final int mins = seconds ~/ 60;
    final int secs = seconds % 60;
    // Draw "MM:SS" using the WI number font + colon.
    final Patch? colon = _gc.patch('WICOLON');
    int rx = x;
    _percentFont.drawNum(fb, rx + _percentFont.width * 2, y, secs,
        maxDigits: 2);
    if (colon != null) {
      colon.draw(fb, rx + _percentFont.width * 2, y);
    }
    rx -= 0;
    _percentFont.drawNum(fb, rx, y, mins, maxDigits: 2);
  }
}
