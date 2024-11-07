import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

class FileOutput extends LogOutput {
  FileOutput(this.file);
  
  final File file;
  
  @override
  void output(OutputEvent event) async {
    final logMessages = event.lines.join('\n');
    await file.writeAsString('$logMessages\n', mode: FileMode.append);
  }
}

class AppLogger {
  late final Logger _logger;
  late final File _logFile;

  AppLogger._internal();

  static final AppLogger _instance = AppLogger._internal();
  
  factory AppLogger() {
    return _instance;
  }

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    print(directory.path);
    final logDir = Directory('${directory.path}/logs');
    // Create the directory if it doesn't exist
    if (!(await logDir.exists())) {
      await logDir.create(recursive: true);
    }
    _logFile = File('${logDir.path}/app_logs.txt');

    _logger = Logger(
      output: FileOutput(_logFile),
    );
  }

 void log(String message) {
    _logger.i(message);
  }

  void close () {
    _logger.close();
  }
}
