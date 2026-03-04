// ============================================================
//  control_screen.dart  —  Pantalla 1: Control del robot
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/robot_state.dart';
import '../services/ble_service.dart';
import '../widgets/bubble_level.dart';
import '../widgets/control_pad.dart';

// ============================================================
class ControlScreen extends StatefulWidget {
  final BleService ble;
  const ControlScreen({super.key, required this.ble});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();

    // Trigger haptic when fall is detected
    if (state.fallDetected) {
      HapticFeedback.heavyImpact();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // ── Advertencia de desconexión ──────────────────────
          if (!state.isConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.15),
                border: Border.all(color: AppColors.orange, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bluetooth_disabled,
                      color: AppColors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Robot no conectado. Ve a Config para escanear.',
                      style:
                          TextStyle(color: AppColors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // ── Burbuja de nivel ────────────────────────────────
          BubbleLevel(
            pitchDeg: state.telemetry.pitchDeg,
            rollDeg: state.telemetry.rollDeg,
          ),

          const SizedBox(height: 8),

          // ── Valores numéricos Pitch / Roll ──────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _imuValue('PITCH',
                  '${state.telemetry.pitchDeg.toStringAsFixed(1)}°',
                  state.telemetry.pitchDeg),
              _imuValue('ROLL',
                  '${state.telemetry.rollDeg.toStringAsFixed(1)}°',
                  state.telemetry.rollDeg),
              _imuLabel('ACCEL Y',
                  '${state.telemetry.accelY.toStringAsFixed(2)} g'),
            ],
          ),

          const SizedBox(height: 16),

          // ── Pad de control ──────────────────────────────────
          ControlPad(
              ble: widget.ble, activeCommand: state.activeCommand),

          const SizedBox(height: 16),

          // ── Botón STOP grande ───────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
              icon: const Icon(Icons.stop_rounded, size: 28),
              label: const Text(
                'STOP',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              onPressed: () => widget.ble.sendCommand(GaitCommand.stop),
            ),
          ),

          const SizedBox(height: 12),

          // ── Botón RECUPERAR CAÍDA ────────────────────────────
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              final fallen = state.fallDetected;
              return Opacity(
                opacity: fallen ? _pulseAnim.value : 1.0,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: fallen
                          ? AppColors.orange
                          : AppColors.cardBg,
                      foregroundColor: fallen
                          ? Colors.white
                          : AppColors.textSecond,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(
                      Icons.sync_rounded,
                      size: 22,
                      color: fallen
                          ? Colors.white
                          : AppColors.textSecond,
                    ),
                    label: const Text(
                      'RECUPERAR CAÍDA',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    onPressed: fallen
                        ? () {
                            HapticFeedback.heavyImpact();
                            widget.ble.sendRecovery();
                          }
                        : null,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _imuValue(String label, String value, double degrees) {
    Color col;
    final abs = degrees.abs();
    if (abs < 15) {
      col = AppColors.green;
    } else if (abs < 45) {
      col = AppColors.orange;
    } else {
      col = AppColors.red;
    }
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecond,
                letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: col)),
      ],
    );
  }

  Widget _imuLabel(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecond,
                letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.cyan)),
      ],
    );
  }
}
