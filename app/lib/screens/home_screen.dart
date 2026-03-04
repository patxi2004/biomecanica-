// ============================================================
//  home_screen.dart  —  Shell principal (BottomNavigationBar)
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/robot_state.dart';
import '../services/ble_service.dart';
import 'control_screen.dart';
import 'monitor_screen.dart';
import 'config_screen.dart';

// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final BleService _ble;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _ble = BleService(context.read<RobotState>());
  }

  @override
  void dispose() {
    _ble.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();

    return Scaffold(
      appBar: _buildAppBar(state),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ControlScreen(ble: _ble),
          const MonitorScreen(),
          ConfigScreen(ble: _ble),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.gamepad_outlined),
            selectedIcon: Icon(Icons.gamepad_rounded),
            label: 'Control',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Config',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(RobotState state) {
    Color btColor;
    String btLabel;
    if (state.isConnected) {
      btColor = AppColors.green;
      btLabel = state.connectedDevName;
    } else {
      btColor = AppColors.textSecond;
      btLabel = 'Desconectado';
    }

    String stabilityLabel;
    Color stabilityColor;
    if (state.fallDetected) {
      stabilityLabel = '⚠ CAÍDA';
      stabilityColor = AppColors.orange;
    } else if (state.telemetry.isFallen) {
      stabilityLabel = '⚠ ALERTA';
      stabilityColor = AppColors.orange;
    } else {
      stabilityLabel = '✓ ESTABLE';
      stabilityColor = AppColors.green;
    }

    return AppBar(
      title: const Text('🦿 BIPED CONTROL'),
      centerTitle: false,
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '🔋 ${state.batteryVoltage.toStringAsFixed(1)}V',
            style: const TextStyle(fontSize: 12, color: AppColors.green),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            stabilityLabel,
            style: TextStyle(
                fontSize: 11,
                color: stabilityColor,
                fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: GestureDetector(
            onTap: state.isConnected ? () => _ble.disconnect() : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: btColor,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(btLabel,
                    style: TextStyle(fontSize: 11, color: btColor)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


