import 'package:super_cache/src/codec/super_codec.dart';
import 'package:super_cache/src/core/cache_config.dart';
import 'package:super_cache/src/core/cache_statistics.dart';
import 'package:super_cache/src/engine/l1_memory_cache.dart';
import 'package:super_cache/src/engine/l2_disk_cache.dart';
import 'package:super_cache/src/eviction/ttl_manager.dart';

/// The central coordinator between the L1 memory cache and the L2 disk cache.
///
/// All public [SuperCache] operations eventually call into this class.
///
/// ─── Read Algorithm (Read-Through) ───────────────────────────────────────
///
///  1. Check L1 — O(1) HashMap lookup.
///     └─ Hit → return immediately (path taken ~90% of the time).
///  2. Check L2 — O(1) seek via B-Index.
///     └─ Hit → decode → promote to L1 → return.
///  3. Miss — return null.
///
/// ─── Write Algorithm (Write-Behind by default) ────────────────────────────
///
///  1. Write to L1 immediately (synchronous, < 1 µs).
///  2. Enqueue encoded bytes in [WriteBuffer].
///  3. [WriteBuffer] flushes to L2 in batches (async, every 500 ms or at 100
///     pending ops — whichever comes first).
///
/// When [CacheConfig.syncWrites] = `true`:
///  1. Write to L1 immediately.
///  2. Write to L2 immediately (awaits disk flush).
///
/// ─── Consistency Guarantee ────────────────────────────────────────────────
///
///  After a successful [put], the value is **always** readable from [get]
///  (because L1 is updated synchronously).  Whether the value survives a
///  crash before the write-buffer flushes depends on [syncWrites].
final class CacheOrchestrator {
  /// Creates a [CacheOrchestrator].
  CacheOrchestrator({
    required this.config,
    required this.l1,
    required this.l2,
    required this.codec,
    required this.stats,
  }) {
    if (config.enableTtlCleanup) {
      _ttlManager = TtlManager(
        interval: config.ttlCleanupInterval,
        onCleanup: _runTtlCleanup,
      );
      _ttlManager!.start();
    }
  }

  /// Cache configuration.
  final CacheConfig config;

  /// L1 in-memory cache.
  final L1MemoryCache l1;

  /// L2 disk cache (may be `null` when disk is disabled).
  final L2DiskCache? l2;

  /// Binary codec.
  final SuperCodec codec;

  /// Live statistics — updated by every operation.
  final CacheStatistics stats;

  TtlManager? _ttlManager;

  // ─────────────────────────────────────────────────────────────────────────
  // Read
  // ─────────────────────────────────────────────────────────────────────────

