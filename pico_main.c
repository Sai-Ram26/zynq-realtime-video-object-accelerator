// ==============================================================================
// File: pico_main.c
// Target: PicoRV32 RV32I Supervisory Processor
// Project: Hardware H.264 Video Compression Accelerator (ZedBoard)
// Stage 3: Dual-Owner Job Mailbox Handshake
// ==============================================================================

#include <stdint.h>

// MMIO Base Address for Accelerator Controller Registers
#define MMIO_BASE               0x80000000U

#define REG_CORE_ID             (*(volatile uint32_t *)(MMIO_BASE + 0x00U))
#define REG_CORE_VERSION        (*(volatile uint32_t *)(MMIO_BASE + 0x04U))
#define REG_CONTROL             (*(volatile uint32_t *)(MMIO_BASE + 0x08U))
#define REG_STATUS              (*(volatile uint32_t *)(MMIO_BASE + 0x0CU))
#define REG_ERROR_CODE          (*(volatile uint32_t *)(MMIO_BASE + 0x10U))
#define REG_JOB_SEQUENCE        (*(volatile uint32_t *)(MMIO_BASE + 0x14U))
#define REG_FRAME_ID_LOW        (*(volatile uint32_t *)(MMIO_BASE + 0x18U))
#define REG_FRAME_ID_HIGH       (*(volatile uint32_t *)(MMIO_BASE + 0x1CU))
#define REG_INPUT_BASE          (*(volatile uint32_t *)(MMIO_BASE + 0x20U))
#define REG_REFERENCE_BASE      (*(volatile uint32_t *)(MMIO_BASE + 0x24U))
#define REG_RECON_BASE          (*(volatile uint32_t *)(MMIO_BASE + 0x28U))
#define REG_CANDIDATE_BASE      (*(volatile uint32_t *)(MMIO_BASE + 0x2CU))
#define REG_METADATA_BASE       (*(volatile uint32_t *)(MMIO_BASE + 0x30U))
#define REG_WIDTH               (*(volatile uint32_t *)(MMIO_BASE + 0x34U))
#define REG_HEIGHT              (*(volatile uint32_t *)(MMIO_BASE + 0x38U))
#define REG_TILES_X             (*(volatile uint32_t *)(MMIO_BASE + 0x3CU))
#define REG_TILES_Y             (*(volatile uint32_t *)(MMIO_BASE + 0x40U))
#define REG_QP                  (*(volatile uint32_t *)(MMIO_BASE + 0x44U))
#define REG_ME_MODE             (*(volatile uint32_t *)(MMIO_BASE + 0x48U))
#define REG_SEARCH_RADIUS       (*(volatile uint32_t *)(MMIO_BASE + 0x4CU))
#define REG_COMPLETED_MB        (*(volatile uint32_t *)(MMIO_BASE + 0x50U))
#define REG_TOTAL_MB            (*(volatile uint32_t *)(MMIO_BASE + 0x54U))
#define REG_IRQ_STATUS          (*(volatile uint32_t *)(MMIO_BASE + 0x78U))
#define REG_IRQ_ENABLE          (*(volatile uint32_t *)(MMIO_BASE + 0x7CU))
#define REG_WATCHDOG_LIMIT      (*(volatile uint32_t *)(MMIO_BASE + 0x80U))
#define REG_PICO_HEARTBEAT      (*(volatile uint32_t *)(MMIO_BASE + 0x84U))

// STATUS register bit masks
#define STATUS_ACTIVE           (1U << 0)
#define STATUS_DONE             (1U << 1)
#define STATUS_JOB_ACCEPTED     (1U << 2)
#define STATUS_ERROR            (1U << 3)

// CONTROL register bit masks
#define CTRL_JOB_START          (1U << 0)
#define CTRL_FAULT_ACK          (1U << 1)

#define EXPECTED_CORE_ID        0x48323634U // "H264"
#define HEARTBEAT_INIT_VAL      0xCAFEB001U
#define HEARTBEAT_OK_VAL        0xCAFEB002U

volatile uint32_t g_core_id = 0;
volatile uint32_t g_core_version = 0;
volatile uint32_t g_heartbeat_counter = 0;
volatile uint32_t g_frames_encoded = 0;
volatile uint32_t g_job_sequence_last = 0xFFFFFFFFU;

// Forward declaration of encoder stub (populated Stage 4+)
static void run_encoder_job(void);

int main(void) {
    // 1. Zero-out status/stats registers
    REG_STATUS       = 0x00000000U;
    REG_ERROR_CODE   = 0x00000000U;
    REG_COMPLETED_MB = 0x00000000U;

    // 2. Write initial heartbeat
    g_heartbeat_counter = HEARTBEAT_INIT_VAL;
    REG_PICO_HEARTBEAT = g_heartbeat_counter;

    // 3. Validate CORE_ID
    g_core_id = REG_CORE_ID;
    g_core_version = REG_CORE_VERSION;

    if (g_core_id == EXPECTED_CORE_ID) {
        g_heartbeat_counter = HEARTBEAT_OK_VAL;
        REG_PICO_HEARTBEAT = g_heartbeat_counter;
    } else {
        // Fatal: unexpected hardware ID - signal error and halt
        REG_ERROR_CODE = 0xDEAD0001U;
        REG_STATUS     = STATUS_ERROR;
        while (1) { ; } // Pico halts; RTL watchdog will trip
    }

    // 4. Main job mailbox loop
    while (1) {
        g_heartbeat_counter++;
        REG_PICO_HEARTBEAT = g_heartbeat_counter;

        uint32_t ctrl = REG_CONTROL;

        if (ctrl & CTRL_JOB_START) {
            uint32_t seq = REG_JOB_SEQUENCE;

            // Guard against duplicate job triggers
            if (seq != g_job_sequence_last) {
                g_job_sequence_last = seq;

                // --- Handshake Step 2: Accept the job ---
                // Clear any stale DONE/ERROR bits; set ACTIVE + JOB_ACCEPTED
                REG_STATUS     = STATUS_ACTIVE | STATUS_JOB_ACCEPTED;
                REG_COMPLETED_MB = 0U;

                // --- Handshake Step 3: Run the encoder ---
                run_encoder_job();

                g_frames_encoded++;

                // --- Handshake Step 4: Signal completion ---
                // Set DONE bit (keeps ACTIVE until ARM ACKs)
                REG_STATUS = STATUS_DONE;
            }
        }
    }

    return 0;
}

// ==============================================================================
// Encoder job stub (Stage 3: simulates per-macroblock progress updates)
// Stages 6-12 will replace this with the full H.264 pipeline
// ==============================================================================
static void run_encoder_job(void) {
    uint32_t total_mb    = REG_TOTAL_MB;
    uint32_t tiles_x     = REG_TILES_X;
    uint32_t tiles_y     = REG_TILES_Y;
    uint32_t mb_count    = 0;

    // Recompute from register values if coherent
    // Note: RV32I has no hardware multiply; use total_mb from register directly
    if (tiles_x > 0 && tiles_y > 0) {
        uint32_t acc = 0;
        for (uint32_t i = 0; i < tiles_x; i++) acc += tiles_y;
        total_mb = acc;
    }

    // Per-macroblock progress loop
    // Stage 6+ will drive m_axi_mem reads and actual H.264 transforms here
    for (uint32_t mb = 0; mb < total_mb; mb++) {
        mb_count++;
        REG_COMPLETED_MB = mb_count;
        g_heartbeat_counter++;
        REG_PICO_HEARTBEAT = g_heartbeat_counter;
    }
}
