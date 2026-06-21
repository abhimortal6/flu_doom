// Frame-interpolation SIM-side tests: prove old-state is captured each tic and,
// critically, that the simulation produces the SAME new positions whether or not
// interpolation is observed (physics is untouched — interpolation is render-only).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';

import 'package:flu_doom/engine/math/fixed.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/world/ticcmd.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/game/play/mobj.dart';
import 'package:flu_doom/game/play/playsim.dart';

World loadWorld() {
  final File f = File('assets/doom1.wad');
  expect(f.existsSync(), true, reason: 'assets/doom1.wad must be present');
  return World.fromWad(WadFile.fromBytes(
      Uint8List.fromList(f.readAsBytesSync())));
}

TicCmd forward(int amount) => TicCmd()..forwardMove = amount;

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  group('interpolation old-state capture', () {
    test('after spawn, old == current (snap, no smear)', () {
      final World w = loadWorld();
      final PlaySim sim = PlaySim(w)..spawnLevel();
      final Mobj mo = sim.player.mo!;
      expect(mo.oldX, mo.x);
      expect(mo.oldY, mo.y);
      expect(mo.oldZ, mo.z);
      expect(w.viewpoint.oldX, w.viewpoint.x);
      expect(w.viewpoint.oldAngle, w.viewpoint.angle);
    });

    test('a moving tic captures the PREVIOUS position as old and advances new',
        () {
      final World w = loadWorld();
      final PlaySim sim = PlaySim(w)..spawnLevel();
      final Mobj mo = sim.player.mo!;

      final fixed_t x0 = mo.x;
      final fixed_t y0 = mo.y;

      // Drive forward for a few tics so the player actually moves.
      for (int i = 0; i < 4; i++) {
        sim.tic(forward(50));
      }
      // Capture the position BEFORE the next tic, run it, and confirm old now
      // holds that pre-tic value while current advanced.
      final fixed_t xBefore = mo.x;
      final fixed_t yBefore = mo.y;
      sim.tic(forward(50));

      expect(mo.oldX, xBefore,
          reason: 'old x should be the position at the start of this tic');
      expect(mo.oldY, yBefore);
      // The player has moved overall from the spawn point.
      expect(mo.x, isNot(equals(x0)));
      expect(mo.y, isNot(equals(y0)));
      // And advanced this last tic too (forward thrust is non-zero).
      expect(mo.x, isNot(equals(xBefore)));
    });
  });

  group('physics is untouched by interpolation infrastructure', () {
    test('two identical runs produce byte-identical NEW positions', () {
      // Run A: interpolation never enabled.
      final World wa = loadWorld();
      final PlaySim sa = PlaySim(wa)..spawnLevel();
      // Run B: interpolation enabled + a frac set (simulating the render path
      // poking the shared state between tics). The SIM must not see it.
      final World wb = loadWorld();
      final PlaySim sb = PlaySim(wb)..spawnLevel();
      wb.interp
        ..enabled = true
        ..active = true
        ..frac = kFracUnit ~/ 3;

      final List<int> cmds = <int>[50, 50, 25, -40, 0, 60, 60, 60];
      for (final int c in cmds) {
        sa.tic(forward(c));
        sb.tic(forward(c));
      }

      final Mobj ma = sa.player.mo!;
      final Mobj mb = sb.player.mo!;
      // The simulation NEW positions must be bit-identical: interpolation never
      // feeds back into physics.
      expect(mb.x, ma.x);
      expect(mb.y, ma.y);
      expect(mb.z, ma.z);
      expect(mb.momX, ma.momX);
      expect(mb.momY, ma.momY);
      expect(mb.angle, ma.angle);
      expect(sb.levelTime, sa.levelTime);
      // Viewpoint (what the renderer reads) advanced identically too.
      expect(wb.viewpoint.x, wa.viewpoint.x);
      expect(wb.viewpoint.y, wa.viewpoint.y);
      expect(wb.viewpoint.z, wa.viewpoint.z);
      expect(wb.viewpoint.angle, wa.viewpoint.angle);
    });
  });

  group('snapInterpolation', () {
    test('forces old == current across a discontinuity', () {
      final World w = loadWorld();
      final PlaySim sim = PlaySim(w)..spawnLevel();
      final Mobj mo = sim.player.mo!;
      // Drive forward so old != current within a tic, then snap.
      sim.tic(forward(50));
      // Artificially desync old to a far value, then snap should re-sync.
      mo.oldX = toInt32(mo.x - 9999 * kFracUnit);
      sim.snapInterpolation();
      expect(mo.oldX, mo.x);
      expect(w.viewpoint.oldX, w.viewpoint.x);
    });
  });
}
