import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Names for USB-HID keyboard usages that are not covered by the ranges in
/// [keyNameForPhysical]. Values are names understood by the `wayclicker` CLI.
const Map<int, String> _otherKeys = {
  0x28: 'ENTER',
  0x29: 'ESC',
  0x2A: 'BACKSPACE',
  0x2B: 'TAB',
  0x2C: 'SPACE',
  0x2D: 'minus',
  0x2E: 'equal',
  0x2F: 'leftbrace',
  0x30: 'rightbrace',
  0x31: 'backslash',
  0x33: 'semicolon',
  0x34: 'apostrophe',
  0x35: 'grave',
  0x36: 'comma',
  0x37: 'dot',
  0x38: 'slash',
  0x39: 'CAPSLOCK',
  0x46: 'printscreen',
  0x47: 'scrolllock',
  0x48: 'pause',
  0x49: 'INSERT',
  0x4A: 'HOME',
  0x4B: 'PAGEUP',
  0x4C: 'DELETE',
  0x4D: 'END',
  0x4E: 'PAGEDOWN',
  0x4F: 'arrowright',
  0x50: 'arrowleft',
  0x51: 'arrowdown',
  0x52: 'arrowup',
  0x53: 'numlock',
  0x54: 'kpslash',
  0x55: 'kpasterisk',
  0x56: 'kpminus',
  0x57: 'kpplus',
  0x58: 'kpenter',
  0x62: 'KP0',
  0x63: 'kpdot',
  0x65: 'menu',
};

/// Modifier usages -> generic name (either the left or the right key works).
const Map<int, String> _modifierKeys = {
  0xE0: 'ctrl',
  0xE1: 'shift',
  0xE2: 'alt',
  0xE3: 'super',
  0xE4: 'ctrl',
  0xE5: 'shift',
  0xE6: 'alt',
  0xE7: 'super',
};

// PointerEvent.buttons bit flags (same values as Flutter's k*MouseButton constants).
const int _buttonSecondary = 0x02;
const int _buttonMiddle = 0x04;
const int _buttonBack = 0x08;
const int _buttonForward = 0x10;

const List<String> _modifierOrder = ['ctrl', 'alt', 'shift', 'super'];

int? _usbUsage(PhysicalKeyboardKey key) {
  final int id = key.usbHidUsage;
  // Page 0x07 is the USB keyboard page; anything else is an unmapped key.
  if ((id >> 16) != 0x0007) return null;
  return id & 0xFFFF;
}

/// Converts a physical key (layout independent, like the kernel's evdev codes)
/// into a key name the wayclicker CLI understands. Returns null if unknown.
String? keyNameForPhysical(PhysicalKeyboardKey key) {
  final int? usage = _usbUsage(key);
  if (usage == null) return null;
  if (_modifierKeys.containsKey(usage)) return _modifierKeys[usage];
  if (usage >= 0x04 && usage <= 0x1D) {
    return String.fromCharCode(0x41 + usage - 0x04); // A-Z
  }
  if (usage >= 0x1E && usage <= 0x26) return '${usage - 0x1E + 1}'; // 1-9
  if (usage == 0x27) return '0';
  if (usage >= 0x3A && usage <= 0x45) return 'F${usage - 0x3A + 1}'; // F1-F12
  if (usage >= 0x68 && usage <= 0x73) return 'F${usage - 0x68 + 13}'; // F13-F24
  if (usage >= 0x59 && usage <= 0x61) return 'KP${usage - 0x59 + 1}'; // KP1-KP9
  return _otherKeys[usage];
}

String? _modifierFor(PhysicalKeyboardKey key) {
  final int? usage = _usbUsage(key);
  if (usage == null) return null;
  return _modifierKeys[usage];
}

/// A text field for entering a key, mouse button or key combination
/// (e.g. `F13`, `ctrl+alt+c`, `shift+BTN_SIDE`) with a "Record" button that
/// captures the next key combination you press, and a drop-down of common keys.
class KeyBindField extends StatefulWidget {
  const KeyBindField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.presets = const [],
    this.presetLabel,
    this.allowMouse = true,
    this.helper,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  /// Common values offered in the drop-down list.
  final List<String> presets;

