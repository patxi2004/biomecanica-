// ============================================================
//  robot_state.dart  —  Modelo del estado del robot
// ============================================================

import 'package:flutter/foundation.dart';

// ─── Comandos de marcha ────────────────────────────────────
enum GaitCommand { stop, forward, backward, turnLeft, turnRight, stand, recover }

extension GaitCommandExt on GaitCommand {
  String get bleString {
    switch (this) {
      case GaitCommand.forward:   return 'CMD:FORWARD';
      case GaitCommand.backward:  return 'CMD:BACKWARD';
      case GaitCommand.turnLeft:  return 'CMD:TURN_LEFT';
      case GaitCommand.turnRight: return 'CMD:TURN_RIGHT';
      case GaitCommand.stop:      return 'CMD:STOP';
      case GaitCommand.stand:     return 'CMD:STAND';
      case GaitCommand.recover:   return 'CMD:RECOVER';
    }
  }
}

// ─── Fases de marcha ───────────────────────────────────────
enum GaitPhase { idle, transferR, swingL, transferL, swingR, unknown }

GaitPhase gaitPhaseFromString(String s) {
  switch (s) {
    case 'IDLE':    return GaitPhase.idle;
    case 'XFER_R':  return GaitPhase.transferR;
    case 'SWING_L': return GaitPhase.swingL;
    case 'XFER_L':  return GaitPhase.transferL;
    case 'SWING_R': return GaitPhase.swingR;
    default:        return GaitPhase.unknown;
  }
}

// ─── Tipos de evento para el log ──────────────────────────
enum LogLevel { info, warning, error, recovery }

class LogEvent {
  final DateTime time;
  final LogLevel level;
  final String   message;
  final double   pitch;
  final double   roll;
  final List<double> servoAngles;

  LogEvent({
    required this.time,
    required this.level,
    required this.message,
    this.pitch = 0.0,
    this.roll  = 0.0,
    List<double>? servoAngles,
  }) : servoAngles = servoAngles ?? List.filled(8, 0.0);

  // Exportación a CSV
  String toCsv() {
    final ts   = '${time.hour.toString().padLeft(2,'0')}:'
                 '${time.minute.toString().padLeft(2,'0')}:'
                 '${time.second.toString().padLeft(2,'0')}';
    final lvl  = level.name.toUpperCase();
    final sv   = servoAngles.map((v) => v.toStringAsFixed(1)).join(';');
    return '$ts,$lvl,"$message",${pitch.toStringAsFixed(2)},${roll.toStringAsFixed(2)},$sv';
  }

  static String csvHeader() =>
      'Timestamp,Level,Event,Pitch(deg),Roll(deg),S1;S2;S3;S4;S5;S6;S7;S8';
}

// ─── Telemetría recibida del ESP32 ─────────────────────────
class RobotTelemetry {
  final double pitchRad;
  final double rollRad;
  final double accelY;      // g — aceleración lateral
  final double zmpX;
  final double zmpY;
  final GaitPhase phase;
  final List<double> servoAngles;  // 8 ángulos en grados
  final DateTime timestamp;

  RobotTelemetry({
    this.pitchRad    = 0.0,
    this.rollRad     = 0.0,
    this.accelY      = 0.0,
    this.zmpX        = 0.0,
    this.zmpY        = 0.0,
    this.phase       = GaitPhase.idle,
    List<double>? servoAngles,
    required this.timestamp,
  }) : servoAngles = servoAngles ?? List.filled(8, 0.0);

  double get pitchDeg => pitchRad * 180.0 / 3.14159265;
  double get rollDeg  => rollRad  * 180.0 / 3.14159265;
  bool   get isFallen => pitchDeg.abs() > 45.0 || rollDeg.abs() > 45.0;

  static RobotTelemetry get empty => RobotTelemetry(timestamp: DateTime.now());
}

// ─── Parámetros configurables ──────────────────────────────
class RobotParams {
  double kp         = 1.0;
  double kd         = 0.03;
  double stepLength = 2.5;   // cm
  double stepHeight = 1.8;   // cm
  double tSwing     = 0.7;   // s (0.5–2.0s)

