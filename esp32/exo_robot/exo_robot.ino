// ============================================================
//  Exo-Robot — Firmware ESP32
//  Placa    : ESP32 Dev Module
//  Hardware : PCA9685 (servos) + MPU-6050 (IMU) via I²C
//  Libs     : Adafruit PWM Servo Driver, MPU6050_light,
//             BluetoothSerial, WiFi (solo OTA), ArduinoOTA,
//             ArduinoJson
// ============================================================

#include <Wire.h>
#include <WiFi.h>                    // Requerido por ArduinoOTA
#include <Adafruit_PWMServoDriver.h>
#include <MPU6050_light.h>
#include <BluetoothSerial.h>
#include <ArduinoOTA.h>
#include <ArduinoJson.h>

// ============================================================
//  CONFIGURACIÓN GLOBAL
// ============================================================

#define DEVICE_NAME   "Exo-Robot"   // Nombre BT y hostname OTA
#define OTA_PASSWORD  "1234"        // Contraseña OTA (cámbiala)

// --- WiFi — solo para OTA (no se usa para control ni servidor web) ---
// ⚠ ArduinoOTA requiere WiFi; el control del exo siempre va por Bluetooth.
#define WIFI_SSID  "TU_RED_WIFI"     // ← cambia esto
#define WIFI_PASS  "TU_CONTRASENA"   // ← cambia esto

// --- PCA9685 ---
#define SERVO_FREQ    50            // Hz PWM (servos estándar)
#define SERVO_MIN    150            // Tick para ~0°
#define SERVO_MAX    600            // Tick para ~180°

// --- Canales PCA9685 → Servos ---
//  S1 Ch0 → Cadera izquierda
//  S2 Ch1 → Cadera derecha
//  S3 Ch2 → Rodilla izquierda
//  S4 Ch3 → Rodilla derecha
//  S5 Ch4 → Tobillo izquierdo (corrección de balance)
//  S6 Ch5 → Tobillo derecho   (corrección de balance)
#define CH_HIP_L     0   // S1
#define CH_HIP_R     1   // S2
#define CH_KNEE_L    2   // S3
#define CH_KNEE_R    3   // S4
#define CH_ANKLE_L   4   // S5 — tobillo izquierdo
#define CH_ANKLE_R   5   // S6 — tobillo derecho

// Ángulo de reposo de cada articulación (grados)
#define REST_HIP     90
#define REST_KNEE    90
#define REST_ANKLE   90

// --- Umbrales de caída ---
#define FALL_THRESHOLD  45.0f       // |roll| > 45° → caído

// --- Telemetría ---
#define TELEMETRY_MS   100          // Intervalo de envío (ms)
#define MPU_READ_MS     10          // Intervalo de lectura IMU (ms)

// --- Ciclo de marcha ---
#define GAIT_FRAMES      8          // Número de frames del ciclo
#define GAIT_BASE_MS   150          // ms entre frames a velocidad 1.0×
                                    // Rango real: 50ms (3.0×) – 500ms (0.3×)

// ============================================================
//  ESTADO DE LA MÁQUINA
// ============================================================

enum State { IDLE, WALKING, GETUP, FALLEN };
State currentState = IDLE;

// ============================================================
//  PARÁMETROS AJUSTABLES (modificables desde la app)
// ============================================================

float walkSpeed = 1.0f;   // Factor 0.3 – 3.0
float Kp        = 2.5f;   // Ganancia proporcional del balance
float Kd        = 0.8f;   // Ganancia derivativa del balance

// ============================================================
//  CICLO DE MARCHA — 8 frames
//  Formato por fila: { hipR(ch1), kneeR(ch3), hipL(ch0), kneeL(ch2) } en grados
//  Los tobillos S5(ch4) y S6(ch5) son controlados exclusivamente por el PD
// ============================================================

const int gaitCycle[GAIT_FRAMES][4] = {
  //  hipR  kneeR  hipL  kneeL
  {  100,    80,    80,   100 },  // F0 — traslado peso a pierna izq
  {  105,    85,    85,    95 },  // F1 — pie derecho se levanta
  {  100,    90,    90,    90 },  // F2 — neutro
  {   90,    95,    95,    85 },  // F3 — pie izquierdo se levanta
  {   80,   100,   100,    80 },  // F4 — traslado peso a pierna der
  {   85,    95,    95,    85 },  // F5 — avance izquierdo
  {   90,    90,    90,    90 },  // F6 — neutro
  {   95,    85,    85,    95 },  // F7 — avance derecho
};

