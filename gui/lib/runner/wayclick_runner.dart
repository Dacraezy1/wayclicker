import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ClickerController {
  Process? _process;
  String _logBuffer = "";

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  bool get isRunning => _process != null;

  Future<String> _findBinaryPath() async {
    // 1. Check side-by-side with running Flutter UI binary
    try {
      final String executablePath = Platform.resolvedExecutable;
      final String executableDir = File(executablePath).parent.path;
      final String sideBySide = '$executableDir/wayclicker';
      final file = File(sideBySide);
      if (await file.exists()) {
        await Process.run('chmod', ['+x', sideBySide]);
        return sideBySide;
      }
    } catch (_) {}

    // 2. Check standard system install path
    final localBin = File('/usr/local/bin/wayclicker');
    if (await localBin.exists()) {
      return localBin.path;
    }

    // 3. Check distribution package install path
    final usrBin = File('/usr/bin/wayclicker');
    if (await usrBin.exists()) {
      return usrBin.path;
    }

    // 4. Try resolving through PATH
    try {
      final whichResult = await Process.run('which', ['wayclicker']);
      if (whichResult.exitCode == 0) {
        final path = whichResult.stdout.toString().trim();
        if (path.isNotEmpty && await File(path).exists()) {
          return path;
        }
      }
    } catch (_) {}

    throw Exception("Binary 'wayclicker' not found side-by-side, in /usr/local/bin, or in PATH.");
  }

  Future<void> start({
    required int interval,
    required String toggleKey,
    required String targetType,
    required String button,
    required String key,
    required String mode,
  }) async {
    if (_process != null) return;

    // Clear previous logs when starting a new session
    _logBuffer = "Attempting to start wayclicker...\n";
    _logController.add(_logBuffer);

    try {
      final String path = await _findBinaryPath();

      final List<String> args = [
        path,
        '--interval', interval.toString(),
        '--toggle-key', toggleKey,
        '--mode', mode,
      ];

      if (targetType == 'keyboard') {
        args.addAll(['--key', key]);
      } else {
        args.addAll(['--button', button]);
      }

      _process = await Process.start('pkexec', args);

      // Handle standard output
      _process!.stdout.transform(utf8.decoder).listen((data) {
        _logBuffer += data;
        _logController.add(_logBuffer);
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
          _logController.add("\n[i] Service Stopped.\n");
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
