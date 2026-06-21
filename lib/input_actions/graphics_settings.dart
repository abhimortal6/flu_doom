// Immutable settings model for the video / graphics PRESENT layer, plus
// persistence (shared_preferences) — same pattern as controls_settings.dart.
//
// IMPORTANT: none of these settings touch the 3D renderer's internal resolution
// or rasterization math. The renderer always produces a full 320x200 indexed
// framebuffer (high detail; there is no low-detail / column-doubling path — see
// CONTRACTS_RENDER.md deviation #2). Everything here is applied at the PRESENT /
// upscale layer (how that 320x200 image is drawn to the device screen).

import 'dart:convert';

import 'package:flutter/widgets.dart' show FilterQuality;
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/video/video_view.dart' show ScaleMode;

/// The upscale filter applied when blitting the 320x200 framebuffer image to the
/// device screen. This is the single biggest visible quality lever.
///   - [sharp]  : nearest-neighbour (FilterQuality.none). Crisp, blocky pixels —
///                the classic look, but chunky on a high-DPI phone.
///   - [smooth] : bilinear-ish (FilterQuality.medium). Softens the blocky pixels;
///                nicer on a phone. This is the mobile default.
enum UpscaleFilter { sharp, smooth }

extension UpscaleFilterX on UpscaleFilter {
  /// Map to the Flutter [FilterQuality] used by the present painter.
  FilterQuality get filterQuality => switch (this) {
        UpscaleFilter.sharp => FilterQuality.none,
        UpscaleFilter.smooth => FilterQuality.medium,
      };
}

/// All persisted video/present options.
class GraphicsSettings {
  const GraphicsSettings({
    this.filter = UpscaleFilter.smooth,
    this.pixelAspectCorrection = true,
    this.scaleMode = ScaleMode.fit,
    this.crtScanlines = false,
    this.crtIntensity = defaultCrtIntensity,
  });

  /// Default CRT effect strength (0..1) used when the toggle is first enabled.
  static const double defaultCrtIntensity = 0.5;

  /// Upscale filter (SHARP nearest vs SMOOTH bilinear).
  final UpscaleFilter filter;

  /// Doom's 4:3 pixel-aspect correction (height * 1.2). ON by default on mobile.
  final bool pixelAspectCorrection;

  /// How the framebuffer image is fit into the device viewport.
  final ScaleMode scaleMode;

  /// Optional retro scanline (and mild glow) overlay. OFF by default.
  final bool crtScanlines;

  /// Strength of the CRT scanline + glow overlay, in the range 0.0..1.0.
  /// 0 = barely visible, 1 = strong. Only applies when [crtScanlines] is on.
  /// The raw stored value is clamped to [0, 1] on read via [crtIntensityClamped].
  final double crtIntensity;

  /// [crtIntensity] clamped to the valid 0..1 range (defensive — JSON may carry
  /// an out-of-range value).
  double get crtIntensityClamped => crtIntensity.clamp(0.0, 1.0);

  /// The CRT intensity that actually drives the present overlay: the clamped
  /// slider value when the toggle is on, or 0 (no overlay) when it is off.
  double get effectiveCrtIntensity => crtScanlines ? crtIntensityClamped : 0.0;

  GraphicsSettings copyWith({
    UpscaleFilter? filter,
    bool? pixelAspectCorrection,
    ScaleMode? scaleMode,
    bool? crtScanlines,
    double? crtIntensity,
  }) {
    return GraphicsSettings(
      filter: filter ?? this.filter,
      pixelAspectCorrection:
          pixelAspectCorrection ?? this.pixelAspectCorrection,
      scaleMode: scaleMode ?? this.scaleMode,
      crtScanlines: crtScanlines ?? this.crtScanlines,
      crtIntensity: crtIntensity ?? this.crtIntensity,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'filter': filter.name,
        'pixelAspectCorrection': pixelAspectCorrection,
        'scaleMode': scaleMode.name,
        'crtScanlines': crtScanlines,
        'crtIntensity': crtIntensity,
      };

  factory GraphicsSettings.fromJson(Map<String, dynamic> j) {
    return GraphicsSettings(
      filter: UpscaleFilter.values
          .where((f) => f.name == j['filter'])
          .cast<UpscaleFilter?>()
          .firstWhere((f) => true, orElse: () => UpscaleFilter.smooth)!,
      pixelAspectCorrection: j['pixelAspectCorrection'] as bool? ?? true,
      scaleMode: ScaleMode.values
          .where((s) => s.name == j['scaleMode'])
          .cast<ScaleMode?>()
          .firstWhere((s) => true, orElse: () => ScaleMode.fit)!,
      crtScanlines: j['crtScanlines'] as bool? ?? false,
      // Backward-compatible: pre-intensity saves omit this key -> default.
      // Tolerate int or num; clamp to 0..1.
      crtIntensity:
          ((j['crtIntensity'] as num?)?.toDouble() ?? defaultCrtIntensity)
              .clamp(0.0, 1.0),
    );
  }

  /// Sensible MOBILE default: smooth filter + 4:3 aspect correction ON, CRT off.
  factory GraphicsSettings.defaults() => const GraphicsSettings();

  @override
  bool operator ==(Object other) =>
      other is GraphicsSettings &&
      other.filter == filter &&
      other.pixelAspectCorrection == pixelAspectCorrection &&
      other.scaleMode == scaleMode &&
      other.crtScanlines == crtScanlines &&
      other.crtIntensity == crtIntensity;

  @override
  int get hashCode => Object.hash(
        filter,
        pixelAspectCorrection,
        scaleMode,
        crtScanlines,
        crtIntensity,
      );
}

/// Loads/saves [GraphicsSettings] via shared_preferences.
///
/// Persistence key: 'flu_doom.graphics' -> JSON of [GraphicsSettings].
class GraphicsSettingsStore {
  GraphicsSettingsStore(this._prefs);

  static const String graphicsKey = 'flu_doom.graphics';

  final SharedPreferences _prefs;

  /// Create a store backed by the platform default SharedPreferences.
  static Future<GraphicsSettingsStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return GraphicsSettingsStore(prefs);
  }

  /// Load settings, falling back to mobile defaults on missing/corrupt data.
  GraphicsSettings load() {
    final raw = _prefs.getString(graphicsKey);
    if (raw == null) return GraphicsSettings.defaults();
    try {
      return GraphicsSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return GraphicsSettings.defaults();
    }
  }

  Future<void> save(GraphicsSettings s) =>
      _prefs.setString(graphicsKey, jsonEncode(s.toJson()));

  /// Reset to defaults and persist.
  Future<void> resetToDefaults() => save(GraphicsSettings.defaults());
}
