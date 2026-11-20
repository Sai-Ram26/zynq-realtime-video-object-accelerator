/*
 * arm_main.c - ZedBoard PS ARM Firmware for Model-4 H.264 Accelerator
 *
 * Tasks 2 & 3: PS Ethernet/DDR transport (M4V1 protocol) and
 *              PS-to-PL descriptor handoff via AXI-Lite registers.
 *
 * Protocol: M4V1 (64-byte big-endian header + typed messages)
 * Transport: LwIP TCP bare-metal, port 5001
 * Hardware:  Xilinx GEM0 (xemacps), AXI-Lite slave for PL control
 *
 * =============================================================================
 * REGISTER MAP (ACCEL_BASE = 0x43C00000)
 * =============================================================================
 * Offset  Name              RTL register        Notes
 * 0x00    CORE_ID           reg_core_id         RO, expect 0x48323634 "H264"
 * 0x04    CORE_VERSION      reg_core_version    RO
 * 0x08    CONTROL           reg_control         WO: bit0=JOB_START, bit1=FAULT_ACK, bit2=SCALE_START
 * 0x0C    STATUS            reg_status          RO: bit0=BUSY, bit1=DONE, bit3=ERROR
 * 0x10    ERROR_CODE        reg_error_code      RO
 * 0x14    JOB_SEQUENCE      reg_job_sequence    WR
 * 0x18    FRAME_ID_LOW      reg_frame_id_low    WR
 * 0x1C    FRAME_ID_HIGH     reg_frame_id_high   WR (unused, frame_id fits 32-bit)
 * 0x20    INPUT_BASE        reg_input_base      WR: Y-plane DDR base (I420 interleaved)
 * 0x24    REFERENCE_BASE    reg_reference_base  WR
 * 0x28    RECON_BASE        reg_recon_base      WR
 * 0x2C    CANDIDATE_BASE    reg_candidate_base  WR
 * 0x30    METADATA_BASE     reg_metadata_base   WR
 * 0x34    WIDTH             reg_width           WR: encode target width (pixels)
 * 0x38    HEIGHT            reg_height          WR: encode target height (pixels)
 * 0x3C    TILES_X           reg_tiles_x         WR: ceil(W/16)
 * 0x40    TILES_Y           reg_tiles_y         WR: ceil(H/16)
 * 0x44    QP                reg_qp              WR: quantization parameter 0-51
 * 0x48    ME_MODE           reg_me_mode         WR
 * 0x4C    SEARCH_RADIUS     reg_search_radius   WR
 * 0x50    COMPLETED_MB      reg_completed_mb    RO (brief incorrectly mapped MAILBOX_CMD here)
 * 0x54    TOTAL_MB          reg_total_mb        RO: set by PL from tiles_x*tiles_y on JOB_START
 * 0x70    OUTPUT_LENGTH     reg_output_length   RO
 * 0x78    IRQ_STATUS        reg_irq_status      W1C
 * 0x7C    IRQ_ENABLE        reg_irq_enable      WR
 * 0x80    WATCHDOG_LIMIT    reg_watchdog_limit  WR
 * 0x84    PICO_HEARTBEAT    reg_pico_heartbeat  WR (PicoRV32 firmware)
 * 0x88    SRC_WIDTH         reg_src_width       WR: source frame width
 * 0x8C    SRC_HEIGHT        reg_src_height      WR: source frame height
 *
 * NOTE: The brief specifies REG_INPUT_U_BASE=0x60, REG_INPUT_V_BASE=0x64,
 *       REG_TOTAL_MB=0x44, REG_QP=0x40, REG_MAILBOX_CMD=0x50.
 *       These do NOT match the RTL (h264_accel_top.sv). The correct addresses
 *       are used below.  The PL expects a single Y-plane DDR base; it internally
 *       derives UV offsets for I420 (planar) using reg_width/reg_height.
 *       Job is triggered by writing bit0 of CONTROL (0x08), not 0x50.
 *
 * =============================================================================
 * DDR MEMORY LAYOUT
 * =============================================================================
 * Slot 0:  Y  0x10000000  (DDR_INPUT_BASE)
 *          U  0x10000000 + W*H
 *          V  0x10000000 + W*H*5/4
 * Slot 1:  Y  0x18000000  (DDR_INPUT_BASE + 0x08000000, +128MB)
 * SOURCE:  0x18000000     (raw receive buffer before scaling - same as slot 1
 *                          for the legacy path; keep separate for M4V1)
 * RECON:   0x12000000     (DDR_RECON_BASE)
 * REF:     0x11000000     (DDR_REF_BASE)
 * BITS:    0x13000000     (DDR_BITSTREAM_BASE)
 *
 * Brief specified base 0x1000000 (16 MB). Actual DDR starts at 0x10000000
 * (256 MB mark) which is safer for Zynq XC7Z020 (512 MB DDR).  We preserve
 * the existing DDR constants.
 */

#include <stdint.h>
#include <string.h>

#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/tcp.h"
#include "lwip/timeouts.h"
#include "netif/xadapter.h"

#include "protocol_m4v1.h"

/* =========================================================================
 * AXI-Lite Register Addresses (ACCEL_BASE from h264_accel_top.sv)
 * ========================================================================= */
#define ACCEL_BASE              0x43C00000U

/* Read-only identification */
#define REG_CORE_ID             (ACCEL_BASE + 0x00U)   /* RO: 0x48323634 "H264" */
#define REG_CORE_VERSION        (ACCEL_BASE + 0x04U)   /* RO */

/* Control / Status */
#define REG_CONTROL             (ACCEL_BASE + 0x08U)   /* WO: [0]=JOB_START [1]=FAULT_ACK [2]=SCALE_START */
#define REG_STATUS              (ACCEL_BASE + 0x0CU)   /* RO: [0]=BUSY [1]=DONE [3]=ERROR */
#define REG_ERROR_CODE          (ACCEL_BASE + 0x10U)   /* RO */

/* Frame identity */
#define REG_JOB_SEQUENCE        (ACCEL_BASE + 0x14U)   /* WR: monotonic counter */
#define REG_FRAME_ID_LOW        (ACCEL_BASE + 0x18U)   /* WR: frame_id[31:0] */
#define REG_FRAME_ID_HIGH       (ACCEL_BASE + 0x1CU)   /* WR: frame_id[63:32] (unused) */

/* DDR pointers */
#define REG_INPUT_BASE          (ACCEL_BASE + 0x20U)   /* WR: Y-plane DDR address (I420 layout) */
#define REG_REFERENCE_BASE      (ACCEL_BASE + 0x24U)   /* WR: reference frame DDR address */
#define REG_RECON_BASE          (ACCEL_BASE + 0x28U)   /* WR: reconstructed frame DDR address */
#define REG_CANDIDATE_BASE      (ACCEL_BASE + 0x2CU)   /* WR */
#define REG_METADATA_BASE       (ACCEL_BASE + 0x30U)   /* WR */