  /// Optional prettier label for a preset value.
  final String Function(String value)? presetLabel;

  /// Whether mouse buttons (middle / right / side / extra) can be recorded.
  final bool allowMouse;

  final String? helper;

  @override
  State<KeyBindField> createState() => _KeyBindFieldState();
}

class _KeyBindFieldState extends State<KeyBindField> {
  late final TextEditingController _text;
  bool _recording = false;
  bool _attached = false;
  final Set<String> _mods = <String>{};

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(KeyBindField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _text.text.trim()) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _detach();
    _text.dispose();
    super.dispose();
  }

  void _attach() {
    if (_attached) return;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _attached = true;
  }

  void _detach() {
    if (!_attached) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _attached = false;
  }

  void _startRecording() {
    setState(() {
      _recording = true;
      _mods.clear();
    });
    _attach();
  }

  void _stopRecording() {
    _detach();
    if (mounted) {
      setState(() {
        _recording = false;
        _mods.clear();
      });
    }
  }

  List<String> _orderedMods() =>
      _modifierOrder.where(_mods.contains).toList(growable: true);

  void _setValue(String v) {
    _text.text = v;
    widget.onChanged(v);
  }

  void _finish(List<String> parts) {
    _setValue(parts.join('+'));
    _stopRecording();
  }

  bool _onKey(KeyEvent event) {
    if (!_recording) return false;

    final String? name = keyNameForPhysical(event.physicalKey);
    if (name == null) return true; // swallow keys we cannot represent
    final String? mod = _modifierFor(event.physicalKey);

    if (event is KeyDownEvent) {
      if (mod != null) {
        setState(() => _mods.add(mod));
        return true;
      }
      if (name == 'ESC' && _mods.isEmpty) {
        _stopRecording(); // Esc alone cancels recording
        return true;
      }
      _finish([..._orderedMods(), name]);
      return true;
    }

    if (event is KeyUpEvent && mod != null && _mods.isNotEmpty) {
      // Modifier(s) pressed and released on their own: bind the modifiers.
      _finish(_orderedMods());
      return true;
    }
    return true;
  }

  void _onPointer(PointerEvent event) {
    if (!_recording || !widget.allowMouse) return;
    if (event is! PointerDownEvent) return;

    final int b = event.buttons;
    String? name;
    if ((b & _buttonMiddle) != 0) {
      name = 'middle';
    } else if ((b & _buttonSecondary) != 0) {
      name = 'right';
    } else if ((b & _buttonBack) != 0) {
      name = 'BTN_SIDE';
    } else if ((b & _buttonForward) != 0) {
      name = 'BTN_EXTRA';
    }
    if (name != null) {
      _finish([..._orderedMods(), name]);
    }
  }

  String get _recordingHint {
    final String held = _orderedMods().join('+');
    final String mouse = widget.allowMouse ? ' or click a mouse button' : '';
    final String prefix = held.isEmpty ? '' : '$held + ';
    return 'Recording: ${prefix}press a key$mouse... (Esc cancels)';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                enabled: !_recording,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: 'e.g. F13, ctrl+alt+c',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (v) => widget.onChanged(v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _recording ? _stopRecording : _startRecording,
              icon: Icon(
                _recording
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record,
                size: 18,
                color: _recording ? null : Colors.redAccent,
              ),
              label: Text(_recording ? 'Cancel' : 'Record'),
            ),
            if (widget.presets.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Pick from common keys',
                icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                enabled: !_recording,
                onSelected: _setValue,
                itemBuilder: (context) => widget.presets
                    .map(
                      (p) => PopupMenuItem<String>(
                        value: p,
                        child: Text(widget.presetLabel?.call(p) ?? p),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _recording
              ? _recordingHint
              : (widget.helper ??
                    'Type any key name or combo joined with +, or press Record.'),
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: _recording ? colorScheme.primary : colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
