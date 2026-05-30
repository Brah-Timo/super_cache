/// super_cache — A blazing-fast, pure-Dart dual-layer cache for Flutter.
///
/// ## Quick Start
///
/// ```dart
/// // Register custom adapters BEFORE init
/// SuperCache.registerAdapter(UserAdapter());
///
/// // Initialize once at app startup
/// await SuperCache.init(
///   config: const CacheConfig(
///     maxMemoryEntries: 2000,
///     defaultTtl: Duration(hours: 24),
///     evictionPolicy: EvictionPolicyType.arc,
///     enableStatistics: true,
///   ),
/// );
///
/// final cache = SuperCache.instance;
///
/// // Write
/// await cache.put('greeting', 'Hello, world!');
/// await cache.put('user', myUser, ttl: const Duration(hours: 1));
///
/// // Read
/// final greeting = await cache.get<String>('greeting'); // nullable
///
/// // Cache-aside pattern
/// final config = await cache.getOrPut(
///   'app_config',
///   () => fetchConfigFromServer(),
///   ttl: const Duration(minutes: 30),
/// );
///
/// // Statistics
/// print(cache.statistics);
///
/// // Clean up
/// await cache.dispose();
/// ```
///
/// ## Named instances
///
/// ```dart
/// await SuperCache.init(name: 'session', config: CacheConfig(boxName: 'session'));
/// final session = SuperCache.named('session');
/// ```
///
/// ## Encryption
///
/// ```dart
/// final key = AesCipher.generateKey(); // store securely!
/// await SuperCache.init(
///   config: CacheConfig(encryptionKey: key),
/// );
/// ```
library super_cache;

// ── Public exports ────────────────────────────────────────────────────────────

export 'src/core/cache_config.dart'
    show CacheConfig, EvictionPolicyType, CacheLogLevel;
export 'src/core/cache_exceptions.dart';
export 'src/core/cache_statistics.dart'
    show CacheStatistics, CacheStatisticsSnapshot;
export 'src/core/super_cache_base.dart' show SuperCacheBase;
export 'src/codec/type_registry.dart' show SuperCacheAdapter, TypeRegistry;
export 'src/codec/binary_reader.dart' show BinaryReader;
export 'src/codec/binary_writer.dart' show BinaryWriter;
export 'src/encryption/cipher.dart' show SuperCacheCipher, NullCipher;
export 'src/encryption/aes_cipher.dart' show AesCipher;
export 'src/encryption/xor_cipher.dart' show XorCipher;
export 'src/eviction/eviction_policy.dart' show EvictionPolicy;
export 'src/eviction/arc_policy.dart' show ArcPolicy;
export 'src/eviction/lru_policy.dart' show LruPolicy;
export 'src/eviction/lfu_policy.dart' show LfuPolicy;
export 'src/utils/byte_utils.dart' show ByteUtils;
export 'src/utils/crc32.dart' show Crc32;
export 'src/utils/hash_utils.dart' show HashUtils;
export 'annotations/cacheable.dart' show Cacheable, CacheField, CacheKey;

// ── Implementation ────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:super_cache/src/codec/adapters/datetime_adapter.dart';
import 'package:super_cache/src/codec/adapters/list_adapter.dart';
import 'package:super_cache/src/codec/adapters/map_adapter.dart';
import 'package:super_cache/src/codec/adapters/primitive_adapter.dart';
import 'package:super_cache/src/codec/super_codec.dart';
import 'package:super_cache/src/codec/type_registry.dart';
import 'package:super_cache/src/core/cache_config.dart';
import 'package:super_cache/src/core/cache_exceptions.dart';
import 'package:super_cache/src/core/cache_statistics.dart';
import 'package:super_cache/src/core/super_cache_base.dart';
import 'package:super_cache/src/engine/cache_orchestrator.dart';
import 'package:super_cache/src/engine/l1_memory_cache.dart';
import 'package:super_cache/src/engine/l2_disk_cache.dart';
import 'package:super_cache/src/eviction/arc_policy.dart';
import 'package:super_cache/src/eviction/eviction_policy.dart';
import 'package:super_cache/src/eviction/lfu_policy.dart';
import 'package:super_cache/src/eviction/lru_policy.dart';
import 'package:super_cache/src/utils/compaction_manager.dart';
import 'package:super_cache/src/utils/logger.dart';

