import 'dart:convert';
import 'dart:io';

class WayclickConfig {
  int interval;
  String toggleKey;
  String triggerMode; // 'hold' or 'toggle'
  String targetType; // 'mouse' or 'keyboard'
  String button; // 'left', 'middle', 'right', 'side', 'extra'
  String key; // 'G', 'F', 'SPACE', etc.
  String mode; // 'click' or 'hold'

  WayclickConfig({
    this.interval = 50,
    this.toggleKey = 'left',
    this.triggerMode = 'hold',
    this.targetType = 'mouse',
    this.button = 'left',
    this.key = 'G',
    this.mode = 'click',
  });

  Map<String, dynamic> toJson() => {
    'interval': interval,
    'toggleKey': toggleKey,
    'triggerMode': triggerMode,
    'targetType': targetType,
    'button': button,
    'key': key,
    'mode': mode,
  };

  factory WayclickConfig.fromJson(Map<String, dynamic> json) {
    return WayclickConfig(
      interval: (json['interval'] as num?)?.toInt() ?? 50,
      toggleKey: json['toggleKey'] as String? ?? 'left',
      triggerMode: json['triggerMode'] as String? ?? 'hold',
      targetType: json['targetType'] as String? ?? 'mouse',
      button: json['button'] as String? ?? 'left',
      key: json['key'] as String? ?? 'G',
      mode: json['mode'] as String? ?? 'click',
    );
  }

  static Future<File> _getConfigFile() async {
    final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
    final home = Platform.environment['HOME'] ?? '.';
    final configDir = (xdgConfig != null && xdgConfig.isNotEmpty)
        ? Directory('$xdgConfig/wayclicker')
        : Directory('$home/.config/wayclicker');

    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
    return File('${configDir.path}/config.json');
  }

  static Future<WayclickConfig> load() async {
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return WayclickConfig.fromJson(json);
      }
    } catch (_) {
      // Fall back to defaults on error
    }
    return WayclickConfig();
  }

  Future<void> save() async {
    try {
      final file = await _getConfigFile();
      await file.writeAsString(jsonEncode(toJson()));
    } catch (_) {
      // Ignore file write errors
    }
  }
}
