// ============================================================
//  config_screen.dart  —  Pantalla 3: BLE + Calibración + Params
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/robot_state.dart';
import '../services/ble_service.dart';

// ============================================================
class ConfigScreen extends StatefulWidget {
  final BleService ble;
  const ConfigScreen({super.key, required this.ble});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late RobotParams _params;
  final _trimValues = List<double>.filled(8, 0.0);

  static const _servoNames = [
    'S1 Cadera Flex Izq', 'S2 Cadera Abd Izq',
    'S3 Rodilla Izq',     'S4 Tobillo Izq',
    'S5 Cadera Flex Der', 'S6 Cadera Abd Der',
    'S7 Rodilla Der',     'S8 Tobillo Der',
  ];

  @override
  void initState() {
    super.initState();
    _params = context.read<RobotState>().params.copyWith();
  }

  // ── Scan helpers ────────────────────────────────────────
  Future<void> _startScan(RobotState state) async {
    state.updateScanning(true);
    await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8));
    if (mounted) state.updateScanning(false);
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // ── Send all params ──────────────────────────────────────
  void _sendParams() => widget.ble.sendParams(_params);

  // ── Reset trims ──────────────────────────────────────────
  void _resetTrims() {
    setState(() {
      for (int i = 0; i < 8; i++) {
        _trimValues[i] = 0.0;
      }
    });
    for (int i = 0; i < 8; i++) {
      widget.ble.sendTrim(i, 0.0);
    }
  }

  // ── Save trims ───────────────────────────────────────────
  void _saveTrims() {
    for (int i = 0; i < 8; i++) {
      widget.ble.sendTrim(i, _trimValues[i]);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trims enviados al robot'),
        backgroundColor: AppColors.cardBg,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── SECCIÓN BLUETOOTH ───────────────────────────────
          _sectionHeader('BLUETOOTH', Icons.bluetooth_rounded),
          const SizedBox(height: 8),
          _BleSection(
            ble: widget.ble,
            state: state,
            onScan: () => _startScan(state),
            onStop: _stopScan,
          ),

          const SizedBox(height: 20),

          // ── SECCIÓN CALIBRACIÓN ──────────────────────────────
          _sectionHeader(
              'CALIBRACIÓN POSICIÓN CERO', Icons.tune_rounded),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ...List.generate(8, (i) => _trimRow(i)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecond,
                          side: const BorderSide(
                              color: AppColors.textSecond),
                        ),
                        onPressed: _resetTrims,
                        icon: const Icon(Icons.restart_alt_rounded,
                            size: 18),
                        label: const Text('↺ Reset'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: AppColors.background,
                        ),
                        onPressed: _saveTrims,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('💾 Guardar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── SECCIÓN PARÁMETROS DE MARCHA ────────────────────
          _sectionHeader(
              'PARÁMETROS DE MARCHA', Icons.directions_walk_rounded),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _sliderRow('Longitud paso', _params.stepLength, 1.0,
                    4.0, 'cm',
                    (v) => setState(() => _params.stepLength = v)),
                _sliderRow('Altura paso', _params.stepHeight, 1.0,
                    3.0, 'cm',
                    (v) => setState(() => _params.stepHeight = v)),
                _sliderRow('Duración swing', _params.tSwing, 0.5,
                    2.0, 's',
                    (v) => setState(() => _params.tSwing = v)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── SECCIÓN PID ─────────────────────────────────────
          _sectionHeader(
              'PID ESTABILIDAD', Icons.balance_rounded),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _sliderRow(
                    'Kp (proporcional)', _params.kp, 0.1, 3.0, '',
                    (v) => setState(() => _params.kp = v),
                    decimals: 2),
                _sliderRow(
                    'Kd (derivativo)', _params.kd, 0.001, 0.1, '',
                    (v) => setState(() => _params.kd = v),
                    decimals: 3),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Botón Enviar global ──────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _sendParams,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar parámetros al robot',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.cyan),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.cyan,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _trimRow(int idx) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(_servoNames[idx],
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecond)),
        ),
        Expanded(
          child: Slider(
            value: _trimValues[idx],
            min: -10.0 * 3.14159 / 180,
            max: 10.0 * 3.14159 / 180,
            divisions: 40,
            activeColor: AppColors.cyan,
            onChanged: (v) => setState(() => _trimValues[idx] = v),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(_trimValues[idx] * 180 / 3.14159).toStringAsFixed(1)}°',
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.cyan,
                fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      String unit, ValueChanged<double> onChanged,
      {int decimals = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecond)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: AppColors.cyan,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${value.toStringAsFixed(decimals)}$unit',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.cyan,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget de sección BLE ───────────────────────────────────
class _BleSection extends StatelessWidget {
  final BleService ble;
  final RobotState state;
  final VoidCallback onScan;
  final VoidCallback onStop;

  const _BleSection({
    required this.ble,
    required this.state,
    required this.onScan,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Connection status row
          Row(
            children: [
              Icon(
                state.isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: state.isConnected
                    ? AppColors.green
                    : AppColors.textSecond,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.isConnected
                      ? 'Conectado: ${state.connectedDevName}'
                      : 'Sin conexión',
                  style: TextStyle(
                    fontSize: 13,
                    color: state.isConnected
                        ? AppColors.green
                        : AppColors.textSecond,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (state.isConnected)
                TextButton(
                  onPressed: () => ble.disconnect(),
                  child: const Text('Desconectar',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.red)),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Scan button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cyan,
                side: const BorderSide(color: AppColors.cyan),
              ),
              onPressed: state.isScanning ? onStop : onScan,
              icon: state.isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.cyan),
                    )
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(
                  state.isScanning ? 'Detener escaneo' : 'Escanear BLE'),
            ),
          ),

          const SizedBox(height: 8),

          // Scan results
          StreamBuilder<List<ScanResult>>(
            stream: ble.scanResults,
            builder: (ctx, snap) {
              final results = snap.data ?? [];
              if (results.isEmpty && !state.isScanning) {
                return const SizedBox.shrink();
              }
              if (results.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Buscando dispositivos...',
                      style: TextStyle(
                          color: AppColors.textSecond, fontSize: 12)),
                );
              }
              return Column(
                children: results.map((r) {
                  final name = r.device.platformName.isEmpty
                      ? r.device.remoteId.toString()
                      : r.device.platformName;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.bluetooth,
                        color: AppColors.cyan, size: 18),
                    title: Text(name,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text('RSSI: ${r.rssi} dBm',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecond)),
                    trailing: TextButton(
                      onPressed: () async {
                        await FlutterBluePlus.stopScan();
                        await ble.connectToDevice(r.device);
                      },
                      child: const Text('Conectar',
                          style: TextStyle(
                              color: AppColors.cyan, fontSize: 12)),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
