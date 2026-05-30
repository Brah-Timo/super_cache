import 'package:meta/meta.dart';

/// The internal data model for a single cached item.
///
/// Every entry carries both the user's value and rich metadata that powers
/// eviction policies, TTL management, and disk persistence.
///
/// This class is intentionally mutable — [recordAccess] and [updateValue]
/// modify it in-place to avoid heap allocation on every cache hit.
@internal
final class CacheEntry<T> {
  /// Creates a [CacheEntry] with the given [key], [value], and measured
  /// [sizeBytes].
  ///
  /// [ttl] overrides any default TTL set in [CacheConfig].
  CacheEntry({
    required this.key,
    required this.value,
    required this.sizeBytes,
    this.ttl,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastAccessedAt = lastAccessedAt ?? DateTime.now(),
        accessCount = 0,
        writeCount = 1,
        version = 1;

  /// The unique string key for this cache entry.
  final String key;

  /// The user-supplied value.
  T value;

  /// Approximate heap size of [value] in bytes.
  ///
  /// Used for memory-budget accounting in L1 and disk-budget accounting in L2.
  int sizeBytes;

  /// Optional time-to-live for this specific entry.
  ///
  /// `null` means the entry lives forever (until evicted by capacity pressure).
  final Duration? ttl;

  /// UTC timestamp at which this entry was first created.
  final DateTime createdAt;

  /// UTC timestamp of the most recent read or write access.
  DateTime lastAccessedAt;

  /// Total number of times this entry has been read.
  ///
  /// Used by [LfuPolicy] and [ArcPolicy].
  int accessCount;

  /// Total number of times this entry has been written (put/update).
  int writeCount;

  /// Monotonically increasing version number.
  ///
  /// Incremented on every [updateValue] call; useful for cache invalidation
  /// and conflict detection.
  int version;

  // ─────────────────────────────────────────────────────────────────────────
  // TTL Queries
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether this entry's TTL has elapsed.
  ///
  /// Always returns `false` when [ttl] is `null`.
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// The absolute [DateTime] at which this entry expires, or `null` if it
  /// has no TTL.
  DateTime? get expiresAt {
    if (ttl == null) return null;
    return createdAt.add(ttl!);
  }

  /// The time remaining before this entry expires.
  ///
  /// Returns [Duration.zero] if already expired.
  /// Returns `null` if [ttl] is `null`.
  Duration? get remainingTtl {
    if (ttl == null) return null;
    final remaining = expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mutation
  // ─────────────────────────────────────────────────────────────────────────

  /// Records a read access: bumps [accessCount] and updates [lastAccessedAt].
  void recordAccess() {
    accessCount++;
    lastAccessedAt = DateTime.now();
  }

  /// Replaces [value] and [sizeBytes] with new data, incrementing [version].
  void updateValue(T newValue, int newSizeBytes) {
    value = newValue;
    sizeBytes = newSizeBytes;
    version++;
    writeCount++;
    lastAccessedAt = DateTime.now();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Serialization (metadata only — value is handled by SuperCodec)
  // ─────────────────────────────────────────────────────────────────────────

  /// Serializes metadata fields to a [Map].
  ///
  /// The [value] itself is NOT included here — it is handled separately by
  /// [SuperCodec] and stored as raw bytes.
  Map<String, dynamic> metadataToMap() => {
        'key': key,
        'sizeBytes': sizeBytes,
        'ttlMs': ttl?.inMilliseconds,
        'createdAtUs': createdAt.microsecondsSinceEpoch,
        'lastAccessedAtUs': lastAccessedAt.microsecondsSinceEpoch,
        'accessCount': accessCount,
        'writeCount': writeCount,
        'version': version,
      };

  /// Reconstructs metadata from a [Map] produced by [metadataToMap].
  static CacheEntry<dynamic> fromMetadataMap(
    Map<String, dynamic> map,
    dynamic value,
  ) {
    final entry = CacheEntry<dynamic>(
      key: map['key'] as String,
      value: value,
      sizeBytes: map['sizeBytes'] as int,
      ttl: map['ttlMs'] != null
          ? Duration(milliseconds: map['ttlMs'] as int)
          : null,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(map['createdAtUs'] as int),
      lastAccessedAt:
          DateTime.fromMicrosecondsSinceEpoch(map['lastAccessedAtUs'] as int),
    );
    entry.accessCount = map['accessCount'] as int;
    entry.writeCount = map['writeCount'] as int;
    entry.version = map['version'] as int;
    return entry;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Object overrides
  // ─────────────────────────────────────────────────────────────────────────

  @override
  String toString() => 'CacheEntry<$T>('
      'key: "$key", '
      'sizeBytes: $sizeBytes, '
      'isExpired: $isExpired, '
      'accessCount: $accessCount, '
      'version: $version'
      ')';
}
