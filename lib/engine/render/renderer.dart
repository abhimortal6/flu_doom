// Top-level 3D renderer — R_RenderPlayerView, ported from Chocolate Doom
// r_main.c. Given a [World] (level geometry + viewpoint + textures) and a
// [Framebuffer], it renders one full 3D frame:
//
//   1. R_SetupFrame      — copy the camera, precompute view trig + clip arrays.
//   2. R_ClearPlanes     — reset the visplane manager.
//   3. R_RenderBSPNode   — walk the BSP front-to-back, drawing solid/2-sided
//                          walls (R_StoreWallRange / R_RenderSegLoop) and
//                          registering floor/ceiling visplanes.
//   4. R_DrawPlanes      — rasterize all floor/ceiling flats + the sky.
//   5. R_DrawMasked      — project + sort sprites and draw them and the masked
//                          midtextures, clipped against the drawsegs.
//
// Build a [Renderer] once for a given framebuffer; call [renderPlayerView] each
// frame. The renderer READS the world only (per CONTRACTS_WORLD.md). Sprites
// arrive via a [SpriteSource] (dependency inversion) — an [EmptySpriteSource]
// renders a valid view with no things.

import '../../game/world/defs.dart';
import '../../game/world/world.dart';
import '../math/angle.dart';
import '../math/fixed.dart';
import '../system/interpolation.dart';
import '../video/framebuffer.dart';
import '../video/palette.dart';
import 'bsp.dart';
import 'draw.dart';
import 'planes.dart';
import 'psprite_source.dart';
import 'render_state.dart';
import 'segs.dart';
import 'sprite_source.dart';
import 'things.dart';

/// The faithful vanilla-Doom 3D view renderer (R_RenderPlayerView).
class Renderer {
  Renderer({
    required this.framebuffer,
    required this.world,
  }) : _draw = DrawContext(framebuffer) {
    final colormap = Colormap.fromWad(world.wad);
    _state = RenderState(
      screenWidth: framebuffer.width,
      screenHeight: framebuffer.height,
      colormap: colormap,
    );
    _draw.centerY = _state.centerY;

    // Sky: F_SKY1 flat means "draw the sky"; sky texture is map-episode based.
    final int skyFlat = world.textures.checkFlatNumForName('F_SKY1');
    final int skyTex = _resolveSkyTexture(world);

    _planes = PlaneRenderer(
      state: _state,
      draw: _draw,
      textures: world.textures,
      skyTexture: skyTex,
      skyFlatNum: skyFlat < 0 ? -1 : skyFlat,
    );
    _segs = SegRenderer(
      state: _state,
      draw: _draw,
      planes: _planes,
      textures: world.textures,
      skyFlatNum: skyFlat < 0 ? -1 : skyFlat,
    );
    _things = ThingRenderer(
      state: _state,
      draw: _draw,
      segRenderer: _segs,
      textures: world.textures,
    );
    _bsp = BspRenderer(
      state: _state,
      segs: _segs,
      planes: _planes,
      things: _things,
    );
  }

  final Framebuffer framebuffer;

  /// The world to render. Reads only (per CONTRACTS_WORLD.md). May be replaced
  /// after a level change (tables/state are reused).
  World world;
  final DrawContext _draw;
  late final RenderState _state;
  late final PlaneRenderer _planes;
  late final SegRenderer _segs;
  late final BspRenderer _bsp;
  late final ThingRenderer _things;

  /// The render state, exposed for tests / debug.
  RenderState get state => _state;

