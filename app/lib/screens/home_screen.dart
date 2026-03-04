// ============================================================
//  home_screen.dart  —  Pantalla principal de control
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../models/robot_state.dart';
import '../services/ble_service.dart';
import '../widgets/control_pad.dart';
import '../widgets/telemetry_panel.dart';

// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final BleService _ble;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _ble  = BleService(context.read<RobotState>());
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _ble.disconnect();
    _tabs.dispose();
    super.dispose();
  }

  // ─── Dialogo de escaneo ────────────────────────────────
  Future<void> _showScanDialog() async {
    final state = context.read<RobotState>();
    await showDialog(
      context: context,
      builder: (ctx) => _ScanDialog(ble: _ble, state: state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();
    final cs    = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bípedo 8-DOF'),
        centerTitle: true,
        actions: [
          // ── Indicador y botón de conexión ────────────────
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: state.isConnected
                  ? () async {
                      await _ble.disconnect();
                    }
                  : _showScanDialog,
              icon: Icon(
                state.isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: state.isConnected ? cs.primary : cs.outline,
              ),
              label: Text(
                state.isConnected
                    ? state.connectedDevName
                    : 'Conectar',
                style: TextStyle(
                  color: state.isConnected ? cs.primary : cs.outline,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.gamepad_rounded),   text: 'Control'),
            Tab(icon: Icon(Icons.analytics_rounded), text: 'Telemetría'),
            Tab(icon: Icon(Icons.tune_rounded),      text: 'Parámetros'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ControlTab(ble: _ble),
          _TelemetryTab(),
          _ParamsTab(ble: _ble),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  PESTAÑA CONTROL
// ────────────────────────────────────────────────────────────
class _ControlTab extends StatelessWidget {
  final BleService ble;
  const _ControlTab({required this.ble});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();
    final cs    = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (!state.isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Robot no conectado. Toca "Conectar" en la barra superior.',
                      style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),

          // ── Pad de control ─────────────────────────────────
          ControlPad(ble: ble, activeCommand: state.activeCommand),
          const SizedBox(height: 32),

          // ── Inclinación rápida ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.device_thermostat,
                  color: cs.outline, size: 16),
              const SizedBox(width: 4),
              Text(
                'Pitch: ${state.telemetry.pitchDeg.toStringAsFixed(1)}°  '
                'Roll: ${state.telemetry.rollDeg.toStringAsFixed(1)}°',
                style: TextStyle(
                  color: cs.outline,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  PESTAÑA TELEMETRÍA
// ────────────────────────────────────────────────────────────
class _TelemetryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: TelemetryPanel(
        telemetry:    state.telemetry,
        pitchHistory: state.pitchHistory,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  PESTAÑA PARÁMETROS
// ────────────────────────────────────────────────────────────
class _ParamsTab extends StatefulWidget {
  final BleService ble;
  const _ParamsTab({required this.ble});

  @override
  State<_ParamsTab> createState() => _ParamsTabState();
}

class _ParamsTabState extends State<_ParamsTab> {
  late RobotParams _params;

  @override
  void initState() {
    super.initState();
    _params = context.read<RobotState>().params;
  }

  void _send() => widget.ble.sendParams(_params);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Control PD de Postura'),
          _slider(context, 'Kp (proporcional)',
              _params.kp, 0.1, 3.0, (v) => setState(() => _params.kp = v)),
          _slider(context, 'Kd (derivativo)',
              _params.kd, 0.001, 0.1, (v) => setState(() => _params.kd = v)),

          const SizedBox(height: 16),
          _sectionTitle(context, 'Parámetros de Marcha'),
          _slider(context, 'Longitud paso (cm)',
              _params.stepLength, 1.0, 5.0, (v) => setState(() => _params.stepLength = v)),
          _slider(context, 'Altura paso (cm)',
              _params.stepHeight, 0.5, 3.5, (v) => setState(() => _params.stepHeight = v)),
          _slider(context, 'Duración swing (s)',
              _params.tSwing, 0.3, 1.5, (v) => setState(() => _params.tSwing = v)),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _send,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar al robot'),
            ),
          ),

          const SizedBox(height: 32),
          _sectionTitle(context, 'Ajuste de Trim (servos)'),
          const SizedBox(height: 8),
          ...List.generate(8, (i) => _trimRow(context, i)),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext ctx, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(ctx).colorScheme.primary)),
      );

  Widget _slider(BuildContext ctx, String label, double value,
      double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(value.toStringAsFixed(3),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.primary)),
          ],
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  // ─── Fila de trim por servo ─────────────────────────────
  static const _servoNames = [
    'S1 — Cadera Flex Izq', 'S2 — Cadera Abd Izq',
    'S3 — Rodilla Izq',    'S4 — Tobillo Izq',
    'S5 — Cadera Flex Der', 'S6 — Cadera Abd Der',
    'S7 — Rodilla Der',    'S8 — Tobillo Der',
  ];

  final _trimValues = List<double>.filled(8, 0.0);

  Widget _trimRow(BuildContext ctx, int idx) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(_servoNames[idx], style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          flex: 4,
          child: Slider(
            value: _trimValues[idx],
            min: -0.2, max: 0.2, divisions: 40,
            label: '${(_trimValues[idx] * 180 / 3.14159).toStringAsFixed(1)}°',
            onChanged: (v) =>
                setState(() => _trimValues[idx] = v),
            onChangeEnd: (v) => widget.ble.sendTrim(idx, v),
          ),
        ),
        Text(
          '${(_trimValues[idx] * 180 / 3.14159).toStringAsFixed(1)}°',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
//  DIALOGO DE ESCANEO BLE
// ────────────────────────────────────────────────────────────
class _ScanDialog extends StatefulWidget {
  final BleService ble;
  final RobotState state;
  const _ScanDialog({required this.ble, required this.state});

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    widget.state.updateScanning(true);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    if (mounted) widget.state.updateScanning(false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();
    return AlertDialog(
      title: Row(
        children: [
          if (state.isScanning)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          const Text('Buscar robot'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: StreamBuilder<List<ScanResult>>(
          stream: widget.ble.scanResults,
          builder: (ctx, snap) {
            final results = snap.data ?? [];
            if (results.isEmpty) {
              return Center(
                child: Text(
                  state.isScanning
                      ? 'Buscando dispositivos BLE...'
                      : 'No se encontraron dispositivos.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            return ListView.builder(
              itemCount: results.length,
              itemBuilder: (ctx, i) {
                final r = results[i];
                final name = r.device.platformName.isEmpty
                    ? r.device.remoteId.toString()
                    : r.device.platformName;
                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(name),
                  subtitle: Text('RSSI: ${r.rssi} dBm'),
                  onTap: () async {
                    await FlutterBluePlus.stopScan();
                    Navigator.of(context).pop();
                    await widget.ble.connectToDevice(r.device);
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await FlutterBluePlus.stopScan();
            Navigator.of(context).pop();
          },
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
