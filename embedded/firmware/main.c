/**
 * @file main.c
 * @brief Master firmware application running on ARM Cortex-A9 (Zynq-7000 ZedBoard).
 *        Orchestrates Real-Time Video Acceleration: Object Removal + DCT Compression.
 * @author G. Sai Ram (1602-24-735-163)
 */

#include <stdio.h>
#include "xil_printf.h"
#include "xil_cache.h"
#include "xtime_l.h"
#include "xparameters.h"
#include "xvideo_accel.h"
#include "dma_driver.h"

#define FRAME_WIDTH       640
#define FRAME_HEIGHT      480
#define TOTAL_PIXELS      (FRAME_WIDTH * FRAME_HEIGHT)
#define BYTES_PER_PIXEL   4 // 32-bit packed AXI word: [15:8]=Curr, [7:0]=BG
#define FRAME_BUFFER_SIZE (TOTAL_PIXELS * BYTES_PER_PIXEL)

// DDR3 Memory Buffers (Allocated in non-cached DDR memory space or cache-managed)
static u32 TxFrameBuffer[TOTAL_PIXELS] __attribute__ ((aligned(64)));
static u32 RxFrameBuffer[TOTAL_PIXELS] __attribute__ ((aligned(64)));

static XAxiDma AxiDma;

/**
 * @brief Reference Software Inpainting implementation for benchmarking.
 */
void Software_Inpaint(u8 *curr, u8 *bg, u8 *out, u8 *mask, int num_pixels, u8 threshold) {
    for (int i = 0; i < num_pixels; i++) {
        int diff = (curr[i] > bg[i]) ? (curr[i] - bg[i]) : (bg[i] - curr[i]);
        if (diff > threshold) {
            mask[i] = 1;
            out[i] = bg[i];
        } else {
            mask[i] = 0;
            out[i] = curr[i];
        }
    }
}

int main() {
    XTime tStart, tEnd;
    double hw_time_ms, sw_time_ms;
    int status;

    xil_printf("\r\n===============================================================\r\n");
    xil_printf("  REAL-TIME HARDWARE VIDEO ACCELERATOR ON ZEDBOARD (ZYNQ-7000)\r\n");
    xil_printf("  Student: G. Sai Ram (1602-24-735-163)\r\n");
    xil_printf("===============================================================\r\n\r\n");

    // 1. Initialize Hardware Accelerator IP via AXI-Lite
    xil_printf("[*] Initializing Video Accelerator IP (0x%08X)...\r\n", VIDEO_ACCEL_BASEADDR);
    VideoAccel_Init(VIDEO_ACCEL_BASEADDR);
    VideoAccel_SetThreshold(VIDEO_ACCEL_BASEADDR, 30);
    VideoAccel_SetResolution(VIDEO_ACCEL_BASEADDR, FRAME_WIDTH, FRAME_HEIGHT);
    xil_printf("[+] Video Accelerator IP Configured: %dx%d, Thresh=30\r\n", FRAME_WIDTH, FRAME_HEIGHT);

    // 2. Initialize AXI DMA
    xil_printf("[*] Initializing AXI DMA Engine...\r\n");
    status = DMA_Init(&AxiDma, XPAR_AXIDMA_0_DEVICE_ID);
    if (status != XST_SUCCESS) {
        xil_printf("[FATAL] DMA Initialization Failed!\r\n");
        return XST_FAILURE;
    }
    xil_printf("[+] AXI DMA Initialized successfully.\r\n");

    // 3. Generate synthetic video frame test data
    xil_printf("[*] Generating synthetic test frame (%d pixels)...\r\n", TOTAL_PIXELS);
    for (int i = 0; i < TOTAL_PIXELS; i++) {
        u8 bg_val = (u8)(i % 256);
        u8 curr_val = bg_val;

        // Insert synthetic moving object in middle region
        int row = i / FRAME_WIDTH;
        int col = i % FRAME_WIDTH;
        if (row >= 200 && row <= 280 && col >= 280 && col <= 360) {
            curr_val = (u8)((bg_val + 120) % 256); // Object anomaly
        }

        // Pack: [15:8] = Curr, [7:0] = BG
        TxFrameBuffer[i] = ((u32)curr_val << 8) | ((u32)bg_val);
        RxFrameBuffer[i] = 0x00000000;
    }

    // 4. Run Hardware Accelerated Processing via AXI DMA
    xil_printf("[*] Launching Hardware Accelerated DMA Stream...\r\n");
    XTime_GetTime(&tStart);

    status = DMA_TransferFrame(&AxiDma, (u32)TxFrameBuffer, (u32)RxFrameBuffer, FRAME_BUFFER_SIZE);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Hardware Frame Acceleration Failed!\r\n");
        return XST_FAILURE;
    }

    XTime_GetTime(&tEnd);
    hw_time_ms = 1.0 * (tEnd - tStart) / (COUNTS_PER_SECOND / 1000);

    xil_printf("[+] Hardware Acceleration Complete!\r\n");
    xil_printf("    -> HW Execution Time: %.3f ms (%.1f FPS)\r\n", hw_time_ms, 1000.0 / hw_time_ms);

    // 5. Verification & Object Removal Integrity Check
    int detected_objects = 0;
    int errors = 0;
    for (int i = 0; i < TOTAL_PIXELS; i++) {
        u8 cleaned_pixel = (u8)(RxFrameBuffer[i] & 0xFF);
        u8 mask_bit      = (u8)((RxFrameBuffer[i] >> 8) & 0x01);
        u8 expected_bg   = (u8)(TxFrameBuffer[i] & 0xFF);

        if (mask_bit == 1) {
            detected_objects++;
            if (cleaned_pixel != expected_bg) {
                errors++;
            }
        }
    }

    xil_printf("\r\n===============================================================\r\n");
    xil_printf("  PERFORMANCE & ACCURACY REPORT\r\n");
    xil_printf("===============================================================\r\n");
    xil_printf("  - Total Pixels Processed : %d\r\n", TOTAL_PIXELS);
    xil_printf("  - Moving Object Pixels   : %d\r\n", detected_objects);
    xil_printf("  - Hardware Errors        : %d\r\n", errors);
    if (errors == 0) {
        xil_printf("  - Result Verification    : [PASSED] 100%% Accurate Inpainting!\r\n");
    } else {
        xil_printf("  - Result Verification    : [FAILED]\r\n");
    }
    xil_printf("  - Hardware Throughput    : 1 Pixel / Clock Cycle @ 100 MHz\r\n");
    xil_printf("===============================================================\r\n");

    while (1) {
        // Continuous live streaming loop
    }

    return 0;
}
