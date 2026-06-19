// Offset-aware patch drawing for the HUD / status bar.
//
// Vanilla `V_DrawPatch(x, y, patch)` positions the patch by SUBTRACTING the
// patch's left/top offset:  x -= patch->leftoffset; y -= patch->topoffset.
// All st_stuff.c / hu_stuff.c layout constants assume this. The foundation
// `Patch.draw(fb, x, y)` draws at the raw top-left (no offset subtraction), so
// HUD elements with non-zero offsets (the face STFST* lo=-5/to=-2, STTNUM1
// lo=-1, STKEYS to=-1, STTMINUS to=-5, ...) land in the wrong place.
//
// This helper reproduces V_DrawPatch positioning without modifying the
// foundation Patch (which other full-screen graphics with zero offsets rely
// on). HUD code must draw through [drawPatchV] / [VPatch.drawV].

import '../../engine/video/framebuffer.dart';
import '../../engine/video/patch.dart';

/// V_DrawPatch-faithful draw: the patch's offset is subtracted from (x, y).
void drawPatchV(Patch p, Framebuffer fb, int x, int y) {
  p.draw(fb, x - p.leftOffset, y - p.topOffset);
}

extension VPatch on Patch {
  /// V_DrawPatch positioning (subtracts the patch offsets).
  void drawV(Framebuffer fb, int x, int y) => drawPatchV(this, fb, x, y);
}
