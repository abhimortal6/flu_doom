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

import '../../game/world/world.dart';
import '../math/angle.dart';
import '../video/framebuffer.dart';
import '../video/palette.dart';
import 'bsp.dart';
import 'draw.dart';
import 'planes.dart';
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
    _bsp = BspRenderer(state: _state, segs: _segs, planes: _planes);
    _things = ThingRenderer(
      state: _state,
      draw: _draw,
      segRenderer: _segs,
      textures: world.textures,
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
  /// [framebuffer], drawing the things supplied by [sprites].
  ///
  /// This is the per-frame integration entry point. Integration code calls it
  /// once inside the GameLoop's onRender hook after the playsim has written the
  /// viewpoint.
  void renderPlayerView([SpriteSource sprites = const EmptySpriteSource()]) {
    final vp = world.viewpoint;
    _state.setupFrame(
      x: vp.x,
      y: vp.y,
      z: vp.z,
      angle: normAngle(vp.angle),
      extraLight: 0,
    );
    _planes.setupFrame();
    _planes.clearPlanes();
    _segs.clear();

    final level = world.level;
    _bsp.render(
      segsList: level.segs,
      subsectors: level.subsectors,
      nodes: level.nodes,
      rootNode: level.rootNode,
    );

    _planes.drawPlanes();
    _things.drawMasked(sprites);
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
