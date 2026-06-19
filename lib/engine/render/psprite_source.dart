// Player-weapon sprite (psprite) dependency-inversion boundary.
//
// Vanilla R_DrawPlayerSprites (r_things.c) reads `viewplayer->psprites[]`
// (the weapon + flash pspdef_t), each pspdef's `state` (-> sprite + frame),
// its `sx`/`sy` screen offsets, the player's `extralight`, and the player's
// invisibility power + the active `fixedcolormap`, then draws the two sprites
// on top of everything in the masked pass.
//
// The renderer must not depend on the play-sim `player_t`/`pspdef_t`, so the
// integration layer adapts the live player into this interface, analogous to
// [SpriteSource] for world things. Patch resolution reuses the same
// [SpriteResolver] the world sprites use (psprites always use rotation 0,
// i.e. spriteframe lump[0], exactly as vanilla R_DrawPSprite).

import '../math/fixed.dart';
import 'sprite_source.dart';

/// One active player sprite to draw (vanilla pspdef_t projected for drawing).
/// Mirrors the fields R_DrawPSprite reads from `psp` + `psp->state`.
class PspriteRequest {
  const PspriteRequest({
    required this.spriteNum,
    required this.frame,
    required this.sx,
    required this.sy,
    required this.fullBright,
  });

  /// Sprite index into the shared [SpriteResolver] (vanilla
  /// `psp->state->sprite`). Opaque key, same space as world [SpriteRequest].
  final int spriteNum;

  /// Base subframe, vanilla `psp->state->frame & FF_FRAMEMASK`.
  final int frame;

  /// Horizontal psprite offset (fixed_t). Vanilla `psp->sx`.
  final fixed_t sx;

  /// Vertical psprite offset (fixed_t). Vanilla `psp->sy`.
  final fixed_t sy;

  /// Whether `psp->state->frame & FF_FULLBRIGHT` is set.
  final bool fullBright;
}

/// Supplies the player-weapon psprites + their lighting context to the renderer.
/// Implemented by the integration layer over the live `Player`.
///
/// The renderer calls [collect] once at the end of the masked pass and draws
/// each request in order (weapon first, then flash) — vanilla iterates
/// `psprites[NUMPSPRITES]` in slot order.
abstract interface class PspriteSource {
  /// The resolver turning (spriteNum, frame, rot) into patch bytes. Shared with
  /// the world sprite source so both use the one built `sprites[]` table.
  SpriteResolver get resolver;

  /// Append every ACTIVE psprite (vanilla: `if (psp->state)`), in slot order,
  /// into [out].
  void collect(List<PspriteRequest> out);

  /// The player's `extralight` (muzzle-flash brightener). Vanilla `extralight`
  /// is added to the psprite light level in R_DrawPlayerSprites.
  int get extraLight;

  /// Sector light level (0..255) under the player's eye. Vanilla reads
  /// `viewplayer->mo->subsector->sector->lightlevel`.
  int get sectorLightLevel;

  /// True while the spectre/invisibility "shadow draw" applies to psprites.
  /// Vanilla: `powers[pw_invisibility] > 4*32 || powers[pw_invisibility] & 8`.
  bool get invisible;
}

/// A psprite source that draws nothing (valid: no weapon on screen).
class EmptyPspriteSource implements PspriteSource {
  const EmptyPspriteSource();

  @override
  SpriteResolver get resolver => const _NullPspriteResolver();

  @override
  void collect(List<PspriteRequest> out) {}

  @override
  int get extraLight => 0;

  @override
  int get sectorLightLevel => 0;

  @override
  bool get invisible => false;
}

class _NullPspriteResolver implements SpriteResolver {
  const _NullPspriteResolver();
  @override
  SpriteFrameInfo? frameInfo(int spriteNum, int frame, int rot) => null;
  @override
  bool isSingleRotation(int spriteNum, int frame) => true;
}