/* Frame geometry */
#define REG_WIDTH               (ACCEL_BASE + 0x34U)   /* WR: encode output width (pixels) */
#define REG_HEIGHT              (ACCEL_BASE + 0x38U)   /* WR: encode output height (pixels) */
#define REG_TILES_X             (ACCEL_BASE + 0x3CU)   /* WR: ceil(width /16) */
#define REG_TILES_Y             (ACCEL_BASE + 0x40U)   /* WR: ceil(height/16) */

/* Encode parameters */
#define REG_QP                  (ACCEL_BASE + 0x44U)   /* WR: QP 0-51 */
#define REG_ME_MODE             (ACCEL_BASE + 0x48U)   /* WR: motion-estimation mode */
#define REG_SEARCH_RADIUS       (ACCEL_BASE + 0x4CU)   /* WR */

/* PL status (read-only from PS) */
#define REG_COMPLETED_MB        (ACCEL_BASE + 0x50U)   /* RO: completed macroblocks */
#define REG_TOTAL_MB            (ACCEL_BASE + 0x54U)   /* RO: total MBs (set by PL on JOB_START) */
#define REG_OUTPUT_LENGTH       (ACCEL_BASE + 0x70U)   /* RO: bitstream bytes */

/* Interrupt control */
#define REG_IRQ_STATUS          (ACCEL_BASE + 0x78U)   /* W1C */
#define REG_IRQ_ENABLE          (ACCEL_BASE + 0x7CU)   /* WR */
#define REG_WATCHDOG_LIMIT      (ACCEL_BASE + 0x80U)   /* WR */

/* PicoRV32 heartbeat (read by PS) */
#define REG_PICO_HEARTBEAT      (ACCEL_BASE + 0x84U)   /* WR by Pico, RO by ARM */

/* Scaler source dimensions */
#define REG_SRC_WIDTH           (ACCEL_BASE + 0x88U)   /* WR: source frame width  (pixels) */
#define REG_SRC_HEIGHT          (ACCEL_BASE + 0x8CU)   /* WR: source frame height (pixels) */

/* =========================================================================
 * CONTROL register bit masks
 * ========================================================================= */
#define CTRL_JOB_START          (1U << 0)   /* bit0: trigger encoder */
#define CTRL_FAULT_ACK          (1U << 1)   /* bit1: clear error */
#define CTRL_SCALE_START        (1U << 2)   /* bit2: trigger scaler DMA */

/* STATUS register bit masks */
#define STATUS_BUSY             (1U << 0)
#define STATUS_DONE             (1U << 1)
#define STATUS_ERROR            (1U << 3)

/* =========================================================================
 * DDR Memory Layout
 * ========================================================================= */
#define DDR_INPUT_BASE          0x10000000U  /* Slot 0 Y-plane start */
#define DDR_REF_BASE            0x11000000U
#define DDR_RECON_BASE          0x12000000U
#define DDR_BITSTREAM_BASE      0x13000000U
#define DDR_SOURCE_BASE         0x18000000U  /* Raw receive / Slot 1 Y-plane */

/* Slot 1 is at +128 MB from slot 0 (matches DDR_SOURCE_BASE for legacy compat) */
#define DDR_SLOT1_BASE          0x18000000U

/* Slot sizes */
#define MAX_FRAME_BYTES         (64U * 1024U * 1024U)
#define MAX_BITSTREAM_BYTES     (2U * 1024U * 1024U)

/* I420 plane offset helpers (W, H must be multiples of 2) */
#define I420_Y_SIZE(w,h)   ((uint32_t)(w) * (uint32_t)(h))
#define I420_U_OFFSET(w,h) (I420_Y_SIZE(w,h))
#define I420_V_OFFSET(w,h) (I420_Y_SIZE(w,h) + I420_Y_SIZE(w,h)/4U)
#define I420_TOTAL(w,h)    (I420_Y_SIZE(w,h) * 3U / 2U)

/* =========================================================================
 * Scaler DMA (simple-DMA in direct register mode)
 * ========================================================================= */
#define SCALE_DMA_BASE          0x40500000U
#define DMA_MM2S_DMACR          0x00U
#define DMA_MM2S_DMASR          0x04U
#define DMA_MM2S_SA             0x18U
#define DMA_MM2S_LENGTH         0x58U
#define DMA_S2MM_DMACR          0x30U
#define DMA_S2MM_DMASR          0x34U
#define DMA_S2MM_DA             0x48U
#define DMA_S2MM_LENGTH         0x58U   /* NOTE: same offset intentional for simple-mode */

/* =========================================================================
 * TCP / Protocol constants
 * ========================================================================= */
#define TCP_PORT                5001U
#define TCP_BACKLOG             1U
#define SERVICE_TIMEOUT_LOOPS   50000000U
#define MAX_TARGET_WIDTH        426U
#define MAX_TARGET_HEIGHT       240U
#define M4V1_MAX_PAYLOAD        (MAX_FRAME_BYTES)

/* Expected accelerator core ID */
#define EXPECTED_CORE_ID        0x48323634U  /* "H264" */

/* =========================================================================
 * Global State
 * ========================================================================= */
static XAxiDma    g_dma;
static uint32_t   g_job_sequence;
static struct netif g_netif;

/*
 * Per-connection M4V1 parser state.
 *
 * The M4V1 protocol is a sequence of framed messages on a single persistent
 * TCP connection:
 *
 *   Host -> ZedBoard:
 *     JOB_BEGIN  (once per encoding session, payload = m4v1_job_begin_payload_t)
 *     For each frame:
 *       FRAME_BEGIN  (payload_length=0, hdr carries width/height/pts)
 *       FRAME_DATA   (one or more chunks, payload_length=chunk_bytes)
 *       FRAME_END    (payload_length=0, hdr.payload_crc32 = CRC of frame data)
 *     JOB_END
 *
 *   ZedBoard -> Host:
 *     ACK  (after JOB_BEGIN, payload = m4v1_job_begin_ack_payload_t, 12 bytes)
 *     OUTPUT_DATA  (encoder bitstream chunk)
 *     OUTPUT_END
 */
typedef enum {
    M4V1_STATE_WAIT_HEADER = 0,  /* collecting the 64-byte fixed header */
    M4V1_STATE_WAIT_PAYLOAD,     /* collecting payload bytes */
    M4V1_STATE_DISPATCH,         /* header+payload complete, process message */
} m4v1_parser_state_t;

