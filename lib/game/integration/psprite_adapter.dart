// Integration adapter: bridges the play-sim's live player weapon sprites
// (player.psprites[], pspdef_t) to the renderer's [PspriteSource] interface.
//
// Faithful to vanilla R_DrawPlayerSprites (r_things.c): each frame, for each
// active psprite (vanilla `if (psp->state)`), read its state's sprite + frame
// and its sx/sy screen offsets, plus the player's extralight, the sector light
// under the player's eye, and the invisibility/shadow-draw condition.
//
// Patch resolution reuses the SHARED [WadSpriteResolver] (the same built
// `sprites[]` table the world things use) so weapon lumps (PISG/PISF/SHTG/...)
// resolve through the identical R_InitSprites path. psprites always draw
// rotation 0 (vanilla lump[0]).

import '../../engine/render/psprite_source.dart';
import '../../engine/render/sprite_source.dart';
import '../play/info.dart';
import '../play/info_tables.dart';
import '../play/player.dart';
import '../play/playsim.dart';
import 'sprite_adapter.dart';

/// pw_invisibility index (doomdef.h powertype_t): invulnerability, strength,
/// invisibility, ironfeet, allmap, infrared.
const int _pwInvisibility = 2;

/// Renderer [PspriteSource] backed by the play-sim's live player.
class PlayPspriteAdapter implements PspriteSource {
  PlayPspriteAdapter(this._sim, this._resolver);

  final PlaySim _sim;
  final WadSpriteResolver _resolver;

  Player get _player => _sim.player;

  @override
  SpriteResolver get resolver => _resolver;

  @override
  int get extraLight => _player.extraLight;

  @override
  int get sectorLightLevel =>
      _player.mo?.subsectorSector?.lightLevel ?? 0;

  @override
  bool get invisible {
    final int t = _player.powers[_pwInvisibility];
    return t > 4 * 32 || (t & 8) != 0;
  }

  @override
  void collect(List<PspriteRequest> out) {
    // add all active psprites, in slot order (weapon then flash).
    for (final Pspdef psp in _player.psprites) {
      // vanilla: if (psp->state).  stateIndex <= 0 means S_NULL / inactive.
      if (psp.stateIndex <= 0) continue;
      final State st = states[psp.stateIndex];
      out.add(PspriteRequest(
        spriteNum: st.sprite.index,
        frame: st.frame & ffFrameMask,
        sx: psp.sx,
        sy: psp.sy,
        fullBright: (st.frame & ffFullBright) != 0,
      ));
    }
  }
}
