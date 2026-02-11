import 'dart:developer' as developer;

/// Professional logging utility for notifications
class NotificationLogger {
  static const String _tag = 'NotificationService';

  static void info(String message, [Map<String, dynamic>? data]) {
    developer.log(
      message,
      name: _tag,
      level: 800, // INFO level
      error: data != null ? data.toString() : null,
    );
  }

  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _tag,
      level: 900, // WARNING level
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _tag,
      level: 1000, // ERROR level
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void debug(String message, [Map<String, dynamic>? data]) {
    developer.log(
      message,
      name: _tag,
      level: 700, // DEBUG level
      error: data != null ? data.toString() : null,
    );
  }
}

