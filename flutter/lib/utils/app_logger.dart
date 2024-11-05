// simple_logger.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class SimpleLogger {
  static IOSink? _logSink;

  static Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    final logDirPath = path.join(directory.path, 'logs');
    final logDir = Directory(logDirPath);

    // Ensure the directory exists
    if (!(await logDir.exists())) {
      await logDir.create(recursive: true);
    }

    final logFilePath = path.join(logDirPath, 'app.log');
    final logFile = File(logFilePath);

    _logSink = logFile.openWrite(mode: FileMode.append);
  }

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message';

    // Write to the log file
    _logSink?.writeln(logMessage);
    _logSink?.flush();

    // Optionally, also print to the console (visible when running from an IDE or command line)
    // Remove the following line if you don't want console output
    print(logMessage);
  }

  static void dispose() {
    _logSink?.close();
  }
}
