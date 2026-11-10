import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wayclicker_gui/config/settings.dart';
import 'package:wayclicker_gui/runner/wayclick_runner.dart';
import 'package:wayclicker_gui/widgets/key_bind_field.dart';

/// Hotkeys offered in the drop-down. Anything else can be typed or recorded.
final List<String> _hotkeyPresets = [
  ...List<String>.generate(24, (i) => 'F${i + 1}'),
  'left',
  'right',
  'middle',
  'BTN_SIDE',
  'BTN_EXTRA',
  'ctrl+alt+c',
];

/// Keys offered for "Keyboard key".
final List<String> _keyPresets = [
  ...List<String>.generate(26, (i) => String.fromCharCode(65 + i)),
  ...List<String>.generate(10, (i) => '$i'),
  'SPACE',
  'ENTER',
  'TAB',
  'ESC',
  'BACKSPACE',
  'arrowup',
  'arrowdown',
  'arrowleft',
  'arrowright',
];

const List<int> _intervalPresets = [10, 50, 100, 250, 500, 1000];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ClickerController _controller = ClickerController();
  final TextEditingController _intervalText = TextEditingController();
  StreamSubscription<void>? _sub;

  Settings _s = Settings();
  bool _loaded = false;
  String? _intervalError;

  @override
  void initState() {
    super.initState();
    _sub = _controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  Future<void> _init() async {
    final loaded = await Settings.load();
    if (!mounted) return;
    setState(() {
      _s = loaded;
      _intervalText.text = loaded.interval.toString();
      _loaded = true;
    });
    await _controller.prepare();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _intervalText.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// Applies a change and saves it.
  void _change(VoidCallback apply) {
    setState(apply);
    unawaited(_s.save());
  }

  void _onIntervalChanged(String text) {
    final value = int.tryParse(text.trim());
    if (value == null || value < minInterval) {
      setState(() => _intervalError = 'Enter a number, 1 or more');
    } else if (value > maxInterval) {
      setState(() => _intervalError = 'Maximum is $maxInterval ms');
    } else {
      _change(() {
        _intervalError = null;
        _s.interval = value;
      });
    }
  }

  void _setInterval(int value) {
    _intervalText.text = '$value';
    _change(() {
      _intervalError = null;
      _s.interval = value;
    });
  }

  Future<void> _onStartStop() async {
    if (_controller.isRunning) {
      await _controller.stop();
      return;
    }
    if (_controller.isActive) return;
    if (!_s.isHoldAction && _intervalError != null) return;

    await _s.save();
    final problem = await _controller.validate(_s);
    if (problem != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problem),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    await _controller.start(_s);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    final active = _controller.isActive;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _header(scheme),
                const SizedBox(height: 16),
                // Settings are locked while running, so what you see is what runs.
                AbsorbPointer(
                  absorbing: active,
                  child: Opacity(
                    opacity: active ? 0.5 : 1,
                    child: Column(
                      children: [
                        _hotkeySection(),
                        const SizedBox(height: 12),
                        _targetSection(),
                        const SizedBox(height: 12),
                        _actionSection(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _startButton(scheme),
                const SizedBox(height: 12),
                _infoBox(scheme),
                if (_controller.error != null) ...[
                  const SizedBox(height: 12),
                  _errorBox(scheme),
                ],
                const SizedBox(height: 8),
                _logTile(scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final (String label, Color color) = switch (_controller.state) {
      RunState.stopped => ('Stopped', scheme.outline),
      RunState.starting => ('Starting', Colors.orange),
      RunState.running => ('Running', Colors.green),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            'Wayclicker',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _hotkeySection() {
    return _section('1. Hotkey', [
      KeyBindField(
        label: 'Hotkey',
        value: _s.hotkey,
        presets: _hotkeyPresets,
        presetLabel: prettyKey,
        helper: 'A key, mouse button or combo such as ctrl+alt+c.',
        onChanged: (v) => _change(() => _s.hotkey = v),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: 'toggle',
              label: Text('Press to start / stop'),
              icon: Icon(Icons.toggle_on_outlined),
            ),
            ButtonSegment(
              value: 'hold',
              label: Text('Hold to run'),
              icon: Icon(Icons.touch_app_outlined),
            ),
          ],
          selected: {_s.triggerMode},
          onSelectionChanged: (v) => _change(() => _s.triggerMode = v.first),
        ),
      ),
    ]);
  }

  Widget _targetSection() {
    const labels = {
      'left': 'Left',
      'middle': 'Middle',
      'right': 'Right',
      'side': 'Side',
      'extra': 'Extra',
    };
    return _section('2. What to press', [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: 'mouse',
              label: Text('Mouse button'),
              icon: Icon(Icons.mouse_outlined),
            ),
            ButtonSegment(
              value: 'keyboard',
              label: Text('Keyboard key'),
              icon: Icon(Icons.keyboard_outlined),
            ),
          ],
          selected: {_s.targetType},
          onSelectionChanged: (v) => _change(() => _s.targetType = v.first),
        ),
      ),
      const SizedBox(height: 12),
      if (_s.targetsMouse)
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final b in mouseButtons)
              ChoiceChip(
                label: Text(labels[b] ?? b),
                selected: _s.button == b,
                onSelected: (_) => _change(() => _s.button = b),
              ),
          ],
        )
      else
        KeyBindField(
          label: 'Key',
          value: _s.key,
          presets: _keyPresets,
          allowMouse: false,
          helper: 'Any key, or a combo such as ctrl+c.',
          onChanged: (v) => _change(() => _s.key = v),
        ),
    ]);
  }

  String _rate(int ms) {
    final perSecond = 1000 / ms;
    if (perSecond >= 10) return '${perSecond.round()} clicks / second';
    if (perSecond >= 1) return '${perSecond.toStringAsFixed(1)} clicks / second';
    final seconds = ms / 1000;
    return '1 click every ${seconds.toStringAsFixed(ms % 1000 == 0 ? 0 : 1)} s';
  }

  Widget _actionSection() {
    final scheme = Theme.of(context).colorScheme;
    return _section('3. How', [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: 'click',
              label: Text('Click repeatedly'),
              icon: Icon(Icons.repeat),
            ),
            ButtonSegment(
              value: 'hold',
              label: Text('Hold down'),
              icon: Icon(Icons.pan_tool_outlined),
            ),
          ],
          selected: {_s.mode},
          onSelectionChanged: (v) => _change(() => _s.mode = v.first),
        ),
      ),
      const SizedBox(height: 12),
      if (_s.isHoldAction)
        Text(
          'The button or key stays pressed while the hotkey is active.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        )
      else ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: _intervalText,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Interval',
                  suffixText: 'ms',
                  isDense: true,
                  errorText: _intervalError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: _onIntervalChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _intervalError == null ? _rate(_s.interval) : '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final ms in _intervalPresets)
              ChoiceChip(
                label: Text(ms >= 1000 ? '${ms ~/ 1000} s' : '$ms ms'),
                selected: _s.interval == ms,
                onSelected: (_) => _setInterval(ms),
              ),
          ],
        ),
      ],
    ]);
  }

  Widget _startButton(ColorScheme scheme) {
    final state = _controller.state;
    final bool running = state == RunState.running;
    final String label = switch (state) {
      RunState.stopped => 'Start',
      RunState.starting => 'Starting...',
      RunState.running => 'Stop',
    };
    final bool blocked =
        state == RunState.stopped && !_s.isHoldAction && _intervalError != null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: (state == RunState.starting || blocked) ? null : _onStartStop,
        style: FilledButton.styleFrom(
          backgroundColor: running ? scheme.error : null,
          foregroundColor: running ? scheme.onError : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _infoBox(ColorScheme scheme) {
    final state = _controller.state;
    final running = state == RunState.running;
    final lines = <String>[
      switch (state) {
        RunState.stopped => _s.describe(),
        RunState.starting => 'Starting. Approve the password prompt if one appears.',
        RunState.running => 'Running. ${_s.describe()}',
      },
      if (state == RunState.stopped && _controller.needsPassword == true)
        'You will be asked for your password when you press Start. '
            'To skip that, see "Permissions" in the README.',
    ];
    final Color accent = running ? Colors.green : scheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: running
            ? Colors.green.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            running ? Icons.check_circle_outline : Icons.info_outline,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lines.first, style: Theme.of(context).textTheme.bodyMedium),
                for (final extra in lines.skip(1)) ...[
                  const SizedBox(height: 6),
                  Text(
                    extra,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _controller.error ?? '',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logTile(ColorScheme scheme) {
    final log = _controller.log;
    return ExpansionTile(
      title: const Text('Log'),
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        Container(
          width: double.infinity,
          height: 140,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              log.isEmpty ? 'Nothing yet.' : log.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
