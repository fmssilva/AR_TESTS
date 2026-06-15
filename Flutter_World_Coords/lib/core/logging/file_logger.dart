import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

// Write timestamped AR debug logs to a file on the device.
// File name embeds the session start time to preserve crash logs across sessions.
class FileLogger {
  static File? _logFile;
  static bool _initialized = false;

  // Initialize the log file. Must be called once before any log() call.
  static Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    _logFile = File('${dir.path}/ar_session_$timestamp.txt');
    _initialized = true;
    await log('=== AR Session started ===');
  }

  // Append a timestamped line to the session log file.
  // Also prints to the IDE debug console via debugPrint when attached.
  static Future<void> log(String message) async {
    if (!_initialized) return;
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $message\n';
    debugPrint(line.trim());
    await _logFile?.writeAsString(line, mode: FileMode.append);
  }

  // Returns the absolute path of the current session log file.
  // Shown on the debug overlay screen so testers can retrieve it via adb.
  static String? get logFilePath => _logFile?.path;
}
