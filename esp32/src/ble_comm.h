#pragma once
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "config.h"
#include "gait.h"

// ============================================================
//  ble_comm.h  —  Comunicación BLE  (Nordic UART Service)
//
//  Protocolo de comandos (app → ESP32):
//    "CMD:FORWARD"       — caminar adelante
//    "CMD:BACKWARD"      — caminar atrás
//    "CMD:TURN_LEFT"     — girar izquierda
//    "CMD:TURN_RIGHT"    — girar derecha
//    "CMD:STOP"          — detener marcha
//    "CMD:STAND"         — postura neutral
//    "PARAM:KP:1.2"      — ajustar ganancia proporcional
//    "PARAM:KD:0.03"     — ajustar ganancia derivativa
//    "PARAM:STEP_LEN:2.5"— longitud de paso (cm)
//    "PARAM:STEP_H:1.8"  — altura de paso (cm)
//    "TRIM:0:0.05"       — trim servo índice:valor_rad
//
//  Protocolo de telemetría (ESP32 → app, vía notify):
//    "IMU:pitch:roll"    — ángulos del torso [rad]
//    "ZMP:x:y"           — posición ZMP [cm]
//    "PHASE:nombre"      — fase de marcha actual
//    "STATE:OK"          — heartbeat
// ============================================================

// ─── Variables globales de configuración PD ────────────────
float g_kp = KP_DEFAULT;
float g_kd = KD_DEFAULT;

// ─── Referencia al generador de marcha (se conecta en main) ─
GaitGenerator* g_gait_ptr = nullptr;

// ─── Función externa para actualizar trim (implementada en main) ─
typedef void (*TrimCallback)(int, float);
TrimCallback g_trim_cb = nullptr;

// ============================================================
class BleComm : public BLEServerCallbacks,
                public BLECharacteristicCallbacks
{
public:
    bool connected = false;

    // ─── Inicializar BLE ───────────────────────────────────
    void begin(GaitGenerator* gait, TrimCallback trim_cb = nullptr)
    {
        g_gait_ptr = gait;
        g_trim_cb  = trim_cb;

        BLEDevice::init(BLE_DEVICE_NAME);
        _server = BLEDevice::createServer();
        _server->setCallbacks(this);

        BLEService* svc = _server->createService(NUS_SERVICE_UUID);

        // TX characteristic: ESP32 → app (notify)
        _tx_char = svc->createCharacteristic(
            NUS_CHAR_TX_UUID,
            BLECharacteristic::PROPERTY_NOTIFY
        );
        _tx_char->addDescriptor(new BLE2902());

        // RX characteristic: app → ESP32 (write)
        _rx_char = svc->createCharacteristic(
            NUS_CHAR_RX_UUID,
            BLECharacteristic::PROPERTY_WRITE |
            BLECharacteristic::PROPERTY_WRITE_NR
        );
        _rx_char->setCallbacks(this);

        svc->start();

        BLEAdvertising* adv = BLEDevice::getAdvertising();
        adv->addServiceUUID(NUS_SERVICE_UUID);
        adv->setScanResponse(true);
        adv->setMinPreferred(0x06);
        BLEDevice::startAdvertising();
    }

    // ─── Enviar telemetría ─────────────────────────────────
    void sendTelemetry(float pitch, float roll, float zmp_x, float zmp_y,
                       GaitPhase phase)
    {
        if (!connected) return;

        // Enviar datos IMU
        char buf[64];
        snprintf(buf, sizeof(buf), "IMU:%.3f:%.3f", pitch, roll);
        _tx_char->setValue((uint8_t*)buf, strlen(buf));
        _tx_char->notify();

        // Enviar ZMP
        snprintf(buf, sizeof(buf), "ZMP:%.2f:%.2f", zmp_x, zmp_y);
        _tx_char->setValue((uint8_t*)buf, strlen(buf));
        _tx_char->notify();

        // Fase actual
        const char* phase_str = phaseToStr(phase);
        snprintf(buf, sizeof(buf), "PHASE:%s", phase_str);
        _tx_char->setValue((uint8_t*)buf, strlen(buf));
        _tx_char->notify();
    }

    // ──────────────────────────────────────────────────────
    // Callbacks del servidor BLE
    void onConnect(BLEServer*) override    { connected = true;  }
    void onDisconnect(BLEServer*) override {
        connected = false;
        BLEDevice::startAdvertising();    // re-advertise al desconectarse
    }

    // ─── Callback de recepción de datos ──────────────────
    void onWrite(BLECharacteristic* c) override
    {
        std::string val = c->getValue();
        if (val.empty()) return;
        parseCommand(val.c_str());
    }

private:
    BLEServer*         _server  = nullptr;
    BLECharacteristic* _tx_char = nullptr;
    BLECharacteristic* _rx_char = nullptr;

    // ─── Parsear comando recibido ─────────────────────────
    void parseCommand(const char* cmd)
    {
        if (!g_gait_ptr) return;

        if (strncmp(cmd, "CMD:", 4) == 0) {
            const char* c = cmd + 4;
            if      (strcmp(c, "FORWARD")    == 0) g_gait_ptr->command = GaitCommand::FORWARD;
            else if (strcmp(c, "BACKWARD")   == 0) g_gait_ptr->command = GaitCommand::BACKWARD;
            else if (strcmp(c, "TURN_LEFT")  == 0) g_gait_ptr->command = GaitCommand::TURN_LEFT;
            else if (strcmp(c, "TURN_RIGHT") == 0) g_gait_ptr->command = GaitCommand::TURN_RIGHT;
            else if (strcmp(c, "STOP")       == 0) g_gait_ptr->command = GaitCommand::STOP;
            else if (strcmp(c, "STAND")      == 0) g_gait_ptr->command = GaitCommand::STAND;
        }
        else if (strncmp(cmd, "PARAM:", 6) == 0) {
            char key[32], val_str[16];
            if (sscanf(cmd + 6, "%31[^:]:%15s", key, val_str) == 2) {
                float v = atof(val_str);
                if      (strcmp(key, "KP")       == 0) g_kp = v;
                else if (strcmp(key, "KD")       == 0) g_kd = v;
                else if (strcmp(key, "STEP_LEN") == 0) g_gait_ptr->step_length  = v;
                else if (strcmp(key, "STEP_H")   == 0) g_gait_ptr->step_height  = v;
                else if (strcmp(key, "T_SWING")  == 0) g_gait_ptr->t_swing      = v;
            }
        }
        else if (strncmp(cmd, "TRIM:", 5) == 0) {
            int idx; float trim;
            if (sscanf(cmd + 5, "%d:%f", &idx, &trim) == 2 && g_trim_cb) {
                g_trim_cb(idx, trim);
            }
        }
    }

    static const char* phaseToStr(GaitPhase p) {
        switch (p) {
        case GaitPhase::IDLE:       return "IDLE";
        case GaitPhase::TRANSFER_R: return "XFER_R";
        case GaitPhase::SWING_L:    return "SWING_L";
        case GaitPhase::TRANSFER_L: return "XFER_L";
        case GaitPhase::SWING_R:    return "SWING_R";
        default:                    return "UNKNOWN";
        }
    }
};
