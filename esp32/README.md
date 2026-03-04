# Firmware ESP32 — Exo-Robot

## Librerías requeridas (instalar desde Gestor de Librerías del IDE)

| Librería | Versión recomendada | Fuente |
|---|---|---|
| Adafruit PWM Servo Driver Library | ≥ 2.4 | Gestor de librerías |
| MPU6050_light by rfetick | ≥ 1.1 | Gestor de librerías |
| ArduinoJson | ≥ 6.21 | Gestor de librerías |
| BluetoothSerial | — | Incluida con el paquete ESP32 |
| WiFi | — | Incluida con el paquete ESP32 (requerida por ArduinoOTA) |
| ArduinoOTA | — | Incluida con el paquete ESP32 |
| Wire | — | Incluida con Arduino |

---

## Asignación de canales PCA9685

| Canal | Servo | Articulación |
|---|---|---|
| 0 | S1 | Cadera izquierda |
| 1 | S2 | Cadera derecha |
| 2 | S3 | Rodilla izquierda |
| 3 | S4 | Rodilla derecha |
| 4 | S5 | **Tobillo izquierdo** (corrección de balance) |
| 5 | S6 | **Tobillo derecho** (corrección de balance) |

---

## Parámetros configurables en el código

| Constante | Valor por defecto | Descripción |
|---|---|---|
| `Kp` | 2.5 | Ganancia proporcional del balance |
| `Kd` | 0.8 | Ganancia derivativa del balance |
| `walkSpeed` | 1.0 | Factor de velocidad (0.3× – 3.0×) |
| `FALL_THRESHOLD` | 45.0° | Ángulo de roll que activa protocolo FALLEN |
| `GAIT_BASE_MS` | 150 ms | Intervalo entre frames a velocidad 1.0× |
| `REST_HIP/KNEE/ANKLE` | 90° | Ángulo de reposo de cada articulación |

---

## Protocolo Bluetooth (JSON + `\n`)

### App → ESP32

```json
{"cmd":"START"}
{"cmd":"STOP"}
{"cmd":"SPEED","val":1.5}
{"cmd":"KP","val":2.5}
{"cmd":"KD","val":0.8}
{"cmd":"GETUP"}
```

### ESP32 → App (cada 100 ms)

```json
{"roll":4.2,"pitch":0.8,"walking":true,"speed":1.0,"kp":2.5,"kd":0.8,"fallen":false}
```

---

## Primera carga (USB)

1. Abrir `exo_robot/exo_robot.ino` en Arduino IDE 2.x
2. Herramientas → Placa → **ESP32 Dev Module**
3. Herramientas → Puerto → seleccionar el COM del ESP32
4. Subir con el botón **→ Upload**

El Monitor Serial a 115200 baud mostrará el proceso de calibración del IMU (~1 s).

## Actualizaciones posteriores (OTA)

> **Realidad técnica:** `ArduinoOTA` necesita WiFi. Bluetooth **no** sirve para OTA.  
> El firmware usa **Bluetooh para control** y **WiFi únicamente para subir firmware** (sin servidor web, sin control por WiFi).

**Antes de la primera carga**, edita en `exo_robot.ino`:
```cpp
#define WIFI_SSID  "TU_RED_WIFI"
#define WIFI_PASS  "TU_CONTRASENA"
```

Una vez cargado el firmware base con USB:

1. Asegurarse de que la **laptop esté en la misma red WiFi** que se configuró en el firmware.
2. En Herramientas → Puerto aparecerá **Exo-Robot (ESP32)**.
3. Seleccionar ese puerto y subir — sin cable USB.
4. El exo se detiene brevemente y se reinicia solo al terminar.

> ⚠ La primera carga **siempre debe ser con USB**. OTA solo funciona si el firmware ya tiene `ArduinoOTA.handle()` en el loop.

**Modo carrera:** Si no hay WiFi disponible, el exo arranca igual y el control Bluetooth funciona con normalidad. Solo se pierde la opción OTA.

---

## Máquina de estados

```
         START cmd
  IDLE ──────────────► WALKING
   ▲                      │
   │  STOP cmd             │
   └──────────────────────┘
   ▲
   │  GETUP completo
 GETUP ◄──── FALLEN ◄── |roll| > 45°
```

---

## Notas de calibración

- Al encender, el MPU-6050 tarda ~1 s en calibrar. **No mover el exo durante ese tiempo.**
- Si los servos tiemblan sin motivo: verificar que el PCA9685 tiene 3.3 V en VCC y 5 V en V+.
- Si el ESP32 se reinicia al mover servos: los servos y el ESP32 comparten el riel de alimentación. Usar los dos módulos buck con GND común pero salidas separadas.
