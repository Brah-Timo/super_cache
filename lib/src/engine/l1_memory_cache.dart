import 'dart:collection';

import 'package:super_cache/src/core/cache_config.dart';
import 'package:super_cache/src/core/cache_entry.dart';
import 'package:super_cache/src/eviction/eviction_policy.dart';

/// The in-memory L1 cache — the primary speed driver of super_cache.
///
/// Internally backed by a [HashMap] for O(1) reads and writes.
/// Every operation that changes the hot set notifies the [EvictionPolicy]
/// so that the policy can maintain accurate access-order tracking.
///
/// **Memory budget enforcement:**
/// Before every insert, [_ensureCapacity] verifies two limits:
/// 1. [CacheConfig.maxMemoryEntries] — maximum number of live keys.
/// 2. [CacheConfig.maxMemorySizeBytes] — maximum total byte footprint.
///
/// When either limit would be exceeded, [EvictionPolicy.selectForEviction]
/// is called repeatedly until enough budget is freed.
///
/// This class is single-isolate and NOT thread-safe.
final class L1MemoryCache {
  /// Creates an [L1MemoryCache] configured by [config] and governed by
  /// [evictionPolicy].
  L1MemoryCache({
    required this.config,
    required this.evictionPolicy,
  }) : _cache = HashMap<String, CacheEntry<dynamic>>();

  /// The cache configuration.
  final CacheConfig config;

  /// The eviction algorithm (LRU / LFU / ARC).
  final EvictionPolicy evictionPolicy;

  final HashMap<String, CacheEntry<dynamic>> _cache;

  int _currentMemoryUsage = 0;

  // ── Counters ──────────────────────────────────────────────────────────────

  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  int _ttlExpiries = 0;

  // ── Public metrics ────────────────────────────────────────────────────────

  /// Number of live entries in L1.
  int get length => _cache.length;

  /// Current byte footprint of all L1 values.
  int get currentMemoryBytes => _currentMemoryUsage;

  /// Total L1 cache hits since last [clear].
  int get hits => _hits;

  /// Total L1 cache misses since last [clear].
  int get misses => _misses;

  /// Total entries evicted by the eviction policy.
  int get evictions => _evictions;

  /// Total entries removed because their TTL elapsed.
  int get ttlExpiries => _ttlExpiries;

  /// Hit rate = hits / (hits + misses).
  double get hitRate {
    final total = _hits + _misses;
    if (total == 0) return 0.0;
    return _hits / total;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Reads the value for [key] from L1.
  ///
  /// Returns `null` if the key does not exist or its TTL has elapsed.
  /// On a hit, records the access with both the entry and the eviction policy.
  T? get<T>(String key) {
    final entry = _cache[key];

    if (entry == null) {
      _misses++;
      return null;
    }

    // Lazy TTL expiry
    if (entry.isExpired) {
      _removeEntry(key, entry);
      _ttlExpiries++;
      _misses++;
      return null;
    }

    entry.recordAccess();
    evictionPolicy.onAccess(key);
    _hits++;
    return entry.value as T?;
  }

  /// Stores [value] under [key] with size [sizeBytes].
  ///
  /// If [key] already exists, the entry is updated in-place (no eviction).
  /// Otherwise, capacity is checked and eviction runs as needed before insert.
  void put<T>(String key, T value, int sizeBytes, {Duration? ttl}) {
    final existing = _cache[key];
    if (existing != null) {
      // In-place update: adjust memory budget delta
      _currentMemoryUsage -= existing.sizeBytes;
      existing.updateValue(value, sizeBytes);
      _currentMemoryUsage += sizeBytes;
      evictionPolicy.onUpdate(key);
      return;
    }

    // New key — ensure budget
    _ensureCapacity(sizeBytes);

    final entry = CacheEntry<T>(
      key: key,
      value: value,
      sizeBytes: sizeBytes,
      ttl: ttl ?? config.defaultTtl,
    );

    _cache[key] = entry;
    _currentMemoryUsage += sizeBytes;
    evictionPolicy.onInsert(key);
  }

  /// Removes [key] from L1.
  ///
  /// Returns `true` if the key was present.
  bool remove(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    _removeEntry(key, entry);
    return true;
  }

  /// Returns `true` if [key] exists and has not expired.
  ///
  /// Does NOT record an access (unlike [get]).
  bool containsKey(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _removeEntry(key, entry);
      _ttlExpiries++;
      return false;
    }
    return true;
  }

  /// Returns the raw [CacheEntry] for [key], or `null`.
  ///
  /// For internal use only — does not record an access.
  CacheEntry<dynamic>? getEntry(String key) => _cache[key];

  /// All live keys in L1 (snapshot — modifications do not affect the iterator).
  Iterable<String> get keys => _cache.keys;

  // ─────────────────────────────────────────────────────────────────────────
  // Bulk Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes all entries from L1, resetting counters and eviction state.
  void clear() {
    _cache.clear();
    _currentMemoryUsage = 0;
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    _ttlExpiries = 0;
    evictionPolicy.clear();
  }

  /// Scans L1 and removes every expired entry.
  ///
  /// Returns the number of entries removed.
  int clearExpired() {
    final expired = _cache.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList(growable: false);

    for (final key in expired) {
      final entry = _cache[key]!;
      _removeEntry(key, entry);
      _ttlExpiries++;
    }
    return expired.length;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private Helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _removeEntry(String key, CacheEntry<dynamic> entry) {
    _cache.remove(key);
    _currentMemoryUsage -= entry.sizeBytes;
    if (_currentMemoryUsage < 0) _currentMemoryUsage = 0;
    evictionPolicy.onRemove(key);
  }

  /// Frees enough capacity to accommodate [requiredBytes] more bytes.
  void _ensureCapacity(int requiredBytes) {
    // Evict by entry count
    while (_cache.length >= config.maxMemoryEntries) {
      if (!_evictOne()) break;
    }

    // Evict by byte budget
    while (
        _currentMemoryUsage + requiredBytes > config.maxMemorySizeBytes &&
        _cache.isNotEmpty) {
      if (!_evictOne()) break;
    }
  }

  /// Evicts one entry.  Returns `false` if the cache is empty.
  bool _evictOne() {
    if (_cache.isEmpty) return false;

    final candidate = evictionPolicy.selectForEviction(_cache.keys.toList());
    if (candidate == null) {
      // Fallback: evict the first key if the policy returns null
      final firstKey = _cache.keys.first;
      remove(firstKey);
      _evictions++;
      return true;
    }

    remove(candidate);
    _evictions++;
    return true;
  }

  @override
  String toString() => 'L1MemoryCache('
      'entries: ${_cache.length}/${config.maxMemoryEntries}, '
      'memory: ${(_currentMemoryUsage / 1024).toStringAsFixed(1)}KB/'
      '${(config.maxMemorySizeBytes / 1048576).toStringAsFixed(0)}MB, '
      'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%'
      ')';
}
