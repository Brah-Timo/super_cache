import 'package:meta/meta.dart';
import 'package:super_cache/src/core/cache_exceptions.dart';

/// Supported eviction policy types.
///
/// - [lru]: Least Recently Used — evicts the entry that was accessed longest ago.
/// - [lfu]: Least Frequently Used — evicts the entry with the fewest accesses.
/// - [arc]: Adaptive Replacement Cache — automatically balances between recency
///   and frequency. **Recommended default** for most real-world workloads.
enum EvictionPolicyType {
  /// Least Recently Used.
  lru,

  /// Least Frequently Used.
  lfu,

  /// Adaptive Replacement Cache (default).
  arc,
}

/// Log verbosity levels for super_cache's internal logger.
enum CacheLogLevel {
  /// Everything, including raw byte counts.
  verbose,

  /// Useful for development debugging.
  debug,

  /// General lifecycle events.
  info,

  /// Non-fatal issues only.
  warning,

  /// Errors only.
  error,

  /// Completely silent.
  none,
}

/// Full configuration for a [SuperCache] instance.
///
/// Every parameter has a carefully tuned default that is appropriate for
/// most Flutter applications. Override only what you need.
///
/// ```dart
/// const config = CacheConfig(
///   maxMemoryEntries: 2000,
///   defaultTtl: Duration(hours: 12),
///   evictionPolicy: EvictionPolicyType.arc,
///   enableStatistics: true,
/// );
/// await SuperCache.init(config: config);
/// ```
@immutable
final class CacheConfig {
  /// Creates a fully immutable cache configuration.
  const CacheConfig({
    // ── L1 Memory ──────────────────────────────────────────────────
    this.maxMemoryEntries = 1000,
    this.maxMemorySizeBytes = 52428800, // 50 MB

    // ── L2 Disk ────────────────────────────────────────────────────
    this.enableDiskCache = true,
    this.maxDiskSizeBytes = 524288000, // 500 MB
    this.diskDirectory,
    this.boxName = 'super_cache_default',

    // ── TTL ────────────────────────────────────────────────────────
    this.defaultTtl,
    this.enableTtlCleanup = true,
    this.ttlCleanupInterval = const Duration(minutes: 5),

    // ── Eviction ───────────────────────────────────────────────────
    this.evictionPolicy = EvictionPolicyType.arc,

    // ── Write Buffer ───────────────────────────────────────────────
    this.writeBufferSize = 100,
    this.writeBufferFlushInterval = const Duration(milliseconds: 500),
    this.syncWrites = false,

    // ── Encryption ─────────────────────────────────────────────────
    this.encryptionKey,

    // ── Isolate ────────────────────────────────────────────────────
    this.enableIsolateSupport = false,

    // ── Compaction ─────────────────────────────────────────────────
    this.compactionThreshold = 0.30,
    this.autoCompact = true,

    // ── Diagnostics ────────────────────────────────────────────────
    this.enableStatistics = true,
    this.enableLogging = false,
    this.logLevel = CacheLogLevel.warning,
  });

  // ── L1 Memory ────────────────────────────────────────────────────────────

  /// Maximum number of entries allowed in the in-memory L1 cache.
  ///
  /// When exceeded, the configured [evictionPolicy] removes the least valuable
  /// entry before inserting a new one.
  final int maxMemoryEntries;

  /// Maximum total memory (in bytes) consumed by L1 cache values.
  ///
  /// Defaults to 50 MB. When exceeded, eviction runs before each new write.
  final int maxMemorySizeBytes;

  // ── L2 Disk ──────────────────────────────────────────────────────────────

  /// Whether the L2 disk cache is enabled.
  ///
  /// Set to `false` for a pure in-memory cache (data lost on app restart).
  final bool enableDiskCache;

  /// Maximum size in bytes for the L2 disk cache.
  ///
  /// Defaults to 500 MB. When exceeded, the oldest disk entries are removed.
  final int maxDiskSizeBytes;

  /// Absolute path to the directory where cache files are stored.
  ///
  /// Defaults to `<applicationDocumentsDirectory>/super_cache/<boxName>`.
  final String? diskDirectory;

  /// Logical name for this cache box.
  ///
  /// Multiple caches with different [boxName]s can coexist in the same app.
  final String boxName;

