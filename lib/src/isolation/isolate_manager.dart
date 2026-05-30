import 'package:super_cache/src/isolation/isolate_channel.dart';

/// High-level facade over [IsolateChannel] that manages the lifecycle of the
/// super_cache worker isolate.
///
/// When [CacheConfig.enableIsolateSupport] is `true`, the [CacheOrchestrator]
/// routes all L2 operations through this manager instead of calling
/// [L2DiskCache] directly, ensuring that disk I/O never blocks the UI thread.
final class IsolateManager {
  /// Creates an [IsolateManager].
  IsolateManager();

  bool _initialized = false;

  /// Starts the worker isolate with the given [configMap].
  Future<void> initialize(Map<String, dynamic> configMap) async {
    if (_initialized) return;
    await IsolateChannel.start(configMap);
    _initialized = true;
  }

  /// Whether the manager has been initialized.
  bool get isInitialized => _initialized;

  /// Disposes the worker isolate.
  Future<void> dispose() async {
    if (!_initialized) return;
    await IsolateChannel.dispose();
    _initialized = false;
  }
}
