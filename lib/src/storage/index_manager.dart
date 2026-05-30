import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:super_cache/src/core/cache_exceptions.dart';

/// Disk position descriptor for a single cache entry in the data file.
final class DiskPosition {
  /// Creates a [DiskPosition].
  const DiskPosition({
    required this.offset,
    required this.length,
    required this.checksum,
  });

  /// Byte offset from the start of the data file.
  final int offset;

  /// Length of the stored bytes (encoded value only; header not included).
  final int length;

  /// CRC-32 checksum of the stored bytes for integrity verification.
  final int checksum;

  @override
  String toString() =>
      'DiskPosition(offset: $offset, length: $length, '
      'crc: 0x${checksum.toRadixString(16).padLeft(8, '0')})';
}

// ─────────────────────────────────────────────────────────────────────────────
// IndexManager
// ─────────────────────────────────────────────────────────────────────────────

/// Maintains a binary B-Index that maps every cache key to its exact byte
/// position in the L2 data file.
///
/// Without this index every cache read would require scanning the data file
/// from the beginning (O(n) like Hive). With the index every read is a
/// direct seek to [DiskPosition.offset] — O(1).
///
/// The index is kept in memory at all times and persisted to a separate
/// `<boxName>.idx` file.  On startup the index is loaded from disk; if the
/// index file is missing or corrupt it is rebuilt by scanning the data file.
///
/// **Binary index file format (v2):**
/// ```
/// [4 bytes] magic  = 0x53434958  ("SCIX")
/// [2 bytes] version = 2
/// [4 bytes] entryCount
/// for each entry:
///   [2 bytes] keyLength
///   [n bytes] key (UTF-8)
///   [8 bytes] offset (int64 big-endian)
///   [4 bytes] length (uint32 big-endian)
///   [4 bytes] checksum (uint32 big-endian)
/// [4 bytes] trailing CRC-32 of the entire preceding content
/// ```
final class IndexManager {
  /// Creates an [IndexManager] that will persist to [indexFilePath].
  IndexManager({required this.indexFilePath});

  /// Absolute path to the `.idx` binary file.
  final String indexFilePath;

  final _index = HashMap<String, DiskPosition>();
  bool _isDirty = false;

  /// Number of keys in the index.
  int get length => _index.length;

  /// All keys currently tracked.
  Iterable<String> get allKeys => _index.keys;

  // ─────────────────────────────────────────────────────────────────────────
  // In-memory CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the disk position for [key], or `null` if not indexed.
  DiskPosition? getPosition(String key) => _index[key];

  /// Registers or updates the disk position for [key].
  void setPosition(String key, DiskPosition position) {
    _index[key] = position;
    _isDirty = true;
  }

  /// Removes [key] from the index.
  ///
  /// Returns `true` if the key was present.
  bool removeKey(String key) {
    final removed = _index.remove(key) != null;
    if (removed) _isDirty = true;
    return removed;
  }

  /// Whether [key] is in the index.
  bool containsKey(String key) => _index.containsKey(key);

