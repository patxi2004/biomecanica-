// ============================================================
//  robot_state.dart  —  Modelo del estado del robot
// ============================================================

import 'package:flutter/foundation.dart';

// ─── Comandos de marcha ────────────────────────────────────
enum GaitCommand { stop, forward, backward, turnLeft, turnRight, stand }

extension GaitCommandExt on GaitCommand {
  String get bleString {
    switch (this) {
      case GaitCommand.forward:   return 'CMD:FORWARD';
      case GaitCommand.backward:  return 'CMD:BACKWARD';
      case GaitCommand.turnLeft:  return 'CMD:TURN_LEFT';
      case GaitCommand.turnRight: return 'CMD:TURN_RIGHT';
      case GaitCommand.stop:      return 'CMD:STOP';
      case GaitCommand.stand:     return 'CMD:STAND';
    }
  }
}

// ─── Fases de marcha (refleja el enum en el ESP32) ─────────
enum GaitPhase { idle, transferR, swingL, transferL, swingR, unknown }

GaitPhase gaitPhaseFromString(String s) {
  switch (s) {
    case 'IDLE':   return GaitPhase.idle;
    case 'XFER_R': return GaitPhase.transferR;
    case 'SWING_L':return GaitPhase.swingL;
    case 'XFER_L': return GaitPhase.transferL;
    case 'SWING_R':return GaitPhase.swingR;
    default:       return GaitPhase.unknown;
  }
}

// ─── Telemetría recibida del ESP32 ─────────────────────────
class RobotTelemetry {
  final double pitchRad;     // inclinación sagital del torso
  final double rollRad;      // inclinación frontal del torso
  final double zmpX;         // posición ZMP [cm]
  final double zmpY;
  final GaitPhase phase;
  final DateTime timestamp;

  const RobotTelemetry({
    this.pitchRad = 0.0,
    this.rollRad  = 0.0,
    this.zmpX     = 0.0,
    this.zmpY     = 0.0,
    this.phase    = GaitPhase.idle,
    required this.timestamp,
  });

  double get pitchDeg => pitchRad * 180.0 / 3.14159265;
  double get rollDeg  => rollRad  * 180.0 / 3.14159265;

  static RobotTelemetry get empty =>
      RobotTelemetry(timestamp: DateTime.now());
}

// ─── Parámetros configurables ──────────────────────────────
class RobotParams {
  double kp         = 1.0;
  double kd         = 0.03;
  double stepLength = 2.5;   // cm
  double stepHeight = 1.8;   // cm
  double tSwing     = 0.7;   // s

  List<String> toBleMessages() => [
    'PARAM:KP:${kp.toStringAsFixed(3)}',
    'PARAM:KD:${kd.toStringAsFixed(4)}',
    'PARAM:STEP_LEN:${stepLength.toStringAsFixed(1)}',
    'PARAM:STEP_H:${stepHeight.toStringAsFixed(1)}',
    'PARAM:T_SWING:${tSwing.toStringAsFixed(2)}',
  ];
}

// ─── Estado global del robot (ChangeNotifier) ──────────────
class RobotState extends ChangeNotifier {
  // Conexión BLE
  bool   isConnected      = false;
  String connectedDevName = '';
  bool   isScanning       = false;

  // Telemetría
  RobotTelemetry telemetry = RobotTelemetry.empty;

  // Parámetros
  RobotParams params = RobotParams();

  // Comando activo
  GaitCommand activeCommand = GaitCommand.stand;

  // Historial de pitch para gráfica (últimos 60 valores)
  final List<double> pitchHistory = [];
  static const int _historyLen = 60;

  void updateConnection(bool connected, String devName) {
    isConnected      = connected;
    connectedDevName = devName;
    notifyListeners();
  }

  void updateScanning(bool scanning) {
    isScanning = scanning;
    notifyListeners();
  }

  void updateTelemetry(RobotTelemetry t) {
    telemetry = t;
    pitchHistory.add(t.pitchDeg);
    if (pitchHistory.length > _historyLen) {
      pitchHistory.removeAt(0);
    }
    notifyListeners();
  }

  void setActiveCommand(GaitCommand cmd) {
    activeCommand = cmd;
    notifyListeners();
  }
}
