# Hardware Architecture & RTL Specification

**Target SoC:** AMD/Xilinx Zynq-7000 XC7Z020-1CLG484 (Avnet ZedBoard)  
**Hardware Acceleration Target:** Downscaling (720p/1080p/4K/8K $\to$ 240p/144p) + H.264 Baseline Intra-Compression (DCT, Quant, CAVLC)

---

## 1. Hardware Architecture Overview

```
+---------------------------------------------------------------------------------+
|                                 ZYNQ PS (ARM)                                   |
|   +-------------------+    +--------------------+    +----------------------+   |
|   | Dual Cortex-A9    |    |   Gigabit Ethernet |    |  AXI Central DMA     |   |
|   | TCP Socket Server |<-->|   Marvell 88E1510  |<-->|  Memory-to-Stream    |   |
|   +---------+---------+    +--------------------+    +----------+-----------+   |
|             | AXI-GP0 (AXI4-Lite)                               | AXI-HP0       |
+-------------|---------------------------------------------------|---------------+
              | Control / Config                                  | Video Data Stream
              v                                                   v
+---------------------------------------------------------------------------------+
|                                 ZYNQ PL (FPGA)                                  |
|                                                                                 |
|   +-------------------------------------------------------------------------+   |
|   | AXI-Lite Slave Registers (Base: 0x43C00000)                             |   |
|   | 0x00: CTRL (Start, Reset, Enable)   0x08: SRC_RES (Width, Height)       |   |
|   | 0x04: STATUS (Busy, Done, Error)    0x0C: TGT_RES (Width, Height)       |   |
|   | 0x10: QP (Quantization Parameter)   0x14: PERF_CYCLES                   |   |
|   +------------------------------------+------------------------------------+   |
|                                        |                                        |
|   +------------------------------------v------------------------------------+   |
|   | AXI4-Stream Video Processing Pipeline                                   |   |
|   |                                                                         |   |
|   |  AXI-S In ---> [ AXI-Stream Input FIFO ]                                |   |
|   |                        |                                                |   |
|   |                        v                                                |   |
|   |                [ RGB to YUV420 Converter ]                              |   |
|   |                        |                                                |   |
|   |                        v                                                |   |
|   |                [ Streaming Polyphase Downscaler ]                       |   |
|   |                - Bilinear / Polyphase Filter                            |   |
|   |                - Dual BRAM Line Buffers (Downscales to 240p/144p)       |   |
|   |                        |                                                |   |
|   |                        v                                                |   |
|   |                [ 4x4 Block Assembler & Raster Buffer ]                  |   |
|   |                        |                                                |   |
|   |                        v                                                |   |
|   |                [ 4x4 H.264 Integer Transform (DCT) ]                    |   |
|   |                - Multiplierless: W = H * X * H^T                        |   |
|   |                        |                                                |   |
|   |                        v                                                |   |
|   |                [ Hardware Quantizer & Zigzag Scanner ]                  |   |
|   |                - Programmable QP scaling                                |   |
|   |                        |                                                |   |
|   |                        v                                                |   |
|   |                [ CAVLC Entropy Encoder ]                                |   |
|   |                - TotalCoeff, TrailingOnes, Levels, Runs                 |   |
|   |                        |                                                |   |
|   |                        v                                                |   |
|   |                [ NAL Unit Header & Bitstream Formatter ]                |   |
|   |                        |                                                |   |
|   |  AXI-S Out <-- [ AXI-Stream Output FIFO ]                               |   |
|   +-------------------------------------------------------------------------+   |
+---------------------------------------------------------------------------------+
```

---

## 2. RTL Module Hierarchy

| Module Name | File Location | Purpose & Functionality |
| :--- | :--- | :--- |
| `video_accelerator_top` | `fpga/rtl/video_accelerator_top.v` | Top-level integration uniting AXI-Lite control and AXI4-Stream data path. |
| `axi_lite_regs` | `fpga/rtl/axi_lite_regs.v` | Memory-mapped register file for host control, resolution selection, and telemetry. |
| `axis_fifo` | `fpga/rtl/axis_fifo.v` | Parameterized elastic dual-clock/synchronous FIFO with valid/ready handshake. |
| `rgb2yuv` | `fpga/rtl/rgb2yuv.v` | Fixed-point color transformation: RGB888 $\to$ YUV420. |
| `streaming_scaler` | `fpga/rtl/streaming_scaler.v` | Streaming spatial decimator/scaler with line-buffers for $720p/1080p/4K/8K \to 240p/144p$. |
| `block_assembler_4x4`| `fpga/rtl/block_assembler_4x4.v` | Re-orders raster-scan stream into 16-sample $4\times 4$ macroblocks. |
| `dct_4x4` | `fpga/rtl/dct_4x4.v` | Standard H.264 4x4 integer forward transform core. |
| `quant_4x4` | `fpga/rtl/quant_4x4.v` | Quantization core supporting QP 0-51 with zigzag coefficient re-ordering. |
| `cavlc_encoder` | `fpga/rtl/cavlc_encoder.v` | Context-Adaptive Variable-Length Coding entropy engine. |
| `nal_formatter` | `fpga/rtl/nal_formatter.v` | Appends H.264 NAL headers, slice start codes, and byte alignment. |

---

## 3. FPGA Resource Budget (XC7Z020-1CLG484)

- **Total Available LUTs:** 53,200
- **Total Available FFs:** 106,400
- **Total BRAM36 Blocks:** 140
- **Total DSP48E1 Slices:** 220
- **Estimated Pipeline Utilization:** ~15,000–22,000 LUTs (<42%), ~25-40 BRAM36s (<30%), ~16-32 DSP48s (<15%).
- **Verification Rule:** All final resource numbers are obtained via Vivado implementation reports (`results/utilization.rpt`) and never fabricated.
