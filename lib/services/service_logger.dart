import 'dart:developer' as dev;
import 'dart:io';

import '../utils/common.dart';

// Custom Logger Class
class AppLogger {
  final List<String> prefixes;

  AppLogger({required this.prefixes});

  /// ANSI color codes
  static const String _reset = '\x1B[0m';
  static const String _blue = '\x1B[34m';
  static const String _yellow = '\x1B[33m';
  static const String _red = '\x1B[31m';
  static const String _white = '\x1B[37m';

  static File? _logFile;
  static const int _maxLogSize = 1024 * 1024; // 1MB rotation limit
  static const String _privacyCleanupMarker = '.fife_log_redaction_v1';
  static final List<String> _logQueue = [];
  static bool _isWriting = false;

  static final RegExp _authorizationPattern = RegExp(
    r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _cookiePattern = RegExp(
    r'(__Secure-[A-Za-z0-9._-]+)=[^;\s]+',
    caseSensitive: false,
  );
  static final RegExp _emailPattern = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s)\]}>]+',
    caseSensitive: false,
  );
  static final RegExp _absolutePathPattern = RegExp(
    r'(?<![A-Za-z0-9])(?:[A-Za-z]:\\(?:[^\\\s]+\\)+[^\\\s]*|/(?:[^/\s]+/)+[^/\s]*)',
  );
  static final RegExp _hashPattern = RegExp(r'\b[A-Fa-f0-9]{32,}\b');
  static final RegExp _sensitiveAssignmentPattern = RegExp(
    r'''(["']?(?:authorization|token|access[_-]?token|refresh[_-]?token|session[_-]?cookie|cookie|app[_-]?key|secret[_-]?key|private[_-]?key|master[_-]?key|file[_-]?hash[_-]?key|key[_-]?cipher|cipher|nonce|otp|password)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^,\s}\]]+)''',
    caseSensitive: false,
  );

  static String sanitize(String value) {
    return value
        .replaceAllMapped(
          _authorizationPattern,
          (match) => '${match.group(1)} [REDACTED]',
        )
        .replaceAllMapped(
          _sensitiveAssignmentPattern,
          (match) => '${match.group(1)}[REDACTED]',
        )
        .replaceAllMapped(
          _cookiePattern,
          (match) => '${match.group(1)}=[REDACTED]',
        )
        .replaceAll(_emailPattern, '[REDACTED_EMAIL]')
        .replaceAll(_urlPattern, '[REDACTED_URL]')
        .replaceAll(_absolutePathPattern, '[REDACTED_PATH]')
        .replaceAll(_hashPattern, '[REDACTED_HASH]');
  }

  static Future<bool> clearLegacyLogsOnce({Directory? directory}) async {
    try {
      final logDirectory = directory ?? await getAppTempDirectory();
      final marker = File('${logDirectory.path}/$_privacyCleanupMarker');
      if (await marker.exists()) return false;

      for (final name in ['app_logs.txt', 'app_logs.txt.old']) {
        final legacyLog = File('${logDirectory.path}/$name');
        if (await legacyLog.exists()) {
          await legacyLog.delete();
        }
      }

      _logFile = null;
      await marker.writeAsString('completed', flush: true);
      return true;
    } catch (e) {
      dev.log('Failed to clear legacy logs', error: sanitize(e.toString()));
      return false;
    }
  }

  /// Get color based on log level
  String _getColor(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return _blue;
      case AppLogLevel.warning:
        return _yellow;
      case AppLogLevel.error:
        return _red;
      default:
        return _white; // Default (info)
    }
  }

  /// Internal helper to get or initialize the log file
  static Future<File> _getLogFile() async {
    if (_logFile != null && await _logFile!.exists()) return _logFile!;
    final tempDir = await getAppTempDirectory();
    _logFile = File('${tempDir.path}/app_logs.txt');
    return _logFile!;
  }

  /// Log a message with an optional error and stack trace
  void log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    AppLogLevel level = AppLogLevel.info,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.toString().split('.').last.toUpperCase();
    final prefixString = prefixes.map((p) => "[$p]").join(' ');

    // Format log message
    final safeMessage = sanitize(message);
    final safeError = error == null ? null : sanitize(error.toString());
    final safeStackTrace = stackTrace == null
        ? null
        : StackTrace.fromString(sanitize(stackTrace.toString()));
    String logMessage =
        "FiFe $prefixString [$levelStr] [$timestamp] $safeMessage";

    // Use dart:developer for efficient logging
    if (Platform.isAndroid || Platform.isIOS) {
      dev.log(logMessage, error: safeError, stackTrace: safeStackTrace);
    }

    if (safeError != null) {
      logMessage += " $safeError";
    }
    if (safeStackTrace != null) {
      logMessage += " $safeStackTrace";
    }
    // Optionally print in debug mode
    if (!const bool.fromEnvironment('dart.vm.product')) {
      final coloredMessage = "${_getColor(level)}$logMessage$_reset";
      stdout.writeln(coloredMessage);
    }

    _enqueueLog(logMessage);
  }

  static void _enqueueLog(String logMessage) {
    _logQueue.add(logMessage);
    _processQueue();
  }

  static Future<void> _processQueue() async {
    if (_isWriting) return;
    _isWriting = true;

    try {
      while (_logQueue.isNotEmpty) {
        final messages = List<String>.from(_logQueue);
        _logQueue.clear();

        final file = await _getLogFile();

        // Production-grade rotation: If file exceeds size limit, rotate to .old
        if (await file.exists() && await file.length() > _maxLogSize) {
          try {
            final oldFile = File('${file.path}.old');
            if (await oldFile.exists()) {
              await oldFile.delete();
            }
            await file.rename(oldFile.path);
          } catch (e) {
            // Ignore rotation errors (e.g., another isolate already rotated the file)
          }
        }

        // Use FileMode.append for atomic writes across multiple isolates/processes.
        await file.writeAsString('${messages.join('\n')}\n',
            mode: FileMode.append);
      }
    } catch (e) {
      dev.log("Failed to write to log file queue", error: e);
    } finally {
      _isWriting = false;
    }
  }

  /// Convenience methods
  void debug(String message) => log(message, level: AppLogLevel.debug);
  void info(String message) => log(message, level: AppLogLevel.info);
  void warning(String message) => log(message, level: AppLogLevel.warning);
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    log(message,
        level: AppLogLevel.error, error: error, stackTrace: stackTrace);
  }
}

/// Enum for log levels
enum AppLogLevel { debug, info, warning, error }
