// flu_doom — a pure-Dart (no FFI) port of vanilla Doom.
// "Base game up" milestone: the integrated, playable E1M1.
// See lib/INTERFACES.md and the CONTRACTS_*.md docs for the subsystem contracts.

import 'package:flutter/material.dart';

import 'game/doom_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
