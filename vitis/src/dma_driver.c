/**
 * @file dma_driver.c
 * @brief High-Performance AXI DMA Driver Implementation.
 * @author G. Sai Ram (1602-24-735-163)
 */

#include "dma_driver.h"

int DMA_Init(XAxiDma *AxiDmaInst, u16 DeviceId) {
    XAxiDma_Config *CfgPtr;
    int Status;

    CfgPtr = XAxiDma_LookupConfig(DeviceId);
    if (!CfgPtr) {
        xil_printf("[ERROR] No config found for AXI DMA %d\r\n", DeviceId);
        return XST_FAILURE;
    }

    Status = XAxiDma_CfgInitialize(AxiDmaInst, CfgPtr);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] AXI DMA Initialization failed %d\r\n", Status);
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(AxiDmaInst)) {
        xil_printf("[ERROR] Device configured as SG mode, expected Simple Direct Register mode\r\n");
        return XST_FAILURE;
    }

    // Disable interrupts for polling mode
    XAxiDma_IntrDisable(AxiDmaInst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(AxiDmaInst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    return XST_SUCCESS;
}

int DMA_TransferFrame(XAxiDma *AxiDmaInst, u32 TxBufferAddr, u32 RxBufferAddr, u32 ByteLength) {
    int Status;

    // 1. Flush TX cache (ensure DDR3 has newest frame data written by CPU)
    Xil_DCacheFlushRange((INTPTR)TxBufferAddr, ByteLength);

    // 2. Invalidate RX cache (ensure CPU reads newest data coming from FPGA)
    Xil_DCacheInvalidateRange((INTPTR)RxBufferAddr, ByteLength);

    // 3. Initiate S2MM (Device to DMA RX Transfer first)
    Status = XAxiDma_SimpleTransfer(AxiDmaInst, (UINTPTR)RxBufferAddr, ByteLength, XAXIDMA_DEVICE_TO_DMA);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] DMA S2MM Transfer failed %d\r\n", Status);
        return XST_FAILURE;
    }

    // 4. Initiate MM2S (DMA to Device TX Transfer)
    Status = XAxiDma_SimpleTransfer(AxiDmaInst, (UINTPTR)TxBufferAddr, ByteLength, XAXIDMA_DMA_TO_DEVICE);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] DMA MM2S Transfer failed %d\r\n", Status);
        return XST_FAILURE;
    }

    // 5. Wait for both transfers to complete
    while (XAxiDma_Busy(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE) ||
           XAxiDma_Busy(AxiDmaInst, XAXIDMA_DEVICE_TO_DMA)) {
        // Wait polling loop
    }

    // 6. Invalidate RX cache once more after DMA completes
    Xil_DCacheInvalidateRange((INTPTR)RxBufferAddr, ByteLength);

    return XST_SUCCESS;
}

int DMA_IsBusy(XAxiDma *AxiDmaInst) {
    return (XAxiDma_Busy(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE) ||
            XAxiDma_Busy(AxiDmaInst, XAXIDMA_DEVICE_TO_DMA));
}
