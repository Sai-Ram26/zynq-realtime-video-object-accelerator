/**
 * @file dma_driver.h
 * @brief High-Performance AXI DMA Driver for Video Streaming to FPGA PL.
 * @author G. Sai Ram (1602-24-735-163)
 */

#ifndef DMA_DRIVER_H
#define DMA_DRIVER_H

#include "xaxidma.h"
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_printf.h"

#ifndef DMA_DEV_ID
#define DMA_DEV_ID          XPAR_AXIDMA_0_DEVICE_ID
#endif

// Function Prototypes
int  DMA_Init(XAxiDma *AxiDmaInst, u16 DeviceId);
int  DMA_TransferFrame(XAxiDma *AxiDmaInst, u32 TxBufferAddr, u32 RxBufferAddr, u32 ByteLength);
int  DMA_IsBusy(XAxiDma *AxiDmaInst);

#endif // DMA_DRIVER_H
