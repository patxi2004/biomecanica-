// ============================================================
//  main.dart  —  Punto de entrada de la app Flutter
//  Control de robot bípedo 8-DOF vía BLE
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/robot_state.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => RobotState(),
      child: const BipedApp(),
    ),
  );
}

class BipedApp extends StatelessWidget {
  const BipedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bípedo 8-DOF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