  // ── TTL ──────────────────────────────────────────────────────────────────

  /// Default time-to-live applied to every entry that does not specify its own TTL.
  ///
  /// `null` means entries never expire unless explicitly removed.
  final Duration? defaultTtl;

  /// Whether to run a background sweep that removes expired entries.
  final bool enableTtlCleanup;

  /// How often the TTL cleanup sweep runs.
  ///
  /// Defaults to every 5 minutes.
  final Duration ttlCleanupInterval;

  // ── Eviction ─────────────────────────────────────────────────────────────

  /// The algorithm used to select which L1 entry to evict when the cache is full.
  ///
  /// [EvictionPolicyType.arc] is the default and performs best in real workloads.
  final EvictionPolicyType evictionPolicy;

  // ── Write Buffer ─────────────────────────────────────────────────────────

  /// Maximum number of pending writes to batch before flushing to disk.
  ///
  /// Larger values mean fewer I/O operations but higher memory usage.
  final int writeBufferSize;

  /// How often the write buffer flushes to disk automatically.
  ///
  /// A shorter interval reduces data loss risk but increases I/O.
  final Duration writeBufferFlushInterval;

  /// When `true`, every [SuperCache.put] waits for the disk write to complete.
  ///
  /// This is slower but guarantees durability. Recommended for financial or
  /// security-sensitive data.
  final bool syncWrites;

  // ── Encryption ───────────────────────────────────────────────────────────

  /// 32-byte (256-bit) AES key for encrypting all disk data.
  ///
  /// When `null`, no encryption is applied (default for maximum performance).
  /// Use [AesCipher.generateKey] to produce a cryptographically random key.
  ///
  /// ⚠️ Never hard-code this in source code. Derive it from a secure
  /// key store (e.g. flutter_secure_storage).
  final List<int>? encryptionKey;

  // ── Isolate ──────────────────────────────────────────────────────────────

  /// When `true`, disk I/O runs in a separate Dart Isolate to avoid blocking
  /// the UI thread.
  ///
  /// Recommended for large caches (> 10 MB writes) in Flutter apps.
  final bool enableIsolateSupport;

  // ── Compaction ───────────────────────────────────────────────────────────

  /// Fragmentation ratio above which the compaction manager rewrites the
  /// data file to reclaim wasted space.
  ///
  /// `0.30` means: compact when ≥ 30% of the file is wasted space.
  final double compactionThreshold;

  /// Whether compaction runs automatically in the background.
  final bool autoCompact;

  // ── Diagnostics ──────────────────────────────────────────────────────────

  /// Whether to collect hit/miss/eviction/write statistics.
  ///
  /// Statistics collection has negligible overhead and is enabled by default.
  final bool enableStatistics;

  /// Whether to print log messages to the console.
  final bool enableLogging;

  /// The minimum severity level for emitted log messages.
  final CacheLogLevel logLevel;

  // ─────────────────────────────────────────────────────────────────────────
  // Validation
  // ─────────────────────────────────────────────────────────────────────────

