// Persistence + model tests for GraphicsSettings / GraphicsSettingsStore.

import 'package:flutter/widgets.dart' show FilterQuality;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flu_doom/engine/video/video_view.dart' show ScaleMode;
import 'package:flu_doom/input_actions/graphics_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('mobile defaults: smooth filter, 4:3 on, fit, CRT off', () {
    const g = GraphicsSettings();
    expect(g.filter, UpscaleFilter.smooth);
    expect(g.pixelAspectCorrection, true);
    expect(g.scaleMode, ScaleMode.fit);
    expect(g.crtScanlines, false);
    // Filter maps to the right Flutter quality.
    expect(UpscaleFilter.smooth.filterQuality, FilterQuality.medium);
    expect(UpscaleFilter.sharp.filterQuality, FilterQuality.none);
  });

  test('JSON round-trip preserves all fields', () {
    const g = GraphicsSettings(
      filter: UpscaleFilter.sharp,
      pixelAspectCorrection: false,
      scaleMode: ScaleMode.integer,
      crtScanlines: true,
    );
    final back = GraphicsSettings.fromJson(g.toJson());
    expect(back, g);
  });

  test('store persists and reloads non-default settings', () async {
    final store = await GraphicsSettingsStore.open();
    // Loading before any save yields defaults.
    expect(store.load(), GraphicsSettings.defaults());

    const custom = GraphicsSettings(
      filter: UpscaleFilter.sharp,
      pixelAspectCorrection: false,
      scaleMode: ScaleMode.fill,
      crtScanlines: true,
    );
    await store.save(custom);

    // A fresh store over the same (mock) prefs reads back the saved values.
    final store2 = await GraphicsSettingsStore.open();
    expect(store2.load(), custom);
  });

  test('resetToDefaults restores mobile defaults', () async {
    final store = await GraphicsSettingsStore.open();
    await store.save(const GraphicsSettings(filter: UpscaleFilter.sharp));
    await store.resetToDefaults();
    expect(store.load(), GraphicsSettings.defaults());
  });

  test('corrupt JSON falls back to defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      GraphicsSettingsStore.graphicsKey: 'not json {',
    });
    final store = await GraphicsSettingsStore.open();
    expect(store.load(), GraphicsSettings.defaults());
  });
}
