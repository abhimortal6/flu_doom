// SpriteSource adapter: exposes the active mobjs as drawable sprite records
// for the renderer (R_AddSprites / R_ProjectSprite inputs).
//
// The renderer agent runs concurrently and has not published CONTRACTS_RENDER.md
// yet (no abstract SpriteSource exists in the tree at the time of writing). To
// avoid blocking, this file defines a self-contained, renderer-friendly
// [PlaySpriteSource] / [MobjSprite] view over the thinker list. When the
// renderer publishes its abstract SpriteSource, integration can either make
// [PlaySpriteSource] implement it (the field set matches the documented
// x/y/z/angle/sprite/frame/flags/sector contract) or wrap it — see
// lib/CONTRACTS_PLAY.md.

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../world/defs.dart';
import 'info.dart';
import 'mobj.dart';
import 'thinker.dart';

/// A single drawable sprite, the subset the renderer needs per mobj.
class MobjSprite {
  MobjSprite(this.mobj);

  final Mobj mobj;

  fixed_t get x => mobj.x;
  fixed_t get y => mobj.y;
  fixed_t get z => mobj.z;
  angle_t get angle => mobj.angle;

  /// Sprite enum + sub-frame (FF_FULLBRIGHT bit included in [frame]).
  SpriteNum get sprite => mobj.sprite;
  int get frame => mobj.frame;
  bool get fullBright => (mobj.frame & ffFullBright) != 0;
  int get baseFrame => mobj.frame & ffFrameMask;

  int get flags => mobj.flags;

  /// The sector the mobj is in (for light level + clipping).
  Sector? get sector => mobj.subsectorSector;
}

/// Live view over the playsim's thinkers, yielding one [MobjSprite] per mobj.
class PlaySpriteSource {
  PlaySpriteSource(this._thinkers);

  final ThinkerList _thinkers;

  /// All currently-active mobjs as drawable sprites.
  Iterable<MobjSprite> get sprites sync* {
    for (final Thinker t in _thinkers.thinkers) {
      if (t is Mobj) yield MobjSprite(t);
    }
  }
}
