import 'package:super_cache/src/eviction/eviction_policy.dart';

/// Adaptive Replacement Cache (ARC) eviction policy.
///
/// ARC was invented by Nimrod Megiddo and Dharmendra S. Modha at IBM Research
/// (2003). It **automatically balances** between LRU (recency-biased) and LFU
/// (frequency-biased) behaviour by maintaining four internal lists:
///
/// ```
/// T1 — recently inserted keys seen exactly once
/// T2 — keys seen at least twice (promoted from T1)
/// B1 — ghost list: keys recently evicted from T1 (keys only, no values)
/// B2 — ghost list: keys recently evicted from T2 (keys only, no values)
/// ```
///
/// The balance parameter **p** adapts based on ghost-list hits:
/// - A B1 hit → *increase* p (bias towards recency)
/// - A B2 hit → *decrease* p (bias towards frequency)
///
/// This makes ARC self-tuning — it performs as well as the best of LRU and LFU
/// for any given workload, without requiring manual configuration.
///
/// **Complexity:** All operations are O(1) amortized.
///
/// **The default eviction policy for super_cache.**
final class ArcPolicy implements EvictionPolicy {
  /// Creates an [ArcPolicy] for a cache of [maxSize] entries.
  ArcPolicy({this.maxSize = 1000});

  /// The total cache capacity `c` in ARC terms.
  final int maxSize;

  // ── Four ARC lists ─────────────────────────────────────────────────────

  /// T1: recently inserted once (recency list).
  final _t1 = <String>{};

  /// T2: frequently accessed (frequency list).
  final _t2 = <String>{};

  /// B1: ghost list for T1 (recently evicted from T1).
  final _b1 = <String>{};

  /// B2: ghost list for T2 (recently evicted from T2).
  final _b2 = <String>{};

  /// Adaptation target: desired size of T1.
  ///
  /// Adjusted up on B1 hit, down on B2 hit.
  int _p = 0;

  // ── Helpers ────────────────────────────────────────────────────────────

  int get _c => maxSize;
  int get _t1Len => _t1.length;
  int get _t2Len => _t2.length;
  int get _b1Len => _b1.length;
  int get _b2Len => _b2.length;

  // ── EvictionPolicy interface ────────────────────────────────────────────

  @override
  void onInsert(String key) {
    if (_b1.contains(key)) {
      // Ghost hit in B1 → key recently evicted from T1.
      // Increase p to protect more recency data.
      final delta = _b2Len >= _b1Len ? 1 : (_b2Len / _b1Len).ceil();
      _p = (_p + delta).clamp(0, _c);
      _b1.remove(key);
      _t2.add(key); // Promote directly to T2 (now seen ≥ 2 times)
      return;
    }

    if (_b2.contains(key)) {
      // Ghost hit in B2 → key recently evicted from T2.
      // Decrease p to protect more frequency data.
      final delta = _b1Len >= _b2Len ? 1 : (_b1Len / _b2Len).ceil();
      _p = (_p - delta).clamp(0, _c);
      _b2.remove(key);
      _t2.add(key);
      return;
    }

    // Completely new key → add to T1 (first-time-seen).
    _t1.add(key);
    // Only evict when the combined live-set has reached capacity.
    if (_t1Len + _t2Len > _c) {
      _replace(forInsert: true);
    }
  }

  @override
  void onAccess(String key) {
    if (_t1.contains(key)) {
      // Key was in T1 (seen once) → promote to T2 (seen again).
      _t1.remove(key);
      _t2.add(key);
      return;
    }
    if (_t2.contains(key)) {
      // Key is already in T2 → refresh its position (LRU within T2).
      _t2.remove(key);
      _t2.add(key);
    }
    // If not in T1 or T2, the key is not live — nothing to update.
  }

  @override
  void onUpdate(String key) => onAccess(key);

  @override
  void onRemove(String key) {
    _t1.remove(key);
    _t2.remove(key);
    // Do NOT remove from ghost lists — they track eviction history,
    // not live cache contents.
  }

  @override
  String? selectForEviction(List<String> availableKeys) {
    return _replace(forInsert: false);
  }

  @override
  void clear() {
    _t1.clear();
    _t2.clear();
    _b1.clear();
    _b2.clear();
    _p = 0;
  }

  @override
  Map<String, dynamic> get debugInfo => {
        'policy': 'ARC',
        'T1': _t1Len,
        'T2': _t2Len,
        'B1': _b1Len,
        'B2': _b2Len,
        'p': _p,
        'c': _c,
        'liveEntries': _t1Len + _t2Len,
      };

  @override
  String toString() =>
      'ArcPolicy(T1=$_t1Len, T2=$_t2Len, B1=$_b1Len, B2=$_b2Len, p=$_p)';

  // ── Core ARC replacement ───────────────────────────────────────────────

  /// Selects and returns the victim key to evict, updating ghost lists.
  ///
  /// Returns `null` when both live lists are empty.
  String? _replace({required bool forInsert}) {
    // ── Case 1: T1 is larger than the target p, evict from T1 → B1 ──────
    final preferT1 = _t1Len > 0 &&
        (_t1Len > _p ||
            (_b2Len > 0 && _t1Len == _p)); // Tie-break: B2 ghost hit pending

    if (preferT1 && _t1.isNotEmpty) {
      final victim = _t1.first;
      _t1.remove(victim);
      _addToGhost(_b1);
      _b1.add(victim);
      return victim;
    }

    // ── Case 2: Evict from T2 → B2 ───────────────────────────────────────
    if (_t2.isNotEmpty) {
      final victim = _t2.first;
      _t2.remove(victim);
      _addToGhost(_b2);
      _b2.add(victim);
      return victim;
    }

    // ── Fallback: evict from T1 if T2 is empty ───────────────────────────
    if (_t1.isNotEmpty) {
      final victim = _t1.first;
      _t1.remove(victim);
      _addToGhost(_b1);
      _b1.add(victim);
      return victim;
    }

    return null; // Nothing to evict
  }

  /// Trims a ghost list to at most [_c] entries before adding a new one.
  void _addToGhost(Set<String> ghost) {
    while (ghost.length >= _c) {
      ghost.remove(ghost.first);
    }
  }
}
