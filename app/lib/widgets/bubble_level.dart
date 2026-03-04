// ============================================================
//  bubble_level.dart  —  Indicador visual tipo nivel de burbuja
//  Muestra dos burbujas: una para Pitch (sagital) y otra para Roll (frontal)
// ============================================================

import 'package:flutter/material.dart';
import '../main.dart';

class BubbleLevel extends StatelessWidget {
  final double pitchDeg;
  final double rollDeg;

  const BubbleLevel({
    super.key,
    required this.pitchDeg,
    required this.rollDeg,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _LevelGauge(
          label:     'PITCH',
          valueDeg:  pitchDeg,
          axis:      _GaugeAxis.vertical,
          warnDeg:   15.0,
          dangerDeg: 45.0,
        ),
        _LevelGauge(
          label:     'ROLL',
          valueDeg:  rollDeg,
          axis:      _GaugeAxis.horizontal,
          warnDeg:   15.0,
          dangerDeg: 45.0,
        ),
      ],
    );
  }
}

enum _GaugeAxis { vertical, horizontal }

class _LevelGauge extends StatelessWidget {
  final String     label;
  final double     valueDeg;
  final _GaugeAxis axis;
  final double     warnDeg;
  final double     dangerDeg;

  const _LevelGauge({
    required this.label,
    required this.valueDeg,
    required this.axis,
    required this.warnDeg,
    required this.dangerDeg,
  });

  Color get _color {
    final a = valueDeg.abs();
    if (a >= dangerDeg) return AppColors.red;
    if (a >= warnDeg)   return AppColors.orange;
    return AppColors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Etiqueta y valor numérico ─────────────────────
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecond, fontSize: 10,
                letterSpacing: 1.2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          '${valueDeg >= 0 ? "+" : ""}${valueDeg.toStringAsFixed(1)}°',
          style: TextStyle(
            color: _color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 6),
        // ── Gauge visual ────────────────────────────────────
        SizedBox(
          width: 60, height: 60,
          child: CustomPaint(
            painter: _BubblePainter(
              valueDeg: valueDeg,
              axis:     axis,
              color:    _color,
              maxDeg:   dangerDeg,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  final double     valueDeg;
  final _GaugeAxis axis;
  final Color      color;
  final double     maxDeg;

  _BubblePainter({
    required this.valueDeg,
    required this.axis,
    required this.color,
    required this.maxDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = size.width  / 2 - 2;

    // ── Círculo externo ───────────────────────────────────
    final outerPaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(cx, cy), r, outerPaint);

    // ── Cruz central ──────────────────────────────────────
    final crossPaint = Paint()
      ..color = AppColors.textSecond.withOpacity(0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), crossPaint);

    // ── Zona segura (círculo interior verde/gris) ─────────
    final safeR = r * (15.0 / maxDeg);
    final safePaint = Paint()
      ..color = AppColors.green.withOpacity(0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), safeR, safePaint);

    // ── Burbuja ───────────────────────────────────────────
    // Normalizar posición: clamp a ±maxDeg, mapear a radio
    final norm  = (valueDeg / maxDeg).clamp(-1.0, 1.0);
    final bR    = 8.0;
    final travel = r - bR - 2;

    double bx = cx;
    double by = cy;
    if (axis == _GaugeAxis.vertical) {
      by = cy - norm * travel;  // pitch + = inclina adelante = burbuja sube
    } else {
      bx = cx + norm * travel;  // roll + = inclina derecha = burbuja va derecha
    }

    final bubblePaint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(bx, by), bR, bubblePaint);

    // Brillo de la burbuja
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(bx - bR * 0.3, by - bR * 0.3), bR * 0.35, glowPaint);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.valueDeg != valueDeg || old.color != color;
}
