import 'package:flutter_test/flutter_test.dart';
import 'package:wayclicker_gui/config/settings.dart';

void main() {
  test('defaults are safe', () {
    final s = Settings();
    expect(s.hotkey, 'F6');
    expect(s.triggerMode, 'toggle');
    expect(s.mode, 'click');
    expect(s.interval, 100);
  });

  test('bad json values fall back to defaults', () {
    final s = Settings.fromJson({
      'interval': -5,
      'toggleKey': '   ',
      'triggerMode': 'banana',
      'targetType': 7,
      'button': 'nope',
      'mode': 'HOLD',
    });
    expect(s.interval, minInterval);
    expect(s.hotkey, 'F6');
    expect(s.triggerMode, 'toggle');
    expect(s.targetType, 'mouse');
    expect(s.button, 'left');
    expect(s.mode, 'hold');
  });

  test('old config files still load', () {
    final s = Settings.fromJson({
      'interval': 50,
      'toggleKey': 'left',
      'triggerMode': 'hold',
      'targetType': 'keyboard',
      'button': 'left',
      'key': 'G',
      'mode': 'click',
    });
    expect(s.hotkey, 'left');
    expect(s.isHoldTrigger, true);
    expect(s.targetsMouse, false);
  });

  test('run arguments for a mouse target', () {
    final args = Settings(hotkey: 'ctrl+alt+c', interval: 25).runArgs();
    expect(args, [
      '--interval', '25',
      '--toggle-key', 'ctrl+alt+c',
      '--trigger-mode', 'toggle',
      '--mode', 'click',
      '--button', 'left',
      '--stdin-control',
    ]);
  });

  test('run arguments for a keyboard target', () {
    final args = Settings(targetType: 'keyboard', key: 'space', mode: 'hold').runArgs();
    expect(args.contains('--key'), true);
    expect(args[args.indexOf('--key') + 1], 'space');
    expect(args.contains('--button'), false);
  });

  test('descriptions are plain English', () {
    expect(
      Settings().describe(),
      'Press F6 to start clicking the left mouse button every 100 ms. Press F6 again to stop.',
    );
    expect(
      Settings(triggerMode: 'hold', mode: 'hold', hotkey: 'BTN_SIDE').describe(),
      'Hold Side button to keep the left mouse button held down. Let go to release it.',
    );
    expect(
      Settings(targetType: 'keyboard', key: 'ctrl+c').targetPhrase,
      'Ctrl+C',
    );
  });

  test('prettyKey', () {
    expect(prettyKey('ctrl+alt+c'), 'Ctrl+Alt+C');
    expect(prettyKey('F13'), 'F13');
    expect(prettyKey('middle'), 'Middle click');
  });
}
