// Shared helpers for render tests: load E1M1 and place the camera at the
// player-1 start exactly as vanilla P_SpawnPlayer + R_SetupFrame would.

import 'dart:io';
import 'dart:typed_data';

import 'package:flu_doom/engine/math/angle.dart';
import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/defs.dart';
import 'package:flu_doom/game/world/world.dart';

/// Vanilla VIEWHEIGHT = 41 units.
const int kEyeHeight = 41 * kFracUnit;

World loadE1M1() {
  final Uint8List bytes = File('assets/doom1.wad').readAsBytesSync();
  return World.fromWad(WadFile.fromBytes(bytes), mapName: 'E1M1');
}

int pointOnSide(fixed_t x, fixed_t y, Node node) {
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

fixed_t floorHeightAt(World world, fixed_t x, fixed_t y) {
  final level = world.level;
  int nodeNum = level.rootNode;
  while ((nodeNum & nfSubsector) == 0) {
    final Node node = level.nodes[nodeNum];
    nodeNum = node.children[pointOnSide(x, y, node)];
  }
  return level.subsectors[nodeNum & ~nfSubsector].sector.floorHeight;
}

/// Place the camera at the player-1 start, optionally rotated by
/// [angleDeltaDeg] degrees (for multi-view dumps).
void setViewToPlayerStart(World world, {int angleDeltaDeg = 0}) {
  final MapThing start =
      world.level.things.firstWhere((MapThing t) => t.type == 1);
  final fixed_t vx = intToFixed(start.x);
  final fixed_t vy = intToFixed(start.y);
  // Vanilla P_SpawnMapThing: angle = ANG45/45 * mapthing.angle.
  final angle_t vang =
      normAngle((kAng45 ~/ 45) * (start.angle + angleDeltaDeg));
  final fixed_t floorZ = floorHeightAt(world, vx, vy);
  world.viewpoint
      .set(x: vx, y: vy, z: toInt32(floorZ + kEyeHeight), angle: vang);
}
