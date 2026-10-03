import 'package:flutter/material.dart';
import 'package:wayclicker_gui/config/config_storage.dart';
import 'package:wayclicker_gui/runner/wayclick_runner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ClickerController _controller = ClickerController();
  late TextEditingController _intervalController;

  final List<String> _allToggleKeys = [
    // Function Keys
    ...List.generate(12, (i) => 'F${i + 1}'),
    // Number Keys
    ...List.generate(10, (i) => '$i'),
    // Alpha Keys
    ...List.generate(26, (i) => String.fromCharCode(65 + i)),
    // Mouse Buttons
    'BTN_LEFT',
    'BTN_RIGHT',
    'BTN_MIDDLE',
    'BTN_SIDE',
    'BTN_EXTRA',
    // Modifiers & Special
    'SHIFT',
    'CTRL',
    'ALT',
    'SPACE',
    'ENTER',
    'TAB',
    'ESC',
  ];

  final List<String> _allTargetKeys = [
    // Alpha Keys
    ...List.generate(26, (i) => String.fromCharCode(65 + i)),
    // Number Keys
    ...List.generate(10, (i) => '$i'),
    // Function Keys
    ...List.generate(12, (i) => 'F${i + 1}'),
    // Navigation & Modifiers
    'SPACE',
    'ENTER',
    'TAB',
    'ESC',
    'BACKSPACE',
    'SHIFT',
    'CTRL',
    'ALT',
    'UP',
    'DOWN',
    'LEFT',
    'RIGHT',
    'INSERT',
    'DELETE',
    'HOME',
    'END',
    'PAGEUP',
    'PAGEDOWN',
  ];

  // Config state
  double _interval = 100;
  String _selectedToggleKey = 'F6';
  String _targetType = 'mouse'; // 'mouse' or 'keyboard'
  String _selectedButton = 'left';
  String _selectedTargetKey = 'G';
  String _actionMode = 'click'; // 'click' or 'hold'

  bool _isConfigLoaded = false;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(text: _interval.toInt().toString());
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await WayclickConfig.load();
    if (!mounted) return;
    setState(() {
      _interval = config.interval.toDouble();
      _selectedToggleKey = _allToggleKeys.contains(config.toggleKey) ? config.toggleKey : 'F6';
      _targetType = (config.targetType == 'keyboard') ? 'keyboard' : 'mouse';
      _selectedButton = config.button;
      _selectedTargetKey = _allTargetKeys.contains(config.key) ? config.key : 'G';
      _actionMode = (config.mode == 'hold') ? 'hold' : 'click';
      _intervalController.text = _interval.toInt().toString();
      _isConfigLoaded = true;
    });
  }

  void _saveConfig() {
    final config = WayclickConfig(
      interval: _interval.toInt(),
      toggleKey: _selectedToggleKey,
      targetType: _targetType,
      button: _selectedButton,
      key: _selectedTargetKey,
      mode: _actionMode,
    );
    config.save();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setInterval(double val) {
    setState(() {
      _interval = val.clamp(1, 999999);
      _intervalController.text = _interval.toInt().toString();
    });
    _saveConfig();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isConfigLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final double maxSlider = (_interval > 5000) ? _interval : 5000;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(colorScheme),
              const SizedBox(height: 20),

              // --- Mode Selection (Click vs Hold) ---
              _sectionHeader("Action Mode"),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'click',
                      label: Text('Click (Repeat)'),
                      icon: Icon(Icons.repeat),
                    ),
                    ButtonSegment(
                      value: 'hold',
                      label: Text('Hold (Continuous)'),
                      icon: Icon(Icons.touch_app),
                    ),
                  ],
                  selected: {_actionMode},
                  onSelectionChanged: (val) {
                    setState(() => _actionMode = val.first);
                    _saveConfig();
                  },
                ),
              ),
              const SizedBox(height: 20),

              // --- Speed (Interval) Section ---
              _sectionHeader(
                _actionMode == 'hold'
                    ? "Speed / Interval (Not needed in Hold mode)"
                    : "Speed (Click Interval)",
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: _actionMode == 'hold' ? 0.4 : 1.0,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _interval.clamp(1, maxSlider),
                            min: 1,
                            max: maxSlider,
                            onChanged: _actionMode == 'hold'
                                ? null
                                : (val) {
                                    setState(() {
                                      _interval = val;
                                      _intervalController.text = val.toInt().toString();
                                    });
                                    _saveConfig();
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _intervalController,
                            enabled: _actionMode != 'hold',
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              suffixText: 'ms',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onChanged: (text) {
                              final parsed = int.tryParse(text);
                              if (parsed != null && parsed > 0) {
                                setState(() {
                                  _interval = parsed.toDouble();
                                });
                                _saveConfig();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Quick Interval Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _presetChip(10, '10ms'),
                          _presetChip(50, '50ms'),
                          _presetChip(100, '100ms'),
                          _presetChip(500, '500ms'),
                          _presetChip(1000, '1s'),
                          _presetChip(2500, '2.5s'),
                          _presetChip(5000, '5s'),
                          _presetChip(10000, '10s'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),

              // --- Target Selection (Mouse vs Keyboard) ---
              _sectionHeader("Action Target"),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'mouse',
                      label: Text('Mouse Button'),
                      icon: Icon(Icons.mouse),
                    ),
                    ButtonSegment(
                      value: 'keyboard',
                      label: Text('Keyboard Key'),
                      icon: Icon(Icons.keyboard),
                    ),
                  ],
                  selected: {_targetType},
                  onSelectionChanged: (val) {
                    setState(() => _targetType = val.first);
                    _saveConfig();
                  },
                ),
              ),
              const SizedBox(height: 12),

              // If Target is Mouse
              if (_targetType == 'mouse') ...[
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'left', label: Text('Left')),
                      ButtonSegment(value: 'middle', label: Text('Middle')),
                      ButtonSegment(value: 'right', label: Text('Right')),
                      ButtonSegment(value: 'side', label: Text('Side')),
                      ButtonSegment(value: 'extra', label: Text('Extra')),
                    ],
                    selected: {_selectedButton},
                    onSelectionChanged: (val) {
                      setState(() => _selectedButton = val.first);
                      _saveConfig();
                    },
                  ),
                ),
              ] else ...[
                // If Target is Keyboard Key
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  initialSelection: _selectedTargetKey,
                  enableSearch: true,
                  menuHeight: 300,
                  label: const Text("Select Target Key (e.g. G, F, Space)"),
                  onSelected: (val) {
                    if (val != null) {
                      setState(() => _selectedTargetKey = val);
                      _saveConfig();
                    }
                  },
                  dropdownMenuEntries: _allTargetKeys.map((k) {
                    return DropdownMenuEntry(
                      value: k,
                      label: k,
                      leadingIcon: const Icon(Icons.keyboard),
                    );
                  }).toList(),
                ),
              ],
              const Divider(height: 32),

              // --- Activation Toggle Key ---
              _sectionHeader("Activation Toggle Key"),
              const SizedBox(height: 8),
              DropdownMenu<String>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: _selectedToggleKey,
                enableSearch: true,
                menuHeight: 300,
                label: const Text("Select Toggle Key"),
                onSelected: (val) {
                  if (val != null) {
                    setState(() => _selectedToggleKey = val);
                    _saveConfig();
                  }
                },
                dropdownMenuEntries: _allToggleKeys.map((k) {
                  return DropdownMenuEntry(
                    value: k,
                    label: k,
                    leadingIcon: k.contains('BTN')
                        ? const Icon(Icons.mouse)
                        : const Icon(Icons.keyboard),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              // --- Start/Stop Action Button ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: () async {
                    if (_controller.isRunning) {
                      _controller.stop();
                    } else {
                      _saveConfig();
                      await _controller.start(
                        interval: _interval.toInt(),
                        toggleKey: _selectedToggleKey,
                        targetType: _targetType,
                        button: _selectedButton,
                        key: _selectedTargetKey,
                        mode: _actionMode,
                      );
                    }
                    setState(() {});
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _controller.isRunning ? Colors.redAccent : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    _controller.isRunning
                        ? Icons.power_settings_new
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    _controller.isRunning ? "STOP SERVICE" : "START SERVICE",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // --- Live Console Output ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionHeader("Live Console Output"),
                  Text(
                    "Config auto-saved",
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withAlpha(120)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: StreamBuilder<String>(
                  stream: _controller.logStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        "Error: ${snapshot.error}",
                        style: const TextStyle(color: Colors.red),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text(
                        "Ready to start. Press START SERVICE to initialize kernel uinput.",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      );
                    }

                    return SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        snapshot.data!,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip(int value, String label) {
    final isSelected = _interval.toInt() == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: _actionMode == 'hold'
            ? null
            : (_) => _setInterval(value.toDouble()),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WAYCLICKER',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: colorScheme.primary,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'Universal Linux Autoclicker (Wayland & X11)',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.1,
      ),
    );
  }
}
