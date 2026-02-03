import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ClickerController {
  Process? _process;
  String _logBuffer = "";

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  bool get isRunning => _process != null;

  Future<String> _getSideBySidePath() async {
    // This gets the path to the current running Flutter UI binary
    final String executablePath = Platform.resolvedExecutable;
    final String executableDir = File(executablePath).parent.path;

    final String binPath = '$executableDir/wayclicker';

    final file = File(binPath);
    if (!await file.exists()) {
      throw Exception("Binary not found at $binPath");
    }

    // Ensure it's executable (just in case the user unzipped it without permissions)
    await Process.run('chmod', ['+x', binPath]);

    return binPath;
  }

  Future<void> start({
    required int interval,
    required String toggleKey,
    required String button,
  }) async {
    if (_process != null) return;

    // Clear previous logs when starting a new session
    _logBuffer = "Attempting to start wayclicker...\n";
    _logController.add(_logBuffer);

    try {
      final String path = await _getSideBySidePath();

      _process = await Process.start('pkexec', [
        path, // Always use the full absolute path
        '--interval', interval.toString(),
        '--toggle-key', toggleKey,
        '--button', button,
      ]);

      // Handle standard output
      _process!.stdout.transform(utf8.decoder).listen((data) {
        _logBuffer += data;
        _logController.add(_logBuffer); // Push the updated history to the UI
      });

      // Handle standard error (CLI errors)
      _process!.stderr.transform(utf8.decoder).listen((data) {
        _logBuffer += "CLI Error: $data";
        _logController.add(_logBuffer);
      });

      // Handle process termination
      _process!.exitCode.then((code) {
        if (code == 126 || code == 127) {
          _logBuffer += "\n[!] Auth failed or binary not found.";
        } else {
          _logBuffer += "\n[i] Process exited (Code: $code)";
        }
        _logController.add(_logBuffer);
        _process = null;
      });
    } catch (e) {
      _logBuffer += "\n[X] Execution Error: $e";
      _logController.add(_logBuffer);
      _process = null;
    }
  }

  void stop() {
    if (_process != null) {
      // Kill the Dart handle for pkexec
      _process?.kill();

      // Use 'pkill' with specific flags:
      // -x prevents killing wayclicker_gui
      // -u 0 Only kill if the process is running as root (the pkexec child)
      Process.run('pkexec', ['pkill', '-x', '-u', '0', 'wayclicker']).then((
        result,
      ) {
        if (result.exitCode == 0) {
          _logController.add("\n[i] Service Stopped.");
        }
      });

      _process = null;
    }
  }

  void dispose() {
    _logController.close();
    _process?.kill();
  }
}
