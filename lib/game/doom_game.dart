// The Phase-1 vertical slice game widget.
//
// Responsibilities:
//  * Load doom1.wad from assets.
//  * Build the palette (PLAYPAL) and colormap (COLORMAP).
//  * Decode TITLEPIC and blit it into the 320x200 framebuffer.
//  * Run the 35Hz game loop, animating one element each tic to prove ticking.
//  * Convert the framebuffer to a ui.Image each frame and display it via
//    VideoView (auto-scaled + selectable scaling mode).
//  * Wire keyboard + touch input into the Doom event queue and log events.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../engine/input/event.dart';
import '../engine/input/keyboard.dart';
import '../engine/system/gameloop.dart';
import '../engine/video/framebuffer.dart';
import '../engine/video/palette.dart';
import '../engine/video/patch.dart';
import '../engine/video/video_view.dart';
import '../engine/wad/wad.dart';
import '../ui/debug_overlay.dart';
import '../ui/touch_overlay.dart';

const String kWadAsset = 'assets/doom1.wad';

class DoomGame extends StatefulWidget {
  const DoomGame({super.key});

  @override
  State<DoomGame> createState() => _DoomGameState();
}

class _DoomGameState extends State<DoomGame>
    with SingleTickerProviderStateMixin {
  final EventQueue _events = EventQueue();
  final Framebuffer _fb = Framebuffer();

  WadFile? _wad;
  Palette? _palette;
  Colormap? _colormap;
  Patch? _titlePic;

  GameLoop? _loop;
  ui.Image? _frame;
  bool _decodingFrame = false;

  String? _error;
  bool _showDebug = true;
  ScaleMode _scaleMode = ScaleMode.fit;
  bool _aspectCorrect = false;

  // Animation/state for proof-of-life.
  int _animTic = 0;
  String _lastEventLog = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final ByteData bytes = await rootBundle.load(kWadAsset);
      final WadFile wad = WadFile.fromBytes(bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ));
      final Palette palette = Palette.fromWad(wad);
      final Colormap colormap = Colormap.fromWad(wad);
      final Patch title = Patch.fromBytes(wad.getLump('TITLEPIC').bytes);

      _wad = wad;
      _palette = palette;
      _colormap = colormap;
      _titlePic = title;

      _loop = GameLoop(
        vsync: this,
        onTic: _onTic,
        onRender: _onRender,
      );
      _renderScene();
      await _present();
      _loop!.start();
      if (mounted) setState(() {});
    } catch (e, st) {
      _error = '$e\n$st';
      if (mounted) setState(() {});
    }
  }

  // --- Game tic: drain input, advance animation. ---
  void _onTic(int gametic) {
    final List<DoomEvent> evs = _events.drain();
    for (final DoomEvent e in evs) {
      _lastEventLog = e.toString();
    }
    _animTic++;
  }

  // --- Frame: redraw the indexed buffer, then schedule image decode. ---
  void _onRender() {
    _renderScene();
    _present();
    if (mounted) setState(() {}); // refresh debug overlay / fps
  }

  void _renderScene() {
    final Patch? title = _titlePic;
    if (title == null) return;
    // Draw TITLEPIC full-screen (it is 320x200).
    title.draw(_fb, 0, 0);

    // Proof-of-life: a marching bar of cycling palette indices across the top.
    final int barY = 4;
    final int phase = _animTic % _fb.width;
    for (int y = barY; y < barY + 6; y++) {
      for (int x = 0; x < _fb.width; x++) {
        final int c = ((x + phase) ~/ 4) & 0xFF;
        _fb.setPixel(x, y, c);
      }
    }
    // A bouncing dot to make ticking obvious.
    final int span = _fb.width - 8;
    final int t = _animTic % (2 * span);
    final int dotX = (t < span ? t : 2 * span - t) + 4;
    for (int dy = 0; dy < 6; dy++) {
      for (int dx = 0; dx < 6; dx++) {
        _fb.setPixel(
            (dotX + dx).clamp(0, _fb.width - 1), 184 + dy, 176); // bright red
      }
    }
  }

  Future<void> _present() async {
    final Palette? palette = _palette;
    if (palette == null || _decodingFrame) return;
    _decodingFrame = true;
    try {
      final ui.Image img = await _fb.toImage(palette);
      final ui.Image? old = _frame;
      _frame = img;
      old?.dispose();
    } finally {
      _decodingFrame = false;
    }
  }

  void _cycleScaleMode() {
    setState(() {
      _scaleMode = ScaleMode
          .values[(_scaleMode.index + 1) % ScaleMode.values.length];
    });
  }

  @override
  void dispose() {
    _loop?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: const Color(0xFF200000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Boot error:\n$_error',
              style: const TextStyle(color: Color(0xFFFF8080), fontSize: 12),
            ),
          ),
        ),
      );
    }

    return DoomKeyboardListener(
      queue: _events,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          VideoView(
            image: _frame,
            scaleMode: _scaleMode,
            pixelAspectCorrection: _aspectCorrect,
          ),
          TouchOverlay(queue: _events),
          if (_showDebug)
            DebugOverlay(
              fps: _loop?.fps ?? 0,
              gametic: _loop?.gametic ?? 0,
              extra: 'lumps ${_wad?.numLumps ?? 0}'
                  '  cmaps ${_colormap?.numMaps ?? 0}'
                  '  scale ${_scaleMode.name}'
                  '${_aspectCorrect ? ' 4:3' : ''}'
                  '${_lastEventLog.isNotEmpty ? '\nlast $_lastEventLog' : ''}',
            ),
          // Controls: scale-mode selector + aspect + debug toggle.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    _MiniButton(
                      label: 'scale: ${_scaleMode.name}',
                      onTap: _cycleScaleMode,
                    ),
                    const SizedBox(width: 8),
                    _MiniButton(
                      label: _aspectCorrect ? '4:3 on' : '4:3 off',
                      onTap: () =>
                          setState(() => _aspectCorrect = !_aspectCorrect),
                    ),
                    const SizedBox(width: 8),
                    _MiniButton(
                      label: _showDebug ? 'dbg on' : 'dbg off',
                      onTap: () => setState(() => _showDebug = !_showDebug),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: const Color(0xAA000000),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF00FF00), fontSize: 11),
        ),
      ),
    );
  }
}
