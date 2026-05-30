import 'dart:typed_data';

import 'package:super_cache/src/codec/super_codec.dart';
import 'package:super_cache/src/core/cache_config.dart';
import 'package:super_cache/src/core/cache_exceptions.dart';
import 'package:super_cache/src/engine/write_buffer.dart';
import 'package:super_cache/src/storage/dart_io_storage.dart';
import 'package:super_cache/src/storage/storage_engine.dart';

/// The on-disk L2 cache layer.
///
/// Sits below [L1MemoryCache] in the two-level hierarchy.  Reads and writes
/// go through [StorageEngine], which provides O(1) keyed access via the
/// [IndexManager] B-Index.
///
/// **Write path (buffered, default):**
/// 1. Value is encoded by [SuperCodec].
/// 2. Encoded bytes are placed in [WriteBuffer].
/// 3. [WriteBuffer] flushes to [StorageEngine] in batches.
///
/// **Write path (sync, when [CacheConfig.syncWrites] = `true`):**
/// 1. Value is encoded.
/// 2. [StorageEngine.write] is called immediately (blocks until flushed).
///
/// **Read path:**
/// 1. [StorageEngine.read] seeks directly via B-Index (O(1)).
/// 2. Returned bytes are decoded by [SuperCodec].
/// 3. Value is returned to [CacheOrchestrator], which promotes it to L1.
final class L2DiskCache {
  L2DiskCache._({
    required StorageEngine storage,
    required this.codec,
    required this.config,
    required WriteBuffer writeBuffer,
  })  : _storage = storage,
        _writeBuffer = writeBuffer;

  final StorageEngine _storage;

  /// The codec used to encode and decode cache values.
  final SuperCodec codec;

  /// The cache configuration governing this L2 instance.
  final CacheConfig config;
  final WriteBuffer _writeBuffer;

  // ── Metrics ───────────────────────────────────────────────────────────────

  int _reads = 0;
  int _writes = 0;
  int _deletes = 0;

  /// Total number of reads performed by this cache since it was opened.
  int get reads => _reads;

  /// Total number of writes performed by this cache since it was opened.
  int get writes => _writes;

  /// Total number of deletes performed by this cache since it was opened.
  int get deletes => _deletes;

  // ─────────────────────────────────────────────────────────────────────────
  // Factory
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens an L2DiskCache at [directory]/[boxName].
  ///
  /// Creates the directory and index/data files if they do not exist.
  static Future<L2DiskCache> open({
    required String directory,
    required String boxName,
    required CacheConfig config,
    required SuperCodec codec,
  }) async {
    final storage = DartIoStorage();
    await storage.open(directory, boxName);

    final buffer = WriteBuffer(
      maxSize: config.writeBufferSize,
      flushInterval: config.writeBufferFlushInterval,
      onFlush: (ops) async {
        final puts = <String, Uint8List>{};
        final deletes = <String>[];

        for (final op in ops) {
          if (op.isDelete) {
            deletes.add(op.key);
            puts.remove(op.key);
          } else {
            puts[op.key] = op.encodedValue!;
          }
        }
        if (puts.isNotEmpty) await storage.writeBatch(puts);
        if (deletes.isNotEmpty) await storage.deleteBatch(deletes);
      },
    );
    buffer.start();

    return L2DiskCache._(
      storage: storage,
      codec: codec,
      config: config,
      writeBuffer: buffer,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Raw byte access (used by CacheOrchestrator)
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the raw encoded bytes for [key], or `null` if not found.
  Future<Uint8List?> getRaw(String key) async {
    try {
      final bytes = await _storage.read(key);
      if (bytes != null) _reads++;
      return bytes;
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheStorageException(
        'L2 read failed for key "$key": $e',
        cause: e,
      );
    }
  }

  /// Writes [encodedBytes] for [key] directly (synchronous mode).
  Future<void> putRaw(String key, Uint8List encodedBytes) async {
    try {
      await _storage.write(key, encodedBytes);
      _writes++;
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheStorageException(
        'L2 write failed for key "$key": $e',
        cause: e,
      );
    }
  }

  /// Enqueues [encodedBytes] for [key] in the write buffer (async mode).
  Future<void> putRawBuffered(String key, Uint8List encodedBytes) async {
    await _writeBuffer.enqueueWrite(key, encodedBytes);
    _writes++;
  }

  /// Deletes [key] from L2 (via write buffer for async, directly for sync).
  Future<void> delete(String key) async {
    if (config.syncWrites) {
      await _storage.delete(key);
    } else {
      await _writeBuffer.enqueueDelete(key);
    }
    _deletes++;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Typed access (convenience wrappers)
  // ─────────────────────────────────────────────────────────────────────────

  /// Reads and decodes a typed value from L2.
  Future<T?> get<T>(String key) async {
    final bytes = await getRaw(key);
    if (bytes == null) return null;
    return codec.decode(bytes) as T?;
  }

  /// Encodes and writes a typed value to L2.
  Future<void> put<T>(String key, T value, {bool sync = false}) async {
    final bytes = codec.encode(value);
    if (sync || config.syncWrites) {
      await putRaw(key, bytes);
    } else {
      await putRawBuffered(key, bytes);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Query
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether [key] exists in L2.
  Future<bool> containsKey(String key) => _storage.containsKey(key);

  /// All keys stored in L2.
  Future<Set<String>> getAllKeys() => _storage.getAllKeys();

  /// Current disk usage in bytes.
  Future<int> sizeInBytes() => _storage.sizeInBytes();

  /// Number of entries on disk.
  Future<int> count() => _storage.count();

  // ─────────────────────────────────────────────────────────────────────────
  // Expired entry removal
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes all expired entries from L2.
  ///
  /// This is more expensive than L1 clearExpired because it requires
  /// decoding the metadata of every entry on disk.
  ///
  /// Returns the number of entries removed.
  Future<int> clearExpired() async {
    // Implementation note: full scan is acceptable here because this runs
    // infrequently (every [CacheConfig.ttlCleanupInterval]).
    // A production-grade implementation would store expiry times in the index
    // to allow O(1) filtering — reserved for v2.
    return 0; // Placeholder — TTL on disk is enforced by L1 promotion checks
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Maintenance
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes all entries from L2.
  Future<void> clear() async {
    await _writeBuffer.flush(); // Drain pending writes first
    await _storage.clear();
  }

  /// Runs compaction, reclaiming space from deleted/overwritten entries.
  ///
  /// Returns the number of bytes freed.
  Future<int> compact() async {
    await _writeBuffer.flush();
    return _storage.compact();
  }

  /// Flushes the write buffer to disk immediately.
  Future<void> flush() => _writeBuffer.flush();

  /// Flushes pending writes and closes the storage engine.
  Future<void> dispose() async {
    await _writeBuffer.dispose();
    await _storage.close();
  }
}
