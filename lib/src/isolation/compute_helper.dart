import 'dart:async';
import 'dart:isolate';

/// Lightweight `compute()`-style helper for running pure functions in a
/// temporary isolate without depending on `package:flutter/foundation.dart`.
///
/// This makes the package usable in pure Dart environments (servers, CLIs)
/// as well as Flutter.
///
/// **Usage:**
/// ```dart
/// final encoded = await SuperCompute.run(
///   _encodeInIsolate,
///   {'key': key, 'value': value},
/// );
/// ```
abstract final class SuperCompute {
  SuperCompute._();

  /// Runs [function] with [message] in a new isolate and returns the result.
  ///
  /// Equivalent to Flutter's `compute()` but dependency-free.
  ///
  /// [function] must be a top-level function or a static method — closures
  /// are not supported across isolate boundaries.
  static Future<R> run<Q, R>(
    FutureOr<R> Function(Q message) function,
    Q message,
  ) async {
    final completer = Completer<R>();
    final receivePort = ReceivePort();

    receivePort.listen((dynamic result) {
      receivePort.close();
      if (result is _ComputeError) {
        completer.completeError(
          Exception(result.message),
          StackTrace.fromString(result.stackTrace),
        );
      } else {
        completer.complete(result as R);
      }
    });

    await Isolate.spawn(
      _isolateEntry<Q, R>,
      _ComputePayload<Q, R>(
        function: function,
        message: message,
        sendPort: receivePort.sendPort,
      ),
    );

    return completer.future;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

final class _ComputePayload<Q, R> {
  const _ComputePayload({
    required this.function,
    required this.message,
    required this.sendPort,
  });

  final FutureOr<R> Function(Q) function;
  final Q message;
  final SendPort sendPort;
}

final class _ComputeError {
  const _ComputeError({required this.message, required this.stackTrace});
  final String message;
  final String stackTrace;
}

Future<void> _isolateEntry<Q, R>(_ComputePayload<Q, R> payload) async {
  try {
    final result = await payload.function(payload.message);
    payload.sendPort.send(result);
  } catch (e, st) {
    payload.sendPort.send(
      _ComputeError(message: e.toString(), stackTrace: st.toString()),
    );
  }
}
