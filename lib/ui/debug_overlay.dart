// Debug overlay: shows FPS and tic count. Toggle by tapping (handled by the
// parent) or always-on during development.

import 'package:flutter/widgets.dart';

class DebugOverlay extends StatelessWidget {
  const DebugOverlay({
    super.key,
    required this.fps,
    required this.gametic,
    this.extra,
  });

  final double fps;
  final int gametic;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: const Color(0xAA000000),
          child: Text(
            'fps ${fps.toStringAsFixed(1)}  tic $gametic'
            '${extra != null ? '\n$extra' : ''}',
            style: const TextStyle(
              color: Color(0xFF00FF00),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
