// Standalone, isolated preview of the input/controls UX layer. Not mounted by
// the real app (that wiring is the integration agent's job). Run via a tiny
// harness, e.g.:
//
//   import 'package:flu_doom/ui/controls/controls_preview.dart';
//   void main() => runApp(const ControlsPreviewApp());
//
// Shows the overlay composed over a placeholder "game view", a live event log,
// and a button to open the controls settings screen. Hardware keyboard input is
// also wired through the binding system so you can verify key handling.

import 'package:flutter/material.dart';

import '../../engine/input/event.dart';
import '../../input_actions/action_dispatcher.dart';
import '../../input_actions/action_keyboard_listener.dart';
import '../../input_actions/controls_settings.dart';
import '../../input_actions/key_bindings.dart';
import '../settings/controls_settings_screen.dart';
import 'touch_controls_overlay.dart';

class ControlsPreviewApp extends StatelessWidget {
  const ControlsPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flu_doom controls preview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const ControlsPreviewPage(),
    );
  }
}

class ControlsPreviewPage extends StatefulWidget {
  const ControlsPreviewPage({super.key});

  @override
  State<ControlsPreviewPage> createState() => _ControlsPreviewPageState();
}

class _ControlsPreviewPageState extends State<ControlsPreviewPage> {
  final EventQueue _queue = EventQueue();
  late final EventQueueActionSink _dispatcher = EventQueueActionSink(_queue);

  OverlaySettings _overlay = OverlaySettings.defaults();
  KeyBindings _bindings = KeyBindings.defaults();
  ControlsSettingsStore? _store;

  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    // Drain the queue periodically for the on-screen log (preview only).
    WidgetsBinding.instance.addPostFrameCallback((_) => _initStore());
  }

  Future<void> _initStore() async {
    try {
      final store = await ControlsSettingsStore.open();
      setState(() {
        _store = store;
        _overlay = store.loadOverlay();
        _bindings = store.loadBindings();
      });
    } catch (_) {
      // No platform prefs in this preview context; keep defaults.
    }
  }

  void _pumpLog() {
    final events = _queue.drain();
    if (events.isEmpty) return;
    setState(() {
      for (final e in events) {
        _log.insert(0, e.toString());
      }
      if (_log.length > 40) _log.removeRange(40, _log.length);
    });
  }

  Future<void> _openSettings() async {
    final store = _store;
    if (store == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ControlsSettingsScreen(
          store: store,
          onChanged: (ov, b) => setState(() {
            _overlay = ov;
            _bindings = b;
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ActionKeyboardListener(
      bindings: _bindings,
      sink: _dispatcher,
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            // Placeholder "game view".
            Positioned.fill(
              child: Container(
                color: const Color(0xFF101418),
                child: const Center(
                  child: Text(
                    'GAME VIEW\n(placeholder)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white24, fontSize: 28),
                  ),
                ),
              ),
            ),
            // Event log + settings button.
            Positioned(
              left: 8,
              top: 40,
              width: 220,
              height: 220,
              child: IgnorePointer(
                ignoring: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: _openSettings,
                          child: const Text('Settings'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _pumpLog,
                          child: const Text('Pump'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: _log
                            .map(
                              (s) => Text(
                                s,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The actual overlay under test.
            TouchControlsOverlay(sink: _dispatcher, settings: _overlay),
          ],
        ),
      ),
    );
  }
}
