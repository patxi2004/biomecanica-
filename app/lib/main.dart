// ============================================================
//  main.dart  —  Punto de entrada de la app Flutter
//  Control de robot bípedo 8-DOF vía BLE
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/robot_state.dart';
import 'screens/home_screen.dart';

// ─── Paleta industrial oscura ──────────────────────────────
class AppColors {
  static const background   = Color(0xFF0D0D0D);
  static const cardBg       = Color(0xFF1A1A2E);
  static const cyan         = Color(0xFF00D4FF);
  static const orange       = Color(0xFFFF8C00);
  static const red          = Color(0xFFFF3A3A);
  static const green        = Color(0xFF00FF88);
  static const textPrimary  = Color(0xFFFFFFFF);
  static const textSecond   = Color(0xFF8A8A9A);
  static const divider      = Color(0xFF2A2A3E);
}

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
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          background:       AppColors.background,
          surface:          AppColors.cardBg,
          surfaceVariant:   AppColors.cardBg,
          primary:          AppColors.cyan,
          secondary:        AppColors.green,
          error:            AppColors.red,
          onBackground:     AppColors.textPrimary,
          onSurface:        AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecond,
          onPrimary:        AppColors.background,
          outline:          AppColors.textSecond,
        ),
        cardColor: AppColors.cardBg,
        dividerColor: AppColors.divider,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.cardBg,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.cardBg,
          indicatorColor: AppColors.cyan.withOpacity(0.18),
          iconTheme: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const IconThemeData(color: AppColors.cyan);
            }
            return const IconThemeData(color: AppColors.textSecond);
          }),
          labelTextStyle: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const TextStyle(
                  color: AppColors.cyan, fontSize: 11,
                  fontWeight: FontWeight.w600);
            }
            return const TextStyle(color: AppColors.textSecond, fontSize: 11);
          }),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.cyan,
          thumbColor: AppColors.cyan,
          inactiveTrackColor: AppColors.divider,
          overlayColor: AppColors.cyan.withOpacity(0.15),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: AppColors.textPrimary),
          bodySmall:  TextStyle(color: AppColors.textSecond),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
