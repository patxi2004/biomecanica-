import 'dart:async';
import 'dart:collection';

import 'package:bluetooth_classic/models/device.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'bluetooth_service.dart' as bt;

// ================================================================
//  HomeScreen — pantalla principal del controlador
// ================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- Parámetros locales (se envían al soltar el slider) ---
  double _speed = 1.0;
  double _kp    = 2.5;
  double _kd    = 0.8;

  // --- Gráfica: últimos 5 s de roll y pitch ---
  //  Guardamos los últimos 50 puntos (100 ms × 50 = 5 s)
  static const int _maxPoints = 50;
  final Queue<FlSpot> _rollPoints  = Queue();
  final Queue<FlSpot> _pitchPoints = Queue();
  double _chartTime = 0.0;

  StreamSubscription<bt.TelemetryData>? _telemetrySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<bt.BluetoothService>().init();
      _subscribeTelemetry();
    });
  }

  void _subscribeTelemetry() {
    final service = context.read<bt.BluetoothService>();
    _telemetrySub = service.telemetryStream.listen((td) {
      if (!mounted) return;
      setState(() {
        _chartTime += 0.1;
        _rollPoints.add(FlSpot(_chartTime, td.roll));
        _pitchPoints.add(FlSpot(_chartTime, td.pitch));
        if (_rollPoints.length  > _maxPoints) _rollPoints.removeFirst();
        if (_pitchPoints.length > _maxPoints) _pitchPoints.removeFirst();
        // Sincronizar parámetros recibidos con los sliders
        _speed = td.speed;
        _kp    = td.kp;
        _kd    = td.kd;
      });
    });
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------------
  //  Conexión / Escaneo
  // ----------------------------------------------------------------

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _showDevicePicker() async {
    await _requestPermissions();
    final service = context.read<bt.BluetoothService>();
    final devices = await service.getBondedDevices();

    if (!mounted) return;

    // Buscar "Exo-Robot" automáticamente
    final Device? exo = devices.where((d) => d.name == 'Exo-Robot').firstOrNull;

    if (exo == null) {
      _showPairingInstructions();
      return;
    }

    final ok = await service.connect(exo);
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar. Intenta emparejar de nuevo.')),
      );
    }
  }

  void _showPairingInstructions() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exo-Robot no encontrado'),
        content: const Text(
          'Ve a Ajustes → Bluetooth en tu Samsung y empareja '
          'el dispositivo "Exo-Robot".\n\nContraseña: 1234\n\n'
          'Después vuelve aquí y toca Conectar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  //  UI principal
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final service   = context.watch<bt.BluetoothService>();
    final telemetry = service.telemetry;
    final connected = service.isConnected;
    final fallen    = telemetry?.fallen ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, service, connected),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSection1(service, connected, telemetry),
                    const SizedBox(height: 12),
                    _buildSection2Chart(telemetry),
                    const SizedBox(height: 12),
                    _buildSection3Balance(service, connected),
                    const SizedBox(height: 12),
                    if (fallen) _buildGetUpButton(service),
                    const SizedBox(height: 8),
                    if (connected) _buildRaceButton(service),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  //  Sección 0 — Barra superior: estado de conexión
  // ----------------------------------------------------------------

  Widget _buildTopBar(
    BuildContext context,
    bt.BluetoothService service,
    bool connected,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: connected ? Colors.greenAccent : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            connected ? 'Conectado — Exo-Robot' : 'Desconectado',
            style: TextStyle(
              color: connected ? Colors.greenAccent : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: connected
                ? () => service.disconnect()
                : _showDevicePicker,
            child: Text(connected ? 'Desconectar' : 'Conectar'),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  //  Sección 1 — START/STOP + Slider velocidad
  // ----------------------------------------------------------------

  Widget _buildSection1(
    bt.BluetoothService service,
    bool connected,
    bt.TelemetryData? td,
  ) {
    final walking = td?.walking ?? false;

    return _card(
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: connected
                  ? () => walking ? service.sendStop() : service.sendStart()
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: walking ? Colors.redAccent : Colors.greenAccent,
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(walking ? 'STOP' : 'START'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Velocidad', style: TextStyle(color: Colors.white70)),
              const Spacer(),
              Text(
                '${_speed.toStringAsFixed(1)}×',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: _speed,
            min: 0.3,
            max: 3.0,
            divisions: 27,
            activeColor: Colors.cyanAccent,
            onChanged: connected ? (v) => setState(() => _speed = v) : null,
            onChangeEnd: connected ? (v) => service.sendSpeed(v) : null,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  //  Sección 2 — Gráfica roll y pitch (últimos 5 s)
  // ----------------------------------------------------------------

  Widget _buildSection2Chart(bt.TelemetryData? td) {
    final rollList  = _rollPoints.toList();
    final pitchList = _pitchPoints.toList();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legend(Colors.cyanAccent, 'Roll  ${td?.roll.toStringAsFixed(1) ?? '--'}°'),
              const SizedBox(width: 16),
              _legend(Colors.orangeAccent, 'Pitch ${td?.pitch.toStringAsFixed(1) ?? '--'}°'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: rollList.isEmpty
                ? const Center(
                    child: Text('Sin datos', style: TextStyle(color: Colors.white38)),
                  )
                : LineChart(
                    LineChartData(
                      minY: -60,
                      maxY:  60,
                      clipData: const FlClipData.all(),
                      gridData: FlGridData(
                        show: true,
                        getDrawingHorizontalLine: (_) =>
                            const FlLine(color: Color(0xFF303030), strokeWidth: 1),
                        getDrawingVerticalLine: (_) =>
                            const FlLine(color: Color(0xFF303030), strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}°',
                              style: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ),
                        ),
                        bottomTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      lineBarsData: [
                        // Línea de Roll
                        LineChartBarData(
                          spots: rollList,
                          isCurved: true,
                          color: Colors.cyanAccent,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                        ),
                        // Línea de Pitch
                        LineChartBarData(
                          spots: pitchList,
                          isCurved: true,
                          color: Colors.orangeAccent,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                        ),
                        // Línea de umbral de caída (±45°)
                        LineChartBarData(
                          spots: rollList.isNotEmpty
                              ? [
                                  FlSpot(rollList.first.x, 45),
                                  FlSpot(rollList.last.x,  45),
                                ]
                              : [],
                          color: Colors.red.withOpacity(0.5),
                          barWidth: 1,
                          dotData: const FlDotData(show: false),
                          dashArray: [4, 4],
                        ),
                        LineChartBarData(
                          spots: rollList.isNotEmpty
                              ? [
                                  FlSpot(rollList.first.x, -45),
                                  FlSpot(rollList.last.x,  -45),
                                ]
                              : [],
                          color: Colors.red.withOpacity(0.5),
                          barWidth: 1,
                          dotData: const FlDotData(show: false),
                          dashArray: [4, 4],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  //  Sección 3 — Sliders Kp y Kd
  // ----------------------------------------------------------------

  Widget _buildSection3Balance(bt.BluetoothService service, bool connected) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Controlador de balance (PD)',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _labeledSlider(
            label: 'Kp',
            value: _kp,
            min: 0.1,
            max: 10.0,
            divisions: 99,
            color: Colors.purpleAccent,
            enabled: connected,
            onChanged: (v) => setState(() => _kp = v),
            onChangeEnd: (v) => service.sendKp(v),
          ),
          _labeledSlider(
            label: 'Kd',
            value: _kd,
            min: 0.0,
            max: 3.0,
            divisions: 30,
            color: Colors.tealAccent,
            enabled: connected,
            onChanged: (v) => setState(() => _kd = v),
            onChangeEnd: (v) => service.sendKd(v),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  //  Sección 4 — Botón GETUP (solo visible cuando fallen = true)
  // ----------------------------------------------------------------

  Widget _buildGetUpButton(bt.BluetoothService service) {
    return SizedBox(
      width: double.infinity,
      height: 72,
      child: ElevatedButton.icon(
        onPressed: service.sendGetUp,
        icon: const Icon(Icons.accessibility_new, size: 28),
        label: const Text('LEVANTARSE', style: TextStyle(fontSize: 20, letterSpacing: 2)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  //  Botón MODO CARRERA
  // ----------------------------------------------------------------

  Widget _buildRaceButton(bt.BluetoothService service) {
    return OutlinedButton.icon(
      onPressed: service.sendRaceMode,
      icon: const Icon(Icons.flash_on, color: Colors.yellowAccent),
      label: const Text(
        'MODO CARRERA',
        style: TextStyle(color: Colors.yellowAccent, letterSpacing: 1.5),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.yellowAccent),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ----------------------------------------------------------------
  //  Helpers de UI
  // ----------------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _labeledSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color color,
    required bool enabled,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: color,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}
