// Button RE-POSITIONING tests:
//   * OverlaySettings position maps persist/round-trip, PORTRAIT and LANDSCAPE
//     kept separate;
//   * reset clears them;
//   * the live overlay places a button at its custom normalized position and
//     CLAMPS an out-of-bounds fraction back inside the screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/input_actions/action_dispatcher.dart';
import 'package:flu_doom/input_actions/controls_settings.dart';
import 'package:flu_doom/ui/controls/overlay_button_id.dart';
import 'package:flu_doom/ui/controls/touch_controls_overlay.dart';

Widget _host(OverlaySettings s, Size size) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
          TouchControlsOverlay(
            sink: EventQueueActionSink(EventQueue()),
            settings: s,
          ),
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('OverlaySettings positions', () {
    test('portrait + landscape maps round-trip independently', () async {
      final store = await ControlsSettingsStore.open();
      await store.saveOverlay(
        const OverlaySettings(
          positionsPortrait: <String, ButtonPosition>{
            OverlayButtonId.fire: ButtonPosition(0.2, 0.3),
          },
          positionsLandscape: <String, ButtonPosition>{
            OverlayButtonId.fire: ButtonPosition(0.8, 0.7),
            OverlayButtonId.use: ButtonPosition(0.6, 0.9),
          },
        ),
      );
      final loaded = store.loadOverlay();
      expect(loaded.positionsPortrait[OverlayButtonId.fire]!.dx,
          closeTo(0.2, 1e-9));
      expect(loaded.positionsPortrait[OverlayButtonId.fire]!.dy,
          closeTo(0.3, 1e-9));
      expect(loaded.positionsLandscape[OverlayButtonId.fire]!.dx,
          closeTo(0.8, 1e-9));
      expect(loaded.positionsLandscape[OverlayButtonId.use]!.dy,
          closeTo(0.9, 1e-9));
      // Portrait must NOT carry the landscape USE override.
      expect(loaded.positionsPortrait[OverlayButtonId.use], isNull);
    });

    test('positionsFor / withPositionsFor select the right orientation', () {
      const s = OverlaySettings();
      final p = s.withPositionsFor(false, const {
        OverlayButtonId.fire: ButtonPosition(0.1, 0.1),
      });
      // Editing portrait left landscape untouched.
      expect(p.positionsFor(false).containsKey(OverlayButtonId.fire), isTrue);
      expect(p.positionsFor(true).containsKey(OverlayButtonId.fire), isFalse);
    });

    test('resetToDefaults clears both position maps', () async {
      final store = await ControlsSettingsStore.open();
      await store.saveOverlay(
        const OverlaySettings(
          positionsPortrait: <String, ButtonPosition>{
            OverlayButtonId.fire: ButtonPosition(0.2, 0.3),
          },
          positionsLandscape: <String, ButtonPosition>{
            OverlayButtonId.use: ButtonPosition(0.6, 0.9),
          },
        ),
      );
      await store.resetToDefaults();
      final loaded = store.loadOverlay();
      expect(loaded.positionsPortrait, isEmpty);
      expect(loaded.positionsLandscape, isEmpty);
    });

    test('legacy single positions map is adopted as portrait', () async {
      // A previously-saved (orientation-agnostic) layout should not be lost.
      final store = await ControlsSettingsStore.open();
      final legacy = OverlaySettings.fromJson(<String, dynamic>{
        'positions': <String, dynamic>{
          OverlayButtonId.fire: <String, dynamic>{'dx': 0.4, 'dy': 0.5},
        },
      });
      expect(legacy.positionsPortrait[OverlayButtonId.fire]!.dx,
          closeTo(0.4, 1e-9));
      expect(legacy.positionsLandscape, isEmpty);
      await store.saveOverlay(legacy); // ensure store is usable end-to-end
    });
  });

  group('live overlay honors custom positions', () {
    testWidgets('places FIRE at its custom landscape position', (tester) async {
      const Size size = Size(1400, 800); // landscape
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Put FIRE near screen center.
      const s = OverlaySettings(
        positionsLandscape: <String, ButtonPosition>{
          OverlayButtonId.fire: ButtonPosition(0.5, 0.5),
        },
      );
      await tester.pumpWidget(_host(s, size));
      await tester.pump();

      final Rect r = tester.getRect(find.bySemanticsLabel('FIRE'));
      // Center should be near the middle of the (SafeArea-insetted) screen.
      expect(r.center.dx, closeTo(700, 60));
      expect(r.center.dy, closeTo(400, 60));
    });

    testWidgets('clamps an out-of-bounds position inside the screen',
        (tester) async {
      const Size size = Size(1400, 800);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Way off the bottom-right corner (dx/dy = 5.0): must clamp on-screen.
      const s = OverlaySettings(
        positionsLandscape: <String, ButtonPosition>{
          OverlayButtonId.fire: ButtonPosition(5.0, 5.0),
        },
      );
      await tester.pumpWidget(_host(s, size));
      await tester.pump();

      final Rect r = tester.getRect(find.bySemanticsLabel('FIRE'));
      expect(r.left, greaterThanOrEqualTo(-0.5));
      expect(r.top, greaterThanOrEqualTo(-0.5));
      expect(r.right, lessThanOrEqualTo(size.width + 0.5));
      expect(r.bottom, lessThanOrEqualTo(size.height + 0.5));
    });

    testWidgets('custom button still fires its GameAction', (tester) async {
      const Size size = Size(1400, 800);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final q = EventQueue();
      const s = OverlaySettings(
        positionsLandscape: <String, ButtonPosition>{
          OverlayButtonId.fire: ButtonPosition(0.5, 0.5),
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF000000))),
                TouchControlsOverlay(
                  sink: EventQueueActionSink(q),
                  settings: s,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final gesture =
          await tester.startGesture(tester.getCenter(find.bySemanticsLabel('FIRE')));
      await tester.pump();
      final events = q.drain();
      expect(events.single.type, EventType.keyDown);
      await gesture.up();
      await tester.pump();
    });
  });
}
