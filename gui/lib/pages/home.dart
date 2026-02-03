import 'package:flutter/material.dart';
import 'package:wayclicker_gui/runner/wayclick_runner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ClickerController _controller = ClickerController();

  void _handleToggle() async {
    if (_controller.isRunning) {
      _controller.stop();
      setState(() {});
    } else {
      // Optionally show a "Waiting for Auth..." spinner here
      await _controller.start(
        interval: _interval.toInt(),
        toggleKey: _selectedKey,
        button: _selectedButton,
      );
      setState(() {});
    }
  }

  final List<String> _allSupportedKeys = [
    // Function Keys
    ...List.generate(12, (i) => 'F${i + 1}'),
    // Alpha Keys
    ...List.generate(26, (i) => String.fromCharCode(65 + i)),
    // Special & Mouse
    'SHIFT',
    'CTRL',
    'ALT',
    'BTN_LEFT',
    'BTN_MIDDLE',
    'BTN_RIGHT',
    'SPACE',
    'ENTER',
  ];

  // variables | args
  double _interval = 25;
  String _selectedKey = 'X';
  String _selectedButton = 'right';
  bool _isActive = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        //borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Title('WayClicker GUI'),
            // --- Interval Section ---
            _sectionHeader("Speed (Interval)"),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _interval,
                    min: 1,
                    max: 1000,
                    onChanged: (val) => setState(() => _interval = val),
                  ),
                ),
                Text(
                  "${_interval.toInt()}ms",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    //width: 50,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            // --- Toggle Key Section ---
            _sectionHeader("Activation Toggle"),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              initialSelection: _selectedKey,
              enableSearch: true,
              menuHeight: 300,
              label: const Text("Select Key"),
              onSelected: (val) => setState(() => _selectedKey = val!),
              dropdownMenuEntries: _allSupportedKeys.map((key) {
                return DropdownMenuEntry(
                  value: key,
                  label: key,
                  leadingIcon: key.contains('BTN')
                      ? const Icon(Icons.mouse)
                      : const Icon(Icons.keyboard),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // --- Mouse Button Section ---
            _sectionHeader("Target Mouse Button"),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'left',
                    label: Text('Left'),
                    icon: Icon(Icons.mouse),
                  ),
                  ButtonSegment(
                    value: 'middle',
                    label: Text('Middle'),
                    icon: Icon(Icons.mouse),
                  ),
                  ButtonSegment(
                    value: 'right',
                    label: Text('Right'),
                    icon: Icon(Icons.mouse),
                  ),
                ],
                selected: {_selectedButton},
                onSelectionChanged: (val) =>
                    setState(() => _selectedButton = val.first),
              ),
            ),
            const SizedBox(height: 40),

            // --- Action Button ---
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () async {
                  if (_controller.isRunning) {
                    _controller.stop();
                  } else {
                    await _controller.start(
                      interval: _interval.toInt(),
                      toggleKey: _selectedKey,
                      button: _selectedButton,
                    );
                  }
                  setState(() {
                    _isActive = _controller.isRunning;
                  });
                },
                style: FilledButton.styleFrom(
                  // Use the controller's state for the color
                  backgroundColor: _controller.isRunning
                      ? Colors.redAccent
                      : null,
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
            _sectionHeader("Live Console Output"),

            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: StreamBuilder<String>(
                  stream: _controller.logStream,
                  builder: (context, snapshot) {
                    // If there's an error or no data yet
                    if (snapshot.hasError)
                      return Text(
                        "Error: ${snapshot.error}",
                        style: const TextStyle(color: Colors.red),
                      );
                    if (!snapshot.hasData)
                      return const Text(
                        "Waiting for service...",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      );

                    return SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        snapshot.data!,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _Title(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title.toUpperCase(),
        //textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
