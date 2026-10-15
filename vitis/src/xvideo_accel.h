/**
 * @file xvideo_accel.h
 * @brief Driver header for Real-Time H.264 Video Compression Accelerator IP
 *        with integrated RISC-V Custom ISA Co-Processor on Zynq-7000 (ZedBoard).
 * @author G. Sai Ram (1602-24-735-163)
 * @institution Vasavi College of Engineering (Autonomous), Hyderabad
 */

#ifndef XVIDEO_ACCEL_H
#define XVIDEO_ACCEL_H

#include "xil_types.h"
#include "xil_io.h"

// Base address mapped in Vivado Address Editor (default: 0x43C00000)
#define VIDEO_ACCEL_BASEADDR        0x43C00000

// ============================================================================
// AXI4-Lite Register Offsets (Word-aligned)
// ============================================================================
#define REG_CTRL_OFFSET             0x00  // [0]=Enable, [1]=SoftReset, [2]=CompEn
#define REG_WIDTH_OFFSET            0x04  // Frame Width in pixels (e.g. 640)
#define REG_HEIGHT_OFFSET           0x08  // Frame Height in pixels (e.g. 480)
#define REG_QP_OFFSET               0x0C  // Quantization Parameter (0-51)
#define REG_STATUS_OFFSET           0x10  // [0]=Busy, [1]=Done, [2]=IRQ
#define REG_PERF_PIXEL_OFFSET       0x14  // Total pixels processed counter
#define REG_PERF_SKIP_OFFSET        0x18  // Total skipped blocks counter

// RISC-V Custom ISA Extension Co-Processor Registers (Opcode 0x0B)
#define REG_RISCV_CTRL_OFFSET       0x1C  // [0]=Trigger pulse, [1]=Busy, [2]=Done
#define REG_RISCV_INSTR_OFFSET      0x20  // 32-bit RISC-V Machine Instruction Word
#define REG_RISCV_RS1_OFFSET        0x24  // Operand 1 (Width / base parameter)
#define REG_RISCV_RS2_OFFSET        0x28  // Operand 2 (Height / stride parameter)
#define REG_RISCV_RS3_OFFSET        0x2C  // Operand 3 ([7:0]=QP, [15:8]=Mode)
#define REG_RISCV_RD_OFFSET         0x30  // Result readback from rd register

// Control Register Masks
#define CTRL_ENABLE_MASK            0x00000001
#define CTRL_RESET_MASK             0x00000002
#define CTRL_COMP_EN_MASK           0x00000004

// Status Register Masks
#define STATUS_BUSY_MASK            0x00000001
#define STATUS_DONE_MASK            0x00000002
#define STATUS_IRQ_MASK             0x00000004

// RISC-V Custom-0 Opcode & Funct3 Definitions
#define RISCV_OPCODE_CUSTOM0        0x0B
#define RISCV_FUNCT3_VBLK           0x0
#define RISCV_FUNCT3_VSCALE         0x1
#define RISCV_FUNCT3_VDCT           0x2
#define RISCV_FUNCT3_VQNT           0x3
#define RISCV_FUNCT3_VENC           0x4
#define RISCV_FUNCT3_VSTATUS        0x5
#define RISCV_FUNCT3_VWAIT          0x6

// ============================================================================
// Accelerator Driver API Functions
// ============================================================================
void VideoAccel_Init(u32 BaseAddr);
void VideoAccel_SetResolution(u32 BaseAddr, u16 Width, u16 Height);
void VideoAccel_SetQP(u32 BaseAddr, u8 QP);
void VideoAccel_Enable(u32 BaseAddr);
void VideoAccel_Disable(u32 BaseAddr);
void VideoAccel_SoftReset(u32 BaseAddr);
u32  VideoAccel_GetStatus(u32 BaseAddr);
u32  VideoAccel_GetPixelCount(u32 BaseAddr);

// ============================================================================
// RISC-V Custom ISA Co-Processor API Functions (ARM -> RISC-V -> Accelerator)
// ============================================================================
u32  VideoAccel_RiscV_Exec(u32 BaseAddr, u32 InstrWord, u32 rs1, u32 rs2, u32 rs3);
void VideoAccel_RiscV_VBLK(u32 BaseAddr, u16 Width, u16 Height, u8 QP);
void VideoAccel_RiscV_VQNT(u32 BaseAddr, u8 QP);
u32  VideoAccel_RiscV_VSTATUS(u32 BaseAddr);

#endif // XVIDEO_ACCEL_H
