// ============================================================
//  ble_service.dart  —  Gestión de la conexión BLE
//  Protocolo Nordic UART (NUS)
//
//  ESP32 → App (notify):
//    "IMU:pitch:roll:accelY"           [rad, rad, g]
//    "ZMP:x:y"                         [cm]
//    "PHASE:nombre"
//    "SERVO:s0:s1:s2:s3:s4:s5:s6:s7"  [grados]
//    "BATT:7.4"                        [V]
//
//  App → ESP32 (write):
//    "CMD:FORWARD|BACKWARD|TURN_LEFT|TURN_RIGHT|STOP|STAND|RECOVER"
//    "PARAM:KP:1.2"
//    "PARAM:KD:0.03"
//    "PARAM:STEP_LEN:2.5"
//    "PARAM:STEP_H:1.8"
//    "PARAM:T_SWING:0.7"
//    "TRIM:0:0.05"
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/widgets.dart';

import '../models/robot_state.dart';

const String _kNusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _kNusRxUuid      = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const String _kNusTxUuid      = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

class BleService {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;

  StreamSubscription<List<int>>?                _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;

  final RobotState _state;

  // Buffer para acumular parciales del notify
  // String buffer for partial incoming messages (used below)

  // Caché de la última telemetría parcial (se combina con cada nuevas msg)
  RobotTelemetry _last = RobotTelemetry.empty;

  BleService(this._state);

  // ─── Escanear ──────────────────────────────────────────
  Future<void> startScan() async {
    _state.updateScanning(true);

    if (!await FlutterBluePlus.isSupported) {
      _state.updateScanning(false);
      return;
    }

    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () {
      _state.updateScanning(false);
      throw Exception('Adaptador BT apagado');
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    final sub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        if (r.device.platformName == 'BipedRobot') {
          await FlutterBluePlus.stopScan();
          await _connectToDevice(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.isScanning.where((s) => !s).first;
    await sub.cancel();
    _state.updateScanning(false);
  }

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Future<void> connectToDevice(BluetoothDevice device) =>
      _connectToDevice(device);

  // ─── Conectar ──────────────────────────────────────────
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _device = device;
      await device.connect(timeout: const Duration(seconds: 10));

      _connStateSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _state.updateConnection(false, '');
          _cleanup();
        }
      });

      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _kNusServiceUuid) {
          for (final char in svc.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            if (uuid == _kNusRxUuid) _rxChar = char;
            if (uuid == _kNusTxUuid) _txChar = char;
          }
        }
      }

      if (_txChar == null || _rxChar == null) {
        throw Exception('NUS characteristics no encontradas');
      }

      await _txChar!.setNotifyValue(true);
      _notifySub = _txChar!.lastValueStream.listen(_onDataReceived);

      _state.updateConnection(true, device.platformName);
    } catch (e) {
      debugPrint('[BLE] Error al conectar: $e');
      _cleanup();
    }
  }

  // ─── Comandos ──────────────────────────────────────────
  Future<void> sendCommand(GaitCommand cmd) async {
    await _writeString(cmd.bleString);
    _state.setActiveCommand(cmd);
  }

  Future<void> sendParams(RobotParams params) async {
    for (final msg in params.toBleMessages()) {
      await _writeString(msg);
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<void> sendTrim(int index, double trimRad) async {
    await _writeString('TRIM:$index:${trimRad.toStringAsFixed(4)}');
  }

  Future<void> sendRecovery() async {
    await _writeString(GaitCommand.recover.bleString);
    _state.setActiveCommand(GaitCommand.recover);
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _cleanup();
    _state.updateConnection(false, '');
  }

  // ─── Parsear datos entrantes ────────────────────────────
  void _onDataReceived(List<int> data) {
    if (data.isEmpty) return;
    final msg = utf8.decode(data, allowMalformed: true).trim();
    if (msg.isEmpty) return;

    final parts = msg.split(':');
    if (parts.isEmpty) return;

    switch (parts[0]) {
      // ── IMU:pitch:roll:accelY  (accelY es opcional) ────
      case 'IMU':
        if (parts.length >= 3) {
          final pitch  = double.tryParse(parts[1]) ?? _last.pitchRad;
          final roll   = double.tryParse(parts[2]) ?? _last.rollRad;
          final accelY = parts.length >= 4
              ? (double.tryParse(parts[3]) ?? _last.accelY)
              : _last.accelY;
          _last = RobotTelemetry(
            pitchRad:    pitch,
            rollRad:     roll,
            accelY:      accelY,
            zmpX:        _last.zmpX,
            zmpY:        _last.zmpY,
            phase:       _last.phase,
            servoAngles: _last.servoAngles,
            timestamp:   DateTime.now(),
          );
          _state.updateTelemetry(_last);
        }
        break;

      // ── ZMP:x:y ───────────────────────────────────────
      case 'ZMP':
        if (parts.length >= 3) {
          final zx = double.tryParse(parts[1]) ?? _last.zmpX;
          final zy = double.tryParse(parts[2]) ?? _last.zmpY;
          _last = RobotTelemetry(
            pitchRad:    _last.pitchRad,
            rollRad:     _last.rollRad,
            accelY:      _last.accelY,
            zmpX:        zx,
            zmpY:        zy,
            phase:       _last.phase,
            servoAngles: _last.servoAngles,
            timestamp:   DateTime.now(),
          );
          // No llamar updateTelemetry aquí — esperar próximo IMU
        }
        break;

      // ── PHASE:nombre ──────────────────────────────────
      case 'PHASE':
        if (parts.length >= 2) {
          final phase = gaitPhaseFromString(parts[1]);
          _last = RobotTelemetry(
            pitchRad:    _last.pitchRad,
            rollRad:     _last.rollRad,
            accelY:      _last.accelY,
            zmpX:        _last.zmpX,
            zmpY:        _last.zmpY,
            phase:       phase,
            servoAngles: _last.servoAngles,
            timestamp:   DateTime.now(),
          );
        }
        break;

      // ── SERVO:s0:s1:s2:s3:s4:s5:s6:s7 (en grados) ───
      case 'SERVO':
        if (parts.length >= 9) {
          final angles = List<double>.generate(8, (i) {
            return double.tryParse(parts[i + 1]) ??
                (_last.servoAngles.length > i ? _last.servoAngles[i] : 0.0);
          });
          _last = RobotTelemetry(
            pitchRad:    _last.pitchRad,
            rollRad:     _last.rollRad,
            accelY:      _last.accelY,
            zmpX:        _last.zmpX,
            zmpY:        _last.zmpY,
            phase:       _last.phase,
            servoAngles: angles,
            timestamp:   DateTime.now(),
          );
        }
        break;

      // ── BATT:voltage ──────────────────────────────────
      case 'BATT':
        if (parts.length >= 2) {
          final v = double.tryParse(parts[1]);
          if (v != null) _state.updateBattery(v);
        }
        break;
    }
  }

  Future<void> _writeString(String s) async {
    if (_rxChar == null || !_state.isConnected) return;
    try {
      await _rxChar!.write(utf8.encode(s),
          withoutResponse: _rxChar!.properties.writeWithoutResponse);
    } catch (e) {
      debugPrint('[BLE] Error al escribir "$s": $e');
    }
  }

  void _cleanup() {
    _notifySub?.cancel();
    _connStateSub?.cancel();
    _rxChar = null;
    _txChar = null;
    _device = null;
  }
}
