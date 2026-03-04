#pragma once
#include <Arduino.h>
#include "config.h"
#include "kinematics.h"

// ============================================================
//  servo_ctrl.h  —  Control PWM de 8 servos SG90 via LEDC
//
//  Mapeo de índices:
//    0 = L_HipFlex   1 = L_HipAbd   2 = L_Knee   3 = L_Ankle
//    4 = R_HipFlex   5 = R_HipAbd   6 = R_Knee   7 = R_Ankle
//
//  La ESP32 usa el periférico LEDC para generar PWM.
//  Cada servo ocupa un canal independiente (0-7).
// ============================================================

// Convierte microsegundos en valor de duty para LEDC
// Timer clock = 80 MHz, prescaler implícito, resolución 16 bits
inline uint32_t usToDuty(uint32_t us)
{
    // Período @ 50 Hz = 20 000 µs
    // Duty = (us / 20000) * 2^16
    return (uint32_t)((us / 20000.0f) * 65536.0f);
}

// Convierte ángulo [rad] a microsegundos de pulso
// Centro servo = SERVO_MID_US (0 rad), rango ±90° = ±π/2 rad
inline uint32_t angleToUs(float angle_rad)
{
    // ±90° = ±π/2 rad → SERVO_MIN_US … SERVO_MAX_US
    float deg = angle_rad * 180.0f / (float)M_PI;
    float us  = SERVO_MID_US + (deg / 90.0f) * (SERVO_MAX_US - SERVO_MID_US) / 1.0f;
    // El SG90 va de 500 a 2500 µs (±90°)
    us = fmaxf(SERVO_MIN_US, fminf(SERVO_MAX_US, us));
    return (uint32_t)us;
}

// ─── Dirección de cada servo (1 = normal, -1 = invertido) ──
//  Ajusta estos valores según el montaje físico de tu robot.
//  Un servo "invertido" gira al revés respecto al convenio
//  del sistema de referencia cinemático.
constexpr int SERVO_DIR[8] = {
     1,   // 0: L_HipFlex
    -1,   // 1: L_HipAbd   (lado izquierdo: invertir abducción)
     1,   // 2: L_Knee
    -1,   // 3: L_Ankle
    -1,   // 4: R_HipFlex  (lado derecho: invertir flexión)
     1,   // 5: R_HipAbd
    -1,   // 6: R_Knee
     1    // 7: R_Ankle
};

// ─── Offsets de trim (rad) — ajustar para cada servo ───────
//  Permite compensar el error de posición en 0°.
float SERVO_TRIM[8] = { 0.0f, 0.0f, 0.0f, 0.0f,
                        0.0f, 0.0f, 0.0f, 0.0f };

// ============================================================
class ServoController {
public:

    // ─── Inicializar los 8 canales LEDC ────────────────────
    void begin()
    {
        for (int i = 0; i < 8; i++) {
            ledcSetup(i, SERVO_FREQ, SERVO_RESOLUTION);
            ledcAttachPin(SERVO_PINS[i], i);
            // Mover a posición central
            writeUs(i, SERVO_MID_US);
        }
        delay(500);
    }

    // ─── Escribir ángulo en un servo ───────────────────────
    //  index: 0-7, angle_rad: ángulo cinemático [rad]
    void writeAngle(int index, float angle_rad)
    {
        if (index < 0 || index > 7) return;
        float a = SERVO_DIR[index] * angle_rad + SERVO_TRIM[index];
        writeUs(index, angleToUs(a));
        _current_angle[index] = a;
    }

    // ─── Aplicar los ángulos de ambas piernas ──────────────
    //  Aplica todos los ángulos de un GaitState de una vez.
    void applyLegs(const LegAngles& left, const LegAngles& right)
    {
        // Pierna izquierda
        writeAngle(0, left.hip_flex);
        writeAngle(1, left.hip_abd);
        writeAngle(2, left.knee);
        writeAngle(3, left.ankle);
        // Pierna derecha
        writeAngle(4, right.hip_flex);
        writeAngle(5, right.hip_abd);
        writeAngle(6, right.knee);
        writeAngle(7, right.ankle);
    }

    // ─── Mover todos los servos a posición neutral ─────────
    void standStill()
    {
        for (int i = 0; i < 8; i++) {
            writeUs(i, SERVO_MID_US);
            _current_angle[i] = 0.0f;
        }
    }

    // ─── Obtener ángulo actual ──────────────────────────────
    float currentAngle(int index) const
    {
        if (index < 0 || index > 7) return 0.0f;
        return _current_angle[index];
    }

    // ─── Actualizar trim (desde app) ───────────────────────
    void setTrim(int index, float trim_rad)
    {
        if (index < 0 || index > 7) return;
        SERVO_TRIM[index] = trim_rad;
    }

private:
    float _current_angle[8] = {};

    void writeUs(int channel, uint32_t us)
    {
        ledcWrite(channel, usToDuty(us));
    }
};
