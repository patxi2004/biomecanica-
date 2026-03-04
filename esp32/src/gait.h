#pragma once
#include <cmath>
#include "config.h"
#include "kinematics.h"

// ============================================================
//  gait.h  —  Generador de trayectoria de marcha estática
//
//  Ciclo de 4 fases:
//    IDLE        → postura neutral, robot quieto
//    TRANSFER_R  → desplazar CoM sobre pie derecho
//    SWING_L     → levantar y avanzar pie izquierdo
//    TRANSFER_L  → desplazar CoM sobre pie izquierdo
//    SWING_R     → levantar y avanzar pie derecho
// ============================================================

enum class GaitCommand {
    STOP = 0,
    FORWARD,
    BACKWARD,
    TURN_LEFT,
    TURN_RIGHT,
    STAND,
    RECOVER       // Recuperar postura tras caída
};

enum class GaitPhase {
    IDLE = 0,
    TRANSFER_R,   // mover CoM hacia pie derecho
    SWING_L,      // pierna izquierda en swing
    TRANSFER_L,   // mover CoM hacia pie izquierdo
    SWING_R       // pierna derecha en swing
};

struct GaitState {
    LegAngles left;
    LegAngles right;
    Vec2      com;
    GaitPhase phase;
    float     phase_t;   // tiempo normalizado dentro de la fase [0..1]
};

// ============================================================
class GaitGenerator {
public:
    // ─── Parámetros configurables ──────────────────────────
    float step_length  = STEP_LENGTH_DEFAULT;
    float step_height  = STEP_HEIGHT_DEFAULT;
    float t_swing      = T_SWING_DEFAULT;
    float t_transfer   = T_TRANSFER_DEFAULT;

    // ─── Estado interno ────────────────────────────────────
    GaitCommand command  = GaitCommand::STAND;
    GaitPhase   phase    = GaitPhase::IDLE;
    float       phase_t  = 0.0f;   // [0..1] dentro de la fase actual

    // Posiciones mundo de los pies (X, Y) — actualizan con cada paso
    // Origen = punto medio inter-cadera, Z = suelo
    float left_foot_x  = 0.0f;
    float right_foot_x = 0.0f;

    // Alturas de pie (Z): 0 = apoyado, >0 = en el aire
    float left_foot_z  = 0.0f;
    float right_foot_z = 0.0f;

    // ─── Postura neutral ────────────────────────────────────
    //  Cadera al suelo: L1+L2+L3 cm en total
    //  Tobillo target en postura neutral (recto, sin flexión)
    Vec3 neutralTarget() const {
        return { 0.0f, 0.0f, -(L1 + L2 + L3) };
    }

    // ─── Postura lateral para soporte ──────────────────────
    //  Al transferir el CoM, se usa abducción cadera
    //  Para simplificar: el tobillo se mantiene en el mismo X,Z
    //  y el Y_abd desplaza la cadera sobre el pie de soporte
    Vec3 targetWithAbd(float foot_world_x, float y_abd_offset) const {
        // Tobillo en el frame de la cadera:
        //   X = posición del pie en mundo - posición cadera en mundo
        //   Y = desplazamiento lateral de la cadera (abducción)
        //   Z = -(L1+L2+L3) (pierna extendida)
        return { foot_world_x, y_abd_offset, -(L1 + L2 + L3) };
    }

