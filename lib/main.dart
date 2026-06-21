// flu_doom — a pure-Dart (no FFI) port of vanilla Doom.
// "Base game up" milestone: the integrated, playable E1M1.
// See lib/INTERFACES.md and the CONTRACTS_*.md docs for the subsystem contracts.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/doom_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Auto-rotation: allow every orientation so the device's physical orientation
  // sensor drives portrait <-> landscape. The game view (VideoView letterboxes
  // the 320x200 framebuffer) and the touch overlay are constraint-driven
  // (LayoutBuilder), so they re-lay-out cleanly on rotation. portraitDown is
  // included for symmetry; Android honors it, iOS iPhone ignores it per
  // Info.plist (which lists portrait + landscape left/right only).
  SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const FlDoomApp());
}

class FlDoomApp extends StatelessWidget {
  const FlDoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: const Color(0xFF000000),
      debugShowCheckedModeBanner: false,
      title: 'flu_doom',
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: DoomGame(),
      ),
    );
  }
}