typedef struct {
    struct tcp_pcb       *pcb;

    /* Current message accumulation */
    m4v1_parser_state_t   state;
    uint8_t               hdr_buf[M4V1_HEADER_SIZE];   /* raw 64-byte header */
    uint32_t              hdr_used;                      /* bytes filled so far */
    m4v1_header_t         hdr;                           /* decoded header */

    uint8_t              *payload_ptr;  /* DDR pointer for current payload */
    uint32_t              payload_expect;
    uint32_t              payload_used;
    uint32_t              running_crc;  /* CRC accumulated over FRAME_DATA chunks */

    /* Job-level context (set by JOB_BEGIN) */
    uint32_t  profile_id;
    uint32_t  out_width;
    uint32_t  out_height;
    uint8_t   job_active;

    /* Frame-level context (set by FRAME_BEGIN) */
    uint32_t  frame_id;
    uint32_t  src_width;
    uint32_t  src_height;
    uint64_t  pts;
    uint32_t  frame_total_bytes;  /* expected total I420 bytes */
    uint32_t  frame_offset;       /* bytes received so far for current frame */
    uint8_t   current_slot;       /* 0 or 1 (double-buffer) */

    /* TX response queue (simple linear buffer for small ACK/OUTPUT_END) */
    uint8_t   tx_buf[M4V1_HEADER_SIZE + 12U]; /* header + max ACK payload */
    uint32_t  tx_total;
    uint32_t  tx_sent;
} m4v1_conn_t;

static m4v1_conn_t g_conn;

/* =========================================================================
 * Utility
 * ========================================================================= */
static uint32_t read_be32_buf(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] <<  8) |  (uint32_t)p[3];
}

static void write_be16_buf(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)(v);
}

static void write_be32_buf(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >>  8);
    p[3] = (uint8_t)(v);
}

static uint32_t crc32_update(uint32_t crc, const uint8_t *data, uint32_t len)
{
    /*
     * CRC-32/ISO-HDLC (reflected 0xEDB88320, init 0xFFFFFFFF, final XOR 0xFFFFFFFF)
     * Equivalent to zlib.crc32() on the Python side.
     */
    static const uint32_t table[16] = {
        0x00000000U, 0x1DB71064U, 0x3B6E20C8U, 0x26D930ACU,
        0x76DC4190U, 0x6B6B51F4U, 0x4DB26158U, 0x5005713CU,
        0xEDB88320U, 0xF00F9344U, 0xD6D6A3E8U, 0xCB61B38CU,
        0x9B64C2B0U, 0x86D3D2D4U, 0xA00AE278U, 0xBDBDF21CU,
    };
    uint32_t i;
    for (i = 0; i < len; i++) {
        crc ^= data[i];
        crc  = (crc >> 4) ^ table[crc & 0x0FU];
        crc  = (crc >> 4) ^ table[crc & 0x0FU];
    }
    return crc;
}

static uint32_t crc32_finish(uint32_t crc) { return crc ^ 0xFFFFFFFFU; }
static uint32_t crc32_init(void)           { return 0xFFFFFFFFU; }

/* =========================================================================
 * DDR helpers
 * ========================================================================= */
static uint32_t slot_y_base(uint8_t slot)
{
    return (slot == 0U) ? DDR_INPUT_BASE : DDR_SLOT1_BASE;
}

static uint32_t slot_u_base(uint8_t slot, uint32_t w, uint32_t h)
{
    return slot_y_base(slot) + I420_U_OFFSET(w, h);
}

static uint32_t slot_v_base(uint8_t slot, uint32_t w, uint32_t h)
{
    return slot_y_base(slot) + I420_V_OFFSET(w, h);
}

/* =========================================================================
 * Scaler DMA (simple-DMA, direct-register mode)
 * ========================================================================= */
static void scale_dma_start(uint32_t src_addr, uint32_t src_bytes,
                             uint32_t dst_addr, uint32_t dst_bytes)
{
    /* Reset both channels */
    Xil_Out32(SCALE_DMA_BASE + DMA_MM2S_DMACR, 0x00000004U);
    Xil_Out32(SCALE_DMA_BASE + DMA_S2MM_DMACR, 0x00000004U);
    /* Enable channels */
    Xil_Out32(SCALE_DMA_BASE + DMA_MM2S_DMACR, 0x00000001U);
    Xil_Out32(SCALE_DMA_BASE + DMA_S2MM_DMACR, 0x00000001U);
    /* Program addresses */
    Xil_Out32(SCALE_DMA_BASE + DMA_MM2S_SA,     src_addr);
    Xil_Out32(SCALE_DMA_BASE + DMA_S2MM_DA,     dst_addr);
    /* Kick transfers (writing LENGTH starts the DMA) */
    Xil_Out32(SCALE_DMA_BASE + DMA_MM2S_LENGTH, src_bytes);
    Xil_Out32(SCALE_DMA_BASE + DMA_S2MM_LENGTH, dst_bytes);
}

static int scale_dma_wait(void)
{
    uint32_t timeout = SERVICE_TIMEOUT_LOOPS;
    while (timeout-- != 0U) {
        uint32_t mm2s = Xil_In32(SCALE_DMA_BASE + DMA_MM2S_DMASR);
        uint32_t s2mm = Xil_In32(SCALE_DMA_BASE + DMA_S2MM_DMASR);
        if (((mm2s | s2mm) & 0x00000070U) != 0U)
            return -1;  /* DMA error bits set */
        if ((mm2s & 0x2U) != 0U && (s2mm & 0x2U) != 0U)
            return 0;   /* Both channels idle (IOC) */
    }
    return -2;  /* Timeout */
}

/* =========================================================================
 * DMA Init (AXI-DMA for bitstream output)
 * ========================================================================= */
static int init_dma(void)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    if (cfg == NULL)
        return -1;
    if (XAxiDma_CfgInitialize(&g_dma, cfg) != XST_SUCCESS)
        return -2;
    XAxiDma_IntrDisable(&g_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return 0;
}

/* =========================================================================
 * Protocol Handler: handle_job_begin
 *
 * Payload: m4v1_job_begin_payload_t (16 bytes, big-endian)
 *   [0..3]  output_profile_id  (1=144p 256x144, 2=240p 426x240)
 *   [4..7]  scaler_filter_id
 *   [8..11] aspect_policy_id
 *   [12..15] input_color_range_id
 *
 * Actions:
 *   1. Validate profile_id (must be 1 or 2).
 *   2. Derive output dimensions from profile.
 *   3. Program AXI-Lite registers for the new job geometry.
 *   4. Send 12-byte ACK payload (m4v1_job_begin_ack_payload_t).
 * ========================================================================= */
