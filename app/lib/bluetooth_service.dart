import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'package:flutter/foundation.dart';

// ================================================================
//  MODEL — datos de telemetría que envía el ESP32 cada 100 ms
// ================================================================

class TelemetryData {
  final double roll;
  final double pitch;
  final bool walking;
  final double speed;
  final double kp;
  final double kd;
  final bool fallen;
  final DateTime timestamp;

  TelemetryData({
    required this.roll,
    required this.pitch,
    required this.walking,
    required this.speed,
    required this.kp,
    required this.kd,
    required this.fallen,
  }) : timestamp = DateTime.now();

  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      roll:    (json['roll']  as num).toDouble(),
      pitch:   (json['pitch'] as num).toDouble(),
      walking: json['walking'] as bool,
      speed:   (json['speed'] as num).toDouble(),
      kp:      (json['kp']    as num).toDouble(),
      kd:      (json['kd']    as num).toDouble(),
      fallen:  json['fallen'] as bool,
    );
  }
}

// ================================================================
//  BluetoothService — ChangeNotifier para usar con Provider
// ================================================================

class BluetoothService extends ChangeNotifier {
  final _plugin = BluetoothClassic();

  // UUID SPP estándar (Serial Port Profile)
  static const _sppUuid = '00001101-0000-1000-8000-00805f9b34fb';

  // --- Estado ---
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // --- Última telemetría ---
  TelemetryData? _telemetry;
  TelemetryData? get telemetry => _telemetry;

  // --- Stream público de telemetría ---
  final _telemetryController = StreamController<TelemetryData>.broadcast();
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  // --- Buffer acumulativo (chunks de BT) ---
  String _rxBuffer = '';

  // --- Suscripciones internas ---
  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<int>?       _statusSub;

  // ----------------------------------------------------------------
  //  Inicialización y permisos — llamar en initState()
  // ----------------------------------------------------------------

  Future<void> init() async {
    await _plugin.initPermissions();
    _statusSub = _plugin.onDeviceStatusChanged().listen(_onStatusChanged);
  }

  void _onStatusChanged(int status) {
    // status: 0 = disconnected, 2 = connected
    if (status == 2 && !_isConnected) {
      _isConnected = true;
      notifyListeners();
    } else if (status == 0 && _isConnected) {
      _handleDisconnect();
    }
  }

  // ----------------------------------------------------------------
  //  Dispositivos emparejados
  // ----------------------------------------------------------------

  Future<List<Device>> getBondedDevices() async {
    try {
      return await _plugin.getPairedDevices();
    } catch (e) {
      debugPrint('[BT] Error listando dispositivos: $e');
      return [];
    }
  }

  // ----------------------------------------------------------------
  //  Conectar al ESP32
  // ----------------------------------------------------------------

  Future<bool> connect(Device device) async {
    try {
      debugPrint('[BT] Conectando a ${device.name} (${device.address})...');
      await _plugin.connect(device.address, _sppUuid);

      _dataSub = _plugin.onDeviceDataReceived().listen(
        _onDataReceived,
        onError: (e) {
          debugPrint('[BT] Error en stream: $e');
          _handleDisconnect();
        },
      );

      _isConnected = true;
      _rxBuffer    = '';
      notifyListeners();
      debugPrint('[BT] Conectado.');
      return true;
    } catch (e) {
      debugPrint('[BT] Error al conectar: $e');
      return false;
    }
  }

  // ----------------------------------------------------------------
  //  Manejo de chunks — buffer acumulativo separado por \n
  //
  //  Los mensajes llegan en trozos arbitrarios (chunks). Se acumulan
  //  en _rxBuffer y se extrae una línea completa por cada \n.
  // ----------------------------------------------------------------

  void _onDataReceived(Uint8List data) {
    _rxBuffer += utf8.decode(data, allowMalformed: true);

    int idx;
    while ((idx = _rxBuffer.indexOf('\n')) != -1) {
      final line = _rxBuffer.substring(0, idx).trim();
      _rxBuffer = _rxBuffer.substring(idx + 1);
      if (line.isNotEmpty) _parseTelemetry(line);
    }
  }

  void _parseTelemetry(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final td   = TelemetryData.fromJson(json);
      _telemetry = td;
      _telemetryController.add(td);
      notifyListeners();
    } catch (e) {
      debugPrint('[BT] JSON inválido: $raw');
    }
  }

  // ----------------------------------------------------------------
  //  Desconexión
  // ----------------------------------------------------------------

  void _handleDisconnect() {
    debugPrint('[BT] Desconectado.');
    _dataSub?.cancel();
    _dataSub     = null;
    _isConnected = false;
    _rxBuffer    = '';
    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      await _plugin.disconnect();
    } finally {
      _handleDisconnect();
    }
  }

  // ----------------------------------------------------------------
  //  Envío de comandos JSON al ESP32
  // ----------------------------------------------------------------

  Future<void> _send(Map<String, dynamic> payload) async {
    if (!_isConnected) return;
    try {
      await _plugin.write('${jsonEncode(payload)}\n');
    } catch (e) {
      debugPrint('[BT] Error al enviar: $e');
    }
  }

  void sendStart()            => _send({'cmd': 'START'});
  void sendStop()             => _send({'cmd': 'STOP'});
  void sendSpeed(double v)    => _send({'cmd': 'SPEED', 'val': v});
  void sendKp(double v)       => _send({'cmd': 'KP',    'val': v});
  void sendKd(double v)       => _send({'cmd': 'KD',    'val': v});
  void sendGetUp()            => _send({'cmd': 'GETUP'});

  // ----------------------------------------------------------------
  //  Modo Carrera — un tap con los parámetros óptimos calibrados
  // ----------------------------------------------------------------

  void sendRaceMode({
    double raceSpeed = 2.0,
    double raceKp    = 3.0,
    double raceKd    = 1.0,
  }) {
    sendStop();
    sendKp(raceKp);
    sendKd(raceKd);
    sendSpeed(raceSpeed);
    sendStart();
  }

  // ----------------------------------------------------------------
  //  Limpieza
  // ----------------------------------------------------------------

  @override
  void dispose() {
    _dataSub?.cancel();
    _statusSub?.cancel();
    _telemetryController.close();
    super.dispose();
  }
}
