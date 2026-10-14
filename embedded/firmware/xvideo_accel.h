/**
 * @file xvideo_accel.h
 * @brief Driver header for Video Accelerator Custom IP on Zynq-7000 (ZedBoard).
 * @author G. Sai Ram (1602-24-735-163)
 */

#ifndef XVIDEO_ACCEL_H
#define XVIDEO_ACCEL_H

#include "xil_types.h"
#include "xil_io.h"

// Base address mapped in Vivado Address Editor (default: 0x43C00000)
#define VIDEO_ACCEL_BASEADDR    0x43C00000

// Register Offsets
#define REG_CTRL_OFFSET         0x00  // Control Register: [0]=Enable, [1]=Soft Reset
#define REG_THRESH_OFFSET       0x04  // Threshold Register: [7:0]=Pixel Difference Threshold
#define REG_WIDTH_OFFSET        0x08  // Frame Width Register (e.g., 640)
#define REG_HEIGHT_OFFSET       0x0C  // Frame Height Register (e.g., 480)
#define REG_STATUS_OFFSET       0x10  // Status Register: [0]=Busy, [1]=Done

// Bit Masks
#define CTRL_ENABLE_MASK        0x00000001
#define CTRL_RESET_MASK         0x00000002

// Driver API Functions
void VideoAccel_Init(u32 BaseAddr);
void VideoAccel_SetThreshold(u32 BaseAddr, u8 Threshold);
void VideoAccel_SetResolution(u32 BaseAddr, u16 Width, u16 Height);
void VideoAccel_Enable(u32 BaseAddr);
void VideoAccel_Disable(u32 BaseAddr);
void VideoAccel_SoftReset(u32 BaseAddr);
u32  VideoAccel_GetStatus(u32 BaseAddr);

#endif // XVIDEO_ACCEL_H