static int handle_job_begin(m4v1_conn_t *c, const m4v1_header_t *hdr,
                             const uint8_t *payload, uint32_t payload_len)
{
    m4v1_job_begin_payload_t job;
    uint32_t out_w, out_h;
    uint32_t tiles_x, tiles_y;
    uint8_t *p;
    err_t err;

    (void)hdr;

    if (payload_len < 16U) {
        xil_printf("[ARM] JOB_BEGIN: payload too short (%u)\r\n", payload_len);
        return -1;
    }

    /* Unpack big-endian fields */
    job.output_profile_id    = read_be32_buf(payload +  0);
    job.scaler_filter_id     = read_be32_buf(payload +  4);
    job.aspect_policy_id     = read_be32_buf(payload +  8);
    job.input_color_range_id = read_be32_buf(payload + 12);

    xil_printf("[ARM] JOB_BEGIN profile=%u filter=%u aspect=%u color=%u\r\n",
               (unsigned)job.output_profile_id,
               (unsigned)job.scaler_filter_id,
               (unsigned)job.aspect_policy_id,
               (unsigned)job.input_color_range_id);

    /* Validate profile: only 1 (144p) and 2 (240p) are supported */
    if (m4v1_derive_output_dims(job.output_profile_id, &out_w, &out_h) != 0) {
        xil_printf("[ARM] JOB_BEGIN: invalid profile_id %u (must be 1 or 2)\r\n",
                   (unsigned)job.output_profile_id);
        return -2;
    }

    if (out_w > MAX_TARGET_WIDTH || out_h > MAX_TARGET_HEIGHT) {
        xil_printf("[ARM] JOB_BEGIN: output dims %ux%u exceed hw limits\r\n",
                   (unsigned)out_w, (unsigned)out_h);
        return -3;
    }

    /* Store job context */
    c->profile_id  = job.output_profile_id;
    c->out_width   = out_w;
    c->out_height  = out_h;
    c->job_active  = 1U;
    c->current_slot = 0U;
    g_job_sequence++;

    tiles_x = (out_w  + 15U) / 16U;
    tiles_y = (out_h  + 15U) / 16U;

    xil_printf("[ARM] Job %u: output %ux%u (%u x %u MBs)\r\n",
               (unsigned)g_job_sequence,
               (unsigned)out_w, (unsigned)out_h,
               (unsigned)tiles_x, (unsigned)tiles_y);

    /*
     * Program PL descriptor registers.
     *
     * Register addresses (ACCEL_BASE = 0x43C00000):
     *   REG_WIDTH      0x43C00034  output width
     *   REG_HEIGHT     0x43C00038  output height
     *   REG_TILES_X    0x43C0003C  ceil(W/16)
     *   REG_TILES_Y    0x43C00040  ceil(H/16)
     *   REG_QP         0x43C00044  default QP (overridden per-frame)
     *   REG_INPUT_BASE 0x43C00020  Y-plane DDR address (slot 0)
     *   REG_RECON_BASE 0x43C00028  reconstructed frame DDR address
     *   REG_JOB_SEQUENCE 0x43C0014 monotonic job counter
     */
    Xil_Out32(REG_WIDTH,        out_w);
    Xil_Out32(REG_HEIGHT,       out_h);
    Xil_Out32(REG_TILES_X,      tiles_x);
    Xil_Out32(REG_TILES_Y,      tiles_y);
    Xil_Out32(REG_QP,           28U);       /* default QP, overridden per-frame */
    Xil_Out32(REG_INPUT_BASE,   slot_y_base(0U));
    Xil_Out32(REG_RECON_BASE,   DDR_RECON_BASE);
    Xil_Out32(REG_REFERENCE_BASE, DDR_REF_BASE);
    Xil_Out32(REG_JOB_SEQUENCE, g_job_sequence);

    /*
     * Build ACK: 64-byte M4V1 header + 12-byte m4v1_job_begin_ack_payload_t
     *
     * ACK header fields (big-endian):
     *   magic[4]            "M4V1"  (0x4D345631)
     *   protocol_version    1
     *   message_type        M4V1_MSG_ACK = 6
     *   sequence_number     (echo hdr->sequence_number)
     *   payload_length      12
     *   (all other fields 0)
     *
     * ACK payload (12 bytes, big-endian):
     *   output_profile_id   [0..3]
     *   output_width        [4..7]
     *   output_height       [8..11]
     */
    p = c->tx_buf;
    memset(p, 0, M4V1_HEADER_SIZE + 12U);

    /* magic = "M4V1" */
    p[0] = 'M'; p[1] = '4'; p[2] = 'V'; p[3] = '1';
    /* protocol_version = 1 (big-endian u16 at offset 4) */
    write_be16_buf(p + 4,  (uint16_t)M4V1_PROTOCOL_VERSION);
    /* message_type = ACK (u16 at offset 6) */
    write_be16_buf(p + 6,  (uint16_t)M4V1_MSG_ACK);
    /* sequence_number (u32 at offset 8) */
    write_be32_buf(p + 8,  hdr->sequence_number);
    /* payload_length = 12 (u32 at offset 40) */
    write_be32_buf(p + 40, 12U);

    /* ACK payload immediately after the 64-byte header */
    write_be32_buf(p + M4V1_HEADER_SIZE + 0,  job.output_profile_id);
    write_be32_buf(p + M4V1_HEADER_SIZE + 4,  out_w);
    write_be32_buf(p + M4V1_HEADER_SIZE + 8,  out_h);

    c->tx_total = M4V1_HEADER_SIZE + 12U;
    c->tx_sent  = 0U;

    /* Best-effort immediate send; remainder flushed in tcp_sent callback */
    err = tcp_write(c->pcb, c->tx_buf, (u16_t)c->tx_total, TCP_WRITE_FLAG_COPY);
    if (err == ERR_OK)
        tcp_output(c->pcb);

    xil_printf("[ARM] JOB_BEGIN ACK sent (profile=%u, %ux%u)\r\n",
               (unsigned)job.output_profile_id, (unsigned)out_w, (unsigned)out_h);
    return 0;
}

/* =========================================================================
 * Protocol Handler: handle_frame_begin
 *
 * Header fields used:
 *   hdr->frame_id        frame identifier
 *   hdr->width           source frame width  (pixels)
 *   hdr->height          source frame height (pixels)
 *   hdr->pts             presentation timestamp
 *   hdr->frame_total_bytes  expected total I420 bytes for this frame
 *
 * Actions:
 *   1. Reserve DDR input slot (double-buffer: flip between slot 0 and 1).
 *   2. Record frame metadata for use in handle_frame_data/end.
 * ========================================================================= */
