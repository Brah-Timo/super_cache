import 'dart:collection';
import 'package:super_cache/src/eviction/eviction_policy.dart';

/// Least Recently Used eviction policy.
///
/// Maintains a doubly-linked hash map ([LinkedHashMap]) ordered by access time.
/// The entry at the *front* of the map is the least recently used; it is
/// evicted first when capacity is exceeded.
///
/// All operations are **O(1)** amortized:
/// - [onInsert]: O(1) — add to tail
/// - [onAccess]: O(1) — move to tail
/// - [selectForEviction]: O(1) — remove from head
///
/// LRU works best when your workload exhibits **temporal locality** —
/// recently accessed data is likely to be accessed again soon.
/// For mixed access patterns consider [ArcPolicy].
final class LruPolicy implements EvictionPolicy {
  /// Creates an [LruPolicy].
  ///
  /// [maxSize] is informational (used for [debugInfo]) — capacity enforcement
  /// is done by [L1MemoryCache], not by the policy itself.
  LruPolicy({this.maxSize = 1000});

  /// The declared capacity. Not enforced here.
  final int maxSize;

  /// Ordered map: key → access order (LRU at front, MRU at back).
  ///
  /// [LinkedHashMap] with [accessOrder] = false is insertion-ordered,
  /// but we simulate access-ordering by removing+reinserting on access.
  final _order = <String, int>{};

  int _counter = 0;

  // ── EvictionPolicy interface ────────────────────────────────────────────

  @override
  void onInsert(String key) {
    _order[key] = _counter++;
  }

  @override
  void onAccess(String key) {
    if (_order.containsKey(key)) {
      // Move to back (most recently used)
      _order.remove(key);
      _order[key] = _counter++;
    }
  }

  @override
  void onUpdate(String key) => onAccess(key);

  @override
  void onRemove(String key) => _order.remove(key);

  @override
  String? selectForEviction(List<String> availableKeys) {
    if (_order.isEmpty) return null;
    // The first key in LinkedHashMap is the least recently inserted/accessed.
    final victim = _order.keys.first;
    _order.remove(victim);
    return victim;
  }

  @override
  void clear() {
    _order.clear();
    _counter = 0;
  }

  @override
  Map<String, dynamic> get debugInfo => {
        'policy': 'LRU',
        'trackedKeys': _order.length,
        'maxSize': maxSize,
      };

  @override
  String toString() =>
      'LruPolicy(tracked: ${_order.length} / max: $maxSize)';
}
