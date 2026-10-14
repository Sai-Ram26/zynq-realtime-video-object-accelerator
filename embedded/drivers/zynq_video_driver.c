/**
 * ============================================================================
 * File: zynq_video_driver.c
 * Project: High-Efficiency Zynq SoC Video Accelerator Architecture
 * Description: Linux Userspace Device Driver for Custom Video Accelerator IP.
 *              Uses /dev/mem to memory-map AXI4-Lite registers at 0x43C00000.
 * Target: AMD Xilinx Zynq-7000 (ARM Cortex-A9 @ 667 MHz, ZedBoard)
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#define ACCEL_BASE_ADDR   0x43C00000UL
#define MAP_SIZE          0x1000UL       /* 4KB page */

/* Register Offsets */
#define REG_CR_CONTROL     (0x00 / 4)
#define REG_CR_INSN        (0x04 / 4)
#define REG_CR_RS1_DATA    (0x08 / 4)
#define REG_CR_CONFIG      (0x0C / 4)
#define REG_CR_PIXEL_IN    (0x10 / 4)
#define REG_CR_Y_BG        (0x14 / 4)
#define REG_SR_STATUS      (0x18 / 4)
#define REG_SR_Y_INP       (0x1C / 4)
#define REG_SR_NAL_WORD    (0x20 / 4)
#define REG_SR_TOT_CYCLES  (0x24 / 4)
#define REG_SR_ACT_CYCLES  (0x28 / 4)
#define REG_SR_STL_CYCLES  (0x2C / 4)
#define REG_SR_PIXEL_CNT   (0x30 / 4)
#define REG_SR_INP_EVENTS  (0x34 / 4)
#define REG_SR_NAL_CNT     (0x38 / 4)

/* Custom RISC-V Opcodes */
#define OPCODE_CUSTOM_VEC  0x0B
#define FUNCT3_RGB2YUV     0x00
#define FUNCT3_BGSUB       0x01
#define FUNCT3_INPAINT     0x02
#define FUNCT3_DCT4X4      0x03
#define FUNCT3_CAVLC       0x04

typedef struct {
    int mem_fd;
    volatile uint32_t *regs;
} zynq_accel_t;

int zynq_accel_init(zynq_accel_t *dev) {
    dev->mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (dev->mem_fd < 0) {
        perror("[-] Failed to open /dev/mem");
        return -1;
    }

    void *mapped = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED,
                        dev->mem_fd, ACCEL_BASE_ADDR);
    if (mapped == MAP_FAILED) {
        perror("[-] Failed to mmap accelerator register block");
        close(dev->mem_fd);
        return -1;
    }

    dev->regs = (volatile uint32_t *)mapped;
    printf("[+] Zynq Video Accelerator initialized at 0x%08lX\n", ACCEL_BASE_ADDR);
    return 0;
}

void zynq_accel_close(zynq_accel_t *dev) {
    if (dev->regs) {
        munmap((void *)dev->regs, MAP_SIZE);
    }
    if (dev->mem_fd >= 0) {
        close(dev->mem_fd);
    }
}

void zynq_accel_configure(zynq_accel_t *dev, uint8_t qp, uint8_t thresh, uint8_t y_bg) {
    uint32_t cfg = ((uint32_t)thresh << 8) | (qp & 0x3F);
    dev->regs[REG_CR_CONFIG] = cfg;
    dev->regs[REG_CR_Y_BG]   = (uint32_t)y_bg;
}

void zynq_accel_set_perf_enable(zynq_accel_t *dev, bool enable) {
    uint32_t ctrl = dev->regs[REG_CR_CONTROL];
    if (enable) ctrl |= (1 << 2);
    else        ctrl &= ~(1 << 2);
    dev->regs[REG_CR_CONTROL] = ctrl;
}

void zynq_accel_dispatch_vector_insn(zynq_accel_t *dev, uint8_t funct3, uint32_t base_addr) {
    uint32_t insn = ((uint32_t)(funct3 & 0x07) << 12) | (OPCODE_CUSTOM_VEC & 0x7F);
    dev->regs[REG_CR_INSN]     = insn;
    dev->regs[REG_CR_RS1_DATA] = base_addr;
    dev->regs[REG_CR_CONTROL]  |= 0x01; // reg_start pulse
}

void zynq_accel_read_perf(zynq_accel_t *dev) {
    printf("\n--- Hardware Performance Monitor Report ---\n");
    printf("Total Clock Cycles:   %u\n", dev->regs[REG_SR_TOT_CYCLES]);
    printf("Active Processing:    %u\n", dev->regs[REG_SR_ACT_CYCLES]);
    printf("Pipeline Stalls:      %u\n", dev->regs[REG_SR_STL_CYCLES]);
    printf("Processed Pixels:     %u\n", dev->regs[REG_SR_PIXEL_CNT]);
    printf("Inpainting Events:    %u\n", dev->regs[REG_SR_INP_EVENTS]);
    printf("Compressed NAL Words: %u\n", dev->regs[REG_SR_NAL_CNT]);
    printf("-------------------------------------------\n");
}

int main(int argc, char **argv) {
    zynq_accel_t dev;
    if (zynq_accel_init(&dev) != 0) {
        return 1;
    }

    /* Configure QP=24, T_thresh=30, Background Y=76 */
    zynq_accel_configure(&dev, 24, 30, 76);
    zynq_accel_set_perf_enable(&dev, true);

    /* Dispatch Custom Inpaint Instruction */
    zynq_accel_dispatch_vector_insn(&dev, FUNCT3_INPAINT, 0x10000000UL);

    /* Read Performance Profile */
    zynq_accel_read_perf(&dev);

    zynq_accel_close(&dev);
    return 0;
}
