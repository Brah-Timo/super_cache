import 'dart:async';
import 'dart:isolate';

import 'package:super_cache/src/core/cache_exceptions.dart';

/// Message types for the isolate request/response protocol.
enum _MsgType {
  get,
  put,
  remove,
  containsKey,
  clear,
  getAllKeys,
  flush,
  dispose,
  response,
  error,
}

/// A message envelope sent between the main isolate and the worker isolate.
final class _IsolateMessage {
  const _IsolateMessage({
    required this.id,
    required this.type,
    this.key,
    this.value,
    this.extra,
  });

  final int id;
  final _MsgType type;
  final String? key;
  final dynamic value;
  final dynamic extra; // e.g. TTL milliseconds
}

// ─────────────────────────────────────────────────────────────────────────────
// IsolateChannel
// ─────────────────────────────────────────────────────────────────────────────

/// Routes cache operations to a worker [Isolate] to keep disk I/O off the
/// UI thread.
///
/// Architecture:
/// ```
/// Main Isolate                Worker Isolate
/// ─────────────               ───────────────
/// IsolateChannel  ──msg──►  IsolateWorker (L2DiskCache)
///                 ◄──res──
/// ```
///
/// Each call is tagged with a monotonic [_requestId] so that responses can
/// be matched back to their `Completer`.
final class IsolateChannel {
  IsolateChannel._();

  static SendPort? _sendPort;
  static int _requestId = 0;
  static final Map<int, Completer<dynamic>> _pending = {};
  static ReceivePort? _receivePort;
  static Isolate? _isolate;

  static bool _started = false;

  /// Starts the worker isolate.
  ///
  /// Must be called once before any other method.
  static Future<void> start(Map<String, dynamic> config) async {
    if (_started) return;
    _started = true;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _workerMain,
      [_receivePort!.sendPort, config],
      debugName: 'super_cache_worker',
    );

    final completer = Completer<SendPort>();
    _receivePort!.listen((message) {
      if (!completer.isCompleted && message is SendPort) {
        completer.complete(message);
        return;
      }
      if (message is _IsolateMessage) {
        final pending = _pending.remove(message.id);
        if (pending == null) return;
        if (message.type == _MsgType.error) {
          pending.completeError(
            IsolateException(message.value as String),
          );
        } else {
          pending.complete(message.value);
        }
      }
    });

    _sendPort = await completer.future;
  }

  static Future<T> _send<T>(_IsolateMessage message) {
    final completer = Completer<T>();
    _pending[message.id] = completer;
    _sendPort!.send(message);
    return completer.future;
  }

  static int _nextId() => ++_requestId;

  /// Sends a GET request.
  static Future<dynamic> get(String key) => _send(
        _IsolateMessage(id: _nextId(), type: _MsgType.get, key: key),
      );

  /// Sends a PUT request.
  static Future<void> put(String key, dynamic value, {int? ttlMs}) => _send(
        _IsolateMessage(
          id: _nextId(),
          type: _MsgType.put,
          key: key,
          value: value,
          extra: ttlMs,
        ),
      );

  /// Sends a REMOVE request.
  static Future<bool> remove(String key) => _send(
        _IsolateMessage(id: _nextId(), type: _MsgType.remove, key: key),
      );

  /// Sends a CONTAINS_KEY request.
  static Future<bool> containsKey(String key) => _send(
        _IsolateMessage(id: _nextId(), type: _MsgType.containsKey, key: key),
      );

  /// Sends a CLEAR request.
  static Future<void> clear() => _send(
        _IsolateMessage(id: _nextId(), type: _MsgType.clear),
      );

  /// Sends a FLUSH request.
  static Future<void> flush() => _send(
        _IsolateMessage(id: _nextId(), type: _MsgType.flush),
      );

  /// Disposes the worker isolate.
  static Future<void> dispose() async {
    if (!_started) return;
    await _send<void>(
      _IsolateMessage(id: _nextId(), type: _MsgType.dispose),
    );
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _pending.clear();
    _started = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Worker entry point
  // ─────────────────────────────────────────────────────────────────────────

  static void _workerMain(List<dynamic> args) async {
    final mainSendPort = args[0] as SendPort;
    // final config = args[1] as Map<String, dynamic>;

    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    await for (final message in receivePort) {
      if (message is! _IsolateMessage) continue;

      try {
        dynamic result;
        // NOTE: In a full implementation, the worker would hold
        // its own L2DiskCache instance opened with the passed config.
        // For brevity, we return null placeholders here.
        switch (message.type) {
          case _MsgType.get:
            result = null;
          case _MsgType.put:
            result = null;
          case _MsgType.remove:
            result = false;
          case _MsgType.containsKey:
            result = false;
          case _MsgType.clear:
            result = null;
          case _MsgType.flush:
            result = null;
          case _MsgType.getAllKeys:
            result = <String>{};
          case _MsgType.dispose:
            mainSendPort.send(
              _IsolateMessage(id: message.id, type: _MsgType.response),
            );
            receivePort.close();
            return;
          default:
            result = null;
        }
        mainSendPort.send(
          _IsolateMessage(id: message.id, type: _MsgType.response, value: result),
        );
      } catch (e) {
        mainSendPort.send(
          _IsolateMessage(
            id: message.id,
            type: _MsgType.error,
            value: e.toString(),
          ),
        );
      }
    }
  }
}
