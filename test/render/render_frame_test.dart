// Renders one real E1M1 frame from the player-1 start and asserts the output
// is a plausible 3D scene (not a flat fill, deterministic, varied palette).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/render/renderer.dart';
import 'package:flu_doom/engine/render/sprite_source.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/world.dart';

/// Eye height added to the player start z (vanilla VIEWHEIGHT = 41 units).
const int kEyeHeight = 41 * kFracUnit;

World _loadWorld() {
  final File f = File('assets/doom1.wad');
  final Uint8List bytes = f.readAsBytesSync();
  final WadFile wad = WadFile.fromBytes(bytes);
  return World.fromWad(wad, mapName: 'E1M1');
}

/// Set the viewpoint to the player-1 start (MapThing type 1). Mirrors vanilla
/// P_SpawnPlayer + R_SetupFrame: shift map units to fixed_t, BAM the angle,
/// floor-height + eye-height for viewz.
void _setViewToPlayerStart(World world) {
  final MapThing start =
      world.level.things.firstWhere((MapThing t) => t.type == 1);
  final fixed_t vx = intToFixed(start.x);
  final fixed_t vy = intToFixed(start.y);
  // angle: degrees -> BAM. (ANG90/90)*deg, as P_SpawnMapThing does.
  final angle_t vang = normAngle((start.angle ~/ 45) * kAng45);

  // Find the floor height of the sector the player stands in (point in
  // subsector via the BSP root walk is overkill; sample the start's sector by
  // brute force using the lowest containing sector is complex — instead use the
  // sector of the subsector found by a simple BSP descent).
  final fixed_t floorZ = _floorHeightAt(world, vx, vy);
  world.viewpoint.set(x: vx, y: vy, z: toInt32(floorZ + kEyeHeight), angle: vang);
}

fixed_t _floorHeightAt(World world, fixed_t x, fixed_t y) {
  final level = world.level;
  int nodeNum = level.rootNode;
  while ((nodeNum & nfSubsector) == 0) {
    final Node node = level.nodes[nodeNum];
    final int side = _pointOnSide(x, y, node);
    nodeNum = node.children[side];
  }
  final int idx = nodeNum & ~nfSubsector;
  return level.subsectors[idx].sector.floorHeight;
}

int _pointOnSide(fixed_t x, fixed_t y, Node node) {
  if (node.dx == 0) {
    if (x <= node.x) return node.dy > 0 ? 1 : 0;
    return node.dy < 0 ? 1 : 0;
  }
  if (node.dy == 0) {
    if (y <= node.y) return node.dx < 0 ? 1 : 0;
    return node.dx > 0 ? 1 : 0;
  }
  final int dx = toInt32(x - node.x);
  final int dy = toInt32(y - node.y);
  final int left = fixedMul(node.dy >> kFracBits, dx);
  final int right = fixedMul(dy, node.dx >> kFracBits);
  return right < left ? 0 : 1;
}

void main() {
  test('projection tables span the FOV (R_InitTextureMapping)', () {
    final World world = _loadWorld();
    _setViewToPlayerStart(world);
    final Framebuffer fb = Framebuffer();
    final Renderer r = Renderer(framebuffer: fb, world: world);
    final s = r.state;
    // xToViewAngle must vary across the screen: left/center/right distinct.
    // (A regression where these collapse to one value yields a noise frame.)
    expect(s.xToViewAngle[0], isNot(equals(s.xToViewAngle[s.centerX])));
    expect(s.xToViewAngle[s.screenWidth],
        isNot(equals(s.xToViewAngle[s.centerX])));
    // Centre column looks straight ahead (angle ~0).
    expect(s.xToViewAngle[s.centerX], equals(0));
    // viewAngleToX must span the whole view width.
    final int minX = s.viewAngleToX.reduce((int a, int b) => a < b ? a : b);
    final int maxX = s.viewAngleToX.reduce((int a, int b) => a > b ? a : b);
    expect(minX, equals(0));
    expect(maxX, equals(s.screenWidth));
  });

  test('renders a real E1M1 frame from the player start', () {
    final World world = _loadWorld();
    _setViewToPlayerStart(world);

    final Framebuffer fb = Framebuffer();
    final Renderer renderer = Renderer(framebuffer: fb, world: world);
    renderer.renderPlayerView(const EmptySpriteSource());

    final Uint8List px = fb.pixels;
    expect(px.length, kScreenWidth * kScreenHeight);

    // 1. Not a single flat colour: count distinct palette indices.
    final Set<int> distinct = px.toSet();
    expect(distinct.length, greaterThan(8),
        reason: 'expected a varied scene, got ${distinct.length} colours');

    // 2. Plausible spread: the most-common colour must not dominate the whole
    //    screen (a real view has walls, floor, ceiling, sky).
    final Map<int, int> hist = <int, int>{};
    for (final int p in px) {
      hist[p] = (hist[p] ?? 0) + 1;
    }
    final int maxCount =
        hist.values.reduce((int a, int b) => a > b ? a : b);
    expect(maxCount, lessThan(px.length * 9 ~/ 10),
        reason: 'one colour fills >90% of the screen ($maxCount px)');

    // 3. A meaningful fraction of pixels are non-zero (geometry was drawn).
    final int nonZero = px.where((int p) => p != 0).length;
    expect(nonZero, greaterThan(px.length ~/ 4),
        reason: 'too few pixels drawn: $nonZero');
  });

  test('is deterministic across two renders', () {
    final World world = _loadWorld();
    _setViewToPlayerStart(world);

    final Framebuffer fb1 = Framebuffer();
    Renderer(framebuffer: fb1, world: world)
        .renderPlayerView(const EmptySpriteSource());

    final Framebuffer fb2 = Framebuffer();
    Renderer(framebuffer: fb2, world: world)
        .renderPlayerView(const EmptySpriteSource());

    expect(fb1.pixels, equals(fb2.pixels));
  });

  test('empty sprite source renders a valid (non-empty) view', () {
    final World world = _loadWorld();
    _setViewToPlayerStart(world);
    final Framebuffer fb = Framebuffer();
    Renderer(framebuffer: fb, world: world)
        .renderPlayerView(const EmptySpriteSource());
    expect(fb.pixels.any((int p) => p != 0), isTrue);
  });
}