int gaitFrameIndex = 0;

// ============================================================
//  OBJETOS
// ============================================================

Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver(); // I²C 0x40
MPU6050 mpu(Wire);
BluetoothSerial SerialBT;

// ============================================================
//  VARIABLES DE CONTROL DE TIEMPO
// ============================================================

unsigned long lastMpuRead   = 0;
unsigned long lastTelemetry = 0;
unsigned long lastGaitStep  = 0;

// ============================================================
//  VARIABLES IMU
// ============================================================

float roll      = 0.0f;
float pitch     = 0.0f;
float prevRoll  = 0.0f;
bool  fallen    = false;

// ============================================================
//  BUFFER BLUETOOTH
//  Los mensajes llegan en chunks; se acumulan hasta encontrar \n
// ============================================================

String btBuffer = "";

// ============================================================
//  FUNCIONES AUXILIARES — SERVOS
// ============================================================

/**
 * Convierte ángulo (0–180°) a tick PCA9685.
 */
int angleToPulse(int angle) {
  return map(constrain(angle, 0, 180), 0, 180, SERVO_MIN, SERVO_MAX);
}

/**
 * Mueve un canal del PCA9685 al ángulo indicado.
 */
void setServoAngle(uint8_t ch, int angle) {
  pwm.setPWM(ch, 0, angleToPulse(angle));
}

/**
 * Lleva todos los servos a posición de reposo en un solo llamado.
 */
void goToRestPosition() {
  setServoAngle(CH_HIP_R,   REST_HIP);
  setServoAngle(CH_KNEE_R,  REST_KNEE);
  setServoAngle(CH_HIP_L,   REST_HIP);
  setServoAngle(CH_KNEE_L,  REST_KNEE);
  setServoAngle(CH_ANKLE_R, REST_ANKLE);
  setServoAngle(CH_ANKLE_L, REST_ANKLE);
}

// ============================================================
//  SETUP
// ============================================================

void setup() {
  Serial.begin(115200);
  Wire.begin();

  // --- PCA9685 ---
  pwm.begin();
  pwm.setOscillatorFrequency(27000000);  // Frecuencia de oscilador interna
  pwm.setPWMFreq(SERVO_FREQ);
  delay(10);
  goToRestPosition();
  Serial.println("[PCA9685] Listo.");

  // --- MPU-6050 ---
  byte mpuStatus = mpu.begin();
  Serial.print("[MPU6050] Status: ");
  Serial.println(mpuStatus);
  if (mpuStatus != 0) {
    Serial.println("[MPU6050] ERROR: no se detectó. Revisa cableado I²C (SDA/SCL).");
    // Continúa sin IMU (modo degradado) — no bloquea el boot
  } else {
    Serial.println("[MPU6050] Calculando offsets. No mover el exo...");
    delay(1000);
    mpu.calcOffsets(true, true);   // Calibra giroscopio y acelerómetro
    Serial.println("[MPU6050] Calibración completa.");
  }

  // --- Bluetooth Classic (control en tiempo real) ---
  SerialBT.begin(DEVICE_NAME);
  Serial.print("[BT] Dispositivo listo. Nombre: ");
  Serial.println(DEVICE_NAME);

  // --- WiFi — solo para OTA (sin servidor web, sin control por WiFi) ---
  Serial.print("[WiFi] Conectando a ");
  Serial.print(WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int wifiRetries = 0;
  while (WiFi.status() != WL_CONNECTED && wifiRetries < 20) {
    delay(500);
    Serial.print(".");
    wifiRetries++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("\n[WiFi] Conectado. IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n[WiFi] Sin conexión — OTA no disponible. Control BT sigue activo.");
  }

  // --- OTA (Over The Air via WiFi) ---
  ArduinoOTA.setHostname(DEVICE_NAME);
  ArduinoOTA.setPassword(OTA_PASSWORD);

  ArduinoOTA.onStart([]() {
    String type = (ArduinoOTA.getCommand() == U_FLASH) ? "sketch" : "filesystem";
    Serial.println("[OTA] Iniciando actualización de: " + type);
    currentState = IDLE;
    goToRestPosition();   // Posición segura antes de actualizar
  });

  ArduinoOTA.onEnd([]() {
    Serial.println("\n[OTA] Actualización completa. Reiniciando...");
  });

  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("[OTA] Progreso: %u%%\r", (progress / (total / 100)));
  });

  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("[OTA] Error[%u]: ", error);
    if      (error == OTA_AUTH_ERROR)    Serial.println("Fallo de autenticación.");
    else if (error == OTA_BEGIN_ERROR)   Serial.println("Fallo al comenzar.");
    else if (error == OTA_CONNECT_ERROR) Serial.println("Fallo de conexión.");
    else if (error == OTA_RECEIVE_ERROR) Serial.println("Fallo de recepción.");
    else if (error == OTA_END_ERROR)     Serial.println("Fallo al finalizar.");
  });

  ArduinoOTA.begin();
  Serial.println("[OTA] Escuchando actualizaciones inalámbricas.");
  Serial.println("[BOOT] Exo-Robot listo.\n");
}

