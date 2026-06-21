// Widget tests for the layout CUSTOMIZER screen:
//   * a drag gesture on a control updates its saved normalized offset;
//   * RESET clears the current orientation's overrides;
//   * SAVE persists the edited layout through the store.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flu_doom/input_actions/controls_settings.dart';
import 'package:flu_doom/ui/controls/controls_customize_screen.dart';
import 'package:flu_doom/ui/controls/overlay_button_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('dragging FIRE updates the saved landscape offset',
      (tester) async {
    const Size size = Size(1400, 800); // landscape
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await ControlsSettingsStore.open();
    OverlaySettings latest = const OverlaySettings();

    await tester.pumpWidget(
      MaterialApp(
        home: ControlsCustomizeScreen(
          store: store,
          initial: const OverlaySettings(),
          onChanged: (ov) => latest = ov,
        ),
      ),
    );
    await tester.pump();

    final fire = find.byKey(const Key('drag_${OverlayButtonId.fire}'));
    expect(fire, findsOneWidget);
    final Offset before = tester.getCenter(fire);

    // Drag FIRE up-and-left by a meaningful amount.
    await tester.drag(fire, const Offset(-200, -150));
    await tester.pump();

    // The landscape override now exists and reflects a leftward/upward move.
    final ButtonPosition? pos =
        latest.positionsLandscape[OverlayButtonId.fire];
    expect(pos, isNotNull);
    final Offset after = tester.getCenter(fire);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    // Portrait map must remain untouched.
    expect(latest.positionsPortrait, isEmpty);
  });

  testWidgets('RESET clears the current orientation overrides',
      (tester) async {
    const Size size = Size(1400, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await ControlsSettingsStore.open();
    OverlaySettings latest = const OverlaySettings();

    await tester.pumpWidget(
      MaterialApp(
        home: ControlsCustomizeScreen(
          store: store,
          initial: const OverlaySettings(
            positionsLandscape: <String, ButtonPosition>{
              OverlayButtonId.fire: ButtonPosition(0.2, 0.2),
            },
            positionsPortrait: <String, ButtonPosition>{
              OverlayButtonId.use: ButtonPosition(0.3, 0.3),
            },
          ),
          onChanged: (ov) => latest = ov,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('customizeReset')));
    await tester.pump();

    expect(latest.positionsLandscape, isEmpty);
    // Portrait overrides survive a landscape reset.
    expect(latest.positionsPortrait.containsKey(OverlayButtonId.use), isTrue);
  });

  testWidgets('renders all 8 controls, in-bounds, in both orientations',
      (tester) async {
    Future<void> check(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = await ControlsSettingsStore.open();
      await tester.pumpWidget(
        MaterialApp(
          home: ControlsCustomizeScreen(
            store: store,
            initial: const OverlaySettings(),
          ),
        ),
      );
      await tester.pump();

      for (final String id in OverlayButtonId.all) {
        final f = find.byKey(Key('drag_$id'));
        expect(f, findsOneWidget, reason: 'control $id missing at $size');
        final Rect r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$id off left');
        expect(r.top, greaterThanOrEqualTo(-0.5), reason: '$id off top');
        expect(r.right, lessThanOrEqualTo(size.width + 0.5),
            reason: '$id off right');
        expect(r.bottom, lessThanOrEqualTo(size.height + 0.5),
            reason: '$id off bottom');
      }
      expect(tester.takeException(), isNull);
    }

    await check(const Size(800, 1400)); // portrait
    await check(const Size(1400, 800)); // landscape
  });

  testWidgets('SAVE persists the edited layout and pops', (tester) async {
    const Size size = Size(1400, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await ControlsSettingsStore.open();

    await tester.pumpWidget(
      MaterialApp(
        home: ControlsCustomizeScreen(
          store: store,
          initial: const OverlaySettings(),
        ),
      ),
    );
    await tester.pump();

    // Drag MENU, then SAVE.
    await tester.drag(
      find.byKey(const Key('drag_${OverlayButtonId.menu}')),
      const Offset(120, 200),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('customizeSave')));
    await tester.pumpAndSettle();

    final loaded = store.loadOverlay();
    expect(loaded.positionsLandscape.containsKey(OverlayButtonId.menu), isTrue);
  });
}
