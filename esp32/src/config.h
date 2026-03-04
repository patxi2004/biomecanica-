#pragma once

// ============================================================
//  config.h  —  Parámetros globales del robot bípedo 8-DOF
//  Ajusta estas constantes cuando tengas las medidas reales.
// ============================================================

// ─── Geometría del robot (cm) ──────────────────────────────
constexpr float L1        = 12.0f;   // Fémur (cadera → rodilla)
constexpr float L2        = 11.0f;   // Tibia (rodilla → tobillo)
constexpr float L3        =  1.0f;   // Tobillo → suelo (centro servo)
constexpr float D_HIP     =  5.5f;   // Ancho entre articulaciones de cadera
constexpr float FOOT_LEN  =  4.2f;   // Longitud del pie
constexpr float FOOT_W    =  2.8f;   // Ancho del pie

// ─── Límites de articulaciones (grados) ────────────────────
constexpr float HIP_FLEX_MIN  = -30.0f;
constexpr float HIP_FLEX_MAX  =  45.0f;
constexpr float HIP_ABD_MIN   = -20.0f;
constexpr float HIP_ABD_MAX   =  20.0f;
constexpr float KNEE_MIN      =   0.0f;
constexpr float KNEE_MAX      =  90.0f;
constexpr float ANKLE_MIN     = -30.0f;
constexpr float ANKLE_MAX     =  30.0f;

// ─── Pines GPIO — Servos SG90 ──────────────────────────────
//  Canal LEDC asociado = índice del array
constexpr int SERVO_PINS[8] = {13, 12, 14, 27, 26, 25, 33, 32};
// Índices:  0=L_HipFlex  1=L_HipAbd  2=L_Knee  3=L_Ankle
//           4=R_HipFlex  5=R_HipAbd  6=R_Knee  7=R_Ankle

// ─── PWM servos ────────────────────────────────────────────
constexpr int   SERVO_FREQ       = 50;      // Hz
constexpr int   SERVO_RESOLUTION = 16;      // bits
constexpr int   SERVO_MIN_US     = 500;     // µs @ -90°
constexpr int   SERVO_MID_US     = 1500;    // µs @ 0°
constexpr int   SERVO_MAX_US     = 2500;    // µs @ +90°

// ─── Pines I²C — MPU-6050 ──────────────────────────────────
constexpr int IMU_SDA = 21;
constexpr int IMU_SCL = 22;

// ─── Filtro complementario ─────────────────────────────────
constexpr float ALPHA_CF = 0.98f;   // peso del giroscopio

// ─── Control PD de postura ─────────────────────────────────
constexpr float KP_DEFAULT = 1.0f;
constexpr float KD_DEFAULT = 0.03f;

// ─── Parámetros de marcha ──────────────────────────────────
constexpr float STEP_LENGTH_DEFAULT  = 2.5f;  // cm
constexpr float STEP_HEIGHT_DEFAULT  = 1.8f;  // cm
constexpr float T_SWING_DEFAULT      = 0.7f;  // s  (duración fase swing)
constexpr float T_TRANSFER_DEFAULT   = 0.4f;  // s  (transferencia CoM)

// ─── Masas relativas (fracciones del total) ────────────────
constexpr float MASS_PELVIS  = 0.40f;
constexpr float MASS_FEMUR   = 0.12f;  // cada pierna
constexpr float MASS_TIBIA   = 0.08f;  // cada pierna
constexpr float MASS_FOOT    = 0.05f;  // cada pierna

// ─── BLE ───────────────────────────────────────────────────
#define BLE_DEVICE_NAME  "BipedRobot"
// Nordic UART Service
#define NUS_SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_CHAR_RX_UUID        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // app escribe
#define NUS_CHAR_TX_UUID        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // esp32 notifica

// ─── Loop timings ──────────────────────────────────────────
constexpr unsigned long CONTROL_LOOP_MS = 10;   // 100 Hz
constexpr unsigned long GAIT_LOOP_MS    = 20;   // 50 Hz
constexpr unsigned long BLE_REPORT_MS   = 100;  // 10 Hz
