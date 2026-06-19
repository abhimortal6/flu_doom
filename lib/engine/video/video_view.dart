// Widget that renders a Doom framebuffer ui.Image scaled to fit, with
// nearest-neighbour filtering (FilterQuality.none) so the 320x200 image stays
// crisp/pixelated. Works in portrait and landscape via letterboxing.
//
// Scaling modes:
//  - [ScaleMode.fit]     : auto-scale preserving the 320x200 aspect, centered
//                          and letterboxed (default).
//  - [ScaleMode.integer] : auto-scale to the largest whole-number multiple of
//                          320x200 that fits, centered (crispest, classic).
//  - [ScaleMode.fill]    : stretch to fill the whole area, ignoring aspect.
//
// Doom's 320x200 was displayed on 4:3 CRTs, i.e. with non-square (1.2x tall)
// pixels. [pixelAspectCorrection] optionally scales the height by 1.2 to match
// the original look.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'framebuffer.dart';

/// How the framebuffer image is scaled into the available space.
enum ScaleMode {
  /// Auto-fit preserving aspect ratio, letterboxed (default).
  fit,

  /// Largest integer multiple that fits, centered.
  integer,

  /// Stretch to fill, ignoring aspect ratio.
  fill,
}

/// Renders a [ui.Image] (typically produced by [Framebuffer.toImage]) scaled
/// into the available space.
class VideoView extends StatelessWidget {
  const VideoView({
    super.key,
    required this.image,
    this.scaleMode = ScaleMode.fit,
    this.pixelAspectCorrection = false,
    this.backgroundColor = const Color(0xFF000000),
  });

  /// The current frame image. May be null before the first frame is decoded.
  final ui.Image? image;

  /// Scaling strategy.
  final ScaleMode scaleMode;

  /// Apply Doom's 4:3 pixel-aspect correction (height * 1.2).
  final bool pixelAspectCorrection;

  /// Letterbox fill color.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: image == null
          ? const SizedBox.expand()
          : CustomPaint(
              size: Size.infinite,
              painter: _FramebufferPainter(
                image: image!,
                scaleMode: scaleMode,
                pixelAspectCorrection: pixelAspectCorrection,
              ),
            ),
    );
  }
}

class _FramebufferPainter extends CustomPainter {
  _FramebufferPainter({
    required this.image,
    required this.scaleMode,
    required this.pixelAspectCorrection,
  });

  final ui.Image image;
  final ScaleMode scaleMode;
  final bool pixelAspectCorrection;

  @override
  void paint(Canvas canvas, Size size) {
    final double srcW = image.width.toDouble();
    final double srcH = image.height.toDouble();
    // Logical aspect: optionally correct 320x200 (1.6) to 4:3 (1.333) by
    // treating the source as 1.2x taller.
    final double logicalH = pixelAspectCorrection ? srcH * 1.2 : srcH;

    double destW;
    double destH;
    switch (scaleMode) {
      case ScaleMode.fill:
        destW = size.width;
        destH = size.height;
      case ScaleMode.integer:
        final int sx = (size.width / srcW).floor();
        final int sy = (size.height / logicalH).floor();
        final int s = (sx < sy ? sx : sy).clamp(1, 1 << 20);
        destW = srcW * s;
        destH = logicalH * s;
      case ScaleMode.fit:
        final double scale =
            (size.width / srcW).clamp(0.0, double.infinity) <
                    (size.height / logicalH)
                ? size.width / srcW
                : size.height / logicalH;
        destW = srcW * scale;
        destH = logicalH * scale;
    }

    final double dx = (size.width - destW) / 2.0;
    final double dy = (size.height - destH) / 2.0;

    final Paint paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, srcW, srcH),
      Rect.fromLTWH(dx, dy, destW, destH),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FramebufferPainter old) =>
      old.image != image ||
      old.scaleMode != scaleMode ||
      old.pixelAspectCorrection != pixelAspectCorrection;
}
