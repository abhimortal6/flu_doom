// Settings save/load tests via the in-memory SharedPreferences mock, plus a
// settings-screen rebind smoke test.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flu_doom/input_actions/controls_settings.dart';
import 'package:flu_doom/input_actions/game_action.dart';
import 'package:flu_doom/input_actions/key_bindings.dart';
import 'package:flu_doom/ui/settings/controls_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('ControlsSettingsStore', () {
    test('defaults when nothing persisted', () async {
      final store = await ControlsSettingsStore.open();
      final ov = store.loadOverlay();
      expect(ov.visible, isTrue);
      expect(ov.handed, HandedLayout.right);
      final b = store.loadBindings();
      expect(b.actionFor(LogicalKeyboardKey.controlLeft), GameAction.fire);
    });

    test('overlay settings round-trip', () async {
      final store = await ControlsSettingsStore.open();
      await store.saveOverlay(
        const OverlaySettings(
          visible: false,
          opacity: 0.8,
          scale: 1.4,
          handed: HandedLayout.left,
        ),
      );
      final loaded = store.loadOverlay();
      expect(loaded.visible, isFalse);
      expect(loaded.opacity, closeTo(0.8, 1e-9));
      expect(loaded.scale, closeTo(1.4, 1e-9));
      expect(loaded.handed, HandedLayout.left);
    });

    test('bindings round-trip after rebind', () async {
      final store = await ControlsSettingsStore.open();
      final b = KeyBindings.defaults();
      b.clearAction(GameAction.fire);
      b.bind(LogicalKeyboardKey.keyF, GameAction.fire);
      await store.saveBindings(b);

      final loaded = store.loadBindings();
      expect(loaded.actionFor(LogicalKeyboardKey.keyF), GameAction.fire);
      expect(loaded.actionFor(LogicalKeyboardKey.controlLeft), isNot(GameAction.fire));
    });

    test('resetToDefaults restores both overlay and bindings', () async {
      final store = await ControlsSettingsStore.open();
      await store.saveOverlay(const OverlaySettings(visible: false));
      await store.resetToDefaults();
      expect(store.loadOverlay().visible, isTrue);
      expect(store.loadBindings().actionFor(LogicalKeyboardKey.space),
          GameAction.use);
    });
  });

  testWidgets('settings screen toggles overlay visibility and persists',
      (tester) async {
    final store = await ControlsSettingsStore.open();
    OverlaySettings? lastOverlay;
    await tester.pumpWidget(
      MaterialApp(
        home: ControlsSettingsScreen(
          store: store,
          onChanged: (ov, _) => lastOverlay = ov,
        ),
      ),
    );

    expect(find.text('On-screen Controls'), findsOneWidget);
    expect(find.text('Keyboard Bindings'), findsOneWidget);

    // Toggle the visibility switch off.
    await tester.tap(find.byKey(const Key('overlayVisible')));
    await tester.pumpAndSettle();

    expect(lastOverlay?.visible, isFalse);
    expect(store.loadOverlay().visible, isFalse);
  });

  testWidgets('rebind dialog captures a key and updates binding',
      (tester) async {
    // Portrait so there is a single scroll view (landscape splits into two).
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await ControlsSettingsStore.open();
    KeyBindings? lastBindings;
    await tester.pumpWidget(
      MaterialApp(
        home: ControlsSettingsScreen(
          store: store,
          onChanged: (_, b) => lastBindings = b,
        ),
      ),
    );

    // Open the rebind dialog for "fire" (scroll it into view first).
    final fireTile = find.byKey(const Key('binding_fire'));
    await tester.scrollUntilVisible(fireTile, 200);
    await tester.tap(fireTile);
    await tester.pumpAndSettle();
    expect(find.textContaining('Press a key'), findsOneWidget);

    // Simulate pressing 'F'.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();

    expect(lastBindings?.actionFor(LogicalKeyboardKey.keyF), GameAction.fire);
    expect(store.loadBindings().actionFor(LogicalKeyboardKey.keyF),
        GameAction.fire);
  });
}
