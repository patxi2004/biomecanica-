// ============================================================
//  control_pad.dart  —  Pad de control direccional del robot
// ============================================================

import 'package:flutter/material.dart';

import '../models/robot_state.dart';
import '../services/ble_service.dart';

class ControlPad extends StatelessWidget {
  final BleService ble;
  final GaitCommand activeCommand;

  const ControlPad({
    super.key,
    required this.ble,
    required this.activeCommand,
  });

  // ─── Color del botón según estado ─────────────────────
  Color _btnColor(GaitCommand cmd, BuildContext context) {
    return activeCommand == cmd
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceVariant;
  }

  // ─── Botón individual ──────────────────────────────────
  Widget _btn({
    required BuildContext context,
    required IconData icon,
    required GaitCommand cmd,
    required VoidCallback onPressed,
    VoidCallback? onReleased,
  }) {
    final isActive = activeCommand == cmd;
    return GestureDetector(
      onTapDown: (_) => onPressed(),
      onTapUp:   (_) => onReleased?.call(),
      onTapCancel: () => onReleased?.call(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: _btnColor(cmd, context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive
              ? [BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                )]
              : [],
        ),
        child: Icon(
          icon,
          size: 32,
          color: isActive
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Fila superior: AVANZAR ──────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _btn(
              context: context,
              icon: Icons.arrow_upward_rounded,
              cmd: GaitCommand.forward,
              onPressed: () => ble.sendCommand(GaitCommand.forward),
              onReleased: () => ble.sendCommand(GaitCommand.stop),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Fila media: GIRO IZQ | STOP | GIRO DER ─────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _btn(
              context: context,
              icon: Icons.rotate_left_rounded,
              cmd: GaitCommand.turnLeft,
              onPressed: () => ble.sendCommand(GaitCommand.turnLeft),
              onReleased: () => ble.sendCommand(GaitCommand.stop),
            ),
            const SizedBox(width: 8),
            _btn(
              context: context,
              icon: Icons.stop_rounded,
              cmd: GaitCommand.stop,
              onPressed: () => ble.sendCommand(GaitCommand.stand),
            ),
            const SizedBox(width: 8),
            _btn(
              context: context,
              icon: Icons.rotate_right_rounded,
              cmd: GaitCommand.turnRight,
              onPressed: () => ble.sendCommand(GaitCommand.turnRight),
              onReleased: () => ble.sendCommand(GaitCommand.stop),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Fila inferior: RETROCEDER ───────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _btn(
              context: context,
              icon: Icons.arrow_downward_rounded,
              cmd: GaitCommand.backward,
              onPressed: () => ble.sendCommand(GaitCommand.backward),
              onReleased: () => ble.sendCommand(GaitCommand.stop),
            ),
          ],
        ),
      ],
    );
  }
}
