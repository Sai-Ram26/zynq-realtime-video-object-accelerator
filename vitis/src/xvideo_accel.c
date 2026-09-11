/**
 * @file xvideo_accel.c
 * @brief Driver implementation for Video Accelerator Custom IP.
 * @author G. Sai Ram (1602-24-735-163)
 */

#include "xvideo_accel.h"

void VideoAccel_Init(u32 BaseAddr) {
    // Reset core and set default parameters
    VideoAccel_SoftReset(BaseAddr);
    VideoAccel_SetThreshold(BaseAddr, 30);
    VideoAccel_SetResolution(BaseAddr, 640, 480);
    VideoAccel_Enable(BaseAddr);
}

void VideoAccel_SetThreshold(u32 BaseAddr, u8 Threshold) {
    Xil_Out32(BaseAddr + REG_THRESH_OFFSET, (u32)Threshold);
}

void VideoAccel_SetResolution(u32 BaseAddr, u16 Width, u16 Height) {
    Xil_Out32(BaseAddr + REG_WIDTH_OFFSET, (u32)Width);
    Xil_Out32(BaseAddr + REG_HEIGHT_OFFSET, (u32)Height);
}

void VideoAccel_Enable(u32 BaseAddr) {
    u32 ctrl = Xil_In32(BaseAddr + REG_CTRL_OFFSET);
    ctrl |= CTRL_ENABLE_MASK;
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
    for (volatile int i = 0; i < 100; i++); // Short delay
    Xil_Out32(BaseAddr + REG_CTRL_OFFSET, CTRL_ENABLE_MASK);
}

u32 VideoAccel_GetStatus(u32 BaseAddr) {
    return Xil_In32(BaseAddr + REG_STATUS_OFFSET);
}