// ============================================================
//  LECTURA IMU + DETECCIÓN DE CAÍDA
// ============================================================

void readMPU() {
  mpu.update();
  prevRoll = roll;
  roll     = mpu.getAngleX();   // Roll  = inclinación lateral
  pitch    = mpu.getAngleY();   // Pitch = inclinación frontal

  bool nowFallen = (abs(roll) > FALL_THRESHOLD);

  if (nowFallen && !fallen) {
    fallen       = true;
    currentState = FALLEN;
    goToRestPosition();
    Serial.printf("[FALL] Caída detectada. Roll=%.1f°\n", roll);
  } else if (!nowFallen && fallen) {
    // Se recuperó (posiblemente por GETUP)
    fallen = false;
    if (currentState == FALLEN) currentState = IDLE;
  }
}

// ============================================================
//  CORRECCIÓN PD DE BALANCE
//  Solo actúa sobre S5 (CH_ANKLE_R) y S6 (CH_ANKLE_L)
//  Se ejecuta siempre — incluso durante la marcha
// ============================================================

void applyBalanceCorrection() {
  if (fallen) return;

  const float dt          = MPU_READ_MS / 1000.0f;   // segundos
  float error             = roll;                    // 0° = vertical
  float derivative        = (roll - prevRoll) / dt;
  float correction        = Kp * error + Kd * derivative;

  // Limitar corrección para no dañar el servomecanismo
  correction = constrain(correction, -30.0f, 30.0f);

  // S5 (tobillo izq, ch4): se inclina cuando roll es positivo (cae a la derecha)
  setServoAngle(CH_ANKLE_L, (int)(REST_ANKLE + correction));
  // S6 (tobillo der, ch5): sentido contrario para acción coordinada
  setServoAngle(CH_ANKLE_R, (int)(REST_ANKLE - correction));
}

// ============================================================
//  CICLO DE MARCHA — avanza un frame
// ============================================================

void executeGaitStep() {
  const int* frame = gaitCycle[gaitFrameIndex];
  setServoAngle(CH_HIP_R,  frame[0]);
  setServoAngle(CH_KNEE_R, frame[1]);
  setServoAngle(CH_HIP_L,  frame[2]);
  setServoAngle(CH_KNEE_L, frame[3]);
  gaitFrameIndex = (gaitFrameIndex + 1) % GAIT_FRAMES;
}

// ============================================================
//  PROTOCOLO GETUP
//  Secuencia de levantarse desde posición de caída.
//  Bloquea el loop brevemente (~0.6 s).
// ============================================================

void executeGetUp() {
  currentState = GETUP;
  Serial.println("[GETUP] Iniciando secuencia de levantarse...");

  // Fase 1: rodillas flexionadas para bajar el centro de gravedad
  setServoAngle(CH_KNEE_R, 120);
  setServoAngle(CH_KNEE_L, 120);
  delay(300);

  // Fase 2: extender caderas hacia adelante
  setServoAngle(CH_HIP_R, 100);
  setServoAngle(CH_HIP_L, 100);
  delay(300);

  // Fase 3: volver a posición de reposo
  goToRestPosition();
  delay(200);

  fallen       = false;
  currentState = IDLE;
  Serial.println("[GETUP] Secuencia completa.");
}

