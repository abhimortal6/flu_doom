// Integration adapter: bridges the play-sim's live mobjs + the WAD sprite
// lumps to the 3D renderer's [SpriteSource] / [SpriteResolver] interfaces.
//
// Two responsibilities, both faithful to vanilla Doom r_things.c:
//
//  1. [PlaySpriteAdapter] (a renderer `SpriteSource`): each frame, iterate the
//     play-sim's active mobjs and emit one [SpriteRequest] per mobj — world
//     position, facing angle (the renderer derives the view-relative rotation
//     itself), sprite/frame, the mobj's sector light level, and the
//     full-bright / shadow flags.
//
//  2. [WadSpriteResolver] (a renderer `SpriteResolver`): builds the vanilla
//     `sprites[]` / `spriteframe_t` table from the S_START..S_END lumps
//     (R_InitSprites / R_InstallSpriteLump) and resolves a
//     (spriteNum, frame, rotation) triple to the WAD patch bytes + flip flag.
//
// `spriteNum` is the opaque key the renderer round-trips: here it is the
// play-sim [SpriteNum] enum index (mobj.sprite.index), which matches the
// `spriteNames[]` table 1:1.

import '../../engine/render/sprite_source.dart';
import '../../engine/wad/wad.dart';
import '../play/info.dart';
import '../play/mobj_flags.dart';
import '../play/playsim.dart';

/// One sprite frame: up to 8 rotation lumps + per-rotation flip flags, mirroring
/// vanilla `spriteframe_t`. [rotate] false means a single lump for all angles.
class _SpriteFrame {
  bool rotate = false;
  // Indexed 0..7; -1 = no lump yet.
  final List<int> lump = List<int>.filled(8, -1);
  final List<bool> flip = List<bool>.filled(8, false);
}

/// All frames for one sprite name (vanilla `spritedef_t`).
class _SpriteDef {
  final List<_SpriteFrame> frames = <_SpriteFrame>[];
}

/// Resolves (spriteNum, frame, rot) -> WAD patch bytes, built from the WAD
/// sprite namespace exactly as vanilla R_InitSprites does.
class WadSpriteResolver implements SpriteResolver {
  WadSpriteResolver(this._wad) {
    _build();
  }

  final WadFile _wad;

  /// One [_SpriteDef] per [SpriteNum] (index-aligned with [spriteNames]).
  final List<_SpriteDef?> _defs =
      List<_SpriteDef?>.filled(spriteNames.length, null);

  void _build() {
    // Locate the S_START..S_END namespace.
    final int sStart = _wad.lumpNumForName('S_START');
    final int sEnd = _wad.lumpNumForName('S_END');
    if (sStart < 0 || sEnd < 0 || sEnd <= sStart) return;

    // Map sprite name -> index for fast lookup.
    final Map<String, int> nameToNum = <String, int>{};
    for (int i = 0; i < spriteNames.length; i++) {
      nameToNum[spriteNames[i]] = i;
    }

    // Temp per-sprite max frame tracking (vanilla maxframe + R_InstallSpriteLump).
    final List<int> maxFrame = List<int>.filled(spriteNames.length, -1);

    void install(int spriteNum, int frame, int rotation, int lump, bool flip) {
      _SpriteDef def = (_defs[spriteNum] ??= _SpriteDef());
      while (def.frames.length <= frame) {
        def.frames.add(_SpriteFrame());
      }
      final _SpriteFrame f = def.frames[frame];
      if (frame > maxFrame[spriteNum]) maxFrame[spriteNum] = frame;
      if (rotation == 0) {
        // Single rotation: fill all 8 slots with this lump.
        f.rotate = false;
        for (int r = 0; r < 8; r++) {
          f.lump[r] = lump;
          f.flip[r] = flip;
        }
      } else {
        f.rotate = true;
        final int r = rotation - 1;
        if (r >= 0 && r < 8 && f.lump[r] < 0) {
          f.lump[r] = lump;
          f.flip[r] = flip;
        }
      }
    }

    for (int l = sStart + 1; l < sEnd; l++) {
      final Lump lump = _wad.lumpByIndex(l);
      final String name = lump.name;
      if (name.length < 6) continue; // need NAME + frame + rot at minimum.
      final String spr = name.substring(0, 4);
      final int? num = nameToNum[spr];
      if (num == null) continue;
      final int frame = name.codeUnitAt(4) - 0x41; // 'A' -> 0
      final int rot = name.codeUnitAt(5) - 0x30; // '0' -> 0
      if (frame < 0 || rot < 0 || rot > 8) continue;
      install(num, frame, rot, l, false);
      // Optional mirrored second frame+rotation (chars 6,7), e.g. TROOA2A8.
      if (name.length >= 8) {
        final int frame2 = name.codeUnitAt(6) - 0x41;
        final int rot2 = name.codeUnitAt(7) - 0x30;
        if (frame2 >= 0 && rot2 >= 0 && rot2 <= 8) {
          install(num, frame2, rot2, l, true);
        }
      }
    }
  }

