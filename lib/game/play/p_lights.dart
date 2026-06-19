// Light effect thinkers, ported from Chocolate Doom src/p_lights.c +
// P_SpawnSpecials (the light-related portion of p_spec.c).
//
// Implements the common sector light animations so lit sectors visibly pulse:
// flicker (T_FireFlicker / T_LightFlash), strobe (T_StrobeFlash) and glow
// (T_Glow). P_SpawnSpecials scans sector specials and attaches the right
// thinker. Damage/secret specials are recorded but their gameplay effect is
// deferred.

import '../world/defs.dart';
import '../world/level.dart';
import 'thinker.dart';

/// GLOWSPEED / STROBEBRIGHT / FASTDARK / SLOWDARK (vanilla p_spec.h).
const int kGlowSpeed = 8;
const int kStrobeBright = 5;
const int kFastDark = 15;
const int kSlowDark = 35;

/// Simple pseudo-random for light flashes (vanilla uses P_Random / M_Random);
/// a small LCG keeps it deterministic and dependency-free.
class _Rng {
  int _s = 0x1234;
  int next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return (_s >> 16) & 0xff;
  }
}

/// T_FireFlicker: flickers a sector light between max and a low value.
class FireFlicker extends Thinker {
  FireFlicker(this.sector, this.owner);
  final Sector sector;
  final LightManager owner;
  int count = 0;
  int maxLight = 0;
  int minLight = 0;
  @override
  void tick() => owner.tickFireFlicker(this);
}

/// T_LightFlash: random on/off flashing.
class LightFlash extends Thinker {
  LightFlash(this.sector, this.owner);
  final Sector sector;
  final LightManager owner;
  int count = 0;
  int maxLight = 0;
  int minLight = 0;
  int maxTime = 0;
  int minTime = 0;
  @override
  void tick() => owner.tickLightFlash(this);
}

/// T_StrobeFlash: regular bright/dark strobe.
class StrobeFlash extends Thinker {
  StrobeFlash(this.sector, this.owner);
  final Sector sector;
  final LightManager owner;
  int count = 0;
  int minLight = 0;
  int maxLight = 0;
  int darkTime = 0;
  int brightTime = 0;
  @override
  void tick() => owner.tickStrobe(this);
}

/// T_Glow: smoothly raise/lower the light.
class GlowLight extends Thinker {
  GlowLight(this.sector, this.owner);
  final Sector sector;
  final LightManager owner;
  int minLight = 0;
  int maxLight = 0;
  int direction = 1;
  @override
  void tick() => owner.tickGlow(this);
}

/// Owns light thinkers + P_SpawnSpecials (light portion).
class LightManager {
  LightManager(this.level, this.thinkers);

  Level level;
  ThinkerList thinkers;
  final _Rng _rng = _Rng();

  /// P_FindMinSurroundingLight: lowest neighbouring light at least below max.
  int _findMinSurroundingLight(Sector sector, int max) {
    int min = max;
    for (final Line line in sector.lines) {
      final Sector? other = _getNextSector(line, sector);
      if (other != null && other.lightLevel < min) {
        min = other.lightLevel;
      }
    }
    return min;
  }

  Sector? _getNextSector(Line line, Sector sec) {
    if ((line.flags & mlTwoSided) == 0) return null;
    if (identical(line.frontSector, sec)) return line.backSector;
    return line.frontSector;
  }

  void tickFireFlicker(FireFlicker f) {
    if (--f.count > 0) return;
    final int amount = (_rng.next() & 3) * 16;
    if (f.sector.lightLevel - amount < f.minLight) {
      f.sector.lightLevel = f.minLight;
    } else {
      f.sector.lightLevel = f.maxLight - amount;
    }
    f.count = 4;
  }

  void tickLightFlash(LightFlash f) {
    if (--f.count > 0) return;
    if (f.sector.lightLevel == f.maxLight) {
      f.sector.lightLevel = f.minLight;
      f.count = (_rng.next() & f.minTime) + 1;
    } else {
      f.sector.lightLevel = f.maxLight;
      f.count = (_rng.next() & f.maxTime) + 1;
    }
  }

  void tickStrobe(StrobeFlash f) {
    if (--f.count > 0) return;
    if (f.sector.lightLevel == f.minLight) {
      f.sector.lightLevel = f.maxLight;
      f.count = f.brightTime;
    } else {
      f.sector.lightLevel = f.minLight;
      f.count = f.darkTime;
    }
  }

  void tickGlow(GlowLight g) {
    if (g.direction == -1) {
      g.sector.lightLevel -= kGlowSpeed;
      if (g.sector.lightLevel <= g.minLight) {
        g.sector.lightLevel = g.minLight;
        g.direction = 1;
      }
    } else {
      g.sector.lightLevel += kGlowSpeed;
      if (g.sector.lightLevel >= g.maxLight) {
        g.sector.lightLevel = g.maxLight;
        g.direction = -1;
      }
    }
  }

  /// P_SpawnSpecials (light portion): attach the appropriate light thinker for
  /// each sector special. Vanilla special numbers preserved.
  void spawnSpecials() {
    for (final Sector sector in level.sectors) {
      switch (sector.special) {
        case 1: // FLICKERING LIGHTS
          final LightFlash f = LightFlash(sector, this)
            ..maxLight = sector.lightLevel
            ..minLight = _findMinSurroundingLight(sector, sector.lightLevel)
            ..maxTime = 64
            ..minTime = 7
            ..count = (_rng.next() & 64) + 1;
          if (f.minLight == f.maxLight) f.minLight = 0;
          thinkers.add(f);
          sector.special = 0;
          break;
        case 2: // STROBE FAST
          _spawnStrobe(sector, kFastDark, false);
          sector.special = 0;
          break;
        case 3: // STROBE SLOW
          _spawnStrobe(sector, kSlowDark, false);
          sector.special = 0;
          break;
        case 8: // GLOWING LIGHT
          final GlowLight g = GlowLight(sector, this)
            ..minLight = _findMinSurroundingLight(sector, sector.lightLevel)
            ..maxLight = sector.lightLevel
            ..direction = -1;
          thinkers.add(g);
          sector.special = 0;
          break;
        case 12: // STROBE SLOW SYNC
          _spawnStrobe(sector, kSlowDark, true);
          break;
        case 13: // STROBE FAST SYNC
          _spawnStrobe(sector, kFastDark, true);
          break;
        case 17: // FIRE FLICKER
          final FireFlicker ff = FireFlicker(sector, this)
            ..maxLight = sector.lightLevel
            ..minLight =
                _findMinSurroundingLight(sector, sector.lightLevel) + 16
            ..count = 4;
          thinkers.add(ff);
          sector.special = 0;
          break;
        default:
          break;
      }
    }
  }

  void _spawnStrobe(Sector sector, int darkTime, bool sync) {
    final StrobeFlash f = StrobeFlash(sector, this)
      ..darkTime = darkTime
      ..brightTime = kStrobeBright
      ..maxLight = sector.lightLevel
      ..minLight = _findMinSurroundingLight(sector, sector.lightLevel);
    if (f.minLight == f.maxLight) f.minLight = 0;
    f.count = sync ? 1 : (_rng.next() & 7) + 1;
    thinkers.add(f);
  }
}
