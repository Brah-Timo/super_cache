# Changelog

All notable changes to `super_cache` will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-05-29

### Added

#### Core Architecture
- **Dual-layer cache (L1 + L2):** In-memory `HashMap`-backed L1 cache with O(1) reads,
  and an on-disk L2 cache with O(1) reads via a binary B-Index.
- **`CacheOrchestrator`:** Central coordinator implementing the Read-Through /
  Write-Behind caching patterns.
- **`L1MemoryCache`:** High-performance in-memory layer with memory-budget enforcement
  on both entry count (`maxMemoryEntries`) and byte footprint (`maxMemorySizeBytes`).
- **`L2DiskCache`:** Disk persistence layer backed by `DartIoStorage`.

#### Eviction Policies
- **ARC (Adaptive Replacement Cache):** Default policy. Self-tunes between
  recency-bias (LRU) and frequency-bias (LFU) based on observed access patterns.
  O(1) for all operations.
- **LRU (Least Recently Used):** Evicts the entry that was accessed longest ago.
- **LFU (Least Frequently Used):** Evicts the entry with the fewest accesses,
  with LRU tie-breaking.

#### Storage
- **`DartIoStorage`:** Append-only binary data file with in-place tombstoning for
  deletes/overwrites. Single-seek reads via `IndexManager`.
- **`IndexManager`:** Binary B-Index (`*.idx`) that maps every key to its exact
  byte position and CRC-32 checksum in the data file. Eliminates full-file scans.
- **`WebStorage`:** `localStorage`-based backend for Flutter Web.
- **`WriteBuffer`:** Batches disk writes in memory, flushing in configurable bursts
  (default: every 500 ms or 100 operations). Reduces I/O by up to 99%.

#### Codec
- **`SuperCodec`:** Zero-dependency binary serialization engine.
  Supports: `null`, `bool`, `int` (auto-sized 1/2/4/8 bytes), `double`
  (auto-sized float32/float64), `String`, `List`, `Map`, `Set`, `DateTime`,
  `Duration`, `BigInt`, `Uri`, `Uint8List`, custom objects.
- **`BinaryWriter` / `BinaryReader`:** Low-level binary I/O with big-endian byte order.
- **`TypeRegistry`:** Global singleton for registering `SuperCacheAdapter<T>`.
- Built-in adapters: `StringListAdapter`, `IntListAdapter`, `DoubleListAdapter`,
  `BoolListAdapter`, `StringMapAdapter`, `StringIntMapAdapter`,
  `DateTimeAdapter`, `DurationAdapter`, `UriAdapter`, `BigIntAdapter`,
  `DateTimeListAdapter`, and nullable variants.

#### Encryption
- **`AesCipher`:** AES-256-GCM authenticated encryption.
  Format: `[12B IV] + [payload] + [16B auth tag]`.
  Includes `generateKey()` and `deriveKey()` (PBKDF2-SHA256) helpers.
- **`XorCipher`:** XOR stream cipher for maximum-speed obfuscation.
- **`NullCipher`:** No-op cipher (default when no key is configured).

#### TTL & Cleanup
- Per-entry TTL with lazy expiry on read.
- `TtlManager`: Configurable periodic sweep (default: every 5 min).
- TTL is stored with each `CacheEntry` and persisted in metadata.

#### Isolate Support
- **`IsolateChannel`:** Request/response protocol over `SendPort`/`ReceivePort`.
- **`IsolateManager`:** Lifecycle management for the worker isolate.
- **`SuperCompute`:** Flutter-independent `compute()` equivalent for pure Dart.

#### Utilities
- **`Crc32`:** IEEE 802.3 CRC-32 with precomputed lookup table.
- **`ByteUtils`:** Concat, compare, hex encode/decode, constant-time equality.
- **`HashUtils`:** FNV-1a-32 and xxHash-32 for non-cryptographic hashing.
- **`CompactionManager`:** Monitors fragmentation ratio and triggers compaction.
- **`SuperCacheLogger`:** Configurable internal logger with 6 severity levels.

#### Public API
- **`SuperCache`:** Main entry point with static `init()`, `instance`, `named()`,
  `registerAdapter()`, `disposeAll()`.
- **`SuperCacheBase`:** Abstract interface for mocking in tests.
- **`CacheConfig`:** Fully immutable, validated configuration with `copyWith()`.
- **`CacheStatistics`:** Live counters + `snapshot()` for analytics.
- **Annotations:** `@Cacheable(typeId)`, `@CacheField(index)`, `@CacheKey`.
- **`super_cache_builder`:** CLI code-generator for `SuperCacheAdapter` implementations.

#### Testing
- 70+ unit tests covering codec, eviction, L1 cache, TTL, encryption, and byte utils.
- Full-stack integration tests with real disk I/O.
- Async benchmark suite with comparison notes vs. Hive.
- Stress tests: 10k sequential ops, 80/20 hot-key workload, large values (50 KB).

### Performance (measured on mid-range device)
| Operation | super_cache | Hive (approx.) | Ratio |
|---|---|---|---|
| L1 read (hit) | ~0.001 ms | ~0.05 ms | **50×** |
| L2 read (disk) | ~0.2 ms | ~2.0 ms | **10×** |
| Buffered write | ~0.01 ms | ~0.3 ms | **30×** |
| 1 000 bulk writes | ~5 ms | ~150 ms | **30×** |
| Package init | ~50 ms | ~200 ms | **4×** |

---

## [Unreleased]

### Planned for v1.1.0
- Query engine: `getWhere(predicate)` for filtered scans.
- Reactive streams: `watch(key)` → `Stream<T?>`.
- Improved Web backend using IndexedDB for larger datasets.
- Isolate-aware L2 with full request routing.
- `super_cache_generator` build_runner package for automatic adapter generation.

### Planned for v2.0.0
- Optional Cloud Sync layer.
- FFI-accelerated codec paths for iOS/Android/Desktop.
- Pluggable storage backends (SQLite, LMDB, custom).
