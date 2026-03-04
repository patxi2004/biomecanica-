#pragma once
#include <cmath>
#include "config.h"

// ============================================================
//  kinematics.h  —  Cinemática directa e inversa
//  Sistema de coordenadas:
//    Origen: articulación de cadera de la pierna analizada
//    X+ : adelante
//    Y+ : izquierda (separación de piernas)
//    Z+ : arriba
// ============================================================

// ─── Estructura para los ángulos de una pierna ─────────────
struct LegAngles {
    float hip_flex;   // flexión/extensión cadera [rad]
    float hip_abd;    // abducción/aducción cadera [rad]
    float knee;       // flexión rodilla           [rad]
    float ankle;      // flexión tobillo           [rad]
    bool  valid;      // false si está fuera de rango
};

// ─── Posición cartesiana del extremo del pie ───────────────
struct Vec3 {
    float x, y, z;
};

// ─── Posición 2D para ZMP y CoM ────────────────────────────
struct Vec2 {
    float x, y;
};

// ============================================================
//  Cinemática directa  —  ángulos → posición del tobillo
//  Entrada:  ángulos en radianes
//  Salida:   posición 3D del tobillo (centro planta del pie)
//            respecto al origen de cadera
// ============================================================
inline Vec3 forwardKinematics(const LegAngles& a)
{
    // ─ Plano sagital (X-Z):
    //   Pelvis → fémur → tibia → tobillo
    float xk = L1 * sinf(a.hip_flex);
    float zk = -L1 * cosf(a.hip_flex);

    float xt = xk + L2 * sinf(a.hip_flex + a.knee);
    float zt = zk - L2 * cosf(a.hip_flex + a.knee);

    // ─ Plano frontal (Y-Z): desplazamiento lateral por abducción
    float y_abd = L1 * sinf(a.hip_abd)
                + L2 * sinf(a.hip_abd);   // aproximación lineal

    return { xt, y_abd, zt - L3 };
}

// ============================================================
//  Cinemática inversa — IK analítica
//
//  Entrada:
//    target  — posición deseada del extremo del pie (tobillo)
//              relativa al origen de cadera [cm]
//    ankle_correction — Δθ de corrección IMU para el tobillo
//
//  Salida:
//    LegAngles con los ángulos calculados, valid=false si
//    el punto está fuera del espacio de trabajo.
// ============================================================
inline LegAngles inverseKinematics(Vec3 target, float ankle_correction = 0.0f)
{
    LegAngles result{};
    result.valid = true;

    // ── Plano frontal: abducción cadera ─────────────────────
    // El componente Y del target indica desplazamiento lateral
    result.hip_abd = atan2f(target.y, -target.z);

    // Proyectar al plano sagital descontando desplazamiento Y
    float z_proj = target.z / cosf(result.hip_abd);  // z efectivo en sagital

    // ── Plano sagital: IK con ley del coseno ────────────────
    float x = target.x;
    float z = z_proj;

    // Distancia directa cadera → tobillo
    float D2 = x * x + z * z;
    float D  = sqrtf(D2);

    // Verificar espacio de trabajo
    if (D > (L1 + L2) * 0.999f) {
        // Punto fuera de rango: estirar la pierna al máximo
        D = (L1 + L2) * 0.999f;
        result.valid = false;
    }
    if (D < 0.5f) {
        D = 0.5f;
        result.valid = false;
    }

    // Ángulo de rodilla (ley del coseno)
    float cos_beta = (L1 * L1 + L2 * L2 - D2) / (2.0f * L1 * L2);
    cos_beta = fmaxf(-1.0f, fminf(1.0f, cos_beta));  // saturar
    float beta = acosf(cos_beta);
    result.knee = M_PI - beta;   // ángulo de flexión (siempre ≥ 0)

    // Ángulo de cadera
    float cos_alpha = (L1 * L1 + D2 - L2 * L2) / (2.0f * L1 * D);
    cos_alpha = fmaxf(-1.0f, fminf(1.0f, cos_alpha));
    float alpha = acosf(cos_alpha);
    float gamma = atan2f(x, -z);           // ángulo del vector cadera→tobillo
    result.hip_flex = gamma - alpha;

    // Ángulo de tobillo: mantiene el pie paralelo al suelo
    result.ankle = -(result.hip_flex + result.knee) + ankle_correction;

    // ── Saturar a límites físicos ────────────────────────────
    auto clamp = [](float v, float mn, float mx) {
        return fmaxf(mn, fminf(mx, v));
    };
    float hip_flex_min = HIP_FLEX_MIN * M_PI / 180.0f;
    float hip_flex_max = HIP_FLEX_MAX * M_PI / 180.0f;
    float hip_abd_min  = HIP_ABD_MIN  * M_PI / 180.0f;
    float hip_abd_max  = HIP_ABD_MAX  * M_PI / 180.0f;
    float knee_min     = KNEE_MIN     * M_PI / 180.0f;
    float knee_max     = KNEE_MAX     * M_PI / 180.0f;
    float ankle_min    = ANKLE_MIN    * M_PI / 180.0f;
    float ankle_max    = ANKLE_MAX    * M_PI / 180.0f;

    result.hip_flex = clamp(result.hip_flex, hip_flex_min, hip_flex_max);
    result.hip_abd  = clamp(result.hip_abd,  hip_abd_min,  hip_abd_max);
    result.knee     = clamp(result.knee,     knee_min,     knee_max);
    result.ankle    = clamp(result.ankle,    ankle_min,    ankle_max);

    return result;
}

