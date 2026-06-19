// Shared cache of decoded [Patch]es by lump name, plus small draw helpers.
//
// The status bar, HUD, menu, automap and intermission all draw Doom "patch"
// graphics from WAD lumps (V_DrawPatch). Decoding a patch is cheap but we cache
// the decoded [Patch] per lump name so repeated frames don't re-parse. A
// missing lump returns null (callers skip it) rather than throwing, so partial
// WADs degrade gracefully.

import '../../engine/video/framebuffer.dart';
import '../../engine/video/patch.dart';
import '../../engine/wad/wad.dart';

/// Caches decoded patches keyed by lump name for a single WAD.
class GraphicsCache {
  GraphicsCache(this.wad);

  /// Source WAD (IWAD/PWAD merged).
  final WadFile wad;

  final Map<String, Patch?> _cache = <String, Patch?>{};

  /// Decode (and cache) the patch named [name], or null if the lump is absent
  /// or fails to decode. Names are matched case-insensitively via the WAD.
  Patch? patch(String name) {
    final String key = name.toUpperCase();
    final Patch? cached = _cache[key];
    if (cached != null || _cache.containsKey(key)) return cached;
    Patch? p;
    final Lump? lump = wad.lumpByName(key);
    if (lump != null) {
      try {
        p = Patch.fromBytes(lump.bytes);
      } catch (_) {
        p = null;
      }
    }
    _cache[key] = p;
    return p;
  }

  /// True if [name] resolves to a decodable patch.
  bool has(String name) => patch(name) != null;

  /// Draw patch [name] at (x, y); silently skips a missing patch. Returns the
  /// patch width drawn (0 if missing), so callers can advance a cursor.
  int draw(Framebuffer fb, String name, int x, int y) {
    final Patch? p = patch(name);
    if (p == null) return 0;
    p.draw(fb, x, y);
    return p.width;
  }
}
