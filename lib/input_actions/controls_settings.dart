// Immutable settings model for the on-screen overlay controls, plus persistence
// (shared_preferences) of both the overlay config AND the keyboard bindings.
//
// All values are JSON-serializable. A single persistence facade
// ([ControlsSettingsStore]) loads/saves everything and supplies sane defaults +
// reset-to-defaults.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'key_bindings.dart';

/// Which side the movement stick sits on. Action buttons mirror to the opposite
/// side. [right] = right-handed (movement left, actions right) is the default.
enum HandedLayout { right, left }

/// Optional per-button position override (drag-to-reposition). Stored as a
/// fractional offset of the available area (0..1) so it survives orientation /
/// resolution changes. (dx, dy) is the normalized CENTER of the button within
/// the overlay's usable area: dx = 0 is the left edge, dx = 1 the right edge,
/// dy = 0 the top, dy = 1 the bottom. The live overlay multiplies these by the
/// actual pixel extent (and clamps so the button body stays on-screen), so the
/// same fraction lands proportionally on any resolution.
class ButtonPosition {
  const ButtonPosition(this.dx, this.dy);
  final double dx; // 0..1 fraction of width (button center)
  final double dy; // 0..1 fraction of height (button center)

  /// Clamp both axes into [0, 1].
  ButtonPosition clamped() =>
      ButtonPosition(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy};
  factory ButtonPosition.fromJson(Map<String, dynamic> j) =>
      ButtonPosition((j['dx'] as num).toDouble(), (j['dy'] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is ButtonPosition && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);
}

/// Configuration for the touch overlay.
class OverlaySettings {
  const OverlaySettings({
    this.visible = true,
    this.opacity = 0.45,
    this.scale = 1.0,
    this.handed = HandedLayout.right,
    this.lookSensitivity = 2.0,
    this.positionsPortrait = const <String, ButtonPosition>{},
    this.positionsLandscape = const <String, ButtonPosition>{},
  });

  /// Whether the overlay is shown at all.
  final bool visible;

  /// Overall opacity of overlay widgets (0..1).
  final double opacity;

  /// Size multiplier for buttons / stick (0.5 .. 2.0 sensible range).
  final double scale;

  /// Left/right-handed cluster layout.
  final HandedLayout handed;

  /// Drag-to-look (camera) sensitivity multiplier applied on top of the base
  /// look gain (`kLookBaseGain` in analog_input.dart). Default 2.0 = brisk
  /// feel; higher turns faster per unit of horizontal drag. UI range 0.5..8.0.
  /// To change the OVERALL feel for everyone, nudge kLookBaseGain instead — this
  /// slider just scales around that baseline.
  final double lookSensitivity;

  /// Optional drag-repositioned button overrides for PORTRAIT, keyed by overlay
  /// button id (see [OverlayButtonId]). Empty = use the built-in default layout.
  /// Kept SEPARATE from landscape because the two layouts differ — dragging a
  /// button in one orientation must not move it in the other.
  final Map<String, ButtonPosition> positionsPortrait;

  /// Optional drag-repositioned button overrides for LANDSCAPE. See
  /// [positionsPortrait].
  final Map<String, ButtonPosition> positionsLandscape;

  /// The override map for the given orientation (`landscape == true` picks the
  /// landscape map).
  Map<String, ButtonPosition> positionsFor(bool landscape) =>
      landscape ? positionsLandscape : positionsPortrait;

  /// A copy with [positions] applied as the override map for the given
  /// orientation, leaving the other orientation untouched.
  OverlaySettings withPositionsFor(
    bool landscape,
    Map<String, ButtonPosition> positions,
  ) {
    return landscape
        ? copyWith(positionsLandscape: positions)
        : copyWith(positionsPortrait: positions);
  }

  OverlaySettings copyWith({
    bool? visible,
    double? opacity,
    double? scale,
    HandedLayout? handed,
    double? lookSensitivity,
    Map<String, ButtonPosition>? positionsPortrait,
    Map<String, ButtonPosition>? positionsLandscape,
  }) {
    return OverlaySettings(
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      scale: scale ?? this.scale,
      handed: handed ?? this.handed,
      lookSensitivity: lookSensitivity ?? this.lookSensitivity,
      positionsPortrait: positionsPortrait ?? this.positionsPortrait,
      positionsLandscape: positionsLandscape ?? this.positionsLandscape,
    );
  }

  Map<String, dynamic> toJson() => {
    'visible': visible,
    'opacity': opacity,
    'scale': scale,
    'handed': handed.name,
    'lookSensitivity': lookSensitivity,
    'positionsPortrait':
        positionsPortrait.map((k, v) => MapEntry(k, v.toJson())),
    'positionsLandscape':
        positionsLandscape.map((k, v) => MapEntry(k, v.toJson())),
  };

  static Map<String, ButtonPosition> _decodePositions(Object? raw) {
    final Map src = (raw as Map?) ?? const {};
    return src.map(
      (k, v) => MapEntry(
        k as String,
        ButtonPosition.fromJson((v as Map).cast<String, dynamic>()),
      ),
    );
  }

  factory OverlaySettings.fromJson(Map<String, dynamic> j) {
    return OverlaySettings(
      visible: j['visible'] as bool? ?? true,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 0.45,
      scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
      lookSensitivity: (j['lookSensitivity'] as num?)?.toDouble() ?? 2.0,
      handed: HandedLayout.values
          .where((h) => h.name == j['handed'])
          .cast<HandedLayout?>()
          .firstWhere((h) => true, orElse: () => HandedLayout.right)!,
      // Back-compat: an older single 'positions' map (orientation-agnostic) is
      // adopted as the portrait map so previously-saved layouts aren't lost.
      positionsPortrait: _decodePositions(
        j['positionsPortrait'] ?? j['positions'],
      ),
      positionsLandscape: _decodePositions(j['positionsLandscape']),
    );
  }

  factory OverlaySettings.defaults() => const OverlaySettings();
}

/// Loads/saves controls settings via shared_preferences.
///
/// Persistence keys:
///   'flu_doom.controls.overlay'  -> JSON of [OverlaySettings]
///   'flu_doom.controls.bindings' -> JSON of [KeyBindings] (keyId->action.name)
class ControlsSettingsStore {
  ControlsSettingsStore(this._prefs);

  static const String overlayKey = 'flu_doom.controls.overlay';
  static const String bindingsKey = 'flu_doom.controls.bindings';

  final SharedPreferences _prefs;

  /// Create a store backed by the platform default SharedPreferences.
  static Future<ControlsSettingsStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return ControlsSettingsStore(prefs);
  }

  /// Load overlay settings, falling back to defaults on missing/corrupt data.
  OverlaySettings loadOverlay() {
    final raw = _prefs.getString(overlayKey);
    if (raw == null) return OverlaySettings.defaults();
    try {
      return OverlaySettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return OverlaySettings.defaults();
    }
  }

  Future<void> saveOverlay(OverlaySettings s) =>
      _prefs.setString(overlayKey, jsonEncode(s.toJson()));

  /// Load key bindings, falling back to vanilla defaults.
  KeyBindings loadBindings() {
    final raw = _prefs.getString(bindingsKey);
    if (raw == null) return KeyBindings.defaults();
    try {
      return KeyBindings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return KeyBindings.defaults();
    }
  }

  Future<void> saveBindings(KeyBindings b) =>
      _prefs.setString(bindingsKey, jsonEncode(b.toJson()));

  /// Reset both overlay + bindings to defaults and persist.
  Future<void> resetToDefaults() async {
    await saveOverlay(OverlaySettings.defaults());
    await saveBindings(KeyBindings.defaults());
  }
}