static int handle_frame_begin(m4v1_conn_t *c, const m4v1_header_t *hdr)
{
    uint32_t expected;

    if (!c->job_active) {
        xil_printf("[ARM] FRAME_BEGIN: no active job\r\n");
        return -1;
    }

    c->frame_id         = hdr->frame_id;
    c->src_width        = hdr->width;
    c->src_height       = hdr->height;
    c->pts              = hdr->pts;
    c->frame_total_bytes = hdr->frame_total_bytes;
    c->frame_offset     = 0U;
    c->running_crc      = crc32_init();

    /* Validate source dimensions */
    if (c->src_width == 0U || c->src_height == 0U ||
        (c->src_width  & 1U) != 0U ||
        (c->src_height & 1U) != 0U) {
        xil_printf("[ARM] FRAME_BEGIN: invalid source dims %ux%u\r\n",
                   (unsigned)c->src_width, (unsigned)c->src_height);
        return -2;
    }

    expected = I420_TOTAL(c->src_width, c->src_height);
    if (c->frame_total_bytes != expected) {
        xil_printf("[ARM] FRAME_BEGIN: frame_total_bytes mismatch (got %u, exp %u)\r\n",
                   (unsigned)c->frame_total_bytes, (unsigned)expected);
        return -3;
    }

    /* Flip DDR double-buffer slot */
    c->current_slot = (c->current_slot == 0U) ? 1U : 0U;

    xil_printf("[ARM] FRAME_BEGIN id=%u src=%ux%u slot=%u\r\n",
               (unsigned)c->frame_id,
               (unsigned)c->src_width, (unsigned)c->src_height,
               (unsigned)c->current_slot);
    return 0;
}

/* =========================================================================
 * Protocol Handler: handle_frame_data
 *
 * DMA-write (CPU copy) chunk to current DDR slot at the correct I420 offset.
 * Accumulates CRC over all received bytes.
 *
 * The source frame is I420 planar:
 *   [0 .. W*H-1]           Y plane
 *   [W*H .. W*H*5/4-1]     U plane (W/2 * H/2)
 *   [W*H*5/4 .. W*H*3/2-1] V plane (W/2 * H/2)
 *
 * We write them contiguously starting at slot_y_base(slot).
 * ========================================================================= */
static int handle_frame_data(m4v1_conn_t *c, const m4v1_header_t *hdr,
                              const uint8_t *data, uint32_t data_len)
{
    uint32_t dst;

    if (!c->job_active) {
        xil_printf("[ARM] FRAME_DATA: no active job\r\n");
        return -1;
    }

    if (c->frame_offset + data_len > c->frame_total_bytes) {
        xil_printf("[ARM] FRAME_DATA: overflow (offset=%u len=%u total=%u)\r\n",
                   (unsigned)c->frame_offset, (unsigned)data_len,
                   (unsigned)c->frame_total_bytes);
        return -2;
    }

    /* Destination: contiguous I420 in DDR starting at slot Y-base */
    dst = slot_y_base(c->current_slot) + c->frame_offset;

    /* CPU copy to DDR (bare-metal, no IOMMU) */
    memcpy((void *)(uintptr_t)dst, data, data_len);

    /* Accumulate CRC */
    c->running_crc   = crc32_update(c->running_crc, data, data_len);
    c->frame_offset += data_len;

    (void)hdr; /* seq / pts carried in hdr but not needed per-chunk */
    return 0;
}

/* =========================================================================
 * Protocol Handler: handle_frame_end
 *
 * Validates CRC, then publishes the frame descriptor to PL via AXI-Lite:
 *   REG_SRC_WIDTH    0x43C00088  source width
 *   REG_SRC_HEIGHT   0x43C0008C  source height
 *   REG_WIDTH        0x43C00034  output width  (from job profile)
 *   REG_HEIGHT       0x43C00038  output height (from job profile)
 *   REG_TILES_X      0x43C0003C  ceil(out_w / 16)
 *   REG_TILES_Y      0x43C00040  ceil(out_h / 16)
 *   REG_QP           0x43C00044  quantization parameter (from flags field)
 *   REG_INPUT_BASE   0x43C00020  Y-plane DDR address for current slot
 *   REG_RECON_BASE   0x43C00028  reconstructed frame base
 *   REG_FRAME_ID_LOW 0x43C00018  frame_id[31:0]
 *   REG_CONTROL      0x43C00008  write CTRL_JOB_START (bit0) to trigger PL
 *
 * Then waits for STATUS_DONE or STATUS_ERROR.
 * Reads output bitstream via AXI-DMA and queues OUTPUT_DATA response.
 *
 * CRC from hdr->payload_crc32 covers the FRAME_DATA payload bytes only
 * (matches Python protocol_m4v1.py crc32_iso_hdlc(frame_bytes)).
 * ========================================================================= */
