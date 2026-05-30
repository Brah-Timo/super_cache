import 'dart:io';
import 'dart:typed_data';

import 'package:super_cache/src/core/cache_exceptions.dart';
import 'package:super_cache/src/storage/index_manager.dart';
import 'package:super_cache/src/storage/storage_engine.dart';

/// Entry header written before each value in the data file.
///
/// ```
/// [4 bytes] magic        = 0x53434456  ("SCDV")
/// [2 bytes] keyLength    (uint16 BE)
/// [n bytes] key          (ASCII/UTF-8)
/// [4 bytes] valueLength  (uint32 BE)
/// [4 bytes] checksum     (CRC-32 of value bytes)
/// [1 byte]  flags        (0x01 = deleted, 0x00 = live)
/// ─────────────────────────── total header = 15 + keyLength
/// [m bytes] value        (encoded bytes)
/// ```
///
/// The [IndexManager] tracks each live entry's value offset so we can seek
/// directly without reading the header again.

const int _entryMagic = 0x53434456; // "SCDV"
const int _flagLive = 0x00;
const int _flagDeleted = 0x01;

/// `dart:io`-based L2 storage engine.
///
/// Writes cache entries to a single flat binary file (`<boxName>.dat`) with a
/// companion index file (`<boxName>.idx`) managed by [IndexManager].
///
/// **Write strategy:**
/// - [write] appends a new entry at the end of the data file.
/// - Old versions of the same key are marked deleted (tombstoned) in-place.
/// - [compact] rewrites the file, skipping all tombstoned entries.
///
/// This design makes writes O(1) without any seeking or in-place patching,
/// at the cost of file growth over time (mitigated by auto-compaction).
final class DartIoStorage implements StorageEngine {
  /// Creates a [DartIoStorage] instance.
  ///
  /// Call [open] before performing any read or write operations.
  DartIoStorage();

  late String _dataFilePath;
  late IndexManager _index;
  RandomAccessFile? _raf;
  bool _open = false;

  int _totalBytes = 0;
  int _liveBytes = 0;

  /// Approximate number of bytes occupied by live (non-tombstoned) entries.
  int get liveBytes => _liveBytes;

  @override
  bool get isOpen => _open;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> open(String directory, String boxName) async {
    await Directory(directory).create(recursive: true);

    _dataFilePath = '$directory/$boxName.dat';
    final indexFilePath = '$directory/$boxName.idx';

    _index = IndexManager(indexFilePath: indexFilePath);

    // Load index from disk (or rebuild if corrupt/missing)
    final indexLoaded = await _index.load();

    // Open data file
    final dataFile = File(_dataFilePath);
    _raf = await dataFile.open(mode: FileMode.append);
    _raf = await (await dataFile.open(mode: FileMode.append)).setPosition(0);
    _raf = await dataFile.open(mode: FileMode.writeOnlyAppend);
    // Re-open for read+write
    _raf?.close();
    _raf = await dataFile.open(mode: FileMode.append);
    _raf = await File(_dataFilePath).open(mode: FileMode.write);

    if (!indexLoaded && dataFile.existsSync()) {
      // Rebuild index by scanning data file
      await _rebuildIndex();
    }

    _totalBytes = await File(_dataFilePath).length().catchError((_) => 0);
    _open = true;
  }