/// The primary entry point for super_cache.
///
/// ## Architecture at a glance
///
/// ```
///  SuperCache (public API)
///       │
///       ▼
///  CacheOrchestrator
///  ┌────────────────────────────────────────┐
///  │  L1 MemoryCache  ← O(1) HashMap       │
///  │  L2 DiskCache    ← O(1) B-Index seek  │
///  │  WriteBuffer     ← batched I/O        │
///  │  TtlManager      ← periodic cleanup   │
///  └────────────────────────────────────────┘
///       │
///       ▼
///  StorageEngine (DartIoStorage / WebStorage)
///       │
///       ▼
///  IndexManager (B-Index in memory + .idx file on disk)
/// ```
final class SuperCache implements SuperCacheBase {
  SuperCache._({required CacheOrchestrator orchestrator})
      : _orchestrator = orchestrator;

  static SuperCache? _defaultInstance;
  static final Map<String, SuperCache> _named = {};

  final CacheOrchestrator _orchestrator;
  CompactionManager? _compactionManager;

  // ── Statistics ─────────────────────────────────────────────────────────────

  @override
  CacheStatistics get statistics => _orchestrator.stats;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────

  /// Initializes a [SuperCache] instance.
  ///
  /// **Must be awaited before any other cache operation.**
  ///
  /// [config] — cache configuration (safe to pass `const CacheConfig()` for
  ///   sensible defaults).
  ///
  /// [name] — when provided, creates a named instance accessible via
  ///   [SuperCache.named].  When `null`, the result is stored as the default
  ///   instance ([SuperCache.instance]).
  ///
  /// Calling [init] twice with the same [name] returns the existing instance.
  static Future<SuperCache> init({
    CacheConfig config = const CacheConfig(),
    String? name,
  }) async {
    // Return existing instance if already initialized
    if (name == null && _defaultInstance != null) return _defaultInstance!;
    if (name != null && _named.containsKey(name)) return _named[name]!;

    // Validate configuration
    config.validate();
    SuperCacheLogger.configure(config);
    SuperCacheLogger.info('Initializing super_cache (box: ${config.boxName})');

    // Register built-in adapters
    _registerBuiltInAdapters();

    // Build eviction policy
    final policy = _buildPolicy(config.evictionPolicy, config.maxMemoryEntries);

    // Build codec
    final codec = SuperCodec(registry: TypeRegistry.instance);

    // Build L1
    final l1 = L1MemoryCache(config: config, evictionPolicy: policy);

    // Build L2
    L2DiskCache? l2;
    if (config.enableDiskCache) {
      final dir = config.diskDirectory ?? await _defaultDirectory(config.boxName);
      l2 = await L2DiskCache.open(
        directory: dir,
        boxName: config.boxName,
        config: config,
        codec: codec,
      );
    }

    // Build stats
    final stats = CacheStatistics();

    // Build orchestrator
    final orchestrator = CacheOrchestrator(
      config: config,
      l1: l1,
      l2: l2,
      codec: codec,
      stats: stats,
    );

    final cache = SuperCache._(orchestrator: orchestrator);

    // Start compaction manager
    if (l2 != null && config.enableDiskCache) {
      cache._compactionManager = CompactionManager(
        l2: l2,
        config: config,
      );
      if (config.autoCompact) {
        cache._compactionManager!.start();
      }
    }

    SuperCacheLogger.info('super_cache ready (box: ${config.boxName})');

    if (name == null) {
      _defaultInstance = cache;
    } else {
      _named[name] = cache;
    }
    return cache;
  }

  /// Returns the default [SuperCache] instance.
  ///
  /// Throws [CacheNotInitializedException] if [init] has not been called yet.
  static SuperCache get instance {
    if (_defaultInstance == null) throw const CacheNotInitializedException();
    return _defaultInstance!;
  }

