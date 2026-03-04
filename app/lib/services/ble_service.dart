// ============================================================
//  ble_service.dart  —  Gestión de la conexión BLE
//  Usa flutter_blue_plus para el protocolo Nordic UART (NUS)
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:flutter/widgets.dart';

import '../models/robot_state.dart';

// ─── UUIDs del Nordic UART Service ────────────────────────
const String _kNusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _kNusRxUuid      = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // write
const String _kNusTxUuid      = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // notify

// ============================================================
class BleService {
  BluetoothDevice?        _device;
  BluetoothCharacteristic?_rxChar;   // app → ESP32
  BluetoothCharacteristic?_txChar;   // ESP32 → app

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;

  final RobotState _state;

  BleService(this._state);

  // ─── Escanear y conectar al primer "BipedRobot" ────────
  Future<void> startScan() async {
    _state.updateScanning(true);

    // Adaptar permisos/estado del adaptador BT
    if (!await FlutterBluePlus.isSupported) {
      debugPrint('[BLE] BLE no soportado en este dispositivo');
      _state.updateScanning(false);
      return;
    }

    // Asegurar que el adaptador está encendido
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () {
      _state.updateScanning(false);
      throw Exception('Adaptador BT apagado');
    });

    // Iniciar escaneo (5 segundos)
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 5),
    );

    // Escuchar resultados
    final sub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        if (r.device.platformName == 'BipedRobot') {
          await FlutterBluePlus.stopScan();
          await _connectToDevice(r.device);
          break;
        }
      }
    });

    // Cuando termine el escaneo, limpiar
    await FlutterBluePlus.isScanning
        .where((s) => !s)
        .first;
    await sub.cancel();
    _state.updateScanning(false);
  }

  // ─── Escanear y devolver lista de dispositivos ─────────
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Future<void> connectToDevice(BluetoothDevice device) =>
      _connectToDevice(device);

  // ─── Conectar y descubrir servicios ────────────────────
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _device = device;
      await device.connect(timeout: const Duration(seconds: 10));

      // Escuchar desconexiones
      _connStateSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _state.updateConnection(false, '');
          _cleanup();
        }
      });

      // Descubrir servicios
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

      // Habilitar notificaciones del TX del ESP32
      await _txChar!.setNotifyValue(true);
      _notifySub = _txChar!.lastValueStream.listen(_onDataReceived);

      _state.updateConnection(true, device.platformName);
      debugPrint('[BLE] Conectado a ${device.platformName}');
    } catch (e) {
      debugPrint('[BLE] Error al conectar: $e');
      _cleanup();
    }
  }

  // ─── Enviar comando al ESP32 ───────────────────────────
  Future<void> sendCommand(GaitCommand cmd) async {
    await _writeString(cmd.bleString);
    _state.setActiveCommand(cmd);
  }

  // ─── Enviar parámetros al ESP32 ───────────────────────
  Future<void> sendParams(RobotParams params) async {
    for (final msg in params.toBleMessages()) {
      await _writeString(msg);
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  // ─── Enviar trim de servo ──────────────────────────────
  Future<void> sendTrim(int index, double trimRad) async {
    await _writeString('TRIM:$index:${trimRad.toStringAsFixed(4)}');
  }

  // ─── Desconectar ──────────────────────────────────────
  Future<void> disconnect() async {
    await _device?.disconnect();
    _cleanup();
    _state.updateConnection(false, '');
  }

  // ─── Parsear datos entrantes del ESP32 ─────────────────
  void _onDataReceived(List<int> data) {
    final msg = utf8.decode(data).trim();
    if (msg.isEmpty) return;

    final parts = msg.split(':');
    if (parts.isEmpty) return;

    final current = _state.telemetry;

    switch (parts[0]) {
      case 'IMU':
        if (parts.length >= 3) {
          final pitch = double.tryParse(parts[1]) ?? current.pitchRad;
          final roll  = double.tryParse(parts[2]) ?? current.rollRad;
          _state.updateTelemetry(RobotTelemetry(
            pitchRad:  pitch,
            rollRad:   roll,
            zmpX:      current.zmpX,
            zmpY:      current.zmpY,
            phase:     current.phase,
            timestamp: DateTime.now(),
          ));
        }
        break;

      case 'ZMP':
        if (parts.length >= 3) {
          final zx = double.tryParse(parts[1]) ?? current.zmpX;
          final zy = double.tryParse(parts[2]) ?? current.zmpY;
          _state.updateTelemetry(RobotTelemetry(
            pitchRad:  current.pitchRad,
            rollRad:   current.rollRad,
            zmpX:      zx,
            zmpY:      zy,
            phase:     current.phase,
            timestamp: DateTime.now(),
          ));
        }
        break;

      case 'PHASE':
        if (parts.length >= 2) {
          final phase = gaitPhaseFromString(parts[1]);
          _state.updateTelemetry(RobotTelemetry(
            pitchRad:  current.pitchRad,
            rollRad:   current.rollRad,
            zmpX:      current.zmpX,
            zmpY:      current.zmpY,
            phase:     phase,
            timestamp: DateTime.now(),
          ));
        }
        break;
    }
  }

  // ─── Escritura con retry ───────────────────────────────
  Future<void> _writeString(String s) async {
    if (_rxChar == null || !(_state.isConnected)) return;
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