// ============================================================
//  Centro de Masa simplificado (modelo de 5 segmentos)
//
//  Entrada: ángulos de ambas piernas
//  Salida:  proyección XY del CoM en el plano del suelo
//           (relativo al punto medio entre ambas caderas)
// ============================================================
inline Vec2 computeCoM(const LegAngles& left, const LegAngles& right)
{
    // Posición de cada articulación en el marco del mundo
    // Origen = punto medio entre caderas (suelo)
    // Cadera izq: (-D_HIP/2, 0, L1+L2+L3)  Cadera der: (+D_HIP/2, 0, ...)

    float hip_height = L1 + L2 + L3;

    // ─ Pierna izquierda ─────────────────────────────────────
    float lhx = -D_HIP / 2.0f;
    float lhy =  0.0f;
    float lhz =  hip_height;

    // Rodilla izq
    float lkx = lhx + L1 * sinf(left.hip_flex);
    float lkz = lhz - L1 * cosf(left.hip_flex);

    // Tobillo izq
    float ltx = lkx + L2 * sinf(left.hip_flex + left.knee);
    float ltz = lkz - L2 * cosf(left.hip_flex + left.knee);

    // ─ Pierna derecha ────────────────────────────────────────
    float rhx =  D_HIP / 2.0f;
    float rhy =  0.0f;
    float rhz =  hip_height;

    float rkx = rhx + L1 * sinf(right.hip_flex);
    float rkz = rhz - L1 * cosf(right.hip_flex);

    float rtx = rkx + L2 * sinf(right.hip_flex + right.knee);
    float rtz = rkz - L2 * cosf(right.hip_flex + right.knee);

    // ─ CoM ponderado ─────────────────────────────────────────
    // Pelvis (centro entre caderas)
    float com_x = 0.0f * MASS_PELVIS;   // pelvis centrada en X
    float com_y = 0.0f * MASS_PELVIS;

    // Fémures (mitad del segmento)
    com_x += ((lhx + lkx) / 2.0f) * MASS_FEMUR;
    com_x += ((rhx + rkx) / 2.0f) * MASS_FEMUR;
    com_y += lhy * MASS_FEMUR;
    com_y += rhy * MASS_FEMUR;

    // Tibias
    com_x += ((lkx + ltx) / 2.0f) * MASS_TIBIA;
    com_x += ((rkx + rtx) / 2.0f) * MASS_TIBIA;
    com_y += lhy * MASS_TIBIA;
    com_y += rhy * MASS_TIBIA;

    // Pies
    com_x += ltx * MASS_FOOT;
    com_x += rtx * MASS_FOOT;

    float total = MASS_PELVIS + 2.0f * (MASS_FEMUR + MASS_TIBIA + MASS_FOOT);
    return { com_x / total, com_y / total };
}

// ============================================================
//  Verificación ZMP (marcha estática: ZMP ≈ CoM proyectado)
//
//  Devuelve true si el ZMP está dentro del polígono de soporte.
//  support_center_y: posición Y del centro del pie de soporte
//  (= +D_HIP/2 para pie derecho, -D_HIP/2 para pie izquierdo)
// ============================================================
inline bool checkZMP(Vec2 com, float support_center_x, float support_center_y,
                     float margin_cm = 0.5f)
{
    float half_len = FOOT_LEN / 2.0f - margin_cm;
    float half_w   = FOOT_W   / 2.0f - margin_cm;

    bool in_x = (com.x > support_center_x - half_len) &&
                (com.x < support_center_x + half_len);
    bool in_y = (com.y > support_center_y - half_w)   &&
                (com.y < support_center_y + half_w);
    return in_x && in_y;
}
