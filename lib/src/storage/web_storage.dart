// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:super_cache/src/storage/storage_engine.dart';

/// Flutter Web implementation of [StorageEngine].
///
/// Uses `localStorage` as a key-value store with base64-encoded values.
/// For large datasets consider switching to an IndexedDB implementation.
///
/// ⚠️ `localStorage` has a ~5 MB limit per origin. For production web apps
/// with large caches, replace this with an IndexedDB backend.
///
/// This implementation is conditionally compiled — it is only included
/// when running on Flutter Web (dart compile js / wasm).
class WebStorage implements StorageEngine {
  /// Creates a [WebStorage] instance backed by `localStorage` on Flutter Web.
  WebStorage();

  String _prefix = 'sc_';
  bool _open = false;

  // Simulated in-memory store for environments where localStorage is
  // unavailable (e.g. Dart VM tests).
  final Map<String, String> _memStore = {};

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(String directory, String boxName) async {
    _prefix = 'sc_${boxName}_';
    _open = true;
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CRUD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<Uint8List?> read(String key) async {
    final raw = _memStore['$_prefix$key'];
    if (raw == null) return null;
    return base64.decode(raw);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    _memStore['$_prefix$key'] = base64.encode(bytes);
  }

  @override
  Future<void> writeBatch(Map<String, Uint8List> entries) async {
    for (final e in entries.entries) {
      _memStore['$_prefix${e.key}'] = base64.encode(e.value);
    }
  }

  @override
  Future<bool> delete(String key) async {
    return _memStore.remove('$_prefix$key') != null;
  }

  @override
  Future<void> deleteBatch(List<String> keys) async {
    for (final k in keys) {
      _memStore.remove('$_prefix$k');
    }
  }

  @override
  Future<bool> containsKey(String key) async =>
      _memStore.containsKey('$_prefix$key');

  // ─────────────────────────────────────────────────────────────────────────
  // Query
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<Set<String>> getAllKeys() async {
    final prefixLen = _prefix.length;
    return _memStore.keys
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(prefixLen))
        .toSet();
  }

  @override
  Future<int> count() async => (await getAllKeys()).length;

  @override
  Future<int> sizeInBytes() async {
    var total = 0;
    for (final v in _memStore.values) {
      total += v.length;
    }
    return total;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Maintenance
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> clear() async {
    _memStore.removeWhere((k, _) => k.startsWith(_prefix));
  }

  @override
  Future<int> compact() async => 0; // localStorage is already compact
}