static int publish_frame_descriptor(m4v1_conn_t *c, uint32_t qp)
{
    uint32_t tiles_x = (c->out_width  + 15U) / 16U;
    uint32_t tiles_y = (c->out_height + 15U) / 16U;
    uint32_t y_base  = slot_y_base(c->current_slot);
    uint32_t status;
    uint32_t out_len;
    uint32_t timeout;

    /* Flush D-cache for the written frame region */
    Xil_DCacheFlushRange((INTPTR)y_base, c->frame_total_bytes);
    /* Invalidate bitstream region (PL will DMA-write here via axis) */
    Xil_DCacheInvalidateRange((INTPTR)DDR_BITSTREAM_BASE, MAX_BITSTREAM_BYTES);

    /*
     * Optionally: scale source -> output dimensions if src != out.
     * For the M4V1 path the host pre-scales to I420 at the target resolution,
     * so we write source dims to SRC_WIDTH/HEIGHT for the PL scaler but skip
     * the AXI-DMA scaler path (data is already at target size in the slot).
     * The scaler is only needed for the legacy path where raw source arrives.
     */
    Xil_Out32(REG_SRC_WIDTH,  c->src_width);   /* 0x43C00088 */
    Xil_Out32(REG_SRC_HEIGHT, c->src_height);  /* 0x43C0008C */

    /* Encode geometry registers */
    Xil_Out32(REG_WIDTH,    c->out_width);     /* 0x43C00034 */
    Xil_Out32(REG_HEIGHT,   c->out_height);    /* 0x43C00038 */
    Xil_Out32(REG_TILES_X,  tiles_x);          /* 0x43C0003C */
    Xil_Out32(REG_TILES_Y,  tiles_y);          /* 0x43C00040 */
    Xil_Out32(REG_QP,       qp);               /* 0x43C00044 */

    /* DDR pointers */
    Xil_Out32(REG_INPUT_BASE,     y_base);         /* 0x43C00020 Y-plane start */
    Xil_Out32(REG_REFERENCE_BASE, DDR_REF_BASE);   /* 0x43C00024 */
    Xil_Out32(REG_RECON_BASE,     DDR_RECON_BASE); /* 0x43C00028 */

    /* Frame identity */
    Xil_Out32(REG_FRAME_ID_LOW,  c->frame_id);     /* 0x43C00018 */
    Xil_Out32(REG_FRAME_ID_HIGH, 0U);              /* 0x43C0001C */
    Xil_Out32(REG_JOB_SEQUENCE,  g_job_sequence);  /* 0x43C00014 */

    xil_printf("[ARM] PL descriptor: Y=0x%08X out=%ux%u MBs=%ux%u QP=%u\r\n",
               (unsigned)y_base,
               (unsigned)c->out_width, (unsigned)c->out_height,
               (unsigned)tiles_x, (unsigned)tiles_y,
               (unsigned)qp);

    /* Arm AXI-DMA S2MM channel to capture bitstream from PL */
    if (XAxiDma_SimpleTransfer(&g_dma, (UINTPTR)DDR_BITSTREAM_BASE,
                               MAX_BITSTREAM_BYTES,
                               XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS) {
        xil_printf("[ARM] DMA transfer arm failed\r\n");
        return -1;
    }

    /* Trigger PL encoder by writing JOB_START to CONTROL[0] */
    Xil_Out32(REG_CONTROL, CTRL_JOB_START);  /* 0x43C00008 bit0 */

    /* Poll STATUS until DONE or ERROR */
    timeout = SERVICE_TIMEOUT_LOOPS;
    while (timeout-- != 0U) {
        status = Xil_In32(REG_STATUS);
        if ((status & STATUS_ERROR) != 0U) {
            xil_printf("[ARM] PL error: code=0x%08X\r\n",
                       (unsigned)Xil_In32(REG_ERROR_CODE));
            Xil_Out32(REG_CONTROL, CTRL_FAULT_ACK);
            return -2;
        }
        if ((status & STATUS_DONE) != 0U)
            break;
    }
    if (timeout == 0U) {
        xil_printf("[ARM] PL timeout\r\n");
        Xil_Out32(REG_CONTROL, CTRL_FAULT_ACK);
        return -3;
    }

    /* Wait for DMA to finish capturing bitstream */
    timeout = SERVICE_TIMEOUT_LOOPS;
    while (XAxiDma_Busy(&g_dma, XAXIDMA_DEVICE_TO_DMA) && timeout-- != 0U) {
        /* spin */
    }
    if (timeout == 0U) {
        Xil_Out32(REG_CONTROL, CTRL_FAULT_ACK);
        return -4;
    }

    out_len = Xil_In32(REG_OUTPUT_LENGTH);  /* 0x43C00070 */
    if (out_len == 0U || out_len > MAX_BITSTREAM_BYTES) {
        xil_printf("[ARM] Bad output_length=%u\r\n", (unsigned)out_len);
        Xil_Out32(REG_CONTROL, 0U);
        return -5;
    }

    Xil_DCacheInvalidateRange((INTPTR)DDR_BITSTREAM_BASE, out_len);
    Xil_Out32(REG_CONTROL, 0U);

    xil_printf("[ARM] Frame %u encoded: %u bytes\r\n",
               (unsigned)c->frame_id, (unsigned)out_len);
    return (int)out_len;
}

static int send_output_response(m4v1_conn_t *c, uint32_t out_len,
                                uint32_t seq, uint32_t frame_id)
{
    uint8_t hbuf[M4V1_HEADER_SIZE];
    err_t err;

    /*
     * OUTPUT_DATA header (64 bytes, big-endian):
     *   [0..3]   magic "M4V1"
     *   [4..5]   protocol_version = 1
     *   [6..7]   message_type = M4V1_MSG_OUTPUT_DATA = 8
     *   [8..11]  sequence_number
     *   [12..15] frame_id
     *   [40..43] payload_length = out_len
     */
    memset(hbuf, 0, sizeof(hbuf));
    hbuf[0]='M'; hbuf[1]='4'; hbuf[2]='V'; hbuf[3]='1';
    write_be16_buf(hbuf + 4,  (uint16_t)M4V1_PROTOCOL_VERSION);
    write_be16_buf(hbuf + 6,  (uint16_t)M4V1_MSG_OUTPUT_DATA);
    write_be32_buf(hbuf + 8,  seq);
    write_be32_buf(hbuf + 12, frame_id);
    write_be32_buf(hbuf + 40, out_len);

    err = tcp_write(c->pcb, hbuf, (u16_t)M4V1_HEADER_SIZE, TCP_WRITE_FLAG_COPY);
    if (err != ERR_OK)
        return -1;

    /* Send bitstream bytes from DDR (zero-copy reference) */
    err = tcp_write(c->pcb, (const void *)(uintptr_t)DDR_BITSTREAM_BASE,
                    (u16_t)out_len, 0U);
    if (err != ERR_OK)
        return -2;

    /*
     * OUTPUT_END header (64 bytes):
     *   message_type = M4V1_MSG_OUTPUT_END = 9
     *   payload_length = 0
     */
    write_be16_buf(hbuf + 6, (uint16_t)M4V1_MSG_OUTPUT_END);
    write_be32_buf(hbuf + 40, 0U);
    err = tcp_write(c->pcb, hbuf, (u16_t)M4V1_HEADER_SIZE, TCP_WRITE_FLAG_COPY);
    if (err != ERR_OK)
        return -3;

    tcp_output(c->pcb);
    return 0;
}

static int handle_frame_end(m4v1_conn_t *c, const m4v1_header_t *hdr)
{
    uint32_t final_crc;
    uint32_t expected_crc;
    uint32_t qp;
    int      out_len;

    if (!c->job_active) {
        xil_printf("[ARM] FRAME_END: no active job\r\n");
        return -1;
    }

    if (c->frame_offset != c->frame_total_bytes) {
        xil_printf("[ARM] FRAME_END: incomplete frame (%u/%u bytes)\r\n",
                   (unsigned)c->frame_offset, (unsigned)c->frame_total_bytes);
        return -2;
    }

    /* Validate CRC (CRC-32/ISO-HDLC over all FRAME_DATA payload bytes) */
    final_crc    = crc32_finish(c->running_crc);
    expected_crc = hdr->payload_crc32;

    if (final_crc != expected_crc) {
        xil_printf("[ARM] FRAME_END: CRC mismatch (got 0x%08X, exp 0x%08X)\r\n",
                   (unsigned)final_crc, (unsigned)expected_crc);
        return -3;
    }

    xil_printf("[ARM] FRAME_END id=%u CRC OK (0x%08X)\r\n",
               (unsigned)c->frame_id, (unsigned)final_crc);

    /*
     * Extract QP from flags field (bits [5:0]) if non-zero;
     * otherwise use the job-level default of 28.
     */
    qp = (hdr->flags & 0x3FU);
    if (qp == 0U || qp > 51U)
        qp = 28U;

    /* Publish descriptor and trigger PL, then read output */
    out_len = publish_frame_descriptor(c, qp);
    if (out_len <= 0) {
        xil_printf("[ARM] FRAME_END: encode failed (%d)\r\n", out_len);
        return -4;
    }

    /* Send encoded bitstream back to host */
    if (send_output_response(c, (uint32_t)out_len,
                             hdr->sequence_number, c->frame_id) != 0) {
        xil_printf("[ARM] FRAME_END: send_output_response failed\r\n");
        return -5;
    }

    return 0;
}

/* =========================================================================
 * M4V1 Header Decoder
 *
 * Wire layout (64 bytes, big-endian):
 *   Offset  Size  Field
 *   0       4     magic "M4V1"
 *   4       2     protocol_version
 *   6       2     message_type
 *   8       4     sequence_number
 *   12      4     frame_id
 *   16      4     width  (source)
 *   20      4     height (source)
 *   24      2     pixel_format
 *   26      2     flags
 *   28      8     pts  (uint64_t)
 *   36      4     duration
 *   40      4     payload_length
 *   44      4     frame_total_bytes
 *   48      4     payload_crc32
 *   52      4     frame_crc32
 *   56      4     timebase_num
 *   60      4     timebase_den
 *   Total: 64
 * ========================================================================= */
static int decode_m4v1_header(m4v1_header_t *out, const uint8_t *raw)
{
    if (raw[0] != 'M' || raw[1] != '4' || raw[2] != 'V' || raw[3] != '1') {
        xil_printf("[ARM] Bad magic: %02X %02X %02X %02X\r\n",
                   raw[0], raw[1], raw[2], raw[3]);
        return -1;
    }

    memcpy(out->magic, raw, 4);
    out->protocol_version  = (uint16_t)(((uint16_t)raw[4]  << 8) | raw[5]);
    out->message_type      = (uint16_t)(((uint16_t)raw[6]  << 8) | raw[7]);
    out->sequence_number   = read_be32_buf(raw +  8);
    out->frame_id          = read_be32_buf(raw + 12);
    out->width             = read_be32_buf(raw + 16);
    out->height            = read_be32_buf(raw + 20);
    out->pixel_format      = (uint16_t)(((uint16_t)raw[24] << 8) | raw[25]);
    out->flags             = (uint16_t)(((uint16_t)raw[26] << 8) | raw[27]);
    out->pts               = ((uint64_t)read_be32_buf(raw + 28) << 32) |
                              (uint64_t)read_be32_buf(raw + 32);
    out->duration          = read_be32_buf(raw + 36);
    out->payload_length    = read_be32_buf(raw + 40);
    out->frame_total_bytes = read_be32_buf(raw + 44);
    out->payload_crc32     = read_be32_buf(raw + 48);
    out->frame_crc32       = read_be32_buf(raw + 52);
    out->timebase_num      = read_be32_buf(raw + 56);
    out->timebase_den      = read_be32_buf(raw + 60);

    if (out->protocol_version != M4V1_PROTOCOL_VERSION) {
        xil_printf("[ARM] Protocol version %u != expected %u\r\n",
                   (unsigned)out->protocol_version,
                   (unsigned)M4V1_PROTOCOL_VERSION);
        return -2;
    }
    return 0;
}

/* =========================================================================
 * TCP Receive Path
 * ========================================================================= */

/*
 * Dispatch a fully-received message.
 *
 * At entry: c->hdr is decoded, payload_ptr points to c->frame_offset region
 * in DDR (for FRAME_DATA) or is NULL.
 */
static err_t dispatch_message(m4v1_conn_t *c)
{
    int rc;

    switch (c->hdr.message_type) {
    case M4V1_MSG_JOB_BEGIN:
        /*
         * Payload is 16 bytes sitting in a small internal buffer.
         * We used payload_ptr == NULL and accumulated into a local stack buf.
         * Actually for small payloads (< M4V1_HEADER_SIZE) we stored them
         * in tx_buf (re-used as scratch).  Retrieve:
         */
        rc = handle_job_begin(c, &c->hdr, c->tx_buf, c->hdr.payload_length);
        break;

    case M4V1_MSG_FRAME_BEGIN:
        rc = handle_frame_begin(c, &c->hdr);
        break;

    case M4V1_MSG_FRAME_DATA:
        /* Data already written to DDR during receive; nothing more to do here */
        rc = 0;
        break;

    case M4V1_MSG_FRAME_END:
        rc = handle_frame_end(c, &c->hdr);
        break;

    case M4V1_MSG_JOB_END:
        xil_printf("[ARM] JOB_END received\r\n");
        c->job_active = 0U;
        rc = 0;
        break;

    default:
        xil_printf("[ARM] Unknown message type %u\r\n",
                   (unsigned)c->hdr.message_type);
        rc = -1;
        break;
    }

    return (rc == 0) ? ERR_OK : ERR_VAL;
}

/*
 * Feed a pbuf fragment into the M4V1 parser state machine.
 *
 * State machine:
 *   WAIT_HEADER:  accumulate 64 header bytes into hdr_buf
 *   WAIT_PAYLOAD: accumulate payload_length bytes into DDR (FRAME_DATA)
 *                 or into tx_buf scratch (small payloads like JOB_BEGIN)
 *   After payload_length bytes received -> dispatch_message -> back to WAIT_HEADER
 *
 * FRAME_DATA payloads go directly to DDR via handle_frame_data() so we
 * do not need a large intermediate buffer.
 */
static err_t m4v1_feed(m4v1_conn_t *c, const uint8_t *data, uint16_t len)
{
    uint16_t pos = 0U;

    while (pos < len) {
        switch (c->state) {

        case M4V1_STATE_WAIT_HEADER: {
            uint32_t need = M4V1_HEADER_SIZE - c->hdr_used;
            uint16_t take = (need > (uint16_t)(len - pos))
                            ? (uint16_t)(len - pos) : (uint16_t)need;
            memcpy(c->hdr_buf + c->hdr_used, data + pos, take);
            c->hdr_used += take;
            pos         += take;
            if (c->hdr_used == M4V1_HEADER_SIZE) {
                if (decode_m4v1_header(&c->hdr, c->hdr_buf) != 0)
                    return ERR_VAL;

                c->payload_expect = c->hdr.payload_length;
                c->payload_used   = 0U;

                if (c->payload_expect == 0U) {
                    /* No payload: dispatch immediately */
                    err_t e = dispatch_message(c);
                    c->hdr_used = 0U;
                    c->state    = M4V1_STATE_WAIT_HEADER;
                    if (e != ERR_OK) return e;
                } else if (c->payload_expect > M4V1_MAX_PAYLOAD) {
                    xil_printf("[ARM] Payload too large: %u\r\n",
                               (unsigned)c->payload_expect);
                    return ERR_VAL;
                } else {
                    /*
                     * Determine payload destination:
                     *  - FRAME_DATA  -> DDR (direct write via handle_frame_data)
                     *  - JOB_BEGIN   -> tx_buf scratch (16 bytes max)
                     *  - Other small -> tx_buf scratch
                     */
                    if (c->hdr.message_type == M4V1_MSG_FRAME_DATA) {
                        c->payload_ptr = NULL; /* handled inline in WAIT_PAYLOAD */
                    } else {
                        /* small payload: store in tx_buf (overwritten after dispatch) */
                        if (c->payload_expect > sizeof(c->tx_buf)) {
                            xil_printf("[ARM] Non-data payload too large: %u\r\n",
                                       (unsigned)c->payload_expect);
                            return ERR_VAL;
                        }
                        c->payload_ptr = c->tx_buf;
                    }
                    c->state = M4V1_STATE_WAIT_PAYLOAD;
                }
            }
            break;
        }

        case M4V1_STATE_WAIT_PAYLOAD: {
            uint32_t need = c->payload_expect - c->payload_used;
            uint16_t take = (need > (uint16_t)(len - pos))
                            ? (uint16_t)(len - pos) : (uint16_t)need;

            if (c->hdr.message_type == M4V1_MSG_FRAME_DATA) {
                /* Direct DDR write path */
                int rc = handle_frame_data(c, &c->hdr, data + pos, take);
                if (rc != 0)
                    return ERR_VAL;
            } else {
                /* Scratch buffer path */
                memcpy(c->payload_ptr + c->payload_used, data + pos, take);
            }
            c->payload_used += take;
            pos             += take;

            if (c->payload_used == c->payload_expect) {
                err_t e = dispatch_message(c);
                c->hdr_used = 0U;
                c->state    = M4V1_STATE_WAIT_HEADER;
                if (e != ERR_OK) return e;
            }
            break;
        }

        default:
            return ERR_VAL;
        }
    }
    return ERR_OK;
}

/* =========================================================================
 * LwIP callbacks
 * ========================================================================= */
static void close_connection(struct tcp_pcb *pcb)
{
    xil_printf("[ARM] Closing connection\r\n");
    tcp_arg(pcb, NULL);
    tcp_recv(pcb, NULL);
    tcp_sent(pcb, NULL);
    tcp_close(pcb);
    memset(&g_conn, 0, sizeof(g_conn));
}

static err_t tcp_recv_callback(void *arg, struct tcp_pcb *pcb,
                               struct pbuf *p, err_t err)
{
    m4v1_conn_t *c = (m4v1_conn_t *)arg;
    err_t result   = ERR_OK;

    if (err != ERR_OK) {
        if (p != NULL) pbuf_free(p);
        return err;
    }
    if (p == NULL || c == NULL) {
        close_connection(pcb);
        return ERR_OK;
    }

    tcp_recved(pcb, p->tot_len);

    /* Walk pbuf chain */
    {
        struct pbuf *seg = p;
        while (seg != NULL && result == ERR_OK) {
            result = m4v1_feed(c, (const uint8_t *)seg->payload,
                               (uint16_t)seg->len);
            seg = seg->next;
        }
    }
    pbuf_free(p);

    if (result != ERR_OK) {
        xil_printf("[ARM] Protocol error; closing connection\r\n");
        tcp_abort(pcb);
        memset(&g_conn, 0, sizeof(g_conn));
        return ERR_ABRT;
    }
    return ERR_OK;
}

static err_t tcp_accept_callback(void *arg, struct tcp_pcb *newpcb, err_t err)
{
    (void)arg;
    if (err != ERR_OK || newpcb == NULL || g_conn.pcb != NULL) {
        if (newpcb != NULL) tcp_abort(newpcb);
        return ERR_ABRT;
    }
    memset(&g_conn, 0, sizeof(g_conn));
    g_conn.pcb   = newpcb;
    g_conn.state = M4V1_STATE_WAIT_HEADER;
    tcp_arg(newpcb,  &g_conn);
    tcp_recv(newpcb, tcp_recv_callback);
    tcp_nagle_disable(newpcb);
    xil_printf("[ARM] Host connected\r\n");
    return ERR_OK;
}

/* =========================================================================
 * Network Init
 * ========================================================================= */
static int init_network(void)
{
    /* Static IP – change to match your lab network */
    unsigned char mac_address[] = {0x02, 0x00, 0x00, 0x00, 0x00, 0x50};
    ip_addr_t address, netmask, gateway;
    struct tcp_pcb *listen_pcb;

    IP4_ADDR(&address, 192, 168, 1, 50);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gateway, 192, 168, 1, 1);

    lwip_init();
    if (xemac_add(&g_netif, &address, &netmask, &gateway,
                  mac_address, XPAR_XEMACPS_0_BASEADDR) == NULL)
        return -1;

    netif_set_default(&g_netif);
    netif_set_up(&g_netif);

    listen_pcb = tcp_new();
    if (listen_pcb == NULL ||
        tcp_bind(listen_pcb, IP_ADDR_ANY, (u16_t)TCP_PORT) != ERR_OK)
        return -2;

    listen_pcb = tcp_listen_with_backlog(listen_pcb, (u8_t)TCP_BACKLOG);
    if (listen_pcb == NULL)
        return -3;

    tcp_accept(listen_pcb, tcp_accept_callback);
    return 0;
}

