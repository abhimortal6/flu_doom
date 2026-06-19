// Visual preview entry point for the 3D renderer.
//
//   flutter run -t lib/render_preview_main.dart -d macos
//
// Loads doom1.wad, builds a World at E1M1, places the camera at the player-1
// start (eye height 41 units), and renders the 3D view with an empty
// SpriteSource into the foundation VideoView. Arrow keys move/turn so the first
// room can be explored; ESC quits. This is for human visual verification only —
// it touches no files outside lib/engine/render + this entry file.

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'engine/math/angle.dart';
import 'engine/math/fixed.dart';
import 'engine/math/tables.dart';
import 'engine/render/renderer.dart';
import 'engine/render/sprite_source.dart';
import 'engine/video/framebuffer.dart';
import 'engine/video/palette.dart';
import 'engine/video/video_view.dart';
import 'engine/wad/wad.dart';
import 'game/world/defs.dart';
import 'game/world/world.dart';

const String _kWadAsset = 'assets/doom1.wad';
const int _kEyeHeight = 41 * kFracUnit;

void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: _RenderPreview(),
    );
  }
}

class _RenderPreview extends StatefulWidget {
  const _RenderPreview();
  @override
  State<_RenderPreview> createState() => _RenderPreviewState();
}

class _RenderPreviewState extends State<_RenderPreview> {
  final Framebuffer _fb = Framebuffer();
  final FocusNode _focus = FocusNode();
  World? _world;
  Renderer? _renderer;
  Palette? _palette;
  ui.Image? _image;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final ByteData data = await rootBundle.load(_kWadAsset);
      final WadFile wad = WadFile.fromBytes(data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes));
      final World world = World.fromWad(wad, mapName: 'E1M1');
      _placeAtPlayerStart(world);
      _world = world;
      _palette = Palette.fromWad(wad);
      _renderer = Renderer(framebuffer: _fb, world: world);
      await _renderFrame();
      _focus.requestFocus();
    } catch (e, st) {
      _error = '$e\n$st';
      if (mounted) setState(() {});
    }
  }

  void _placeAtPlayerStart(World world) {
    final MapThing start =
        world.level.things.firstWhere((MapThing t) => t.type == 1);
    final fixed_t vx = intToFixed(start.x);
    final fixed_t vy = intToFixed(start.y);
    final angle_t vang = normAngle((start.angle ~/ 45) * kAng45);
    final fixed_t floorZ = _floorHeightAt(world, vx, vy);
    world.viewpoint
        .set(x: vx, y: vy, z: toInt32(floorZ + _kEyeHeight), angle: vang);
  }

  fixed_t _floorHeightAt(World world, fixed_t x, fixed_t y) {
    final level = world.level;
    int n = level.rootNode;
    while ((n & nfSubsector) == 0) {
      final Node node = level.nodes[n];
      int side;
      if (node.dx == 0) {
        side = x <= node.x ? (node.dy > 0 ? 1 : 0) : (node.dy < 0 ? 1 : 0);
      } else if (node.dy == 0) {
        side = y <= node.y ? (node.dx < 0 ? 1 : 0) : (node.dx > 0 ? 1 : 0);
      } else {
        final int dx = toInt32(x - node.x), dy = toInt32(y - node.y);
        side = fixedMul(dy, node.dx >> 16) < fixedMul(node.dy >> 16, dx)
            ? 0
            : 1;
      }
      n = node.children[side];
    }
    return level.subsectors[n & ~nfSubsector].sector.floorHeight;
  }

  Future<void> _renderFrame() async {
    final Renderer? r = _renderer;
    final Palette? pal = _palette;
    if (r == null || pal == null || _busy) return;
    _busy = true;
    r.renderPlayerView(const EmptySpriteSource());
    final ui.Image img = await _fb.toImage(pal);
    _image?.dispose();
    _image = img;
    _busy = false;
    if (mounted) setState(() {});
  }

  void _onKey(KeyEvent ev) {
    final World? world = _world;
    if (world == null || ev is KeyUpEvent) return;
    final vp = world.viewpoint;
    const int move = 16 * kFracUnit;
    const int turn = 0x08000000; // ~11.25 degrees
    final int fi = angleToFineIndex(vp.angle);
    final int cos = finecosine[fi], sin = finesine[fi];
    final LogicalKeyboardKey k = ev.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      vp.set(
          x: toInt32(vp.x + fixedMul(move, cos)),
          y: toInt32(vp.y + fixedMul(move, sin)),
          z: vp.z,
          angle: vp.angle);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      vp.set(
          x: toInt32(vp.x - fixedMul(move, cos)),
          y: toInt32(vp.y - fixedMul(move, sin)),
          z: vp.z,
          angle: vp.angle);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      vp.set(x: vp.x, y: vp.y, z: vp.z, angle: normAngle(vp.angle + turn));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      vp.set(x: vp.x, y: vp.y, z: vp.z, angle: normAngle(vp.angle - turn));
    } else {
      return;
    }
    _renderFrame();
  }

  @override
  void dispose() {
    _image?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: const Color(0xFF300000),
        child: Center(
          child: Text(_error!,
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12)),
        ),
      );
    }
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: VideoView(
        image: _image,
        scaleMode: ScaleMode.fit,
        pixelAspectCorrection: true,
      ),
    );
  }
}
