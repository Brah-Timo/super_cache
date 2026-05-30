import 'dart:async';

import 'package:super_cache/src/core/cache_config.dart';
import 'package:super_cache/src/engine/l2_disk_cache.dart';

/// Monitors disk fragmentation and triggers compaction when needed.
///
/// Compaction rewrites the L2 data file, skipping all tombstoned (deleted
/// or overwritten) entries.  This reclaims the disk space consumed by stale
/// data at the cost of a full file rewrite (O(n)).
///
/// **Fragmentation ratio:**
/// ```
/// ratio = waste_bytes / total_bytes
/// ```
/// where `waste_bytes = total_bytes - live_bytes`.
///
/// Compaction runs when `ratio >= [CacheConfig.compactionThreshold]` (default 30%).
final class CompactionManager {
  /// Creates a [CompactionManager] for the given [l2] cache.
  CompactionManager({
    required this.l2,
    required this.config,
    this.checkInterval = const Duration(minutes: 10),
  });

  /// The L2 disk cache to compact.
  final L2DiskCache l2;

  /// Cache configuration (reads [CacheConfig.compactionThreshold]).
  final CacheConfig config;

  /// How often the compaction check runs.
  final Duration checkInterval;

  Timer? _timer;
  bool _running = false;

  // ── Metrics ───────────────────────────────────────────────────────────────

  int _compactionRuns = 0;
  int _totalBytesReclaimed = 0;

  /// Number of compaction runs completed.
  int get compactionRuns => _compactionRuns;

  /// Total bytes freed by compaction.
  int get totalBytesReclaimed => _totalBytesReclaimed;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts the periodic compaction check timer.
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(checkInterval, (_) => checkAndCompact());
  }

  /// Stops the compaction timer.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Compaction
  // ─────────────────────────────────────────────────────────────────────────

  /// Checks the fragmentation ratio and runs compaction if needed.
  ///
  /// Returns the number of bytes freed (0 if compaction was not needed).
  Future<int> checkAndCompact() async {
    if (!config.autoCompact) return 0;

    final totalBytes = await l2.sizeInBytes();
    if (totalBytes == 0) return 0;

    final liveEntries = await l2.count();
    // Rough heuristic: each entry averages 256 bytes;
    // if total >> estimated_live * avg_entry_size → high fragmentation.
    // A more accurate implementation would expose live bytes from storage.
    final estimatedLiveBytes = liveEntries * 256;
    if (estimatedLiveBytes >= totalBytes) return 0; // Not fragmented

    final ratio = 1.0 - (estimatedLiveBytes / totalBytes);
    if (ratio < config.compactionThreshold) return 0;

    return runCompaction();
  }

  /// Runs compaction immediately, regardless of the fragmentation ratio.
  ///
  /// Returns the number of bytes freed.
  Future<int> runCompaction() async {
    final freed = await l2.compact();
    _compactionRuns++;
    _totalBytesReclaimed += freed;
    return freed;
  }

  @override
  String toString() => 'CompactionManager('
      'runs: $_compactionRuns, '
      'reclaimed: ${(_totalBytesReclaimed / 1024).toStringAsFixed(1)}KB'
      ')';
}
