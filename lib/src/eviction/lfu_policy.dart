import 'dart:collection';
import 'package:super_cache/src/eviction/eviction_policy.dart';

/// Least Frequently Used eviction policy.
///
/// Tracks the access frequency (hit count) of every key. When eviction is
/// needed, it removes the key with the **lowest frequency**. Among keys with
/// equal frequency, it removes the one that was *least recently used* (LRU
/// tie-breaking).
///
/// Implementation: O(1) per operation using the classic doubly-linked list
/// + frequency bucket technique (Ketan Shah, 2010).
///
/// LFU works best when your workload has a **heavy-hitter** pattern — a small
/// set of hot keys are accessed far more than the rest.
final class LfuPolicy implements EvictionPolicy {
  /// Creates an [LfuPolicy].
  LfuPolicy({this.maxSize = 1000});

  /// The declared capacity.
  final int maxSize;

  // Map: key → frequency
  final _frequencies = <String, int>{};

  // Map: frequency → LRU-ordered set of keys at that frequency
  final _freqToKeys = <int, LinkedHashSet<String>>{};

  // The current minimum frequency (used for O(1) eviction)
  int _minFreq = 0;

  // ── EvictionPolicy interface ────────────────────────────────────────────

  @override
  void onInsert(String key) {
    // New keys start at frequency 1
    _frequencies[key] = 1;
    _freqToKeys.putIfAbsent(1, LinkedHashSet.new).add(key);
    // If this is the only key, or first insertion, min freq is 1
    if (_minFreq == 0 || _minFreq > 1) _minFreq = 1;
  }

  @override
  void onAccess(String key) {
    final freq = _frequencies[key];
    if (freq == null) return; // Key not tracked (was evicted already)

    // Increment frequency
    final newFreq = freq + 1;
    _frequencies[key] = newFreq;

    // Remove from current bucket
    final bucket = _freqToKeys[freq]!;
    bucket.remove(key);
    if (bucket.isEmpty) {
      _freqToKeys.remove(freq);
      // If min-freq bucket is now empty, the min freq must have increased
      if (_minFreq == freq) _minFreq = newFreq;
    }

    // Add to new bucket
    _freqToKeys.putIfAbsent(newFreq, LinkedHashSet.new).add(key);
  }

  @override
  void onUpdate(String key) => onAccess(key);

  @override
  void onRemove(String key) {
    final freq = _frequencies.remove(key);
    if (freq == null) return;
    final bucket = _freqToKeys[freq];
    if (bucket == null) return;
    bucket.remove(key);
    if (bucket.isEmpty) _freqToKeys.remove(freq);
  }

  @override
  String? selectForEviction(List<String> availableKeys) {
    if (_freqToKeys.isEmpty) return null;

    // Find the actual minimum frequency (in case _minFreq is stale)
    final minFreqBucket = _freqToKeys[_minFreq];
    if (minFreqBucket != null && minFreqBucket.isNotEmpty) {
      final victim = minFreqBucket.first;
      minFreqBucket.remove(victim);
      if (minFreqBucket.isEmpty) _freqToKeys.remove(_minFreq);
      _frequencies.remove(victim);
      return victim;
    }

    // Fallback: scan for actual minimum frequency
    var minF = double.maxFinite.toInt();
    for (final f in _freqToKeys.keys) {
      if (f < minF) minF = f;
    }
    _minFreq = minF;
    final bucket = _freqToKeys[_minFreq]!;
    final victim = bucket.first;
    bucket.remove(victim);
    if (bucket.isEmpty) _freqToKeys.remove(_minFreq);
    _frequencies.remove(victim);
    return victim;
  }

  @override
  void clear() {
    _frequencies.clear();
    _freqToKeys.clear();
    _minFreq = 0;
  }

  @override
  Map<String, dynamic> get debugInfo => {
        'policy': 'LFU',
        'trackedKeys': _frequencies.length,
        'minFrequency': _minFreq,
        'frequencyBuckets': _freqToKeys.length,
        'maxSize': maxSize,
      };

  @override
  String toString() =>
      'LfuPolicy(tracked: ${_frequencies.length}, minFreq: $_minFreq)';
}
