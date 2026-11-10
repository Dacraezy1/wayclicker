import 'dart:convert';
import 'dart:io';

/// Mouse buttons the CLI understands for `--button`.
const List<String> mouseButtons = ['left', 'middle', 'right', 'side', 'extra'];

const int minInterval = 1;
const int maxInterval = 3600000; // one hour

/// Everything the user can configure. Pure Dart so it can be unit-tested.
class Settings {
  Settings({
    this.interval = 100,
    this.hotkey = 'F6',
    this.triggerMode = 'toggle',
    this.targetType = 'mouse',
    this.button = 'left',
    this.key = 'G',
    this.mode = 'click',
  });

  int interval; // ms between clicks
  String hotkey; // key, mouse button or combo, e.g. F6, BTN_SIDE, ctrl+alt+c
  String triggerMode; // 'toggle' (press to start/stop) or 'hold' (while held)
  String targetType; // 'mouse' or 'keyboard'
  String button; // one of [mouseButtons]
  String key; // keyboard key or combo to press
  String mode; // 'click' (repeat) or 'hold' (keep pressed down)

  bool get isHoldTrigger => triggerMode == 'hold';
  bool get isHoldAction => mode == 'hold';
  bool get targetsMouse => targetType == 'mouse';

  // The JSON key for the hotkey stays "toggleKey" so old config files still load.
  Map<String, dynamic> toJson() => {
    'interval': interval,
    'toggleKey': hotkey,
    'triggerMode': triggerMode,
    'targetType': targetType,
    'button': button,
    'key': key,
    'mode': mode,
  };

  /// Builds settings from JSON, replacing anything invalid with a safe default.
  factory Settings.fromJson(Map<String, dynamic> json) {
    String text(String name, String fallback) {
      final v = json[name];
      return (v is String && v.trim().isNotEmpty) ? v.trim() : fallback;
    }

    String oneOf(String name, List<String> allowed, String fallback) {
      final v = text(name, fallback).toLowerCase();
      return allowed.contains(v) ? v : fallback;
    }

    final rawInterval = json['interval'];
    final interval = rawInterval is num ? rawInterval.toInt() : 100;

    return Settings(
      interval: interval.clamp(minInterval, maxInterval),
      hotkey: text('toggleKey', 'F6'),
      triggerMode: oneOf('triggerMode', ['toggle', 'hold'], 'toggle'),
      targetType: oneOf('targetType', ['mouse', 'keyboard'], 'mouse'),
      button: oneOf('button', mouseButtons, 'left'),
      key: text('key', 'G'),
      mode: oneOf('mode', ['click', 'hold'], 'click'),
    );
  }

  /// Arguments that only check the key names (no permissions needed).
  List<String> validateArgs() => [
    '--validate',
    '--toggle-key',
    hotkey,
    if (targetsMouse) ...['--button', button] else ...['--key', key],
  ];

  /// Arguments for a real run.
  List<String> runArgs() => [
    '--interval',
    interval.toString(),
    '--toggle-key',
    hotkey,
    '--trigger-mode',
    triggerMode,
    '--mode',
    mode,
    if (targetsMouse) ...['--button', button] else ...['--key', key],
    '--stdin-control',
  ];

  /// One plain-English sentence describing what will happen.
  String describe() {
    final trigger = prettyKey(hotkey);
    final target = targetPhrase;
    final every = '${interval.toString()} ms';
    if (isHoldTrigger) {
      return isHoldAction
          ? 'Hold $trigger to keep $target held down. Let go to release it.'
          : 'Hold $trigger to click $target every $every. Let go to stop.';
    }
    return isHoldAction
        ? 'Press $trigger to hold $target down. Press $trigger again to release it.'
        : 'Press $trigger to start clicking $target every $every. Press $trigger again to stop.';
  }

  String get targetPhrase {
    if (targetsMouse) return 'the ${button.toLowerCase()} mouse button';
    final k = prettyKey(key);
    return k.contains('+') ? k : 'the $k key';
  }

  // ---- storage ----

  static Future<File> _file() async {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory(
      (xdg != null && xdg.isNotEmpty) ? '$xdg/wayclicker' : '$home/.config/wayclicker',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/config.json');
  }

  static Future<Settings> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          return Settings.fromJson(decoded);
        }
      }
    } catch (_) {
      // Fall back to defaults when the file is missing or damaged.
    }
    return Settings();
  }

  Future<void> save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(toJson()));
    } catch (_) {
      // Not being able to save must never break the app.
    }
  }
}

/// Turns CLI key names into readable text: `BTN_SIDE` -> `Side button`,
/// `ctrl+alt+c` -> `Ctrl+Alt+C`.
String prettyKey(String value) {
  String one(String part) {
    switch (part.trim().toLowerCase()) {
      case 'left':
      case 'btn_left':
        return 'Left click';
      case 'right':
      case 'btn_right':
        return 'Right click';
      case 'middle':
      case 'btn_middle':
        return 'Middle click';
      case 'side':
      case 'btn_side':
        return 'Side button';
      case 'extra':
      case 'btn_extra':
        return 'Extra button';
      case 'ctrl':
        return 'Ctrl';
      case 'alt':
        return 'Alt';
      case 'shift':
        return 'Shift';
      case 'super':
        return 'Super';
      default:
        final p = part.trim();
        return p.length == 1 ? p.toUpperCase() : p;
    }
  }

  return value.split('+').map(one).join('+');
}
