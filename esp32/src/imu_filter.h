#pragma once
#include <Wire.h>
#include "config.h"

// ============================================================
//  imu_filter.h  —  Lectura MPU-6050 + Filtro Complementario
//
//  El MPU-6050 se conecta por I²C (SDA=21, SCL=22).
//  Ángulos resultantes:
//    pitch  → inclinación adelante/atrás (plano sagital)
//    roll   → inclinación izquierda/derecha (plano frontal)
// ============================================================

// Dirección I²C del MPU-6050 (AD0=GND → 0x68)
constexpr uint8_t MPU6050_ADDR    = 0x68;

// Registros relevantes
constexpr uint8_t REG_PWR_MGMT_1  = 0x6B;
constexpr uint8_t REG_ACCEL_XOUT  = 0x3B;
constexpr uint8_t REG_GYRO_XOUT   = 0x43;
constexpr uint8_t REG_CONFIG       = 0x1A;
constexpr uint8_t REG_GYRO_CONFIG  = 0x1B;
constexpr uint8_t REG_ACCEL_CONFIG = 0x1C;

// Escalas por defecto
constexpr float ACCEL_SCALE = 16384.0f;  // LSB/g  (±2g)
constexpr float GYRO_SCALE  =   131.0f;  // LSB/(°/s)  (±250°/s)

// ============================================================
class ImuFilter {
public:
    float pitch = 0.0f;   // [rad]
    float roll  = 0.0f;   // [rad]

    // Datos crudos (útiles para debug)
    float ax = 0.0f, ay = 0.0f, az = 0.0f;  // [g]
    float gx = 0.0f, gy = 0.0f, gz = 0.0f;  // [rad/s]

    bool  initialized = false;

    // ─── Inicialización ────────────────────────────────────
    bool begin(int sda = IMU_SDA, int scl = IMU_SCL)
    {
        Wire.begin(sda, scl);
        Wire.setClock(400000);  // Fast mode I²C

        // Despertar el MPU-6050 (sale de sleep)
        writeReg(REG_PWR_MGMT_1, 0x00);
        delay(100);

        // DLPF a 44 Hz (suaviza vibraciones de servos)
        writeReg(REG_CONFIG, 0x03);

        // Rango giroscopio: ±250°/s
        writeReg(REG_GYRO_CONFIG, 0x00);

        // Rango acelerómetro: ±2g
        writeReg(REG_ACCEL_CONFIG, 0x00);

        // Verificar who-am-i
        uint8_t who = readReg(0x75);
        initialized = (who == 0x68);
        return initialized;
    }

    // ─── Actualizar filtro  ────────────────────────────────
    //  Llama en cada iteración del loop de control.
    //  dt: tiempo desde la última llamada [s]
    void update(float dt)
    {
        if (!initialized) return;

        // Leer 14 bytes: accel (6B) + temp (2B) + gyro (6B)
        Wire.beginTransmission(MPU6050_ADDR);
        Wire.write(REG_ACCEL_XOUT);
        Wire.endTransmission(false);
        Wire.requestFrom(MPU6050_ADDR, (uint8_t)14);

        if (Wire.available() < 14) return;

        int16_t raw_ax = (Wire.read() << 8) | Wire.read();
        int16_t raw_ay = (Wire.read() << 8) | Wire.read();
        int16_t raw_az = (Wire.read() << 8) | Wire.read();
        Wire.read(); Wire.read();  // temperatura (ignorada)
        int16_t raw_gx = (Wire.read() << 8) | Wire.read();
        int16_t raw_gy = (Wire.read() << 8) | Wire.read();
        int16_t raw_gz = (Wire.read() << 8) | Wire.read();

        // Convertir a unidades físicas
        ax = raw_ax / ACCEL_SCALE;
        ay = raw_ay / ACCEL_SCALE;
        az = raw_az / ACCEL_SCALE;
        gx = (raw_gx / GYRO_SCALE) * (float)M_PI / 180.0f;  // → rad/s
        gy = (raw_gy / GYRO_SCALE) * (float)M_PI / 180.0f;
        gz = (raw_gz / GYRO_SCALE) * (float)M_PI / 180.0f;

        // ── Filtro complementario ─────────────────────────
        //  Ángulo acelerómetro (referencia estática)
        float pitch_acc = atan2f(ay, az);
        float roll_acc  = atan2f(-ax, az);

        //  Integrar giroscopio + fusionar
        pitch = ALPHA_CF * (pitch + gx * dt) + (1.0f - ALPHA_CF) * pitch_acc;
        roll  = ALPHA_CF * (roll  + gy * dt) + (1.0f - ALPHA_CF) * roll_acc;
    }

    // ─── Calibración de offset (llamar con robot inmóvil) ──
    //  Mide bias del giroscopio promediando N muestras.
    void calibrate(int samples = 200)
    {
        if (!initialized) return;

        float bias_gx = 0, bias_gy = 0, bias_gz = 0;
        for (int i = 0; i < samples; i++) {
            Wire.beginTransmission(MPU6050_ADDR);
            Wire.write(REG_GYRO_XOUT);
            Wire.endTransmission(false);
            Wire.requestFrom(MPU6050_ADDR, (uint8_t)6);
            int16_t rx = (Wire.read() << 8) | Wire.read();
            int16_t ry = (Wire.read() << 8) | Wire.read();
            int16_t rz = (Wire.read() << 8) | Wire.read();
            bias_gx += rx / GYRO_SCALE;
            bias_gy += ry / GYRO_SCALE;
            bias_gz += rz / GYRO_SCALE;
            delay(5);
        }
        _bias_gx = bias_gx / samples;
        _bias_gy = bias_gy / samples;
        _bias_gz = bias_gz / samples;
    }

private:
    float _bias_gx = 0, _bias_gy = 0, _bias_gz = 0;

    void writeReg(uint8_t reg, uint8_t val)
    {
        Wire.beginTransmission(MPU6050_ADDR);
        Wire.write(reg);
        Wire.write(val);
        Wire.endTransmission();
    }

    uint8_t readReg(uint8_t reg)
    {
        Wire.beginTransmission(MPU6050_ADDR);
        Wire.write(reg);
        Wire.endTransmission(false);
        Wire.requestFrom(MPU6050_ADDR, (uint8_t)1);
        return Wire.available() ? Wire.read() : 0xFF;
    }
};
