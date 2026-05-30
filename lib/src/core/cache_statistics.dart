import 'dart:math' as math;

/// Snapshot of live performance metrics for a [SuperCache] instance.
///
/// Obtain the current snapshot via [SuperCache.statistics].
///
/// All counters are reset when [reset] is called or when the cache is cleared.
final class CacheStatistics {
  /// Creates a fresh [CacheStatistics] with all counters at zero.
  CacheStatistics() : _startTime = DateTime.now();

  DateTime _startTime;

  // ── Read counters ─────────────────────────────────────────────────────────

  int _l1Hits = 0;
  int _l2Hits = 0;
  int _misses = 0;

  // ── Write / Delete counters ───────────────────────────────────────────────

  int _writes = 0;
  int _deletes = 0;
  int _evictions = 0;
  int _ttlExpirations = 0;

  // ── Timing accumulators (microseconds) ───────────────────────────────────

  int _totalReadUs = 0;
  int _totalWriteUs = 0;
  int _readSamples = 0;
  int _writeSamples = 0;

  // ── Size tracking ─────────────────────────────────────────────────────────

  int _currentMemoryBytes = 0;
  int _currentDiskBytes = 0;
  int _totalBytesWritten = 0;
  int _totalBytesRead = 0;

  // ── Compaction ────────────────────────────────────────────────────────────

  int _compactionRuns = 0;
  int _bytesReclaimedByCompaction = 0;

  // ─────────────────────────────────────────────────────────────────────────
  // Public read-only getters
  // ─────────────────────────────────────────────────────────────────────────

  /// Number of reads satisfied from the in-memory L1 cache.
  int get l1Hits => _l1Hits;

  /// Number of reads satisfied from the on-disk L2 cache (promoted to L1).
  int get l2Hits => _l2Hits;

  /// Number of cache misses (key not found in L1 or L2).
  int get misses => _misses;

  /// Total number of successful reads (L1 + L2).
  int get totalHits => _l1Hits + _l2Hits;

  /// Total number of read requests (hits + misses).
  int get totalRequests => totalHits + _misses;

  /// Number of [put] operations.
  int get writes => _writes;

  /// Number of explicit [remove] operations.
  int get deletes => _deletes;

  /// Number of entries evicted due to capacity pressure.
  int get evictions => _evictions;

  /// Number of entries removed because their TTL elapsed.
  int get ttlExpirations => _ttlExpirations;

  /// Fraction of read requests that were satisfied by the cache (0.0 – 1.0).
  double get hitRate {
    if (totalRequests == 0) return 0.0;
    return totalHits / totalRequests;
  }

  /// Fraction of reads that were L1 hits.
  double get l1HitRate {
    if (totalRequests == 0) return 0.0;
    return _l1Hits / totalRequests;
  }

  /// Fraction of reads that were L2 hits (promoted from disk).
  double get l2HitRate {
    if (totalRequests == 0) return 0.0;
    return _l2Hits / totalRequests;
  }

  /// Fraction of reads that were cache misses.
  double get missRate => 1.0 - hitRate;

  /// Average latency per read, in microseconds.
  ///
  /// Returns 0 when no reads have been timed yet.
  double get avgReadLatencyUs {
    if (_readSamples == 0) return 0.0;
    return _totalReadUs / _readSamples;
  }

  /// Average latency per write, in microseconds.
  double get avgWriteLatencyUs {
    if (_writeSamples == 0) return 0.0;
    return _totalWriteUs / _writeSamples;
  }

  /// Current L1 memory usage in bytes.
  int get currentMemoryBytes => _currentMemoryBytes;

  /// Current L2 disk usage in bytes.
  int get currentDiskBytes => _currentDiskBytes;

  /// Total bytes written to the cache since last [reset].
  int get totalBytesWritten => _totalBytesWritten;

  /// Total bytes read from the cache since last [reset].
  int get totalBytesRead => _totalBytesRead;

  /// Number of compaction runs completed.
  int get compactionRuns => _compactionRuns;

  /// Total bytes reclaimed by compaction runs.
  int get bytesReclaimedByCompaction => _bytesReclaimedByCompaction;