  /// Reads the value for [key], checking L1 then L2.
  Future<T?> get<T>(String key) async {
    final sw = config.enableStatistics ? (Stopwatch()..start()) : null;

    // ── L1 lookup ────────────────────────────────────────────────────────────
    final l1Value = l1.get<T>(key);
    if (l1Value != null) {
      sw?.stop();
      stats.recordL1Hit(latencyUs: sw?.elapsedMicroseconds ?? 0);
      return l1Value;
    }

    // ── L2 lookup ────────────────────────────────────────────────────────────
    if (l2 == null) {
      sw?.stop();
      stats.recordMiss(latencyUs: sw?.elapsedMicroseconds ?? 0);
      return null;
    }

    final encodedBytes = await l2!.getRaw(key);
    if (encodedBytes == null) {
      sw?.stop();
      stats.recordMiss(latencyUs: sw?.elapsedMicroseconds ?? 0);
      return null;
    }

    // Decode
    final value = codec.decode(encodedBytes) as T?;
    if (value == null) {
      sw?.stop();
      stats.recordMiss(latencyUs: sw?.elapsedMicroseconds ?? 0);
      return null;
    }

    // Promote from L2 → L1 (cache promotion)
    l1.put<T>(key, value, encodedBytes.length);

    sw?.stop();
    stats.recordL2Hit(
      bytes: encodedBytes.length,
      latencyUs: sw?.elapsedMicroseconds ?? 0,
    );
    return value;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write
  // ─────────────────────────────────────────────────────────────────────────

  /// Writes [value] under [key].
  ///
  /// L1 is always written synchronously.
  /// L2 is written synchronously when [forceSync] or [CacheConfig.syncWrites]
  /// is `true`; otherwise the write is buffered.
  Future<void> put<T>(
    String key,
    T value, {
    Duration? ttl,
    bool forceSync = false,
  }) async {
    final sw = config.enableStatistics ? (Stopwatch()..start()) : null;

    // Encode once, share bytes between L1 size accounting and L2 storage.
    final encoded = codec.encode(value);

    // Write to L1 immediately (O(1) in-memory)
    l1.put<T>(key, value, encoded.length, ttl: ttl);

    // Write to L2 (async buffered or sync)
    if (l2 != null) {
      if (forceSync || config.syncWrites) {
        await l2!.putRaw(key, encoded);
      } else {
        await l2!.putRawBuffered(key, encoded);
      }
    }

    sw?.stop();
    stats.recordWrite(
      bytes: encoded.length,
      latencyUs: sw?.elapsedMicroseconds ?? 0,
    );
    stats.updateMemoryUsage(l1.currentMemoryBytes);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Delete
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes [key] from L1 and L2.
  Future<bool> remove(String key) async {
    final removedFromL1 = l1.remove(key);
    if (l2 != null) {
      await l2!.delete(key);
    }
    if (removedFromL1) stats.recordDelete();
    stats.updateMemoryUsage(l1.currentMemoryBytes);
    return removedFromL1;
  }

  /// Removes all keys in [keys] from L1 and L2.
  Future<void> removeAll(List<String> keys) async {
    for (final key in keys) {
      await remove(key);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Existence
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns `true` if [key] is present in L1 or L2 and not expired.
  Future<bool> containsKey(String key) async {
    if (l1.containsKey(key)) return true;
    if (l2 == null) return false;
    return l2!.containsKey(key);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Batch
  // ─────────────────────────────────────────────────────────────────────────

  /// Writes all entries in [entries] with optional shared [ttl].
  Future<void> putAll(Map<String, dynamic> entries, {Duration? ttl}) async {
    for (final e in entries.entries) {
      await put(e.key, e.value, ttl: ttl);
    }
  }

  /// Reads multiple [keys] at once.
  Future<Map<String, dynamic>> getAll(List<String> keys) async {
    final result = <String, dynamic>{};
    for (final key in keys) {
      final value = await get(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cache-Aside
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the cached value for [key], or calls [loader] and caches the result.
  Future<T> getOrPut<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  }) async {
    final cached = await get<T>(key);
    if (cached != null) return cached;

    final value = await loader();
    await put<T>(key, value, ttl: ttl);
    return value;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Management
  // ─────────────────────────────────────────────────────────────────────────

  /// Clears both L1 and L2.
  Future<void> clear() async {
    l1.clear();
    if (l2 != null) await l2!.clear();
    stats.reset();
  }

  /// Returns all keys from L1 ∪ L2.
  Future<Set<String>> getAllKeys() async {
    final keys = l1.keys.toSet();
    if (l2 != null) {
      keys.addAll(await l2!.getAllKeys());
    }
    return keys;
  }

  /// Pre-loads [keys] from L2 into L1.
  Future<void> warmUp(List<String> keys) async {
    if (l2 == null) return;
    for (final key in keys) {
      if (!l1.containsKey(key)) {
        final bytes = await l2!.getRaw(key);
        if (bytes != null) {
          final value = codec.decode(bytes);
          l1.put(key, value, bytes.length);
        }
      }
    }
  }

  /// Forces the write buffer to flush to disk.
  Future<void> flush() => l2?.flush() ?? Future.value();

  // ─────────────────────────────────────────────────────────────────────────
  // TTL cleanup callback
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> _runTtlCleanup() async {
    final l1Removed = l1.clearExpired();
    stats.updateMemoryUsage(l1.currentMemoryBytes);
    // L2 TTL cleanup is deferred to compaction for performance
    return l1Removed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Flushes pending writes, stops TTL cleanup, and disposes resources.
  Future<void> dispose() async {
    await _ttlManager?.dispose();
    await l2?.dispose();
  }
}
