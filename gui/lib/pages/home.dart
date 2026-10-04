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
    'left',
    'right',
    'middle',
    'BTN_SIDE',
    'BTN_EXTRA',
    // Function Keys
    ...List.generate(12, (i) => 'F${i + 1}'),
    // Number Keys
    ...List.generate(10, (i) => '$i'),
    // Alpha Keys
    ...List.generate(26, (i) => String.fromCharCode(65 + i)),
    // Modifiers & Special
    'SPACE',
    'ENTER',
    'TAB',
    'ESC',
    'SHIFT',
    'CTRL',
    'ALT',
  ];

  final List<String> _allTargetKeys = [
    ...List.generate(26, (i) => String.fromCharCode(65 + i)),
    ...List.generate(10, (i) => '$i'),
    ...List.generate(12, (i) => 'F${i + 1}'),
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
  double _interval = 50;
  String _triggerMode = 'hold'; // 'hold' (autoclick while held) or 'toggle' (click to toggle on/off)
  String _selectedToggleKey = 'left';
  String _targetType = 'mouse'; // 'mouse' or 'keyboard'
  String _selectedButton = 'left';
  String _selectedTargetKey = 'G';
  String _actionMode = 'click'; // 'click' (pulse clicks) or 'hold' (continuous virtual hold)

  bool _isConfigLoaded = false;
  bool _showAdvancedOptions = false;

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
      _triggerMode = (config.triggerMode == 'toggle') ? 'toggle' : 'hold';
      _selectedToggleKey = _allToggleKeys.contains(config.toggleKey) ? config.toggleKey : 'left';
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
      triggerMode: _triggerMode,
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

  String _formatKeyDisplay(String key) {
    switch (key.toLowerCase()) {
      case 'left':
      case 'btn_left':
        return 'Left Click';
      case 'right':
      case 'btn_right':
        return 'Right Click';
      case 'middle':
      case 'btn_middle':
        return 'Middle Click';
      case 'btn_side':
        return 'Mouse Side (Back)';
      case 'btn_extra':
        return 'Mouse Extra (Forward)';
      default:
        return key;
    }
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
    final double cps = (_interval > 0) ? (1000.0 / _interval) : 0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(colorScheme),
              const SizedBox(height: 20),

              // --- 1. Activation Mode Selection (Hold to Click vs Toggle) ---
              _sectionHeader("Activation Mode"),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'hold',
                      label: Text('Hold to Click (While Held)'),
                      icon: Icon(Icons.touch_app),
                    ),
                    ButtonSegment(
                      value: 'toggle',
                      label: Text('Toggle (Tap On / Off)'),
                      icon: Icon(Icons.toggle_on),
                    ),
                  ],
                  selected: {_triggerMode},
                  onSelectionChanged: (val) {
                    setState(() => _triggerMode = val.first);
                    _saveConfig();
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _triggerMode == 'hold'
                    ? "✨ Autoclicks continuously only while holding down the button or key. Stops as soon as you let go."
                    : "✨ Tap your hotkey once to start clicking continuously, tap again to stop.",
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 20),

              // --- 2. Button / Key Trigger Selection ---
              _sectionHeader(
                _triggerMode == 'hold'
                    ? "Hold Which Button to Autoclick?"
                    : "Activation Hotkey / Button",
              ),
              const SizedBox(height: 8),
              if (_triggerMode == 'hold') ...[
                // Quick preset for Left, Right, Middle, or Other
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'left', label: Text('Left Click')),
                      ButtonSegment(value: 'right', label: Text('Right Click')),
                      ButtonSegment(value: 'middle', label: Text('Middle Click')),
                      ButtonSegment(value: 'custom', label: Text('Other Key')),
                    ],
                    selected: {
                      ['left', 'right', 'middle'].contains(_selectedToggleKey)
                          ? _selectedToggleKey
                          : 'custom'
                    },
                    onSelectionChanged: (val) {
                      final selected = val.first;
                      setState(() {
                        if (selected == 'custom') {
                          _selectedToggleKey = 'F6';
                        } else {
                          _selectedToggleKey = selected;
                          // In hold-click mode, automatically align target button to trigger button
                          _selectedButton = selected;
                          _targetType = 'mouse';
                        }
                      });
                      _saveConfig();
                    },
                  ),
                ),
                if (!['left', 'right', 'middle'].contains(_selectedToggleKey)) ...[
                  const SizedBox(height: 12),
                  DropdownMenu<String>(
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: _selectedToggleKey,
                    enableSearch: true,
                    menuHeight: 300,
                    label: const Text("Select Custom Trigger Key / Mouse Button"),
                    onSelected: (val) {
                      if (val != null) {
                        setState(() => _selectedToggleKey = val);
                        _saveConfig();
                      }
                    },
                    dropdownMenuEntries: _allToggleKeys.map((k) {
                      return DropdownMenuEntry(
                        value: k,
                        label: _formatKeyDisplay(k),
                        leadingIcon: k.contains('BTN') || ['left', 'right', 'middle'].contains(k)
                            ? const Icon(Icons.mouse)
                            : const Icon(Icons.keyboard),
                      );
                    }).toList(),
                  ),
                ],
              ] else ...[
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  initialSelection: _selectedToggleKey,
                  enableSearch: true,
                  menuHeight: 300,
                  label: const Text("Select Toggle Key / Mouse Button"),
                  onSelected: (val) {
                    if (val != null) {
                      setState(() => _selectedToggleKey = val);
                      _saveConfig();
                    }
                  },
                  dropdownMenuEntries: _allToggleKeys.map((k) {
                    return DropdownMenuEntry(
                      value: k,
                      label: _formatKeyDisplay(k),
                      leadingIcon: k.contains('BTN') || ['left', 'right', 'middle'].contains(k)
                          ? const Icon(Icons.mouse)
                          : const Icon(Icons.keyboard),
                    );
                  }).toList(),
                ),
              ],
              const Divider(height: 32),

              // --- 3. Autoclicker Speed (Interval & CPS) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionHeader("Click Speed (Interval)"),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "${cps.toStringAsFixed(cps >= 10 ? 0 : 1)} clicks/sec",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _interval.clamp(1, maxSlider),
                      min: 1,
                      max: maxSlider,
                      onChanged: (val) {
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
                    _presetChip(10, '10ms (100 CPS)'),
                    _presetChip(25, '25ms (40 CPS)'),
                    _presetChip(50, '50ms (20 CPS)'),
                    _presetChip(100, '100ms (10 CPS)'),
                    _presetChip(250, '250ms'),
                    _presetChip(500, '500ms'),
                    _presetChip(1000, '1s'),
                    _presetChip(3000, '3s'),
                    _presetChip(5000, '5s'),
                  ],
                ),
              ),
              const Divider(height: 32),

              // --- 4. Target Action (Button or Key) ---
              InkWell(
                onTap: () => setState(() => _showAdvancedOptions = !_showAdvancedOptions),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _sectionHeader("Target to Click"),
                        const SizedBox(width: 8),
                        Text(
                          _targetType == 'mouse'
                              ? "(${_formatKeyDisplay(_selectedButton)})"
                              : "(Key: $_selectedTargetKey)",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      _showAdvancedOptions ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
              if (_showAdvancedOptions) ...[
                const SizedBox(height: 12),
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
              ],
              const SizedBox(height: 28),

              // --- 5. Start/Stop Action Button ---
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
                        triggerMode: _triggerMode,
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
              const SizedBox(height: 12),

              // Active instructions badge
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _controller.isRunning
                      ? Colors.green.withAlpha(isDark ? 50 : 30)
                      : colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _controller.isRunning ? Colors.green : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _controller.isRunning ? Icons.check_circle : Icons.info_outline,
                      size: 20,
                      color: _controller.isRunning ? Colors.green : colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _triggerMode == 'hold'
                            ? (_controller.isRunning
                                ? "RUNNING: Hold down ${_formatKeyDisplay(_selectedToggleKey)} with your hand to autoclick!"
                                : "When started: HOLD DOWN ${_formatKeyDisplay(_selectedToggleKey)} to autoclick at ${_interval.toInt()}ms. Stops when released.")
                            : (_controller.isRunning
                                ? "RUNNING: Tap ${_formatKeyDisplay(_selectedToggleKey)} to toggle autoclicking ON/OFF."
                                : "When started: TAP ${_formatKeyDisplay(_selectedToggleKey)} once to toggle ON, tap again to stop."),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _controller.isRunning
                              ? (isDark ? Colors.lightGreenAccent : Colors.green.shade800)
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- 6. Live Console Output ---
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
                height: 130,
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
        onSelected: (_) => _setInterval(value.toDouble()),
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
