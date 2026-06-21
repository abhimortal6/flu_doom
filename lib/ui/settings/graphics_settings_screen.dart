// Graphics / Video settings screen (its own route). Exposes the PRESENT-layer
// quality levers that do NOT touch the 1:1 320x200 software renderer:
//   - Upscale filter: SHARP (nearest) vs SMOOTH (bilinear).
//   - 4:3 pixel-aspect correction on/off.
//   - Scale mode: fit / integer / fill.
//   - CRT scanline overlay on/off + intensity (0..1) when on.
// Persists through a [GraphicsSettingsStore] and live-applies via [onChanged].

import 'package:flutter/material.dart';

import '../../engine/video/video_view.dart' show ScaleMode;
import '../../input_actions/graphics_settings.dart';

class GraphicsSettingsScreen extends StatefulWidget {
  const GraphicsSettingsScreen({
    super.key,
    required this.store,
    this.onChanged,
  });

  /// Persistence backend.
  final GraphicsSettingsStore store;

  /// Called whenever settings are saved (live-apply hook for the game shell).
  final void Function(GraphicsSettings settings)? onChanged;

  @override
  State<GraphicsSettingsScreen> createState() => _GraphicsSettingsScreenState();
}

class _GraphicsSettingsScreenState extends State<GraphicsSettingsScreen> {
  late GraphicsSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.store.load();
  }

  void _set(GraphicsSettings s) {
    setState(() => _settings = s);
    widget.store.save(s);
    widget.onChanged?.call(s);
  }

  Future<void> _resetDefaults() async {
    await widget.store.resetToDefaults();
    setState(() => _settings = widget.store.load());
    widget.onChanged?.call(_settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Graphics'),
        actions: <Widget>[
          TextButton(
            onPressed: _resetDefaults,
            child: const Text('RESET', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('Upscale'),
          ListTile(
            title: const Text('Filter'),
            subtitle: const Text(
              'Sharp keeps the classic blocky pixels; Smooth softens them '
              '(nicer on a phone).',
            ),
            trailing: SegmentedButton<UpscaleFilter>(
              key: const Key('gfxFilter'),
              segments: const <ButtonSegment<UpscaleFilter>>[
                ButtonSegment(value: UpscaleFilter.sharp, label: Text('Sharp')),
                ButtonSegment(
                    value: UpscaleFilter.smooth, label: Text('Smooth')),
              ],
              selected: <UpscaleFilter>{_settings.filter},
              onSelectionChanged: (sel) =>
                  _set(_settings.copyWith(filter: sel.first)),
            ),
          ),
          const Divider(),
          const _SectionHeader('Aspect & Fit'),
          ListTile(
            title: const Text('Aspect ratio'),
            subtitle: const Text(
              'Widescreen renders a WIDER field of view (more scene left/right) '
              'to fill a 16:9 screen with no stretching. 4:3 is the classic '
              'letterboxed view.',
            ),
            trailing: SegmentedButton<AspectMode>(
              key: const Key('gfxAspectMode'),
              segments: const <ButtonSegment<AspectMode>>[
                ButtonSegment(
                    value: AspectMode.fourThree, label: Text('4:3')),
                ButtonSegment(
                    value: AspectMode.widescreen, label: Text('Wide')),
              ],
              selected: <AspectMode>{_settings.aspectMode},
              onSelectionChanged: (sel) =>
                  _set(_settings.copyWith(aspectMode: sel.first)),
            ),
          ),
          SwitchListTile(
            key: const Key('gfxAspect'),
            title: const Text('4:3 pixel-aspect correction'),
            subtitle: const Text(
              "Stretches height x1.2 to match Doom's original CRT look.",
            ),
            value: _settings.pixelAspectCorrection,
            onChanged: (v) =>
                _set(_settings.copyWith(pixelAspectCorrection: v)),
          ),
          ListTile(
            title: const Text('Scale mode'),
            subtitle: const Text(
              'Fit = letterboxed; Integer = whole-pixel multiples (crispest); '
              'Fill = stretch.',
            ),
            trailing: SegmentedButton<ScaleMode>(
              key: const Key('gfxScaleMode'),
              segments: const <ButtonSegment<ScaleMode>>[
                ButtonSegment(value: ScaleMode.fit, label: Text('Fit')),
                ButtonSegment(value: ScaleMode.integer, label: Text('Int')),
                ButtonSegment(value: ScaleMode.fill, label: Text('Fill')),
              ],
              selected: <ScaleMode>{_settings.scaleMode},
              onSelectionChanged: (sel) =>
                  _set(_settings.copyWith(scaleMode: sel.first)),
            ),
          ),
          const Divider(),
          const _SectionHeader('Motion'),
          SwitchListTile(
            key: const Key('gfxSmoothMotion'),
            title: const Text('Smooth motion'),
            subtitle: const Text(
              'Interpolates the view, sprites and moving doors/lifts between the '
              "35Hz game tics so motion is fluid at your display's refresh rate. "
              'Render-only — the game logic is unchanged. On by default.',
            ),
            value: _settings.smoothMotion,
            onChanged: (v) => _set(_settings.copyWith(smoothMotion: v)),
          ),
          const Divider(),
          const _SectionHeader('Retro'),
          SwitchListTile(
            key: const Key('gfxCrt'),
            title: const Text('CRT scanlines'),
            subtitle: const Text(
              'Subtle horizontal scanlines + mild glow overlay. Off by default.',
            ),
            value: _settings.crtScanlines,
            onChanged: (v) => _set(_settings.copyWith(crtScanlines: v)),
          ),
          ListTile(
            enabled: _settings.crtScanlines,
            title: const Text('CRT intensity'),
            subtitle: Text(
              'Strength of the scanlines + glow '
              '(${(_settings.crtIntensityClamped * 100).round()}%).',
            ),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                key: const Key('gfxCrtIntensity'),
                min: 0.0,
                max: 1.0,
                divisions: 20,
                value: _settings.crtIntensityClamped,
                label: '${(_settings.crtIntensityClamped * 100).round()}%',
                // Disabled (greyed) when CRT is off; live-applies + persists.
                onChanged: _settings.crtScanlines
                    ? (v) => _set(_settings.copyWith(crtIntensity: v))
                    : null,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Note: the 3D view is a faithful 320x200 software render. These '
              'options only affect how that image is scaled and displayed — the '
              'render itself is always full (high) detail.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
