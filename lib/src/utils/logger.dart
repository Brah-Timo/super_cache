import 'package:super_cache/src/core/cache_config.dart';

/// Internal diagnostic logger for super_cache.
///
/// All log output goes through [print] by default.  You can replace
/// [SuperCacheLogger.output] with your own sink (e.g. `dart:developer log`)
/// without modifying the package.
///
/// Logging is disabled entirely unless [CacheConfig.enableLogging] = `true`.
final class SuperCacheLogger {
  SuperCacheLogger._();

  static CacheLogLevel _minLevel = CacheLogLevel.warning;
  static bool _enabled = false;

  /// Custom log output function.  Defaults to `print`.
  static void Function(String message) output = print;

  // ── Configuration ─────────────────────────────────────────────────────────

  /// Configures the logger from [config].
  static void configure(CacheConfig config) {
    _enabled = config.enableLogging;
    _minLevel = config.logLevel;
  }

  // ── Log methods ───────────────────────────────────────────────────────────

  /// Logs a verbose message.
  static void verbose(String message, {String? tag}) =>
      _log(CacheLogLevel.verbose, message, tag: tag);

  /// Logs a debug message.
  static void debug(String message, {String? tag}) =>
      _log(CacheLogLevel.debug, message, tag: tag);

  /// Logs an informational message.
  static void info(String message, {String? tag}) =>
      _log(CacheLogLevel.info, message, tag: tag);

  /// Logs a warning.
  static void warning(String message, {String? tag, Object? error}) =>
      _log(CacheLogLevel.warning, message, tag: tag, error: error);

  /// Logs an error.
  static void error(String message, {String? tag, Object? error}) =>
      _log(CacheLogLevel.error, message, tag: tag, error: error);

  // ── Internal ──────────────────────────────────────────────────────────────

  static void _log(
    CacheLogLevel level,
    String message, {
    String? tag,
    Object? error,
  }) {
    if (!_enabled) return;
    if (level.index < _minLevel.index) return;

    final prefix = _levelPrefix(level);
    final tagStr = tag != null ? '[$tag] ' : '';
    final timestamp = DateTime.now().toIso8601String();
    final errorStr = error != null ? '\n  ↳ $error' : '';

    output('$timestamp $prefix [super_cache] $tagStr$message$errorStr');
  }

  static String _levelPrefix(CacheLogLevel level) {
    switch (level) {
      case CacheLogLevel.verbose:
        return '🔍 VERBOSE';
      case CacheLogLevel.debug:
        return '🐛 DEBUG  ';
      case CacheLogLevel.info:
        return 'ℹ️  INFO   ';
      case CacheLogLevel.warning:
        return '⚠️  WARN   ';
      case CacheLogLevel.error:
        return '❌ ERROR  ';
      case CacheLogLevel.none:
        return '';
    }
  }
}