  /// Throws [InvalidConfigException] if the configuration contains
  /// contradictory or impossible values.
  void validate() {
    if (maxMemoryEntries < 1) {
      throw const InvalidConfigException(
        'maxMemoryEntries must be at least 1.',
      );
    }
    if (maxMemorySizeBytes < 1024) {
      throw const InvalidConfigException(
        'maxMemorySizeBytes must be at least 1024 bytes.',
      );
    }
    if (maxDiskSizeBytes < maxMemorySizeBytes && enableDiskCache) {
      throw const InvalidConfigException(
        'maxDiskSizeBytes should be >= maxMemorySizeBytes for optimal performance.',
      );
    }
    if (writeBufferSize < 1) {
      throw const InvalidConfigException(
        'writeBufferSize must be at least 1.',
      );
    }
    if (compactionThreshold <= 0.0 || compactionThreshold >= 1.0) {
      throw const InvalidConfigException(
        'compactionThreshold must be between 0.0 and 1.0 (exclusive).',
      );
    }
    if (encryptionKey != null && encryptionKey!.length != 32) {
      throw InvalidConfigException(
        'encryptionKey must be exactly 32 bytes for AES-256. '
        'Got ${encryptionKey!.length} bytes.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // copyWith
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a copy of this configuration with the given fields replaced.
  CacheConfig copyWith({
    int? maxMemoryEntries,
    int? maxMemorySizeBytes,
    bool? enableDiskCache,
    int? maxDiskSizeBytes,
    String? diskDirectory,
    String? boxName,
    Duration? defaultTtl,
    bool? enableTtlCleanup,
    Duration? ttlCleanupInterval,
    EvictionPolicyType? evictionPolicy,
    int? writeBufferSize,
    Duration? writeBufferFlushInterval,
    bool? syncWrites,
    List<int>? encryptionKey,
    bool? enableIsolateSupport,
    double? compactionThreshold,
    bool? autoCompact,
    bool? enableStatistics,
    bool? enableLogging,
    CacheLogLevel? logLevel,
  }) {
    return CacheConfig(
      maxMemoryEntries: maxMemoryEntries ?? this.maxMemoryEntries,
      maxMemorySizeBytes: maxMemorySizeBytes ?? this.maxMemorySizeBytes,
      enableDiskCache: enableDiskCache ?? this.enableDiskCache,
      maxDiskSizeBytes: maxDiskSizeBytes ?? this.maxDiskSizeBytes,
      diskDirectory: diskDirectory ?? this.diskDirectory,
      boxName: boxName ?? this.boxName,
      defaultTtl: defaultTtl ?? this.defaultTtl,
      enableTtlCleanup: enableTtlCleanup ?? this.enableTtlCleanup,
      ttlCleanupInterval: ttlCleanupInterval ?? this.ttlCleanupInterval,
      evictionPolicy: evictionPolicy ?? this.evictionPolicy,
      writeBufferSize: writeBufferSize ?? this.writeBufferSize,
      writeBufferFlushInterval:
          writeBufferFlushInterval ?? this.writeBufferFlushInterval,
      syncWrites: syncWrites ?? this.syncWrites,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      enableIsolateSupport: enableIsolateSupport ?? this.enableIsolateSupport,
      compactionThreshold: compactionThreshold ?? this.compactionThreshold,
      autoCompact: autoCompact ?? this.autoCompact,
      enableStatistics: enableStatistics ?? this.enableStatistics,
      enableLogging: enableLogging ?? this.enableLogging,
      logLevel: logLevel ?? this.logLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheConfig &&
          maxMemoryEntries == other.maxMemoryEntries &&
          maxMemorySizeBytes == other.maxMemorySizeBytes &&
          enableDiskCache == other.enableDiskCache &&
          maxDiskSizeBytes == other.maxDiskSizeBytes &&
          diskDirectory == other.diskDirectory &&
          boxName == other.boxName &&
          defaultTtl == other.defaultTtl &&
          enableTtlCleanup == other.enableTtlCleanup &&
          ttlCleanupInterval == other.ttlCleanupInterval &&
          evictionPolicy == other.evictionPolicy &&
          writeBufferSize == other.writeBufferSize &&
          writeBufferFlushInterval == other.writeBufferFlushInterval &&
          syncWrites == other.syncWrites &&
          enableIsolateSupport == other.enableIsolateSupport &&
          compactionThreshold == other.compactionThreshold &&
          autoCompact == other.autoCompact &&
          enableStatistics == other.enableStatistics &&
          enableLogging == other.enableLogging &&
          logLevel == other.logLevel;

  @override
  int get hashCode => Object.hashAll([
        maxMemoryEntries,
        maxMemorySizeBytes,
        enableDiskCache,
        maxDiskSizeBytes,
        diskDirectory,
        boxName,
        defaultTtl,
        enableTtlCleanup,
        ttlCleanupInterval,
        evictionPolicy,
        writeBufferSize,
        writeBufferFlushInterval,
        syncWrites,
        enableIsolateSupport,
        compactionThreshold,
        autoCompact,
        enableStatistics,
        enableLogging,
        logLevel,
      ]);

  @override
  String toString() => 'CacheConfig('
      'boxName: $boxName, '
      'maxMemoryEntries: $maxMemoryEntries, '
      'maxMemorySizeBytes: ${maxMemorySizeBytes ~/ 1024}KB, '
      'enableDiskCache: $enableDiskCache, '
      'evictionPolicy: ${evictionPolicy.name}, '
      'defaultTtl: $defaultTtl, '
      'syncWrites: $syncWrites'
      ')';
}
