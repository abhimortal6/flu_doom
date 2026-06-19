// flu_doom — a pure-Dart (no FFI) port of vanilla Doom.
// Phase 1: foundation vertical slice. See lib/INTERFACES.md for the stable
// public contracts that later modules build against.

import 'package:flutter/widgets.dart';

import 'game/doom_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlDoomApp());
}

class FlDoomApp extends StatelessWidget {
  const FlDoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF000000),
      debugShowCheckedModeBanner: false,
      title: 'flu_doom',
      builder: (BuildContext context, Widget? child) {
        return const ColoredBox(
          color: Color(0xFF000000),
          child: DoomGame(),
        );
      },
    );
  }
}