// ============================================================
//  PARSEO DE COMANDOS JSON desde la app
// ============================================================

void parseCommand(const String& json) {
  StaticJsonDocument<128> doc;
  DeserializationError err = deserializeJson(doc, json);

  if (err) {
    Serial.print("[BT] JSON inválido: ");
    Serial.println(err.c_str());
    return;
  }

  const char* cmd = doc["cmd"] | "";

  if (strcmp(cmd, "START") == 0) {
    if (!fallen) {
      gaitFrameIndex = 0;
      currentState   = WALKING;
      Serial.println("[CMD] START — marcha iniciada.");
    } else {
      Serial.println("[CMD] START ignorado — exo caído. Usar GETUP primero.");
    }

  } else if (strcmp(cmd, "STOP") == 0) {
    currentState = IDLE;
    goToRestPosition();
    Serial.println("[CMD] STOP — marcha detenida.");

  } else if (strcmp(cmd, "SPEED") == 0) {
    float v   = doc["val"] | 1.0f;
    walkSpeed = constrain(v, 0.3f, 3.0f);
    Serial.printf("[CMD] SPEED → %.2f×\n", walkSpeed);

  } else if (strcmp(cmd, "KP") == 0) {
    Kp = doc["val"] | Kp;
    Serial.printf("[CMD] KP → %.3f\n", Kp);

  } else if (strcmp(cmd, "KD") == 0) {
    Kd = doc["val"] | Kd;
    Serial.printf("[CMD] KD → %.3f\n", Kd);

  } else if (strcmp(cmd, "GETUP") == 0) {
    executeGetUp();

  } else {
    Serial.print("[CMD] Comando desconocido: ");
    Serial.println(cmd);
  }
}

// ============================================================
//  LECTURA BLUETOOTH — maneja chunks y buffer de línea
// ============================================================

void readBluetooth() {
  while (SerialBT.available()) {
    char c = (char)SerialBT.read();
    if (c == '\n') {
      btBuffer.trim();
      if (btBuffer.length() > 0) {
        parseCommand(btBuffer);
      }
      btBuffer = "";      // Limpiar buffer para el próximo mensaje
    } else {
      btBuffer += c;
    }
  }
}

// ============================================================
//  ENVÍO DE TELEMETRÍA al celular (cada 100 ms)
// ============================================================

void sendTelemetry() {
  StaticJsonDocument<256> doc;

  // Redondear a 1 decimal para reducir tráfico
  doc["roll"]    = roundf(roll  * 10.0f) / 10.0f;
  doc["pitch"]   = roundf(pitch * 10.0f) / 10.0f;
  doc["walking"] = (currentState == WALKING);
  doc["speed"]   = walkSpeed;
  doc["kp"]      = Kp;
  doc["kd"]      = Kd;
  doc["fallen"]  = fallen;

  String output;
  serializeJson(doc, output);
  output += '\n';           // Delimitador de mensaje
  SerialBT.print(output);
}

// ============================================================
//  LOOP PRINCIPAL
// ============================================================

void loop() {
  // --- OTA: debe estar siempre en el loop ---
  ArduinoOTA.handle();

  unsigned long now = millis();

  // 1. Lectura IMU cada 10 ms
  if (now - lastMpuRead >= MPU_READ_MS) {
    lastMpuRead = now;
    readMPU();
    applyBalanceCorrection();   // Se aplica siempre, incluso en marcha
  }

  // 2. Ciclo de marcha — intervalo inversamente proporcional a la velocidad
  if (currentState == WALKING) {
    unsigned long interval = (unsigned long)(GAIT_BASE_MS / walkSpeed);
    if (now - lastGaitStep >= interval) {
      lastGaitStep = now;
      executeGaitStep();
    }
  }

  // 3. Recepción de comandos Bluetooth
  readBluetooth();

  // 4. Telemetría cada 100 ms (solo si hay cliente conectado)
  if (now - lastTelemetry >= TELEMETRY_MS) {
    lastTelemetry = now;
    if (SerialBT.hasClient()) {
      sendTelemetry();
    }
  }
}