  /// Returns the named [SuperCache] instance created by `init(name: ...)`.
  ///
  /// Throws [CacheNotInitializedException] if the named instance does not exist.
  static SuperCache named(String name) {
    final inst = _named[name];
    if (inst == null) {
      throw CacheNotInitializedException(
        'No SuperCache instance with name "$name". '
        'Call await SuperCache.init(name: "$name") first.',
      );
    }
    return inst;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Reads the value for [key], or `null` if missing / expired.
  @override
  Future<T?> get<T>(String key) => _orchestrator.get<T>(key);

  /// Writes [value] under [key].
  ///
  /// [ttl] overrides [CacheConfig.defaultTtl] for this entry only.
  /// Set [forceSync] = `true` to block until the value is flushed to disk.
  @override
  Future<void> put<T>(
    String key,
    T value, {
    Duration? ttl,
    bool forceSync = false,
  }) =>
      _orchestrator.put<T>(key, value, ttl: ttl, forceSync: forceSync);

  /// Removes [key] from both L1 and L2.
  @override
  Future<bool> remove(String key) => _orchestrator.remove(key);

  /// Returns `true` if [key] is present and not expired.
  @override
  Future<bool> containsKey(String key) => _orchestrator.containsKey(key);

  // ─────────────────────────────────────────────────────────────────────────
  // Batch Operations
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> putAll(Map<String, dynamic> entries, {Duration? ttl}) =>
      _orchestrator.putAll(entries, ttl: ttl);

  @override
  Future<Map<String, dynamic>> getAll(List<String> keys) =>
      _orchestrator.getAll(keys);

  @override
  Future<void> removeAll(List<String> keys) => _orchestrator.removeAll(keys);

  // ─────────────────────────────────────────────────────────────────────────
  // Cache-Aside Pattern
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the cached value for [key], or calls [loader] if missing.
  ///
  /// ```dart
  /// final user = await cache.getOrPut(
  ///   'user:$id',
  ///   () => api.fetchUser(id),
  ///   ttl: const Duration(hours: 1),
  /// );
  /// ```
  @override
  Future<T> getOrPut<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  }) =>
      _orchestrator.getOrPut<T>(key, loader, ttl: ttl);

  // ─────────────────────────────────────────────────────────────────────────
  // Management
  // ─────────────────────────────────────────────────────────────────────────

  /// Clears all entries from L1 and L2.
  @override
  Future<void> clear() => _orchestrator.clear();

  /// Returns all keys in the cache (L1 ∪ L2).
  @override
  Future<Set<String>> getAllKeys() => _orchestrator.getAllKeys();

  /// Pre-loads [keys] from L2 into L1 at app startup.
  @override
  Future<void> warmUp(List<String> keys) => _orchestrator.warmUp(keys);

  /// Flushes the write buffer to disk immediately.
  @override
  Future<void> flush() => _orchestrator.flush();

  /// Runs disk compaction immediately.
  Future<int> compact() =>
      _compactionManager?.runCompaction() ?? Future.value(0);

  // ─────────────────────────────────────────────────────────────────────────
  // Adapter Registration
  // ─────────────────────────────────────────────────────────────────────────

  /// Registers a [SuperCacheAdapter] for a custom type.
  ///
  /// **Must be called before [init]** so that the adapter is available when
  /// the first [put] or [get] for that type occurs.
  ///
  /// ```dart
  /// SuperCache.registerAdapter(UserAdapter());
  /// SuperCache.registerAdapter(ProductAdapter());
  /// await SuperCache.init();
  /// ```
  static void registerAdapter<T>(SuperCacheAdapter<T> adapter) {
    TypeRegistry.instance.register<T>(adapter);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Disposes this [SuperCache] instance, flushing pending writes and
  /// releasing all resources.
  ///
  /// After calling [dispose], this instance must not be used again.
  @override
  Future<void> dispose() async {
    await _compactionManager?.dispose();
    await _orchestrator.dispose();
    SuperCacheLogger.info('super_cache disposed');
  }

  /// Disposes all named and default instances.
  ///
  /// Useful in tests to start fresh between test cases.
  static Future<void> disposeAll() async {
    for (final cache in _named.values) {
      await cache.dispose();
    }
    _named.clear();
    if (_defaultInstance != null) {
      await _defaultInstance!.dispose();
      _defaultInstance = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  static EvictionPolicy _buildPolicy(EvictionPolicyType type, int maxSize) {
    switch (type) {
      case EvictionPolicyType.lru:
        return LruPolicy(maxSize: maxSize);
      case EvictionPolicyType.lfu:
        return LfuPolicy(maxSize: maxSize);
      case EvictionPolicyType.arc:
        return ArcPolicy(maxSize: maxSize);
    }
  }

  static Future<String> _defaultDirectory(String boxName) async {
    // Pure-Dart fallback: use the platform's temp directory as a safe default.
    // Flutter users should always provide CacheConfig.diskDirectory explicitly.
    final base = Directory.systemTemp.path;
    return p.join(base, 'super_cache', boxName);
  }

  static bool _builtInAdaptersRegistered = false;

  static void _registerBuiltInAdapters() {
    if (_builtInAdaptersRegistered) return;
    _builtInAdaptersRegistered = true;

    final registry = TypeRegistry.instance;
    registry
      ..register(NullableStringAdapter())
      ..register(NullableIntAdapter())
      ..register(NullableDoubleAdapter())
      ..register(NullableBoolAdapter())
      ..register(StringListAdapter())
      ..register(IntListAdapter())
      ..register(DoubleListAdapter())
      ..register(BoolListAdapter())
      ..register(StringMapAdapter())
      ..register(StringIntMapAdapter())
      ..register(DateTimeAdapter())
      ..register(DurationAdapter())
      ..register(UriAdapter())
      ..register(BigIntAdapter())
      ..register(DateTimeListAdapter());
  }
}
