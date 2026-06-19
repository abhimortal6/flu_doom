// WAD file loader, ported from Chocolate Doom src/w_wad.{c,h}.
//
// A WAD is: a 12-byte header (4-byte ASCII id "IWAD"/"PWAD", int32 numlumps,
// int32 infotableofs) followed by lump data, then a directory of 16-byte
// entries (int32 filepos, int32 size, 8-byte name). All integers little-endian.
//
// Lump names are up to 8 ASCII chars, NUL-padded, case-insensitive, stored
// uppercase. Later lumps with the same name override earlier ones (PWAD
// patching) — lookups therefore scan from the end.

import 'dart:typed_data';

/// A single lump directory entry plus access to its bytes.
class Lump {
  Lump({
    required this.name,
    required this.position,
    required this.size,
    required this.index,
    required Uint8List source,
  }) : _source = source;

  /// Uppercased, trimmed lump name (max 8 chars).
  final String name;

  /// Byte offset of the lump data within the WAD file.
  final int position;

  /// Size of the lump in bytes.
  final int size;

  /// Directory index of this lump (its global lump number).
  final int index;

  final Uint8List _source;

  /// The raw lump bytes as a zero-copy view over the WAD buffer.
  Uint8List get bytes => Uint8List.sublistView(_source, position, position + size);

  /// The raw lump bytes as a [ByteData] view (for structured reads).
  ByteData get data => ByteData.sublistView(_source, position, position + size);

  @override
  String toString() => 'Lump($name, pos=$position, size=$size, #$index)';
}

/// Thrown when a WAD cannot be parsed or a required lump is missing.
class WadException implements Exception {
  WadException(this.message);
  final String message;
  @override
  String toString() => 'WadException: $message';
}

/// A loaded WAD file. Holds the full file bytes in memory and the parsed lump
/// directory. Supports IWAD and PWAD identification.
class WadFile {
  WadFile._(this.identification, this._bytes, this.lumps, this._byName);

  /// "IWAD" or "PWAD".
  final String identification;

  /// All lumps in directory order.
  final List<Lump> lumps;

  // Map of name -> list of lump indices in directory order (for override scan).
  final Map<String, List<int>> _byName;

  // ignore: unused_field
  final Uint8List _bytes;

  /// Total number of lumps.
  int get numLumps => lumps.length;

  /// True if this is an IWAD (the primary game data file).
  bool get isIwad => identification == 'IWAD';

  /// Parse a WAD from raw bytes.
  static WadFile fromBytes(Uint8List bytes) {
    if (bytes.length < 12) {
      throw WadException('File too small to be a WAD (${bytes.length} bytes)');
    }
    final ByteData bd = ByteData.sublistView(bytes);
    final String id = String.fromCharCodes(bytes.sublist(0, 4));
    if (id != 'IWAD' && id != 'PWAD') {
      throw WadException('Bad WAD identification: "$id"');
    }
    final int numLumps = bd.getInt32(4, Endian.little);
    final int dirOffset = bd.getInt32(8, Endian.little);
    if (dirOffset < 0 || dirOffset + numLumps * 16 > bytes.length) {
      throw WadException('Lump directory out of range');
    }

    final List<Lump> lumps = <Lump>[];
    final Map<String, List<int>> byName = <String, List<int>>{};
    int p = dirOffset;
    for (int i = 0; i < numLumps; i++) {
      final int filepos = bd.getInt32(p, Endian.little);
      final int size = bd.getInt32(p + 4, Endian.little);
      final String name = _readName(bytes, p + 8);
      final Lump lump = Lump(
        name: name,
        position: filepos,
        size: size,
        index: i,
        source: bytes,
      );
      lumps.add(lump);
      byName.putIfAbsent(name, () => <int>[]).add(i);
      p += 16;
    }
    return WadFile._(id, bytes, lumps, byName);
  }

  static String _readName(Uint8List bytes, int offset) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 8; i++) {
      final int c = bytes[offset + i];
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString().toUpperCase();
  }

  /// Look up a lump by name (case-insensitive). Returns the LAST matching lump
  /// in directory order (vanilla override semantics), or null if not found.
  Lump? lumpByName(String name) {
    final List<int>? indices = _byName[name.toUpperCase()];
    if (indices == null || indices.isEmpty) return null;
    return lumps[indices.last];
  }

  /// Like [lumpByName] but throws [WadException] if missing.
  Lump getLump(String name) {
    final Lump? l = lumpByName(name);
    if (l == null) throw WadException('Lump not found: $name');
    return l;
  }

  /// Returns true if a lump with [name] exists.
  bool hasLump(String name) => _byName.containsKey(name.toUpperCase());

  /// Look up a lump by its global index.
  Lump lumpByIndex(int index) => lumps[index];

  /// Find the index of a named marker lump (e.g. "S_START"), searching from
  /// the end. Returns -1 if not found. Useful for namespace scans.
  int lumpNumForName(String name) {
    final List<int>? indices = _byName[name.toUpperCase()];
    if (indices == null || indices.isEmpty) return -1;
    return indices.last;
  }
}
