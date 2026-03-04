import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'bluetooth_service.dart';
import 'home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => BluetoothService(),
      child: const ExoApp(),
    ),
  );
}

class ExoApp extends StatelessWidget {
  const ExoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exo-Robot Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary:   Colors.cyanAccent,
          secondary: Colors.cyanAccent.shade700,
        ),
        sliderTheme: const SliderThemeData(
          thumbColor:           Colors.white,
          overlayColor:         Color(0x29FFFFFF),
          trackHeight:          4,
          inactiveTrackColor:   Color(0xFF444444),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