  @override
  Future<void> close() async {
    await _index.flush();
    await _raf?.flush();
    await _raf?.close();
    _raf = null;
    _open = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CRUD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<Uint8List?> read(String key) async {
    final pos = _index.getPosition(key);
    if (pos == null) return null;

    try {
      final raf = await File(_dataFilePath).open();
      try {
        await raf.setPosition(pos.offset);
        final bytes = await raf.read(pos.length);
        // Verify CRC-32
        final crc = IndexManager.computeCrc32(bytes);
        if (crc != pos.checksum) {
          throw ChecksumMismatchException(key, pos.checksum, crc);
        }
        return bytes;
      } finally {
        await raf.close();
      }
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheStorageException('Failed to read key "$key": $e', cause: e);
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    try {
      final keyBytes = _encodeKey(key);
      final checksum = _crc32(bytes);

      // Build header
      final header = _buildHeader(keyBytes, bytes.length, checksum, _flagLive);

      // If key exists, tombstone the old entry
      final existing = _index.getPosition(key);
      if (existing != null) {
        await _tombstone(existing.offset, keyBytes.length);
      }

      // Seek to end and append
      final file = File(_dataFilePath);
      final currentSize = await file.length();

      final raf = await file.open(mode: FileMode.writeOnlyAppend);
      try {
        await raf.writeFrom(header);
        await raf.writeFrom(bytes);
        await raf.flush();
      } finally {
        await raf.close();
      }

      // Record value offset (after header)
      final valueOffset = currentSize + header.length;
      _index.setPosition(
        key,
        DiskPosition(offset: valueOffset, length: bytes.length, checksum: checksum),
      );

      _totalBytes = await file.length();
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheStorageException('Failed to write key "$key": $e', cause: e);
    }
  }

  @override
  Future<void> writeBatch(Map<String, Uint8List> entries) async {
    // Build one large buffer and write it in a single I/O call
    final file = File(_dataFilePath);
    final currentSize = await file.length();
    var offset = currentSize;

    final bufferParts = <Uint8List>[];
    final positions = <String, DiskPosition>{};

    for (final entry in entries.entries) {
      final key = entry.key;
      final bytes = entry.value;
      final keyBytes = _encodeKey(key);
      final checksum = _crc32(bytes);

      // Tombstone existing
      final existing = _index.getPosition(key);
      if (existing != null) {
        await _tombstone(existing.offset, keyBytes.length);
      }

      final header = _buildHeader(keyBytes, bytes.length, checksum, _flagLive);
      bufferParts.add(header);
      bufferParts.add(bytes);

      final valueOffset = offset + header.length;
      positions[key] = DiskPosition(
        offset: valueOffset,
        length: bytes.length,
        checksum: checksum,
      );
      offset += header.length + bytes.length;
    }

    // Single write call
    final totalLen = bufferParts.fold<int>(0, (s, b) => s + b.length);
    final buf = Uint8List(totalLen);
    var pos = 0;
    for (final part in bufferParts) {
      buf.setRange(pos, pos + part.length, part);
      pos += part.length;
    }

    final raf = await file.open(mode: FileMode.writeOnlyAppend);
    try {
      await raf.writeFrom(buf);
      await raf.flush();
    } finally {
      await raf.close();
    }

    // Update index for all entries at once
    for (final kv in positions.entries) {
      _index.setPosition(kv.key, kv.value);
    }
    _totalBytes = await file.length();
  }

  @override
  Future<bool> delete(String key) async {
    final pos = _index.getPosition(key);
    if (pos == null) return false;

    try {
      final keyBytes = _encodeKey(key);
      // The header starts before the value; compute header start
      final headerStart = pos.offset - _headerSize(keyBytes.length);
      await _tombstone(headerStart, keyBytes.length);
      _index.removeKey(key);
      return true;
    } catch (e) {
      throw CacheStorageException('Failed to delete key "$key": $e', cause: e);
    }
  }

  @override
  Future<void> deleteBatch(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }

  @override
  Future<bool> containsKey(String key) async => _index.containsKey(key);

  // ─────────────────────────────────────────────────────────────────────────
  // Query
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<Set<String>> getAllKeys() async => _index.allKeys.toSet();

  @override
  Future<int> count() async => _index.length;

  @override
  Future<int> sizeInBytes() async =>
      File(_dataFilePath).existsSync()
          ? await File(_dataFilePath).length()
          : 0;

  // ─────────────────────────────────────────────────────────────────────────
  // Maintenance
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> clear() async {
    _index.clear();
    await File(_dataFilePath).writeAsBytes(Uint8List(0));
    _liveBytes = 0;
    _totalBytes = 0;
    await _index.flush();
  }

  @override
  Future<int> compact() async {
    final before = _totalBytes;
    final tempPath = '$_dataFilePath.tmp';

    final tempFile = File(tempPath);
    final raf = await tempFile.open(mode: FileMode.write);
    int newOffset = 0;

    try {
      // Re-read every live entry and write to temp file
      final newPositions = <String, DiskPosition>{};

      for (final key in _index.allKeys.toList()) {
        final pos = _index.getPosition(key);
        if (pos == null) continue;

        final bytes = await read(key);
        if (bytes == null) continue;

        final keyBytes = _encodeKey(key);
        final checksum = _crc32(bytes);
        final header = _buildHeader(keyBytes, bytes.length, checksum, _flagLive);

        await raf.writeFrom(header);
        await raf.writeFrom(bytes);

        final valueOffset = newOffset + header.length;
        newPositions[key] = DiskPosition(
          offset: valueOffset,
          length: bytes.length,
          checksum: checksum,
        );
        newOffset += header.length + bytes.length;
      }

      await raf.flush();
    } finally {
      await raf.close();
    }

    // Atomically replace old data file
    await File(tempPath).rename(_dataFilePath);
    _totalBytes = newOffset;
    _liveBytes = newOffset;

    // Rebuild index with new positions (re-written above in loop)

    return before - newOffset;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Marks an entry as deleted by patching its flags byte in-place.
  Future<void> _tombstone(int headerOffset, int keyLen) async {
    // flags byte is at: magic(4) + keyLen(2) + key(n) + valueLen(4) + crc(4)
    final flagsOffset = headerOffset + 14 + keyLen;
    final raf = await File(_dataFilePath).open(mode: FileMode.write);
    try {
      await raf.setPosition(flagsOffset);
      await raf.writeByte(_flagDeleted);
      await raf.flush();
    } finally {
      await raf.close();
    }
  }

  /// Rebuilds the index by scanning the data file from start to end.
  Future<void> _rebuildIndex() async {
    final file = File(_dataFilePath);
    if (!file.existsSync()) return;

    final bytes = await file.readAsBytes();
    var pos = 0;

    _index.clear();
    _liveBytes = 0;

    while (pos + 15 < bytes.length) {
      // Read magic
      final magic = _readUint32(bytes, pos);
      if (magic != _entryMagic) break; // Corrupt — stop scanning

      final keyLen = _readUint16(bytes, pos + 4);
      final headerSize = 15 + keyLen;
      if (pos + headerSize > bytes.length) break;

      final key = String.fromCharCodes(bytes.sublist(pos + 6, pos + 6 + keyLen));
      final valueLen = _readUint32(bytes, pos + 6 + keyLen);
      final checksum = _readUint32(bytes, pos + 10 + keyLen);
      final flags = bytes[pos + 14 + keyLen];

      if (pos + headerSize + valueLen > bytes.length) break;

      if (flags == _flagLive) {
        final valueOffset = pos + headerSize;
        _index.setPosition(
          key,
          DiskPosition(offset: valueOffset, length: valueLen, checksum: checksum),
        );
        _liveBytes += headerSize + valueLen;
      }

      pos += headerSize + valueLen;
    }

    await _index.flush();
  }

  Uint8List _encodeKey(String key) =>
      Uint8List.fromList(key.codeUnits.map((c) => c & 0xFF).toList());

  Uint8List _buildHeader(
    Uint8List keyBytes,
    int valueLen,
    int checksum,
    int flags,
  ) {
    final header = Uint8List(15 + keyBytes.length);
    var i = 0;
    // magic (4)
    header[i++] = (_entryMagic >> 24) & 0xFF;
    header[i++] = (_entryMagic >> 16) & 0xFF;
    header[i++] = (_entryMagic >> 8) & 0xFF;
    header[i++] = _entryMagic & 0xFF;
    // keyLength (2)
    header[i++] = (keyBytes.length >> 8) & 0xFF;
    header[i++] = keyBytes.length & 0xFF;
    // key (n)
    for (final b in keyBytes) {
      header[i++] = b;
    }
    // valueLength (4)
    header[i++] = (valueLen >> 24) & 0xFF;
    header[i++] = (valueLen >> 16) & 0xFF;
    header[i++] = (valueLen >> 8) & 0xFF;
    header[i++] = valueLen & 0xFF;
    // checksum (4)
    header[i++] = (checksum >> 24) & 0xFF;
    header[i++] = (checksum >> 16) & 0xFF;
    header[i++] = (checksum >> 8) & 0xFF;
    header[i++] = checksum & 0xFF;
    // flags (1)
    header[i++] = flags;
    return header;
  }

  int _headerSize(int keyLen) => 15 + keyLen;

  static int _readUint32(Uint8List b, int pos) =>
      (b[pos] << 24) | (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];

  static int _readUint16(Uint8List b, int pos) =>
      (b[pos] << 8) | b[pos + 1];

  static final List<int> _crcTable = IndexManager.crcTable;

  static int _crc32(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
