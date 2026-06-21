// Widget tests: VideoView honors the graphics settings at the PRESENT layer.
//
// Strategy: build the VideoView, extract its CustomPaint painter, and drive
// painter.paint() against a capturing Canvas that records every drawImageRect /
// drawRect call (with the Paint used). We then assert:
//   * SHARP -> FilterQuality.none, SMOOTH -> the configured smoothing quality;
//   * pixel-aspect correction changes the destination rect height;
//   * CRT scanlines add extra overlay draws on top of the single image blit.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/video/video_view.dart';

Future<ui.Image> _image(int w, int h) async {
  final Uint8List rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final desc = ui.ImageDescriptor.raw(buffer,
      width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await desc.instantiateCodec();
  final frame = await codec.getNextFrame();
  buffer.dispose();
  desc.dispose();
  codec.dispose();
  return frame.image;
}

/// A Canvas that records image-rect blits and rect fills with their paints.
class _RecordingCanvas implements Canvas {
  final List<({Rect dst, FilterQuality fq})> blits = [];
  final List<({Rect rect, int alpha, BlendMode blend})> rectDraws = [];

  // Back-compat accessor for existing assertions (just the rects).
  List<Rect> get rects =>
      rectDraws.map((e) => e.rect).toList(growable: false);

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    blits.add((dst: dst, fq: paint.filterQuality));
  }

  @override
  void drawRect(Rect rect, Paint paint) => rectDraws.add((
        rect: rect,
        alpha: (paint.color.a * 255.0).round().clamp(0, 255),
        blend: paint.blendMode,
      ));

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Build a VideoView, grab its painter, and paint into a recording canvas.
/// Image decode must run OUTSIDE the fake-async zone (tester.runAsync), or the
/// codec future never resolves.
Future<_RecordingCanvas> _capture(
  WidgetTester tester,
  VideoView Function(ui.Image img) build, {
  Size size = const Size(640, 400),
  int srcW = 320,
  int srcH = 200,
}) async {
  final ui.Image img =
      (await tester.runAsync<ui.Image>(() => _image(srcW, srcH)))!;
  final VideoView view = build(img);
  await tester.pumpWidget(
    Center(child: SizedBox(width: size.width, height: size.height, child: view)),
  );
  final CustomPaint cp = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.byWidget(view),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
  final rec = _RecordingCanvas();
  cp.painter!.paint(rec, size);
  img.dispose();
  return rec;
}

void main() {
  testWidgets('SHARP uses FilterQuality.none, SMOOTH uses smoothing',
      (tester) async {
    final sharp = await _capture(
      tester,
      (img) => VideoView(image: img, filterQuality: FilterQuality.none),
    );
    expect(sharp.blits.single.fq, FilterQuality.none);

    final smooth = await _capture(
      tester,
      (img) => VideoView(image: img, filterQuality: FilterQuality.medium),
    );
    expect(smooth.blits.single.fq, FilterQuality.medium);
  });

  testWidgets('4:3 pixel-aspect correction makes the dest rect taller',
      (tester) async {
    // Narrow+tall viewport so width is the constraint: both fit at scale 1.0,
    // and only the corrected one stretches height x1.2 (200 -> 240).
    const size = Size(320, 600);
    final noCorr = await _capture(
      tester,
      (img) => VideoView(image: img, pixelAspectCorrection: false),
      size: size,
    );
    final corr = await _capture(
      tester,
      (img) => VideoView(image: img, pixelAspectCorrection: true),
      size: size,
    );

    expect(noCorr.blits.single.dst.height, 200.0);
    expect(corr.blits.single.dst.height, 240.0); // 200 * 1.2
    expect(corr.blits.single.dst.height,
        greaterThan(noCorr.blits.single.dst.height));
  });

  testWidgets('scale mode integer snaps to a whole multiple of 320x200',
      (tester) async {
    // 700x460 viewport -> integer scale 2 -> 640x400 dest exactly.
    final rec = await _capture(
      tester,
      (img) => VideoView(image: img, scaleMode: ScaleMode.integer),
      size: const Size(700, 460),
    );
    final dst = rec.blits.single.dst;
    expect(dst.width, 640.0); // 320 * 2
    expect(dst.height, 400.0); // 200 * 2
  });

  testWidgets('CRT scanlines add overlay draws on top of the image blit',
      (tester) async {
    final plain = await _capture(tester, (img) => VideoView(image: img));
    expect(plain.rects, isEmpty, reason: 'no overlay without CRT');

    final crt = await _capture(
      tester,
      (img) => VideoView(image: img, crtScanlines: true),
    );
    expect(crt.blits, hasLength(1)); // still exactly one framebuffer blit
    expect(crt.rects, isNotEmpty, reason: 'scanline + glow overlay rects');
  });

  // Total "ink" the overlay lays down: sum of alpha over every overlay rect
  // (scanlines + glow). Higher intensity must mean strictly more ink.
  int overlayInk(_RecordingCanvas rec) =>
      rec.rectDraws.fold(0, (sum, e) => sum + e.alpha);

  testWidgets('higher crtIntensity -> stronger overlay (more total alpha ink)',
      (tester) async {
    final low = await _capture(
      tester,
      (img) => VideoView(image: img, crtScanlines: true, crtIntensity: 0.2),
    );
    final high = await _capture(
      tester,
      (img) => VideoView(image: img, crtScanlines: true, crtIntensity: 1.0),
    );

    // Same number of overlay rects (glow + same scanline rows), but the high
    // setting paints with strictly more alpha -> stronger effect.
    expect(low.rectDraws, isNotEmpty);
    expect(high.rectDraws, isNotEmpty);
    expect(overlayInk(high), greaterThan(overlayInk(low)),
        reason: 'intensity 1.0 must lay down more ink than 0.2');

    // Both the glow (additive/plus blend) and scanline alphas scale up.
    final lowGlow = low.rectDraws
        .firstWhere((e) => e.blend == BlendMode.plus)
        .alpha;
    final highGlow = high.rectDraws
        .firstWhere((e) => e.blend == BlendMode.plus)
        .alpha;
    expect(highGlow, greaterThan(lowGlow), reason: 'glow scales with intensity');

    final lowLine = low.rectDraws
        .firstWhere((e) => e.blend != BlendMode.plus)
        .alpha;
    final highLine = high.rectDraws
        .firstWhere((e) => e.blend != BlendMode.plus)
        .alpha;
    expect(highLine, greaterThan(lowLine),
        reason: 'scanline darkness scales with intensity');
  });

  testWidgets('crtIntensity 0 with CRT on draws no overlay ink',
      (tester) async {
    final zero = await _capture(
      tester,
      (img) => VideoView(image: img, crtScanlines: true, crtIntensity: 0.0),
    );
    expect(zero.blits, hasLength(1)); // framebuffer still blitted
    expect(zero.rectDraws, isEmpty,
        reason: 'intensity 0 => barely-there: overlay skipped entirely');
  });

  testWidgets('VideoView exposes crtIntensity param', (tester) async {
    const view = VideoView(image: null, crtScanlines: true, crtIntensity: 0.8);
    expect(view.crtIntensity, 0.8);
  });

  testWidgets('VideoView exposes the present params', (tester) async {
    const view = VideoView(
      image: null,
      scaleMode: ScaleMode.integer,
      pixelAspectCorrection: true,
      filterQuality: FilterQuality.medium,
      crtScanlines: true,
    );
    expect(view.scaleMode, ScaleMode.integer);
    expect(view.pixelAspectCorrection, true);
    expect(view.filterQuality, FilterQuality.medium);
    expect(view.crtScanlines, true);
  });
}