  RobotParams copyWith({
    double? kp,
    double? kd,
    double? stepLength,
    double? stepHeight,
    double? tSwing,
  }) {
    return RobotParams()
      ..kp         = kp ?? this.kp
      ..kd         = kd ?? this.kd
      ..stepLength = stepLength ?? this.stepLength
      ..stepHeight = stepHeight ?? this.stepHeight
      ..tSwing     = tSwing ?? this.tSwing;
  }

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
  // ── Conexión BLE ──────────────────────────────────────────
  bool   isConnected      = false;
  String connectedDevName = '';
  bool   isScanning       = false;

  // ── Batería ───────────────────────────────────────────────
  double batteryVoltage   = 0.0;

  // ── Telemetría ────────────────────────────────────────────
  RobotTelemetry telemetry = RobotTelemetry.empty;
  bool fallDetected        = false;

  // ── Parámetros ────────────────────────────────────────────
  RobotParams params = RobotParams();

  // ── Comando activo ────────────────────────────────────────
  GaitCommand activeCommand = GaitCommand.stand;

  // ── Historial de gráficas (últimas 200 muestras @ 10 Hz = 20s) ──
  static const int _histLen = 200;
  final List<double> pitchHistory  = [];
  final List<double> rollHistory   = [];
  final List<double> accelYHistory = [];

  // ── Log de eventos ────────────────────────────────────────
  static const int _maxLog = 200;
  final List<LogEvent> eventLog = [];

  // ─────────────────────────────────────────────────────────
  void updateConnection(bool connected, String devName) {
    isConnected      = connected;
    connectedDevName = devName;
    if (connected) {
      addEvent(LogLevel.info, 'Conectado a $devName');
    } else {
      addEvent(LogLevel.warning, 'Desconectado');
    }
    notifyListeners();
  }

  void updateScanning(bool scanning) {
    isScanning = scanning;
    notifyListeners();
  }

  void updateBattery(double voltage) {
    batteryVoltage = voltage;
    notifyListeners();
  }

  void updateTelemetry(RobotTelemetry t) {
    final prevFall = fallDetected;
    fallDetected   = t.isFallen;

    // Registrar eventos de caída / recuperación
    if (!prevFall && fallDetected) {
      addEvent(LogLevel.error, 'Caída detectada',
          pitch: t.pitchDeg, roll: t.rollDeg, sv: t.servoAngles);
    } else if (prevFall && !fallDetected) {
      addEvent(LogLevel.recovery, 'Recuperación completada',
          pitch: t.pitchDeg, roll: t.rollDeg, sv: t.servoAngles);
    } else if (!fallDetected &&
               (t.pitchDeg.abs() > 15 || t.rollDeg.abs() > 15)) {
      // Advertencia por inclinación alta (máx una vez por segundo)
      if (eventLog.isEmpty ||
          DateTime.now().difference(eventLog.last.time).inMilliseconds > 1000) {
        addEvent(LogLevel.warning,
            'Inclinación alta pitch=${t.pitchDeg.toStringAsFixed(1)}° roll=${t.rollDeg.toStringAsFixed(1)}°',
            pitch: t.pitchDeg, roll: t.rollDeg);
      }
    }

    telemetry = t;
    _addHistory(pitchHistory,  t.pitchDeg);
    _addHistory(rollHistory,   t.rollDeg);
    _addHistory(accelYHistory, t.accelY);
    notifyListeners();
  }

  void setActiveCommand(GaitCommand cmd) {
    activeCommand = cmd;
    addEvent(LogLevel.info, 'CMD: ${cmd.name}');
    notifyListeners();
  }

  void addEvent(LogLevel level, String message,
      {double pitch = 0, double roll = 0, List<double>? sv}) {
    eventLog.add(LogEvent(
      time:        DateTime.now(),
      level:       level,
      message:     message,
      pitch:       pitch,
      roll:        roll,
      servoAngles: sv,
    ));
    if (eventLog.length > _maxLog) eventLog.removeAt(0);
    // No llamar notifyListeners aquí — ya lo hace el llamador
  }

  String exportLogCsv() {
    final buf = StringBuffer();
    buf.writeln(LogEvent.csvHeader());
    for (final e in eventLog) {
      buf.writeln(e.toCsv());
    }
    return buf.toString();
  }

  void clearLog() {
    eventLog.clear();
    notifyListeners();
  }

  void _addHistory(List<double> list, double value) {
    list.add(value);
    if (list.length > _histLen) list.removeAt(0);
  }
}


