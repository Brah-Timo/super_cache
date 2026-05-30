import 'package:super_cache/src/core/cache_statistics.dart';

/// Abstract interface that every super_cache implementation must satisfy.
///
/// Consumers that want to write code that works with both the real
/// [SuperCache] and a fake/mock for testing should program to this interface.
abstract interface class SuperCacheBase {
  // ── CRUD ──────────────────────────────────────────────────────────────────

  /// Returns the value associated with [key], or `null` if it is missing or
  /// expired.
  ///
  /// Searches L1 (memory) first, then L2 (disk) if L2 is enabled.
  /// A disk hit automatically promotes the value into L1.
  Future<T?> get<T>(String key);

  /// Stores [value] under [key].
  ///
  /// [ttl] overrides the default TTL set in [CacheConfig.defaultTtl].
  /// Pass [forceSync] = `true` to block until the value is persisted to disk.
  Future<void> put<T>(
    String key,
    T value, {
    Duration? ttl,
    bool forceSync = false,
  });

  /// Removes the entry with [key] from both L1 and L2.
  ///
  /// Returns `true` if the key existed and was removed.
  Future<bool> remove(String key);

  /// Returns `true` if [key] exists and has not expired.
  Future<bool> containsKey(String key);

  // ── Batch ─────────────────────────────────────────────────────────────────

  /// Writes all entries in [entries] with the same optional [ttl].
  Future<void> putAll(Map<String, dynamic> entries, {Duration? ttl});

  /// Reads multiple [keys] at once.
  ///
  /// Returns a map containing only the keys that exist and are not expired.
  Future<Map<String, dynamic>> getAll(List<String> keys);

  /// Removes all entries whose key is in [keys].
  Future<void> removeAll(List<String> keys);

  // ── Cache-Aside Pattern ───────────────────────────────────────────────────

  /// Returns the cached value for [key] if present, otherwise calls [loader],
  /// stores the result, and returns it.
  ///
  /// This is the canonical **cache-aside** (lazy-loading) pattern.
  ///
  /// ```dart
  /// final user = await cache.getOrPut(
  ///   'user:$id',
  ///   () => api.fetchUser(id),
  ///   ttl: const Duration(minutes: 30),
  /// );
  /// ```
  Future<T> getOrPut<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  });

  // ── Management ────────────────────────────────────────────────────────────

  /// Removes all entries from both L1 and L2.
  Future<void> clear();

  /// Returns all keys currently stored in this cache (L1 ∪ L2).
  Future<Set<String>> getAllKeys();

  /// Pre-loads the given [keys] from L2 (disk) into L1 (memory).
  ///
  /// Call this at app start with the keys you know will be accessed first.
  Future<void> warmUp(List<String> keys);

  /// Forces any pending write-buffer entries to flush to disk immediately.
  Future<void> flush();

  // ── Diagnostics ───────────────────────────────────────────────────────────

  /// Live performance statistics for this cache instance.
  CacheStatistics get statistics;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Flushes pending writes and releases all resources held by this cache.
  ///
  /// After [dispose] returns, no further operations should be called.
  Future<void> dispose();
}
