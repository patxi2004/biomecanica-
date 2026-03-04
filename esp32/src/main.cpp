// ============================================================
//  main.cpp  —  Robot bípedo 8-DOF con ESP32
//
//  Pipeline (cada iteración):
//    1. Leer IMU → filtro complementario → pitch, roll
//    2. Corrección PD: Δθ_ankle = Kp·error + Kd·d(error)/dt
//    3. Generador de marcha → posición cartesiana de pies
//    4. IK → ángulos de servo para cada pierna
//    5. Verificar ZMP dentro del polígono de soporte
//    6. Escribir PWM a los 8 servos
//    7. Reportar telemetría por BLE cada 100 ms
// ============================================================

#include <Arduino.h>
#include "config.h"
#include "kinematics.h"
#include "gait.h"
#include "imu_filter.h"
#include "servo_ctrl.h"
#include "ble_comm.h"

// ─── Instancias globales ────────────────────────────────────
ImuFilter       imu;
GaitGenerator   gait;
ServoController servo;
BleComm         ble;

// ─── Temporización ─────────────────────────────────────────
unsigned long last_control_ms = 0;
unsigned long last_gait_ms    = 0;
unsigned long last_ble_ms     = 0;

// ─── Estado del control PD ─────────────────────────────────
float pd_error_prev = 0.0f;
float ankle_corr    = 0.0f;   // corrección aplicada a ambos tobillos [rad]

// ─── Último GaitState calculado ────────────────────────────
GaitState current_state;

// ─── Callback para actualizar trim desde la app ────────────
void onTrimCallback(int idx, float trim_rad)
{
    servo.setTrim(idx, trim_rad);
}

// ============================================================
void setup()
{
    Serial.begin(115200);
    Serial.println("[BIPED] Iniciando...");

    // ── Servos ───────────────────────────────────────────────
    servo.begin();
    Serial.println("[SERVO] OK");

    // ── IMU ──────────────────────────────────────────────────
    if (!imu.begin()) {
        Serial.println("[IMU] ERROR: MPU-6050 no detectado. Revisa conexiones I2C.");
    } else {
        Serial.println("[IMU] Calibrando giroscopio...");
        imu.calibrate(300);
        Serial.println("[IMU] OK");
    }

    // ── Marcha ───────────────────────────────────────────────
    gait.reset();

    // ── BLE ──────────────────────────────────────────────────
    ble.begin(&gait, onTrimCallback);
    Serial.println("[BLE] Advertising como '" BLE_DEVICE_NAME "'");

    Serial.println("[BIPED] Listo. Esperando conexión BLE...");

    // Postura inicial
    servo.standStill();
    delay(500);

    last_control_ms = millis();
    last_gait_ms    = millis();
    last_ble_ms     = millis();
}

// ============================================================
void loop()
{
    unsigned long now = millis();

    // ══════════════════════════════════════════════════════════
    //  LOOP DE CONTROL (100 Hz)
    //  Lectura IMU + cálculo corrección PD
    // ══════════════════════════════════════════════════════════
    if (now - last_control_ms >= CONTROL_LOOP_MS) {
        float dt = (now - last_control_ms) / 1000.0f;
        last_control_ms = now;

        // Actualizar filtro complementario
        imu.update(dt);

        // ─ Control PD de postura ─────────────────────────────
        // θ_target = 0 rad (robot vertical)
        float error = imu.pitch;   // positivo = inclinado adelante
        float d_error = (error - pd_error_prev) / dt;
        ankle_corr = g_kp * error + g_kd * d_error;

        // Saturar corrección a ±0.2 rad (~11°) para proteger servos
        ankle_corr = fmaxf(-0.2f, fminf(0.2f, ankle_corr));
        pd_error_prev = error;
    }

    // ══════════════════════════════════════════════════════════
    //  LOOP DE MARCHA (50 Hz)
    //  Generar trayectoria + IK + verificar ZMP + mover servos
    // ══════════════════════════════════════════════════════════
    if (now - last_gait_ms >= GAIT_LOOP_MS) {
        float dt = (now - last_gait_ms) / 1000.0f;
        last_gait_ms = now;

        // Avanzar el generador de marcha
        current_state = gait.update(dt, ankle_corr);

        // ─ Verificar ZMP: si está fuera del polígono de soporte,
        //   no aplicar el movimiento y volver a IDLE ─────────────
        // Determinar pie de soporte según la fase
        float support_cx = 0.0f;
        float support_cy = 0.0f;
        bool  check_single_support = false;

        switch (current_state.phase) {
        case GaitPhase::SWING_L:
            // Pie derecho soporta
            support_cx = gait.right_foot_x;
            support_cy = D_HIP / 2.0f;
            check_single_support = true;
            break;
        case GaitPhase::SWING_R:
            // Pie izquierdo soporta
            support_cx = gait.left_foot_x;
            support_cy = -D_HIP / 2.0f;
            check_single_support = true;
            break;
        default:
            break;
        }

        if (check_single_support) {
            bool zmp_ok = checkZMP(current_state.com,
                                   support_cx, support_cy, 0.5f);
            if (!zmp_ok) {
                // ZMP fuera del polígono: abortar marcha, volver a neutro
                Serial.println("[ZMP] FAIL — abortando marcha");
                gait.command = GaitCommand::STOP;
            }
        }

        // ─ Aplicar ángulos a los servos ─────────────────────
        servo.applyLegs(current_state.left, current_state.right);
    }

    // ══════════════════════════════════════════════════════════
    //  TELEMETRÍA BLE (10 Hz)
    // ══════════════════════════════════════════════════════════
    if (now - last_ble_ms >= BLE_REPORT_MS) {
        last_ble_ms = now;

        // ZMP ≈ CoM para marcha estática
        ble.sendTelemetry(
            imu.pitch,
            imu.roll,
            imu.ay,                  // aceleración Y en g
            current_state.com.x,
            current_state.com.y,
            current_state.phase
        );

        // Ángulos de servo (radianes → convertidos a grados en BleComm)
        float angles[8];
        for (int i = 0; i < 8; i++) angles[i] = servo.currentAngle(i);
        ble.sendServoTelemetry(angles);

        // Batería: leer ADC y escalar
        int raw_batt = analogRead(BATT_ADC_PIN);
        float batt_v = (raw_batt / BATT_ADC_MAX) * BATT_REF_V * BATT_DIV_RATIO;
        ble.sendBattery(batt_v);

        // Debug por Serial (opcional)
        if (Serial.availableForWrite() > 50) {
            Serial.printf("[IMU] pitch=%.2f° roll=%.2f° | [BLE] %s\n",
                imu.pitch * 180.0f / (float)M_PI,
                imu.roll  * 180.0f / (float)M_PI,
                ble.connected ? "conectado" : "desconectado"
            );
        }
    }
}
