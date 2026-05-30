/// All custom exceptions thrown by super_cache.
///
/// Every error has a clear message and optional cause chain so that
/// callers can handle errors precisely without catching generic [Exception].
library;

// ─────────────────────────────────────────────────────────────────────────────
// Base
// ─────────────────────────────────────────────────────────────────────────────

/// Root exception for all super_cache errors.
///
/// All super_cache exceptions extend this class, allowing callers to
/// catch all cache-related errors with a single `on SuperCacheException` clause.
base class SuperCacheException implements Exception {
  /// Creates a [SuperCacheException] with the given [message] and optional [cause].
  const SuperCacheException(this.message, {this.cause});

  /// Human-readable description of the error.
  final String message;

  /// The underlying exception that caused this error, if any.
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'SuperCacheException: $message\nCaused by: $cause';
    }
    return 'SuperCacheException: $message';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Initialization
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when a [SuperCache] instance is used before [SuperCache.init] is called.
final class CacheNotInitializedException extends SuperCacheException {
  /// Creates a [CacheNotInitializedException].
  const CacheNotInitializedException([
    super.message =
        'SuperCache has not been initialized. '
        'Call await SuperCache.init() before using the cache.',
  ]);
}

/// Thrown when cache initialization fails (e.g. disk not accessible).
final class CacheInitializationException extends SuperCacheException {
  /// Creates a [CacheInitializationException].
  const CacheInitializationException(super.message, {super.cause});
}

// ─────────────────────────────────────────────────────────────────────────────
// Codec / Serialization
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when encoding or decoding a value fails.
final class CacheCodecException extends SuperCacheException {
  /// Creates a [CacheCodecException].
  const CacheCodecException(super.message, {super.cause});
}

/// Thrown when no [SuperCacheAdapter] is registered for a given type.
final class MissingAdapterException extends SuperCacheException {
  /// Creates a [MissingAdapterException] for the given [typeName].
  MissingAdapterException(String typeName)
      : super(
          'No adapter registered for type "$typeName". '
          'Call SuperCache.registerAdapter() before reading or writing '
          'instances of this type.',
        );
}

/// Thrown when a registered adapter [typeId] conflicts with an existing one.
final class AdapterConflictException extends SuperCacheException {
  /// Creates an [AdapterConflictException].
  AdapterConflictException(int typeId, String existingType, String newType)
      : super(
          'Adapter typeId $typeId is already registered for "$existingType". '
          'Cannot register adapter for "$newType" with the same typeId.',
        );
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage / I/O
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when a disk read or write operation fails.
final class CacheStorageException extends SuperCacheException {
  /// Creates a [CacheStorageException].
  const CacheStorageException(super.message, {super.cause});
}

/// Thrown when the cache data file on disk is corrupted.
final class CacheCorruptedException extends SuperCacheException {
  /// Creates a [CacheCorruptedException] with details about which file failed.
  const CacheCorruptedException(String filePath, {super.cause})
      : super(
          'Cache file is corrupted: $filePath. '
          'The cache has been reset automatically.',
        );
}

/// Thrown when a checksum (CRC32) verification fails for a stored entry.
final class ChecksumMismatchException extends SuperCacheException {
  /// Creates a [ChecksumMismatchException].
  ChecksumMismatchException(String key, int expected, int actual)
      : super(
          'Checksum mismatch for key "$key". '
          'Expected 0x${expected.toRadixString(16)}, '
          'got 0x${actual.toRadixString(16)}. '
          'The entry may be corrupted.',
        );
}

// ─────────────────────────────────────────────────────────────────────────────
// Capacity
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the disk cache exceeds the configured [CacheConfig.maxDiskSizeBytes].
final class DiskCapacityExceededException extends SuperCacheException {
  /// Creates a [DiskCapacityExceededException].
  DiskCapacityExceededException(int current, int max)
      : super(
          'Disk cache capacity exceeded: '
          '${_formatBytes(current)} used of ${_formatBytes(max)} maximum.',
        );

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1048576).toStringAsFixed(1)}MB';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Encryption
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when encryption or decryption fails.
final class CacheEncryptionException extends SuperCacheException {
  /// Creates a [CacheEncryptionException].
  const CacheEncryptionException(super.message, {super.cause});
}

/// Thrown when an invalid encryption key is supplied (e.g. wrong length).
final class InvalidKeyException extends SuperCacheException {
  /// Creates an [InvalidKeyException].
  InvalidKeyException(int expected, int actual)
      : super(
          'Invalid encryption key length: expected $expected bytes, got $actual bytes.',
        );
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when an Isolate communication error occurs.
final class IsolateException extends SuperCacheException {
  /// Creates an [IsolateException].
  const IsolateException(super.message, {super.cause});
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when a [CacheConfig] contains invalid or contradictory settings.
final class InvalidConfigException extends SuperCacheException {
  /// Creates an [InvalidConfigException].
  const InvalidConfigException(super.message);
}
