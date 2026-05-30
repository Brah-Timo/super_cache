import 'dart:async';

/// Manages periodic TTL (Time-To-Live) cleanup sweeps for the cache.
///
/// Runs a [Timer] at [interval] that fires the [onCleanup] callback.
/// The callback receives the current UTC time and should return the number
/// of expired entries that were removed.
///
/// The manager is deliberately decoupled from the cache internals — it only
/// fires a callback; it never directly accesses the cache map.
///
/// **Usage:**
/// ```dart
/// final ttlManager = TtlManager(
///   interval: const Duration(minutes: 5),
///   onCleanup: () async => await l1.clearExpired() + await l2.clearExpired(),
/// );
/// ttlManager.start();
/// // ...
/// await ttlManager.dispose();
/// ```
final class TtlManager {
  /// Creates a [TtlManager].
  ///
  /// [interval] — how often the cleanup sweep runs.
  /// [onCleanup] — async callback that performs the sweep; returns the count
  ///   of entries removed.
  TtlManager({
    required this.interval,
    required this.onCleanup,
  });

  /// How frequently the cleanup sweep fires.
  final Duration interval;

  /// The sweep callback.  Must return the number of entries removed.
  final Future<int> Function() onCleanup;

  Timer? _timer;
  bool _running = false;

  // ── Statistics ────────────────────────────────────────────────────────────

  int _sweepCount = 0;
  int _totalExpiredRemoved = 0;
  DateTime? _lastSweepAt;

  /// Total number of cleanup sweeps performed.
  int get sweepCount => _sweepCount;

  /// Total number of entries removed by all sweeps so far.
  int get totalExpiredRemoved => _totalExpiredRemoved;

  /// UTC timestamp of the last completed sweep, or `null` if none yet.
  DateTime? get lastSweepAt => _lastSweepAt;

  /// Whether the manager is currently running.
  bool get isRunning => _running;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts the periodic cleanup timer.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => _runSweep());
  }

  /// Runs one sweep immediately (regardless of the timer schedule).
  ///
  /// Returns the number of expired entries removed.
  Future<int> runNow() => _runSweep();

  /// Cancels the cleanup timer and releases resources.
  ///
  /// Does NOT run a final sweep — call [runNow] first if you need that.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<int> _runSweep() async {
    try {
      final removed = await onCleanup();
      _sweepCount++;
      _totalExpiredRemoved += removed;
      _lastSweepAt = DateTime.now().toUtc();
      return removed;
    } catch (_) {
      // Never crash the app due to a TTL sweep error.
      return 0;
    }
  }

  @override
  String toString() => 'TtlManager('
      'interval: $interval, '
      'sweeps: $_sweepCount, '
      'totalRemoved: $_totalExpiredRemoved'
      ')';
}
