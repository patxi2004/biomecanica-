// ============================================================
//  telemetry_panel.dart  —  Panel de datos IMU y ZMP en tiempo real
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/robot_state.dart';

// ─── Etiqueta de la fase de marcha ─────────────────────────
String _phaseLabel(GaitPhase p) {
  switch (p) {
    case GaitPhase.idle:      return 'Quieto';
    case GaitPhase.transferR: return 'Transfiriendo → Der';
    case GaitPhase.swingL:    return 'Paso Izq ↑';
    case GaitPhase.transferL: return 'Transfiriendo → Izq';
    case GaitPhase.swingR:    return 'Paso Der ↑';
    case GaitPhase.unknown:   return '—';
  }
}

// ============================================================
class TelemetryPanel extends StatelessWidget {
  final RobotTelemetry telemetry;
  final List<double>   pitchHistory;

  const TelemetryPanel({
    super.key,
    required this.telemetry,
    required this.pitchHistory,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Ángulos IMU ─────────────────────────────────────
        _sectionTitle(context, 'IMU — Torso'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _angleCard(context, 'Pitch',
                telemetry.pitchDeg, cs.primary)),
            const SizedBox(width: 8),
            Expanded(child: _angleCard(context, 'Roll',
                telemetry.rollDeg,  cs.secondary)),
          ],
        ),
        const SizedBox(height: 12),

        // ── Gráfica de pitch ─────────────────────────────────
        _sectionTitle(context, 'Inclinación Pitch (últimos 60 muestras)'),
        const SizedBox(height: 6),
        SizedBox(
          height: 80,
          child: pitchHistory.isEmpty
              ? Center(child: Text('—', style: TextStyle(color: cs.outline)))
              : CustomPaint(
                  painter: _PitchPlot(pitchHistory, cs.primary),
                  size: const Size(double.infinity, 80),
                ),
        ),
        const SizedBox(height: 12),

        // ── ZMP ──────────────────────────────────────────────
        _sectionTitle(context, 'ZMP'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _dataCard(context, 'ZMP X',
                '${telemetry.zmpX.toStringAsFixed(2)} cm')),
            const SizedBox(width: 8),
            Expanded(child: _dataCard(context, 'ZMP Y',
                '${telemetry.zmpY.toStringAsFixed(2)} cm')),
          ],
        ),
        const SizedBox(height: 12),

        // ── Fase de marcha ───────────────────────────────────
        _sectionTitle(context, 'Fase de marcha'),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _phaseLabel(telemetry.phase),
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext ctx, String title) => Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(ctx).colorScheme.outline,
          letterSpacing: 0.5,
        ),
      );

  Widget _angleCard(BuildContext ctx, String label, double value, Color color) {
    final cs = Theme.of(ctx).colorScheme;
    // Clamp visual a ±30° para el arco
    final norm = (value.clamp(-30.0, 30.0) / 30.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(1)}°',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: norm.abs() > 0.6 ? Colors.red : color,
            ),
          ),
          const SizedBox(height: 4),
          // Barra de inclinación
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: norm >= 0
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              widthFactor: norm.abs(),
              child: Container(
                decoration: BoxDecoration(
                  color: norm.abs() > 0.6 ? Colors.red : color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataCard(BuildContext ctx, String label, String value) {
    final cs = Theme.of(ctx).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─── Painter para la gráfica de pitch ──────────────────────
class _PitchPlot extends CustomPainter {
  final List<double> data;
  final Color color;
  _PitchPlot(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final bgPaint = Paint()..color = color.withOpacity(0.06);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        bgPaint);

    // Línea central (0°)
    final centerPaint = Paint()
      ..color = color.withOpacity(0.25)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2),
        centerPaint);

    // Línea de datos
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    const double range = 30.0;  // ±30°

    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height / 2 - (data[i] / range) * (size.height / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_PitchPlot old) => old.data != data;
}
