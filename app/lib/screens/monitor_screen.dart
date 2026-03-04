// ============================================================
//  monitor_screen.dart  —  Pantalla 2: Telemetría en tiempo real
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/robot_state.dart';

// ============================================================
class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  static const _servoNames = [
    'Cadera Izq Flex', 'Cadera Izq Abd',
    'Rodilla Izq',     'Tobillo Izq',
    'Cadera Der Flex', 'Cadera Der Abd',
    'Rodilla Der',     'Tobillo Der',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── SECCIÓN SERVOS ──────────────────────────────────
          _sectionHeader('SERVOS', Icons.settings_rounded),
          const SizedBox(height: 6),
          _ServoAnglesCard(
              angles: state.telemetry.servoAngles, names: _servoNames),

          const SizedBox(height: 16),

          // ── SECCIÓN IMU CHART ───────────────────────────────
          _sectionHeader('IMU — Historial (200 muestras)',
              Icons.show_chart_rounded),
          const SizedBox(height: 6),
          _ImuChartCard(
            pitchHistory: state.pitchHistory,
            rollHistory: state.rollHistory,
            accelYHistory: state.accelYHistory,
          ),

          const SizedBox(height: 16),

          // ── SECCIÓN LOG ─────────────────────────────────────
          Row(
            children: [
              _sectionHeader('LOG DE EVENTOS', Icons.list_alt_rounded),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _exportLog(context, state),
                icon: const Icon(Icons.download_rounded,
                    size: 16, color: AppColors.cyan),
                label: const Text('Exportar',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.cyan)),
              ),
              TextButton.icon(
                onPressed: () => state.clearLog(),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.textSecond),
                label: const Text('Limpiar',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecond)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _EventLogCard(events: state.eventLog),

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
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  void _exportLog(BuildContext context, RobotState state) {
    final csv = state.exportLogCsv();
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copiado al portapapeles'),
        backgroundColor: AppColors.cardBg,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ── Tarjeta de ángulos de servo ────────────────────────────
class _ServoAnglesCard extends StatelessWidget {
  final List<double> angles;
  final List<String> names;

  const _ServoAnglesCard({required this.angles, required this.names});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(math.min(8, angles.length), (i) {
          final angle = angles[i];
          final normalized = ((angle + 90) / 180).clamp(0.0, 1.0);
          Color barColor;
          if (angle.abs() < 30) {
            barColor = AppColors.green;
          } else if (angle.abs() < 60) {
            barColor = AppColors.orange;
          } else {
            barColor = AppColors.red;
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    names[i],
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecond),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: normalized,
                      backgroundColor: AppColors.background,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(barColor),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${angle.toStringAsFixed(1)}°',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: barColor,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ── Tarjeta de gráfica IMU multi-linea ────────────────────
class _ImuChartCard extends StatelessWidget {
  final List<double> pitchHistory;
  final List<double> rollHistory;
  final List<double> accelYHistory;

  const _ImuChartCard({
    required this.pitchHistory,
    required this.rollHistory,
    required this.accelYHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend
          Row(
            children: [
              _legendDot(AppColors.cyan, 'Pitch'),
              const SizedBox(width: 12),
              _legendDot(AppColors.orange, 'Roll'),
              const SizedBox(width: 12),
              _legendDot(AppColors.green, 'AccelY×10'),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _MultiLinePainter(
                pitchHistory: pitchHistory,
                rollHistory: rollHistory,
                accelYHistory: accelYHistory,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecond)),
      ],
    );
  }
}

class _MultiLinePainter extends CustomPainter {
  final List<double> pitchHistory;
  final List<double> rollHistory;
  final List<double> accelYHistory;

  _MultiLinePainter({
    required this.pitchHistory,
    required this.rollHistory,
    required this.accelYHistory,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    final gridPaint = Paint()
      ..color = AppColors.textSecond.withOpacity(0.15)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawLine(canvas, size, pitchHistory, AppColors.cyan, 90.0);
    _drawLine(canvas, size, rollHistory, AppColors.orange, 90.0);
    // AccelY is in g units, scale ×10 to match degrees range
    _drawLine(canvas, size, accelYHistory, AppColors.green, 2.0,
        scale: 10.0);
  }

  void _drawLine(Canvas canvas, Size size, List<double> data, Color color,
      double range, {double scale = 1.0}) {
    if (data.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final val = (data[i] * scale).clamp(-range, range);
      final y = size.height * (1.0 - (val + range) / (2.0 * range));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MultiLinePainter old) => true;
}

// ── Tarjeta de log de eventos ──────────────────────────────
class _EventLogCard extends StatelessWidget {
  final List<LogEvent> events;
  const _EventLogCard({required this.events});

  static const _levelIcon = {
    LogLevel.info: '✅',
    LogLevel.warning: '⚠️',
    LogLevel.error: '🚨',
    LogLevel.recovery: '🔄',
  };

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Sin eventos registrados.',
              style: TextStyle(
                  color: AppColors.textSecond, fontSize: 13)),
        ),
      );
    }

    final reversed = events.reversed.toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: reversed.length,
        itemBuilder: (ctx, i) {
          final ev = reversed[i];
          final icon = _levelIcon[ev.level] ?? '•';
          final ts = _formatTime(ev.time);
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(ts,
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecond,
                        fontFamily: 'monospace')),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ev.message,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
