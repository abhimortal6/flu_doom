// The separate controls settings screen (its own route). Two sections:
//   1. Overlay configuration: visibility, opacity, scale, handedness.
//   2. Keyboard bindings: rebind every action via capture-key UX.
// Plus reset-to-defaults. Persists through a [ControlsSettingsStore].
//
// Orientation-aware: a single scrolling column in portrait; two side-by-side
// columns (overlay | bindings) in landscape.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../input_actions/controls_settings.dart';
import '../../input_actions/game_action.dart';
import '../../input_actions/key_bindings.dart';

class ControlsSettingsScreen extends StatefulWidget {
  const ControlsSettingsScreen({
    super.key,
    required this.store,
    this.onChanged,
  });

  /// Persistence backend.
  final ControlsSettingsStore store;

  /// Called whenever settings are saved (live-apply hook for the game shell).
  final void Function(OverlaySettings overlay, KeyBindings bindings)? onChanged;

  @override
  State<ControlsSettingsScreen> createState() => _ControlsSettingsScreenState();
}

class _ControlsSettingsScreenState extends State<ControlsSettingsScreen> {
  late OverlaySettings _overlay;
  late KeyBindings _bindings;

  @override
  void initState() {
    super.initState();
    _overlay = widget.store.loadOverlay();
    _bindings = widget.store.loadBindings();
  }

  Future<void> _persist() async {
    await widget.store.saveOverlay(_overlay);
    await widget.store.saveBindings(_bindings);
    widget.onChanged?.call(_overlay, _bindings);
  }

  void _setOverlay(OverlaySettings s) {
    setState(() => _overlay = s);
    _persist();
  }

  Future<void> _resetDefaults() async {
    await widget.store.resetToDefaults();
    setState(() {
      _overlay = widget.store.loadOverlay();
      _bindings = widget.store.loadBindings();
    });
    widget.onChanged?.call(_overlay, _bindings);
  }

  Future<void> _rebind(GameAction action) async {
    final LogicalKeyboardKey? captured = await showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (_) => _KeyCaptureDialog(action: action),
    );
    if (captured == null) return;
    setState(() {
      // One key -> one action: clear this action's old keys, then bind.
      _bindings.clearAction(action);
      _bindings.bind(captured, action);
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controls'),
        actions: <Widget>[
          TextButton(
            onPressed: _resetDefaults,
            child: const Text(
              'RESET',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool landscape = constraints.maxWidth >= constraints.maxHeight;
          final Widget overlaySection = _OverlaySection(
            settings: _overlay,
            onChanged: _setOverlay,
          );
          final Widget bindingSection = _BindingSection(
            bindings: _bindings,
            onRebind: _rebind,
          );

          if (landscape) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(child: overlaySection),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SingleChildScrollView(child: bindingSection),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[overlaySection, const Divider(), bindingSection],
            ),
          );
        },
      ),
    );
  }
}

class _OverlaySection extends StatelessWidget {
  const _OverlaySection({required this.settings, required this.onChanged});

  final OverlaySettings settings;
  final void Function(OverlaySettings) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionHeader('On-screen Controls'),
        SwitchListTile(
          key: const Key('overlayVisible'),
          title: const Text('Show overlay'),
          value: settings.visible,
          onChanged: (v) => onChanged(settings.copyWith(visible: v)),
        ),
        ListTile(
          title: const Text('Opacity'),
          subtitle: Slider(
            key: const Key('overlayOpacity'),
            min: 0.1,
            max: 1.0,
            divisions: 18,
            value: settings.opacity,
            label: settings.opacity.toStringAsFixed(2),
            onChanged: (v) => onChanged(settings.copyWith(opacity: v)),
          ),
        ),
        ListTile(
          title: const Text('Size'),
          subtitle: Slider(
            key: const Key('overlayScale'),
            min: 0.6,
            max: 1.8,
            divisions: 12,
            value: settings.scale,
            label: '${(settings.scale * 100).round()}%',
            onChanged: (v) => onChanged(settings.copyWith(scale: v)),
          ),
        ),
        ListTile(
          title: const Text('Look sensitivity'),
          subtitle: Slider(
            key: const Key('overlayLookSensitivity'),
            // 0.5x (clearly-too-slow) .. 8x (very fast ceiling); 2.0x default is
            // already brisk thanks to kLookBaseGain in analog_input.dart.
            min: 0.5,
            max: 8.0,
            divisions: 30,
            value: settings.lookSensitivity.clamp(0.5, 8.0),
            label: '${settings.lookSensitivity.toStringAsFixed(2)}x',
            onChanged: (v) =>
                onChanged(settings.copyWith(lookSensitivity: v)),
          ),
        ),
        ListTile(
          title: const Text('Handedness'),
          trailing: SegmentedButton<HandedLayout>(
            segments: const <ButtonSegment<HandedLayout>>[
              ButtonSegment(value: HandedLayout.right, label: Text('Right')),
              ButtonSegment(value: HandedLayout.left, label: Text('Left')),
            ],
            selected: <HandedLayout>{settings.handed},
            onSelectionChanged: (sel) =>
                onChanged(settings.copyWith(handed: sel.first)),
          ),
        ),
      ],
    );
  }
}

class _BindingSection extends StatelessWidget {
  const _BindingSection({required this.bindings, required this.onRebind});

  final KeyBindings bindings;
  final void Function(GameAction) onRebind;

  String _keyLabel(GameAction action) {
    final ids = bindings.keysFor(action);
    if (ids.isEmpty) return 'Unbound';
    return ids
        .map((id) {
          final k = LogicalKeyboardKey.findKeyByKeyId(id);
          return k?.keyLabel.isNotEmpty == true
              ? k!.keyLabel
              : (k?.debugName ?? '0x${id.toRadixString(16)}');
        })
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionHeader('Keyboard Bindings'),
        for (final action in GameAction.values)
          ListTile(
            key: Key('binding_${action.name}'),
            title: Text(ActionKeys.label(action)),
            subtitle: Text(_keyLabel(action)),
            trailing: const Icon(Icons.edit),
            onTap: () => onRebind(action),
          ),
      ],
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
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Modal that captures the next physical key press for rebinding.
class _KeyCaptureDialog extends StatefulWidget {
  const _KeyCaptureDialog({required this.action});
  final GameAction action;

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  final FocusNode _node = FocusNode(debugLabel: 'KeyCapture');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Escape cancels.
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      Navigator.of(context).pop(event.logicalKey);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Bind: ${ActionKeys.label(widget.action)}'),
      content: Focus(
        focusNode: _node,
        autofocus: true,
        onKeyEvent: _onKey,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Press a key…  (Esc to cancel)'),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