/* =========================================================================
 * main
 * ========================================================================= */
int main(void)
{
    uint32_t core_id;

    xil_printf("\r\n[ARM] ZedBoard Model-4 H.264 Accelerator Firmware\r\n");
    xil_printf("[ARM] Protocol: M4V1 v%u, TCP port %u\r\n",
               (unsigned)M4V1_PROTOCOL_VERSION, (unsigned)TCP_PORT);

    /* Verify PL core identity */
    core_id = Xil_In32(REG_CORE_ID);
    xil_printf("[ARM] Core ID=0x%08X version=0x%08X\r\n",
               (unsigned)core_id,
               (unsigned)Xil_In32(REG_CORE_VERSION));
    if (core_id != EXPECTED_CORE_ID) {
        xil_printf("[ARM] ERROR: unexpected core ID (expected 0x%08X)\r\n",
                   (unsigned)EXPECTED_CORE_ID);
        return -1;
    }

    /* Clear any stale error from prior run */
    Xil_Out32(REG_CONTROL, CTRL_FAULT_ACK);
    Xil_Out32(REG_CONTROL, 0U);

    if (init_dma() != 0) {
        xil_printf("[ARM] DMA init failed\r\n");
        return -2;
    }
    if (init_network() != 0) {
        xil_printf("[ARM] Network init failed\r\n");
        return -3;
    }

    xil_printf("[ARM] Listening on 192.168.1.50:%u (M4V1)\r\n",
               (unsigned)TCP_PORT);

    /* Bare-metal event loop */
    while (1) {
        xemacif_input(&g_netif);
        sys_check_timeouts();
    }

    /* Not reached */
    return 0;
}
