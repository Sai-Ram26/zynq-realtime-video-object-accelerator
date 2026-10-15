/**
 * @file xvideo_accel.c
 * @brief Driver implementation for Video Accelerator Custom IP and RISC-V Co-Processor.
 * @author G. Sai Ram (1602-24-735-163)
 * @institution Vasavi College of Engineering (Autonomous), Hyderabad
 */

#include "xvideo_accel.h"

void VideoAccel_Init(u32 BaseAddr) {
    // Reset core and set default parameters (640x480, QP=28)
    VideoAccel_SoftReset(BaseAddr);
    VideoAccel_SetResolution(BaseAddr, 640, 480);
    VideoAccel_SetQP(BaseAddr, 28);
    VideoAccel_Enable(BaseAddr);
}

void VideoAccel_SetResolution(u32 BaseAddr, u16 Width, u16 Height) {
    Xil_Out32(BaseAddr + REG_WIDTH_OFFSET, (u32)Width);
    Xil_Out32(BaseAddr + REG_HEIGHT_OFFSET, (u32)Height);
}

void VideoAccel_SetQP(u32 BaseAddr, u8 QP) {
    Xil_Out32(BaseAddr + REG_QP_OFFSET, (u32)(QP & 0x3F));
}

void VideoAccel_Enable(u32 BaseAddr) {
    u32 ctrl = Xil_In32(BaseAddr + REG_CTRL_OFFSET);
    ctrl |= (CTRL_ENABLE_MASK | CTRL_COMP_EN_MASK);
    ctrl &= ~CTRL_RESET_MASK;
    Xil_Out32(BaseAddr + REG_CTRL_OFFSET, ctrl);
}

void VideoAccel_Disable(u32 BaseAddr) {
    u32 ctrl = Xil_In32(BaseAddr + REG_CTRL_OFFSET);
    ctrl &= ~CTRL_ENABLE_MASK;
    Xil_Out32(BaseAddr + REG_CTRL_OFFSET, ctrl);
}

void VideoAccel_SoftReset(u32 BaseAddr) {
    Xil_Out32(BaseAddr + REG_CTRL_OFFSET, CTRL_RESET_MASK);
    for (volatile int i = 0; i < 100; i++); // Short settle delay
    Xil_Out32(BaseAddr + REG_CTRL_OFFSET, CTRL_ENABLE_MASK | CTRL_COMP_EN_MASK);
}

u32 VideoAccel_GetStatus(u32 BaseAddr) {
    return Xil_In32(BaseAddr + REG_STATUS_OFFSET);
}

u32 VideoAccel_GetPixelCount(u32 BaseAddr) {
    return Xil_In32(BaseAddr + REG_PERF_PIXEL_OFFSET);
}

// ============================================================================
// RISC-V Custom ISA Co-Processor Driver Functions
// ============================================================================

u32 VideoAccel_RiscV_Exec(u32 BaseAddr, u32 InstrWord, u32 rs1, u32 rs2, u32 rs3) {
    // 1. Write operands to co-processor registers
    Xil_Out32(BaseAddr + REG_RISCV_RS1_OFFSET, rs1);
    Xil_Out32(BaseAddr + REG_RISCV_RS2_OFFSET, rs2);
    Xil_Out32(BaseAddr + REG_RISCV_RS3_OFFSET, rs3);

    // 2. Writing instruction word automatically triggers execution
    Xil_Out32(BaseAddr + REG_RISCV_INSTR_OFFSET, InstrWord);

    // 3. Short wait for co-processor completion handshake
    for (volatile int i = 0; i < 20; i++);

    // 4. Return result from RISC-V destination register rd
    return Xil_In32(BaseAddr + REG_RISCV_RD_OFFSET);
}

void VideoAccel_RiscV_VBLK(u32 BaseAddr, u16 Width, u16 Height, u8 QP) {
    // Encode RISC-V Custom-0 instruction: funct3=000, opcode=0x0B
    u32 instr = 0x0000000B; // opcode 0x0B, funct3=000
    u32 rs1   = (u32)Width;
    u32 rs2   = (u32)Height;
    u32 rs3   = (u32)(QP & 0x3F);
    VideoAccel_RiscV_Exec(BaseAddr, instr, rs1, rs2, rs3);
}

void VideoAccel_RiscV_VQNT(u32 BaseAddr, u8 QP) {
    // Encode RISC-V Custom-0 instruction: funct3=011, opcode=0x0B
    u32 instr = 0x0000300B; // funct3=3'b011, opcode=0x0B
    u32 rs3   = (u32)(QP & 0x3F);
    VideoAccel_RiscV_Exec(BaseAddr, instr, 0, 0, rs3);
}

u32 VideoAccel_RiscV_VSTATUS(u32 BaseAddr) {
    // Encode RISC-V Custom-0 instruction: funct3=101, opcode=0x0B
    u32 instr = 0x0000500B; // funct3=3'b101, opcode=0x0B
    return VideoAccel_RiscV_Exec(BaseAddr, instr, 0, 0, 0);
}
