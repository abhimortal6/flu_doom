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

  test('mobile defaults: smooth filter, 4:3 on, fit, CRT off, intensity 0.5',
      () {
    const g = GraphicsSettings();
    expect(g.filter, UpscaleFilter.smooth);
    expect(g.pixelAspectCorrection, true);
    expect(g.scaleMode, ScaleMode.fit);
    expect(g.crtScanlines, false);
    expect(g.crtIntensity, 0.5);
    // True-widescreen rendering is the mobile default.
    expect(g.aspectMode, AspectMode.widescreen);
    expect(GraphicsSettings.defaultCrtIntensity, 0.5);
    // Toggle off -> overlay effectively disabled regardless of slider value.
    expect(g.effectiveCrtIntensity, 0.0);
    // Filter maps to the right Flutter quality.
    expect(UpscaleFilter.smooth.filterQuality, FilterQuality.medium);
    expect(UpscaleFilter.sharp.filterQuality, FilterQuality.none);
  });

  test('JSON round-trip preserves all fields incl. crtIntensity + aspectMode',
      () {
    const g = GraphicsSettings(
      filter: UpscaleFilter.sharp,
      pixelAspectCorrection: false,
      scaleMode: ScaleMode.integer,
      crtScanlines: true,
      crtIntensity: 0.85,
      aspectMode: AspectMode.fourThree,
    );
    final back = GraphicsSettings.fromJson(g.toJson());
    expect(back, g);
    expect(back.crtIntensity, 0.85);
    expect(back.aspectMode, AspectMode.fourThree);
  });

  test('legacy save without aspectMode key falls back to widescreen', () {
    final legacy = <String, dynamic>{
      'filter': 'smooth',
      'pixelAspectCorrection': true,
      'scaleMode': 'fit',
      'crtScanlines': false,
    };
    final g = GraphicsSettings.fromJson(legacy);
    expect(g.aspectMode, AspectMode.widescreen);
  });

  test('aspectMode round-trips through the store', () async {
    final store = await GraphicsSettingsStore.open();
    await store.save(
      const GraphicsSettings(aspectMode: AspectMode.fourThree),
    );
    final store2 = await GraphicsSettingsStore.open();
    expect(store2.load().aspectMode, AspectMode.fourThree);
  });

  test('effectiveCrtIntensity gates on the toggle and clamps', () {
    const on = GraphicsSettings(crtScanlines: true, crtIntensity: 0.7);
    expect(on.effectiveCrtIntensity, 0.7);
    const off = GraphicsSettings(crtScanlines: false, crtIntensity: 0.7);
    expect(off.effectiveCrtIntensity, 0.0);
    // Out-of-range stored values clamp to 0..1.
    const high = GraphicsSettings(crtScanlines: true, crtIntensity: 5.0);
    expect(high.crtIntensityClamped, 1.0);
    expect(high.effectiveCrtIntensity, 1.0);
    const low = GraphicsSettings(crtScanlines: true, crtIntensity: -2.0);
    expect(low.crtIntensityClamped, 0.0);
    expect(low.effectiveCrtIntensity, 0.0);
  });

  test('crtIntensity round-trips through the store', () async {
    final store = await GraphicsSettingsStore.open();
    await store.save(
      const GraphicsSettings(crtScanlines: true, crtIntensity: 0.3),
    );
    final store2 = await GraphicsSettingsStore.open();
    expect(store2.load().crtIntensity, 0.3);
    expect(store2.load().crtScanlines, true);
  });

  test('legacy save without crtIntensity key falls back to default', () {
    // Simulate a settings blob saved before crtIntensity existed.
    final legacy = <String, dynamic>{
      'filter': 'sharp',
      'pixelAspectCorrection': false,
      'scaleMode': 'fill',
      'crtScanlines': true,
    };
    final g = GraphicsSettings.fromJson(legacy);
    expect(g.crtIntensity, GraphicsSettings.defaultCrtIntensity);
    expect(g.crtScanlines, true);
    expect(g.filter, UpscaleFilter.sharp);
  });

  test('out-of-range / wrong-type crtIntensity in JSON is clamped/tolerated',
      () {
    expect(
      GraphicsSettings.fromJson(<String, dynamic>{'crtIntensity': 9.0})
          .crtIntensity,
      1.0,
    );
    expect(
      GraphicsSettings.fromJson(<String, dynamic>{'crtIntensity': -3.0})
          .crtIntensity,
      0.0,
    );
    // Integer (num) value is tolerated.
    expect(
      GraphicsSettings.fromJson(<String, dynamic>{'crtIntensity': 1})
          .crtIntensity,
      1.0,
    );
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