  /// Time elapsed since the cache was initialized or last reset.
  Duration get uptime => DateTime.now().difference(_startTime);

  /// Approximate read throughput in requests per second.
  double get requestsPerSecond {
    final secs = uptime.inMicroseconds / 1e6;
    if (secs <= 0) return 0.0;
    return totalRequests / secs;
  }

  /// Throughput in bytes read per second.
  double get readThroughputBytesPerSecond {
    final secs = uptime.inMicroseconds / 1e6;
    if (secs <= 0) return 0.0;
    return _totalBytesRead / secs;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal recording methods (called by cache internals only)
  // ─────────────────────────────────────────────────────────────────────────

  /// @nodoc
  void recordL1Hit({int bytes = 0, int latencyUs = 0}) {
    _l1Hits++;
    _totalBytesRead += bytes;
    if (latencyUs > 0) {
      _totalReadUs += latencyUs;
      _readSamples++;
    }
  }

  /// @nodoc
  void recordL2Hit({int bytes = 0, int latencyUs = 0}) {
    _l2Hits++;
    _totalBytesRead += bytes;
    if (latencyUs > 0) {
      _totalReadUs += latencyUs;
      _readSamples++;
    }
  }

  /// @nodoc
  void recordMiss({int latencyUs = 0}) {
    _misses++;
    if (latencyUs > 0) {
      _totalReadUs += latencyUs;
      _readSamples++;
    }
  }

  /// @nodoc
  void recordWrite({int bytes = 0, int latencyUs = 0}) {
    _writes++;
    _totalBytesWritten += bytes;
    if (latencyUs > 0) {
      _totalWriteUs += latencyUs;
      _writeSamples++;
    }
  }

  /// @nodoc
  void recordDelete() => _deletes++;

  /// @nodoc
  void recordEviction() => _evictions++;

  /// @nodoc
  void recordTtlExpiration() => _ttlExpirations++;

  /// @nodoc
  void updateMemoryUsage(int bytes) => _currentMemoryBytes = math.max(0, bytes);

  /// @nodoc
  void updateDiskUsage(int bytes) => _currentDiskBytes = math.max(0, bytes);

  /// @nodoc
  void recordCompaction({int bytesReclaimed = 0}) {
    _compactionRuns++;
    _bytesReclaimedByCompaction += bytesReclaimed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Snapshot
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns an immutable point-in-time snapshot of current statistics.
  CacheStatisticsSnapshot snapshot() => CacheStatisticsSnapshot(
        l1Hits: _l1Hits,
        l2Hits: _l2Hits,
        misses: _misses,
        writes: _writes,
        deletes: _deletes,
        evictions: _evictions,
        ttlExpirations: _ttlExpirations,
        hitRate: hitRate,
        l1HitRate: l1HitRate,
        avgReadLatencyUs: avgReadLatencyUs,
        avgWriteLatencyUs: avgWriteLatencyUs,
        currentMemoryBytes: _currentMemoryBytes,
        currentDiskBytes: _currentDiskBytes,
        totalBytesWritten: _totalBytesWritten,
        totalBytesRead: _totalBytesRead,
        compactionRuns: _compactionRuns,
        bytesReclaimedByCompaction: _bytesReclaimedByCompaction,
        uptime: uptime,
        requestsPerSecond: requestsPerSecond,
      );

  /// Resets all counters and restarts the uptime clock.
  void reset() {
    _l1Hits = _l2Hits = _misses = 0;
    _writes = _deletes = _evictions = _ttlExpirations = 0;
    _totalReadUs = _totalWriteUs = _readSamples = _writeSamples = 0;
    _currentMemoryBytes = _currentDiskBytes = 0;
    _totalBytesWritten = _totalBytesRead = 0;
    _compactionRuns = _bytesReclaimedByCompaction = 0;
    _startTime = DateTime.now();
  }

  @override
  String toString() {
    final hr = (hitRate * 100).toStringAsFixed(1);
    final l1r = (l1HitRate * 100).toStringAsFixed(1);
    final l2r = (l2HitRate * 100).toStringAsFixed(1);
    final memMB = (_currentMemoryBytes / 1048576).toStringAsFixed(2);
    final diskMB = (_currentDiskBytes / 1048576).toStringAsFixed(2);
    final rpsStr = requestsPerSecond.toStringAsFixed(0);

    return '''
╔══════════════════════════════════════════════╗
║          super_cache — Live Statistics        ║
╠══════════════════════════════════════════════╣
║  Overall Hit Rate :  $hr%                
║  L1 (Memory) Hits :  $_l1Hits ($l1r%)         
║  L2 (Disk) Hits   :  $_l2Hits ($l2r%)         
║  Misses           :  $_misses                  
║  Writes           :  $_writes                  
║  Deletes          :  $_deletes                 
║  Evictions        :  $_evictions               
║  TTL Expirations  :  $_ttlExpirations          
║  Avg Read Latency :  ${avgReadLatencyUs.toStringAsFixed(1)}µs           
║  Avg Write Latency:  ${avgWriteLatencyUs.toStringAsFixed(1)}µs           
║  Memory Usage     :  ${memMB}MB               
║  Disk Usage       :  ${diskMB}MB               
║  Throughput       :  $rpsStr req/s           
║  Uptime           :  $uptime     
╚══════════════════════════════════════════════╝''';
  }
}

/// An immutable snapshot of [CacheStatistics] at a specific point in time.
final class CacheStatisticsSnapshot {
  /// Creates a statistics snapshot. All fields are required.
  const CacheStatisticsSnapshot({
    required this.l1Hits,
    required this.l2Hits,
    required this.misses,
    required this.writes,
    required this.deletes,
    required this.evictions,
    required this.ttlExpirations,
    required this.hitRate,
    required this.l1HitRate,
    required this.avgReadLatencyUs,
    required this.avgWriteLatencyUs,
    required this.currentMemoryBytes,
    required this.currentDiskBytes,
    required this.totalBytesWritten,
    required this.totalBytesRead,
    required this.compactionRuns,
    required this.bytesReclaimedByCompaction,
    required this.uptime,
    required this.requestsPerSecond,
  });

  /// @nodoc
  final int l1Hits;

  /// @nodoc
  final int l2Hits;

  /// @nodoc
  final int misses;

  /// @nodoc
  final int writes;

  /// @nodoc
  final int deletes;

  /// @nodoc
  final int evictions;

  /// @nodoc
  final int ttlExpirations;

  /// @nodoc
  final double hitRate;

  /// @nodoc
  final double l1HitRate;

  /// @nodoc
  final double avgReadLatencyUs;

  /// @nodoc
  final double avgWriteLatencyUs;

  /// @nodoc
  final int currentMemoryBytes;

  /// @nodoc
  final int currentDiskBytes;

  /// @nodoc
  final int totalBytesWritten;

  /// @nodoc
  final int totalBytesRead;

  /// @nodoc
  final int compactionRuns;

  /// @nodoc
  final int bytesReclaimedByCompaction;

  /// @nodoc
  final Duration uptime;

  /// @nodoc
  final double requestsPerSecond;

  /// Converts this snapshot to a plain [Map] for logging or analytics.
  Map<String, dynamic> toMap() => {
        'l1Hits': l1Hits,
        'l2Hits': l2Hits,
        'misses': misses,
        'writes': writes,
        'deletes': deletes,
        'evictions': evictions,
        'ttlExpirations': ttlExpirations,
        'hitRate': hitRate,
        'l1HitRate': l1HitRate,
        'avgReadLatencyUs': avgReadLatencyUs,
        'avgWriteLatencyUs': avgWriteLatencyUs,
        'currentMemoryBytes': currentMemoryBytes,
        'currentDiskBytes': currentDiskBytes,
        'totalBytesWritten': totalBytesWritten,
        'totalBytesRead': totalBytesRead,
        'compactionRuns': compactionRuns,
        'bytesReclaimedByCompaction': bytesReclaimedByCompaction,
        'uptimeMs': uptime.inMilliseconds,
        'requestsPerSecond': requestsPerSecond,
      };
}
