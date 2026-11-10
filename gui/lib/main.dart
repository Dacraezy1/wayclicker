import 'package:flutter/material.dart';
import 'package:wayclicker_gui/pages/home.dart';

void main() {
  runApp(const WayclickerApp());
}

class WayclickerApp extends StatelessWidget {
  const WayclickerApp({super.key});

  static const Color _seed = Color(0xFF5B5BD6);

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wayclicker',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
