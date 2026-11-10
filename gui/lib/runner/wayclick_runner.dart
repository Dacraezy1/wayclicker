import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wayclicker_gui/config/settings.dart';

enum RunState { stopped, starting, running }

/// Starts and stops the `wayclicker` CLI. Pure Dart (no Flutter imports).
///
/// * If the user can already use /dev/uinput and /dev/input (udev rule +
///   `input` group), the CLI runs as the user: no password prompt.
/// * Otherwise it runs through `pkexec` (one password prompt per start).
/// * The CLI is told to quit through its stdin, so stopping never needs a
///   second password, and closing the GUI can never leave it running.
class ClickerController {
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  RunState _state = RunState.stopped;
  RunState get state => _state;
  bool get isActive => _state != RunState.stopped;
  bool get isRunning => _state == RunState.running;

  final List<String> _log = <String>[];
  List<String> get log => List<String>.unmodifiable(_log);

  String? _error;
  String? get error => _error;

  /// null until [prepare] has finished.
  bool? _needsPassword;
  bool? get needsPassword => _needsPassword;

  String? _binary;
  Process? _process;
  bool _stopRequested = false;
  String? _lastStderr;
  bool _disposed = false;

  void _notify() {
    if (!_disposed && !_changes.isClosed) _changes.add(null);
  }

  void _addLog(String line) {
    _log.add(line);
    if (_log.length > 300) _log.removeRange(0, _log.length - 300);
  }

  void _fail(String message) {
    _error = message;
    _addLog('[error] $message');
    _state = RunState.stopped;
    _notify();
  }

  /// Finds the CLI and checks whether it can run without a password.
  Future<void> prepare() async {
    try {
      _binary = await _findBinary();
    } catch (e) {
      _binary = null;
      _error = e.toString();
      _notify();
      return;
    }
    try {
      final r = await Process.run(_binary!, ['--check-access']);
      _needsPassword = r.exitCode != 0;
    } catch (_) {
      _needsPassword = true;
    }
    _notify();
  }

  static Future<String> _findBinary() async {
    final candidates = <String>[];
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$dir/wayclicker');
    } catch (_) {}
    candidates.addAll(['/usr/local/bin/wayclicker', '/usr/bin/wayclicker']);
    final path = Platform.environment['PATH'];
    if (path != null) {
      for (final dir in path.split(':')) {
        if (dir.isNotEmpty) candidates.add('$dir/wayclicker');
      }
    }
    for (final c in candidates) {
      if (await FileSystemEntity.isFile(c)) return c;
    }
    throw 'The "wayclicker" program was not found next to the app or in PATH.';
  }

  static Future<String?> _which(String name) async {
    final path = Platform.environment['PATH'] ?? '';
    final dirs = [...path.split(':'), '/run/wrappers/bin', '/usr/bin', '/bin'];
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      final candidate = '$dir/$name';
      if (await FileSystemEntity.isFile(candidate)) return candidate;
    }
    return null;
  }

  /// Checks the key names without any permissions. Returns null when valid,
  /// otherwise a readable error message.
  Future<String?> validate(Settings settings) async {
    final bin = _binary;
    if (bin == null) return _error ?? 'The "wayclicker" program was not found.';
    try {
      final result = await Process.run(bin, settings.validateArgs());
      if (result.exitCode == 0) return null;
      var message = result.stderr.toString().trim();
      if (message.startsWith('Error:')) message = message.substring(6).trim();
      return message.isEmpty ? 'Invalid key settings.' : message;
    } catch (_) {
      return null; // let start() report the real problem
    }
  }

  /// pkexec runs the program as root, and root cannot read an AppImage's
  /// FUSE mount. In that case the CLI is copied to a private runtime folder.
  static Future<String> _stageForPkexec(String bin) async {
    final inAppImage =
        Platform.environment.containsKey('APPIMAGE') || bin.contains('/.mount_');
    if (!inAppImage) return bin;
    try {
      final base =
          Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path;
      final dir = Directory('$base/wayclicker');
      await dir.create(recursive: true);
      await Process.run('chmod', ['700', dir.path]);
      final dest = '${dir.path}/wayclicker';
      await File(bin).copy(dest);
      await Process.run('chmod', ['755', dest]);
      return dest;
    } catch (_) {
      return bin;
    }
  }

  Future<void> start(Settings settings) async {
    if (isActive) return;
    _error = null;
    _lastStderr = null;
    _stopRequested = false;
    _log.clear();

    final bin = _binary;
    if (bin == null) {
      _fail(_error ?? 'The "wayclicker" program was not found.');
      return;
    }

    _state = RunState.starting;
    _notify();

    var executable = bin;
    var args = settings.runArgs();
    if (_needsPassword ?? true) {
      final pkexec = await _which('pkexec');
      if (pkexec == null) {
        _fail(
          'Wayclicker needs permission to read input devices, and "pkexec" '
          '(polkit) is not installed. Install polkit, or add yourself to the '
          '"input" group (see the README, section Permissions).',
        );
        return;
      }
      final staged = await _stageForPkexec(bin);
      executable = pkexec;
      args = [staged, ...args];
      _addLog('Waiting for your password...');
      _notify();
    }

    final Process process;
    try {
      process = await Process.start(executable, args);
    } catch (e) {
      _fail('Could not start Wayclicker: $e');
      return;
    }
    _process = process;
    // A broken pipe on stdin (process already gone) must not crash the GUI.
    unawaited(process.stdin.done.catchError((Object _) {}));

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdout);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStderr);
    unawaited(process.exitCode.then(_onExit));
  }

  void _onStdout(String line) {
    _addLog(line);
    if (_state == RunState.starting && line.trim() == 'Ready.') {
      _state = RunState.running;
    }
    _notify();
  }

  void _onStderr(String line) {
    if (line.trim().isEmpty) return;
    _lastStderr = line.trim();
    _addLog(line);
    _notify();
  }

  void _onExit(int code) {
    final wasStarting = _state == RunState.starting;
    _process = null;
    _state = RunState.stopped;
    if (!_stopRequested && (wasStarting || code != 0)) {
      if (code == 126 || code == 127) {
        _error = 'Permission was not granted (password prompt cancelled or failed).';
      } else {
        var message = _lastStderr ?? 'Wayclicker stopped unexpectedly (code $code).';
        if (message.startsWith('Error:')) message = message.substring(6).trim();
        _error = message;
      }
      _addLog('[error] $_error');
    } else {
      _addLog('Stopped.');
    }
    _notify();
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    _stopRequested = true;
    try {
      process.stdin.writeln('stop');
      await process.stdin.flush();
    } catch (_) {}
    try {
      await process.stdin.close();
    } catch (_) {}
    await process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }

  Future<void> dispose() async {
    await stop();
    _disposed = true;
    await _changes.close();
  }
}
