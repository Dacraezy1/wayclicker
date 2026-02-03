import 'package:flutter/material.dart';
import 'package:wayclicker_gui/pages/home.dart';

void main() {
  runApp(const WayClicker());
}

class WayClicker extends StatelessWidget {
  const WayClicker({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      darkTheme: ThemeData(
        //useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
      ),
    );
  }
}