  /// R_RenderPlayerView: render one frame from [world.viewpoint] into
  /// [framebuffer], drawing the world things supplied by [sprites] and the
  /// player weapon psprites supplied by [psprites].
  ///
  /// This is the per-frame integration entry point. Integration code calls it
  /// once inside the GameLoop's onRender hook after the playsim has written the
  /// viewpoint. [psprites] carries the player's `extralight` (R_SetupFrame reads
  /// `player->extralight`) and the weapon/flash psprites drawn last
  /// (R_DrawPlayerSprites). Pass nothing for a view with no weapon.
  void renderPlayerView([
    SpriteSource sprites = const EmptySpriteSource(),
    PspriteSource psprites = const EmptyPspriteSource(),
  ]) {
    final vp = world.viewpoint;
    final InterpolationState interp = world.interp;
    final bool lerp = interp.interpolating;
    final fixed_t frac = interp.renderFrac;

    // FRAME INTERPOLATION (Crispy R_InterpolateView): blend the previous tic's
    // viewpoint toward the current one by the inter-tic fraction. At
    // renderFrac == FRACUNIT (off / paused / old==new) every lerp returns the
    // CURRENT value, so R_SetupFrame gets exactly today's camera (golden holds).
    fixed_t vx = vp.x, vy = vp.y, vz = vp.z;
    angle_t va = vp.angle;
    if (lerp) {
      // Snap on a large view jump (teleport / level load) — no smear.
      const fixed_t snapThreshold = 128 * kFracUnit;
      final bool snap =
          (toInt32(vp.x - vp.oldX)).abs() > snapThreshold ||
              (toInt32(vp.y - vp.oldY)).abs() > snapThreshold ||
              (toInt32(vp.z - vp.oldZ)).abs() > snapThreshold;
      if (!snap) {
        vx = lerpFixed(vp.oldX, vp.x, frac);
        vy = lerpFixed(vp.oldY, vp.y, frac);
        vz = lerpFixed(vp.oldZ, vp.z, frac);
        va = lerpAngle(vp.oldAngle, vp.angle, frac);
      }
    }

    // FRAME INTERPOLATION (Crispy interpolated sector heights): temporarily write
    // lerp(old, current, frac) into the real floorHeight/ceilingHeight of moving
    // sectors so the ~30 renderer read sites (segs/bsp/planes) draw the
    // in-between height. Restored after the frame (see [_restoreSectors]) so the
    // sim never observes the interpolated value. No-op when not interpolating.
    final List<Sector>? interpSectors =
        lerp ? _interpolateSectors(frac) : null;

    // R_SetupFrame (vanilla copies extralight = player->extralight).
    _state.setupFrame(
      x: vx,
      y: vy,
      z: vz,
      angle: normAngle(va),
      extraLight: psprites.extraLight,
    );
    _draw.centerY = _state.centerY;

    // Clear buffers — EXACT vanilla R_RenderPlayerView order. Every one of
    // these runs EVERY frame; missing any leaves stale clip/visplane/drawseg
    // data that smears walls as the camera turns.
    _bsp.clearClipSegs(); // R_ClearClipSegs (solidsegs sentinels)
    _segs.clearDrawSegs(); // R_ClearDrawSegs (ds_p = drawsegs)
    _segs.clearOpenings(); // lastopening = openings (part of R_ClearPlanes)
    _planes.clearPlanes(); // R_ClearPlanes (visplanes, floorclip/ceilingclip)
    _things.clearSprites(); // R_ClearSprites (vissprite_p = vissprites)

    final level = world.level;
    // R_RenderBSPNode(numnodes-1).
    _bsp.render(
      segsList: level.segs,
      subsectors: level.subsectors,
      nodes: level.nodes,
      rootNode: level.rootNode,
    );

    _planes.drawPlanes(); // R_DrawPlanes
    _things.drawMasked(sprites, psprites); // R_DrawMasked (+ psprites)

    // R_RestoreInterpolations: put the real (current-tic) sector heights back so
    // the simulation never observes the interpolated values. Critically, this
    // does NOT clobber the captured old* heights, so EVERY render frame within
    // the same tic re-blends from the same (old, current) pair.
    if (interpSectors != null) _restoreSectors();
  }

  // FRAME INTERPOLATION sector-height helpers (Crispy R_InterpolateView /
  // R_RestoreInterpolations). Write lerped heights into the live sector fields
  // for the duration of one frame; remember the true current heights in a side
  // table so they can be restored afterward WITHOUT touching the captured old*.
  static const fixed_t _sectorSnapThreshold = 128 * kFracUnit;
  final List<Sector> _interpTouched = <Sector>[];
  final List<fixed_t> _interpSavedFloor = <fixed_t>[];
  final List<fixed_t> _interpSavedCeil = <fixed_t>[];

  List<Sector> _interpolateSectors(fixed_t frac) {
    _interpTouched.clear();
    _interpSavedFloor.clear();
    _interpSavedCeil.clear();
    for (final Sector sec in world.level.sectors) {
      // Only sectors with an active mover have meaningful old heights captured.
      if (sec.specialData == null) continue;
      final fixed_t fOld = sec.oldFloorHeight;
      final fixed_t cOld = sec.oldCeilingHeight;
      final fixed_t fNew = sec.floorHeight;
      final fixed_t cNew = sec.ceilingHeight;
      // Snap on a large jump (no smear); otherwise blend.
      final bool snap = (toInt32(fNew - fOld)).abs() > _sectorSnapThreshold ||
          (toInt32(cNew - cOld)).abs() > _sectorSnapThreshold;
      if (snap) continue;
      // Save the true current heights, then write the interpolated heights into
      // the live fields for this frame. old* are left untouched.
      _interpTouched.add(sec);
      _interpSavedFloor.add(fNew);
      _interpSavedCeil.add(cNew);
      sec.floorHeight = lerpFixed(fOld, fNew, frac);
      sec.ceilingHeight = lerpFixed(cOld, cNew, frac);
    }
    return _interpTouched;
  }

  void _restoreSectors() {
    for (int i = 0; i < _interpTouched.length; i++) {
      final Sector sec = _interpTouched[i];
      sec.floorHeight = _interpSavedFloor[i];
      sec.ceilingHeight = _interpSavedCeil[i];
    }
    _interpTouched.clear();
    _interpSavedFloor.clear();
    _interpSavedCeil.clear();
  }

  int _resolveSkyTexture(World world) {
    // Episode 1 uses SKY1; default to the first sky texture present.
    for (final String name in const <String>['SKY1', 'SKY2', 'SKY3']) {
      final int n = world.textures.checkTextureNumForName(name);
      if (n > 0) return n;
    }
    return 0;
  }
}