    // ============================================================
    //  update(dt)  —  Avanza el generador de marcha
    //
    //  dt: tiempo transcurrido desde el último llamado [segundos]
    //  ankle_corr: corrección IMU para el tobillo [rad]
    //
    //  Devuelve el estado actual (ángulos + fase)
    // ============================================================
    GaitState update(float dt, float ankle_corr = 0.0f)
    {
        GaitState state{};
        state.phase = phase;

        // Signo del paso: positivo = adelante, negativo = atrás
        float step_dir = (command == GaitCommand::BACKWARD) ? -1.0f : 1.0f;

        switch (phase) {
        // ── IDLE / STAND ──────────────────────────────────────
        case GaitPhase::IDLE: {
            Vec3 tgt = neutralTarget();
            state.left  = inverseKinematics(tgt, ankle_corr);
            state.right = inverseKinematics(tgt, ankle_corr);
            if (command == GaitCommand::RECOVER) {
                // Recuperar: ir a postura neutral y volver a STAND
                command = GaitCommand::STAND;
            } else if (command == GaitCommand::FORWARD ||
                command == GaitCommand::BACKWARD ||
                command == GaitCommand::TURN_LEFT ||
                command == GaitCommand::TURN_RIGHT) {
                phase   = GaitPhase::TRANSFER_R;
                phase_t = 0.0f;
            }
            break;
        }

        // ── TRANSFERENCIA DE CoM → DERECHA ───────────────────
        case GaitPhase::TRANSFER_R: {
            phase_t += dt / t_transfer;
            if (phase_t > 1.0f) { phase_t = 1.0f; }

            // Coseno suavizado [0→1]
            float s = (1.0f - cosf(M_PI * phase_t)) / 2.0f;
            // y_off: desplaza la pelvis D_HIP/2 sobre pie derecho
            float y_off = -s * D_HIP * 0.45f;  // negativo = hacia derecha

            Vec3 tgt_r = targetWithAbd(right_foot_x,  y_off);
            Vec3 tgt_l = targetWithAbd(left_foot_x,   y_off);

            state.right = inverseKinematics(tgt_r, ankle_corr);
            state.left  = inverseKinematics(tgt_l, ankle_corr);

            if (phase_t >= 1.0f) {
                phase   = GaitPhase::SWING_L;
                phase_t = 0.0f;
            }
            break;
        }

        // ── SWING PIERNA IZQUIERDA ────────────────────────────
        case GaitPhase::SWING_L: {
            phase_t += dt / t_swing;
            if (phase_t > 1.0f) { phase_t = 1.0f; }

            // Arco del pie: parábola seno
            float swing_x_start = left_foot_x;
            float swing_x_end   = left_foot_x + step_dir * step_length;
            float foot_x = swing_x_start + (swing_x_end - swing_x_start) * phase_t;
            float foot_z = step_height * sinf(M_PI * phase_t);

            // Pierna de soporte (derecha): sigue manteniendo CoM a la derecha
            float y_off = -D_HIP * 0.45f;
            Vec3 tgt_r = targetWithAbd(right_foot_x, y_off);

            // Pierna swing (izquierda): tobillo en (foot_x, 0, -(L1+L2+L3-foot_z))
            Vec3 tgt_l = { foot_x, y_off, -(L1 + L2 + L3 - foot_z) };

            state.right = inverseKinematics(tgt_r, ankle_corr);
            state.left  = inverseKinematics(tgt_l, ankle_corr);

            if (phase_t >= 1.0f) {
                left_foot_x = swing_x_end;   // actualizar posición del pie
                phase   = GaitPhase::TRANSFER_L;
                phase_t = 0.0f;
            }
            break;
        }

        // ── TRANSFERENCIA DE CoM → IZQUIERDA ──────────────────
        case GaitPhase::TRANSFER_L: {
            phase_t += dt / t_transfer;
            if (phase_t > 1.0f) { phase_t = 1.0f; }

            float s     = (1.0f - cosf(M_PI * phase_t)) / 2.0f;
            float y_off = (s - 1.0f) * D_HIP * 0.45f;  // va de -D/2 a 0 a +D/2

            Vec3 tgt_r = targetWithAbd(right_foot_x, y_off);
            Vec3 tgt_l = targetWithAbd(left_foot_x,  y_off);

            state.right = inverseKinematics(tgt_r, ankle_corr);
            state.left  = inverseKinematics(tgt_l, ankle_corr);

            if (phase_t >= 1.0f) {
                // Si comando es STOP → volver a IDLE
                if (command == GaitCommand::STOP ||
                    command == GaitCommand::STAND ||
                    command == GaitCommand::RECOVER) {
                    phase = GaitPhase::IDLE;
                } else {
                    phase   = GaitPhase::SWING_R;
                }
                phase_t = 0.0f;
            }
            break;
        }

        // ── SWING PIERNA DERECHA ──────────────────────────────
        case GaitPhase::SWING_R: {
            phase_t += dt / t_swing;
            if (phase_t > 1.0f) { phase_t = 1.0f; }

            float swing_x_start = right_foot_x;
            float swing_x_end   = right_foot_x + step_dir * step_length;
            float foot_x = swing_x_start + (swing_x_end - swing_x_start) * phase_t;
            float foot_z = step_height * sinf(M_PI * phase_t);

            float y_off = D_HIP * 0.45f;  // CoM sobre izquierda
            Vec3 tgt_l = targetWithAbd(left_foot_x, y_off);
            Vec3 tgt_r = { foot_x, y_off, -(L1 + L2 + L3 - foot_z) };

            state.left  = inverseKinematics(tgt_l, ankle_corr);
            state.right = inverseKinematics(tgt_r, ankle_corr);

            if (phase_t >= 1.0f) {
                right_foot_x = swing_x_end;
                // Si comando es STOP → TRANSFER_L para volver a neutro
                if (command == GaitCommand::STOP ||
                    command == GaitCommand::STAND) {
                    phase = GaitPhase::TRANSFER_L;
                } else {
                    phase = GaitPhase::TRANSFER_R;
                }
                phase_t = 0.0f;
            }
            break;
        }
        }

        state.phase_t = phase_t;
        state.com     = computeCoM(state.left, state.right);
        return state;
    }

    // ─── Reset a postura neutral ────────────────────────────
    void reset() {
        phase        = GaitPhase::IDLE;
        phase_t      = 0.0f;
        left_foot_x  = 0.0f;
        right_foot_x = 0.0f;
        command      = GaitCommand::STAND;
    }
};
