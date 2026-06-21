// Bring-your-own-WAD import screen.
//
// flu_doom ships NO game data. This screen is shown on first run (or whenever no
// usable WAD is stored) and lets the user pick their own Doom-format IWAD/PWAD.
// The picked file is validated as a real WAD, copied into app storage, its path
// is persisted, and then [onImported] is called with the stored path so the
// shell can boot the game.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../game/wad_store.dart';

class WadImportScreen extends StatefulWidget {
  const WadImportScreen({
    super.key,
    required this.store,
    required this.onImported,
  });

  /// Persistence + validation/copy backend.
  final WadStore store;

  /// Called with the stored WAD path once a valid WAD has been imported.
  final void Function(String wadPath) onImported;

  @override
  State<WadImportScreen> createState() => _WadImportScreenState();
}

class _WadImportScreenState extends State<WadImportScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select a Doom WAD',
        type: FileType.any,
        // Some desktop platforms ignore custom extensions unless FileType.custom
        // is used; we accept any and validate the header ourselves so a WAD with
        // an unusual extension still works.
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        // User cancelled the picker.
        if (mounted) setState(() => _busy = false);
        return;
      }

      final PlatformFile file = picked.files.first;
      WadImportResult result;
      if (file.bytes != null) {
        // withData succeeded (web / some platforms): validate + copy the bytes.
        result = await widget.store.importFromBytes(file.bytes!);
      } else if (file.path != null) {
        result = await widget.store.importFromPath(file.path!);
      } else {
        result = const WadImportResult.failure(
            'Could not read the selected file.');
      }

      if (!mounted) return;
      if (result.ok && result.path != null) {
        widget.onImported(result.path!);
        return;
      }
      setState(() {
        _error = result.error ?? 'Import failed.';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open the file picker: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'flu_doom',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFF4040),
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'This app ships no game data. To play, import a '
                    'Doom-format IWAD file (a .wad).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You can use the free, BSD-licensed Freedoom WADs '
                    '(freedoom1.wad / freedoom2.wad), or your own commercial '
                    'doom.wad / doom1.wad / doom2.wad if you own the game.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  if (_error != null) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x33FF0000),
                        border: Border.all(color: const Color(0xFFFF4040)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFFFB0B0), fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  FilledButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open),
                    label: Text(_busy ? 'Importing…' : 'Select WAD file'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFB00000),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'The WAD is copied into this app\'s private storage. You '
                    'can change it later from the title screen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF808080), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