  @override
  SpriteFrameInfo? frameInfo(int spriteNum, int frame, int rot) {
    if (spriteNum < 0 || spriteNum >= _defs.length) return null;
    final _SpriteDef? def = _defs[spriteNum];
    if (def == null || frame < 0 || frame >= def.frames.length) return null;
    final _SpriteFrame f = def.frames[frame];
    final int r = (rot >= 0 && rot < 8) ? rot : 0;
    final int lump = f.lump[r];
    if (lump < 0) {
      // Fall back to rotation 0's lump if the requested one is missing.
      final int l0 = f.lump[0];
      if (l0 < 0) return null;
      return SpriteFrameInfo(
        lumpPatchBytes: _wad.lumpByIndex(l0).bytes,
        flip: f.flip[0],
      );
    }
    return SpriteFrameInfo(
      lumpPatchBytes: _wad.lumpByIndex(lump).bytes,
      flip: f.flip[r],
    );
  }

  @override
  bool isSingleRotation(int spriteNum, int frame) {
    if (spriteNum < 0 || spriteNum >= _defs.length) return true;
    final _SpriteDef? def = _defs[spriteNum];
    if (def == null || frame < 0 || frame >= def.frames.length) return true;
    return !def.frames[frame].rotate;
  }
}

/// Renderer [SpriteSource] backed by the play-sim's active mobjs.
class PlaySpriteAdapter implements SpriteSource {
  PlaySpriteAdapter(this._sim, WadFile wad)
      : _resolver = WadSpriteResolver(wad);

  final PlaySim _sim;
  final WadSpriteResolver _resolver;

  /// The built `sprites[]` resolver, exposed so the psprite adapter can SHARE
  /// it (R_InitSprites builds the table once for world things AND psprites).
  WadSpriteResolver get spriteResolver => _resolver;

  @override
  SpriteResolver get resolver => _resolver;

  @override
  void collect(List<SpriteRequest> out) {
    for (final mobjSprite in _sim.spriteSource.sprites) {
      final mobj = mobjSprite.mobj;
      // Don't draw the player's own mobj (vanilla skips mobj == camera).
      if (identical(mobj, _sim.player.mo)) continue;
      final int baseFrame = mobj.frame & ffFrameMask;
      int flags = 0;
      if ((mobj.frame & ffFullBright) != 0) {
        flags |= SpriteRequestFlags.fullBright;
      }
      if ((mobj.flags & mfShadow) != 0) {
        flags |= SpriteRequestFlags.shadow;
      }
      final int light = mobjSprite.sector?.lightLevel ?? 255;
      out.add(SpriteRequest(
        x: mobj.x,
        y: mobj.y,
        z: mobj.z,
        angle: mobj.angle,
        spriteNum: mobj.sprite.index,
        frame: baseFrame,
        lightLevel: light,
        flags: flags,
      ));
    }
  }
}
