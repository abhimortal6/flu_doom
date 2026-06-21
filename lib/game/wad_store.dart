// Bring-your-own-WAD storage.
//
// flu_doom ships NO game data (clean open-source release). The user imports their
// own Doom-format IWAD/PWAD (e.g. a free Freedoom WAD, or their own doom.wad /
// doom1.wad) on first run. This file persists the path to the imported WAD via
// shared_preferences and owns the import/copy/validate logic.
//
// The imported file is COPIED into the app's documents directory so it survives
// even if the originally-picked file is moved/deleted, and so the engine can
// load it like any normal file at boot.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/wad/wad.dart';

/// Result of validating + importing a candidate WAD file.
class WadImportResult {
  const WadImportResult.ok(this.path)
      : error = null,
        identification = _idUnknown;
  const WadImportResult.okWith(this.path, this.identification) : error = null;
  const WadImportResult.failure(this.error)
      : path = null,
        identification = null;

  static const String _idUnknown = 'WAD';

  /// The stored (copied) WAD path on success; null on failure.
  final String? path;

  /// "IWAD" / "PWAD" on success; null on failure.
  final String? identification;

  /// A human-readable error message on failure; null on success.
  final String? error;

  bool get ok => error == null;
}

/// Persists and resolves the active WAD file the engine boots from.
///
/// Persistence key: 'flu_doom.wadPath' -> absolute path of the imported WAD.
class WadStore {
  WadStore(this._prefs);

  static const String wadPathKey = 'flu_doom.wadPath';

  /// Filename the imported WAD is copied to inside the app documents directory.
  static const String importedFileName = 'imported.wad';

  /// Minimum plausible size for a real IWAD/PWAD. A bare 12-byte header (or a
  /// truncated file) is rejected as "not a real WAD". (doom1.wad is ~4 MB; the
  /// smallest sane PWAD is still many KB, but we keep the floor low to allow
  /// tiny test PWADs while still rejecting garbage.)
  static const int minWadBytes = 4096;

  final SharedPreferences _prefs;

  /// Create a store backed by the platform default SharedPreferences.
  static Future<WadStore> open() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return WadStore(prefs);
  }

  /// The saved WAD path, or null if none has been imported yet.
  String? get savedPath => _prefs.getString(wadPathKey);

  /// Resolve the active WAD path: the saved path if it still exists on disk,
  /// else null (caller should show the import screen). Never throws.
  String? resolveExistingPath() {
    final String? p = savedPath;
    if (p == null) return null;
    try {
      if (File(p).existsSync()) return p;
    } catch (_) {
      // Fall through to null on any IO error.
    }
    return null;
  }

  /// Forget the stored WAD (used by "Change WAD"). The copied file is left in
  /// place; the next import overwrites it. Never throws.
  Future<void> clear() async {
    try {
      await _prefs.remove(wadPathKey);
    } catch (_) {}
  }

  /// Validate [sourcePath] as a real Doom WAD, copy it into the app documents
  /// directory, persist its new path, and return the result. On any failure the
  /// stored path is left UNCHANGED and a descriptive error is returned.
  Future<WadImportResult> importFromPath(String sourcePath) async {
    Uint8List bytes;
    try {
      final File src = File(sourcePath);
      if (!src.existsSync()) {
        return const WadImportResult.failure('The selected file no longer '
            'exists. Please pick it again.');
      }
      bytes = await src.readAsBytes();
    } catch (e) {
      return WadImportResult.failure('Could not read the selected file: $e');
    }
    return importFromBytes(bytes);
  }

  /// Validate raw [bytes] as a Doom WAD, copy them into the app documents
  /// directory, persist the path, and return the result. Exposed separately so
  /// the file_picker "withData" path (web / some platforms hand back bytes, not
  /// a path) and tests can reuse the exact same validation + copy logic.
  Future<WadImportResult> importFromBytes(Uint8List bytes) async {
    final String? validationError = validateBytes(bytes);
    if (validationError != null) {
      return WadImportResult.failure(validationError);
    }

    final String id = String.fromCharCodes(bytes.sublist(0, 4));

    final String dest;
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      dest = '${dir.path}${Platform.pathSeparator}$importedFileName';
      final File out = File(dest);
      await out.writeAsBytes(bytes, flush: true);
    } catch (e) {
      return WadImportResult.failure('Could not save the WAD into app '
          'storage: $e');
    }

    try {
      await _prefs.setString(wadPathKey, dest);
    } catch (e) {
      return WadImportResult.failure('Could not record the WAD location: $e');
    }
    return WadImportResult.okWith(dest, id);
  }

  /// Returns null if [bytes] is a structurally valid, non-trivial IWAD/PWAD;
  /// otherwise a human-readable reason it was rejected. Reads the 4-byte magic
  /// and fully parses the lump directory via [WadFile.fromBytes] so a corrupt /
  /// non-Doom file is caught here, not at boot.
  static String? validateBytes(Uint8List bytes) {
    if (bytes.length < minWadBytes) {
      return 'That file is too small to be a Doom WAD '
          '(${bytes.length} bytes). Pick a doom.wad, doom1.wad, or a '
          'Freedoom WAD.';
    }
    final String id = bytes.length >= 4
        ? String.fromCharCodes(bytes.sublist(0, 4))
        : '';
    if (id != 'IWAD' && id != 'PWAD') {
      return 'That file is not a Doom WAD (its header is "$id", not '
          '"IWAD"/"PWAD"). Pick a real .wad file.';
    }
    try {
      final WadFile wad = WadFile.fromBytes(bytes);
      if (wad.numLumps <= 0) {
        return 'That WAD contains no lumps. Pick a complete Doom WAD.';
      }
    } on WadException catch (e) {
      return 'That WAD could not be parsed: ${e.message}';
    } catch (e) {
      return 'That WAD could not be parsed: $e';
    }
    return null;
  }
}