  /// Clears all index entries.
  void clear() {
    _index.clear();
    _isDirty = true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Persistence
  // ─────────────────────────────────────────────────────────────────────────

  static const int _magic = 0x53434958; // "SCIX"
  static const int _version = 2;

  /// Flushes the in-memory index to [indexFilePath] if it has changed.
  ///
  /// A no-op when [_isDirty] is `false`.
  Future<void> flush() async {
    if (!_isDirty) return;

    try {
      final writer = _IndexWriter();

      // Header
      writer.writeUint32(_magic);
      writer.writeUint16(_version);
      writer.writeUint32(_index.length);

      // Entries
      for (final entry in _index.entries) {
        final keyBytes = _encodeKey(entry.key);
        writer.writeUint16(keyBytes.length);
        writer.writeBytes(keyBytes);
        writer.writeInt64(entry.value.offset);
        writer.writeUint32(entry.value.length);
        writer.writeUint32(entry.value.checksum);
      }

      // Trailing CRC-32 of everything written so far
      final content = writer.toBytes();
      final crc = _crc32(content);
      final fullWriter = _IndexWriter();
      fullWriter.writeBytes(content);
      fullWriter.writeUint32(crc);

      final file = File(indexFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(fullWriter.toBytes(), flush: true);
      _isDirty = false;
    } catch (e) {
      throw CacheStorageException(
        'Failed to write index file "$indexFilePath": $e',
        cause: e,
      );
    }
  }

  /// Loads the index from [indexFilePath].
  ///
  /// Returns `true` on success. Returns `false` (and clears the index) if
  /// the file does not exist or is corrupt.
  Future<bool> load() async {
    final file = File(indexFilePath);
    if (!file.existsSync()) return false;

    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < 14) return false; // Too small to be valid

      // Verify trailing CRC-32
      final contentBytes = bytes.sublist(0, bytes.length - 4);
      final storedCrc = _readUint32(bytes, bytes.length - 4);
      final computedCrc = _crc32(contentBytes);
      if (storedCrc != computedCrc) {
        _index.clear();
        return false;
      }

      final reader = _IndexReader(contentBytes);

      // Header
      final magic = reader.readUint32();
      if (magic != _magic) {
        _index.clear();
        return false;
      }

      final version = reader.readUint16();
      if (version != _version) {
        // Version mismatch — trigger rebuild
        _index.clear();
        return false;
      }

      final count = reader.readUint32();
      _index.clear();

      for (var i = 0; i < count; i++) {
        final keyLen = reader.readUint16();
        final keyBytes = reader.readBytes(keyLen);
        final key = String.fromCharCodes(keyBytes);
        final offset = reader.readInt64();
        final length = reader.readUint32();
        final checksum = reader.readUint32();

        _index[key] = DiskPosition(
          offset: offset,
          length: length,
          checksum: checksum,
        );
      }

      _isDirty = false;
      return true;
    } catch (_) {
      _index.clear();
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Uint8List _encodeKey(String key) {
    // ASCII fast-path for the common case
    if (key.length <= 255) {
      final out = Uint8List(key.length);
      for (var i = 0; i < key.length; i++) {
        out[i] = key.codeUnitAt(i) & 0xFF;
      }
      return out;
    }
    return Uint8List.fromList(key.codeUnits);
  }

  static int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  // ── CRC-32 (IEEE 802.3 polynomial) ─────────────────────────────────────

  static final List<int> _crcTable = _buildCrcTable();

  /// Public access to the precomputed CRC-32 lookup table.
  ///
  /// Shared by [DartIoStorage] to avoid duplicate table allocation.
  static List<int> get crcTable => _crcTable;

  static List<int> _buildCrcTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var j = 0; j < 8; j++) {
        crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
      }
      table[i] = crc;
    }
    return table;
  }

  static int _crc32(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Computes the CRC-32 checksum of [data].
  ///
  /// Public version used by [DartIoStorage] for integrity verification.
  static int computeCrc32(Uint8List data) => _crc32(data);
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal read / write helpers
// ─────────────────────────────────────────────────────────────────────────────

final class _IndexWriter {
  final _buf = <int>[];

  void writeByte(int v) => _buf.add(v & 0xFF);

  void writeUint16(int v) {
    _buf
      ..add((v >> 8) & 0xFF)
      ..add(v & 0xFF);
  }

  void writeUint32(int v) {
    _buf
      ..add((v >> 24) & 0xFF)
      ..add((v >> 16) & 0xFF)
      ..add((v >> 8) & 0xFF)
      ..add(v & 0xFF);
  }

  void writeInt64(int v) {
    final bd = ByteData(8)..setInt64(0, v, Endian.big);
    _buf.addAll(bd.buffer.asUint8List());
  }

  void writeBytes(Uint8List bytes) => _buf.addAll(bytes);

  Uint8List toBytes() => Uint8List.fromList(_buf);
}

final class _IndexReader {
  _IndexReader(this._bytes) : _pos = 0;
  final Uint8List _bytes;
  int _pos;

  int readByte() => _bytes[_pos++];

  int readUint16() {
    final v = (_bytes[_pos] << 8) | _bytes[_pos + 1];
    _pos += 2;
    return v;
  }

  int readUint32() {
    final v = (_bytes[_pos] << 24) |
        (_bytes[_pos + 1] << 16) |
        (_bytes[_pos + 2] << 8) |
        _bytes[_pos + 3];
    _pos += 4;
    return v;
  }

  int readInt64() {
    final bd = ByteData.sublistView(_bytes, _pos, _pos + 8);
    _pos += 8;
    return bd.getInt64(0, Endian.big);
  }

  Uint8List readBytes(int n) {
    final slice = _bytes.sublist(_pos, _pos + n);
    _pos += n;
    return slice;
  }
}
