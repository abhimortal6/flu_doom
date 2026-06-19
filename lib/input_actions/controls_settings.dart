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
/// resolution changes.
class ButtonPosition {
  const ButtonPosition(this.dx, this.dy);
  final double dx; // 0..1 fraction of width
  final double dy; // 0..1 fraction of height

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy};
  factory ButtonPosition.fromJson(Map<String, dynamic> j) =>
      ButtonPosition((j['dx'] as num).toDouble(), (j['dy'] as num).toDouble());
}

/// Configuration for the touch overlay.
class OverlaySettings {
  const OverlaySettings({
    this.visible = true,
    this.opacity = 0.45,
    this.scale = 1.0,
    this.handed = HandedLayout.right,
    this.positions = const <String, ButtonPosition>{},
  });

  /// Whether the overlay is shown at all.
  final bool visible;

  /// Overall opacity of overlay widgets (0..1).
  final double opacity;

  /// Size multiplier for buttons / stick (0.5 .. 2.0 sensible range).
  final double scale;

  /// Left/right-handed cluster layout.
  final HandedLayout handed;

  /// Optional drag-repositioned button overrides, keyed by overlay button id
  /// (see [OverlayButtonId]). Empty = use default layout positions.
  final Map<String, ButtonPosition> positions;

  OverlaySettings copyWith({
    bool? visible,
    double? opacity,
    double? scale,
    HandedLayout? handed,
    Map<String, ButtonPosition>? positions,
  }) {
    return OverlaySettings(
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      scale: scale ?? this.scale,
      handed: handed ?? this.handed,
      positions: positions ?? this.positions,
    );
  }

  Map<String, dynamic> toJson() => {
    'visible': visible,
    'opacity': opacity,
    'scale': scale,
    'handed': handed.name,
    'positions': positions.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory OverlaySettings.fromJson(Map<String, dynamic> j) {
    final posRaw = (j['positions'] as Map?) ?? const {};
    return OverlaySettings(
      visible: j['visible'] as bool? ?? true,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 0.45,
      scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
      handed: HandedLayout.values
          .where((h) => h.name == j['handed'])
          .cast<HandedLayout?>()
          .firstWhere((h) => true, orElse: () => HandedLayout.right)!,
      positions: posRaw.map(
        (k, v) => MapEntry(
          k as String,
          ButtonPosition.fromJson((v as Map).cast<String, dynamic>()),
        ),
      ),
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
