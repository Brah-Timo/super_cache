import 'dart:typed_data';

/// Abstract contract for a super_cache L2 storage backend.
///
/// Concrete implementations include:
/// - [DartIoStorage] — uses `dart:io` [File] APIs (mobile, desktop, server).
/// - [WebStorage]   — uses `localStorage` / `IndexedDB` (Flutter Web).
///
/// All operations are asynchronous because storage I/O is inherently blocking.
/// Implementations MUST be safe to call from a single isolate — concurrent
/// access from multiple isolates requires an [IsolateChannel] wrapper.
abstract interface class StorageEngine {
  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Opens the storage backend for the given [directory] and [boxName].
  ///
  /// Creates the directory and any necessary files if they do not exist.
  /// Must be called before any other method.
  Future<void> open(String directory, String boxName);

  /// Flushes all pending writes and releases file handles.
  ///
  /// After [close], the engine must be [open]ed again before reuse.
  Future<void> close();

  // ── CRUD ─────────────────────────────────────────────────────────────────

  /// Reads the raw encoded bytes for [key].
  ///
  /// Returns `null` if the key does not exist.
  Future<Uint8List?> read(String key);

  /// Writes [bytes] under [key], overwriting any previous value.
  Future<void> write(String key, Uint8List bytes);

  /// Writes multiple [entries] atomically (best-effort).
  ///
  /// Implementations should batch the writes into as few I/O operations
  /// as possible.
  Future<void> writeBatch(Map<String, Uint8List> entries);

  /// Deletes the entry for [key].
  ///
  /// Returns `true` if the key existed and was deleted.
  Future<bool> delete(String key);

  /// Deletes all entries for the keys in [keys].
  Future<void> deleteBatch(List<String> keys);

  /// Returns `true` if [key] has an entry in this storage backend.
  Future<bool> containsKey(String key);

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Returns the set of all keys stored in this backend.
  Future<Set<String>> getAllKeys();

  /// Returns the number of entries stored.
  Future<int> count();

  /// Returns the approximate total size in bytes used by this backend.
  Future<int> sizeInBytes();

  // ── Maintenance ───────────────────────────────────────────────────────────

  /// Removes all entries from this storage backend.
  Future<void> clear();

  /// Compacts the storage file, reclaiming space from deleted/overwritten entries.
  ///
  /// Returns the number of bytes freed.
  Future<int> compact();

  /// Whether the storage backend is currently open and usable.
  bool get isOpen;
}
