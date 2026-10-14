# System Architecture: Offline FPGA Video Compression Accelerator

**Target System:** Avnet ZedBoard (AMD/Xilinx Zynq-7000 SoC XC7Z020)  
**Host Controller:** Local Laptop Software (Completely Offline)  
**Document Classification:** Rigorous Research & Architecture Plan

---

## 1. Mathematical Grounding: The Raw Video Bandwidth Problem

To determine physical feasibility without fabrication, we calculate the uncompressed data rates across target resolutions.

### 1.1 Uncompressed Frame & Throughput Calculations

Let width be $W$, height be $H$, frame rate be $F = 60\text{ fps}$.
- **RGB888**: 24 bits/pixel (3 bytes/pixel).
- **YUV 4:2:0**: 12 bits/pixel (1.5 bytes/pixel: $W \times H$ bytes for Y, $(W/2 \times H/2) = W \cdot H / 4$ bytes each for U and V).

$$\text{Data per frame (Bytes)} = W \times H \times (\text{Bytes per pixel})$$
$$\text{Bitrate (Gbps)} = \frac{W \times H \times (\text{Bits per pixel}) \times 60}{10^9}$$
$$\text{Bandwidth (GB/s)} = \frac{W \times H \times (\text{Bytes per pixel}) \times 60}{10^9}$$

| Resolution | Dimensions ($W \times H$) | Pixels / Frame | RGB888 / Frame | RGB888 @ 60fps (GB/s) | RGB888 @ 60fps (Gbps) | YUV 4:2:0 / Frame | YUV420 @ 60fps (GB/s) | YUV420 @ 60fps (Gbps) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **720p** | $1280 \times 720$ | 0.92 M | 2.76 MB | 0.166 GB/s | 1.33 Gbps | 1.38 MB | 0.083 GB/s | 0.66 Gbps |
| **1080p** | $1920 \times 1080$ | 2.07 M | 6.22 MB | 0.373 GB/s | 2.99 Gbps | 3.11 MB | 0.187 GB/s | 1.49 Gbps |
| **4K UHD** | $3840 \times 2160$ | 8.29 M | 24.88 MB | 1.493 GB/s | 11.94 Gbps | 12.44 MB | 0.746 GB/s | 5.97 Gbps |
| **8K UHD** | $7680 \times 4320$ | 33.18 M | 99.53 MB | 5.972 GB/s | 47.78 Gbps | 49.77 MB | 2.986 GB/s | 23.89 Gbps |

*(Note: If calculated at high precision: $7680 \times 4320 \times 3 \times 60 = 5.972 \times 10^{10} \text{ bits/s} \approx 47.8 \text{ Gbps}$ in decimal, or $59.7 \text{ GB/s}$ when evaluating un-subsampled bus transactions).*

### 1.2 Communication Feasibility Analysis
- **Gigabit Ethernet Physical Limit**: 1.0 Gbps physical signaling.
- **Maximum Theoretical Payload**: $\approx 125\text{ MB/s}$ ($1.0 \times 10^9 / 8$).
- **Realistic TCP/IP Application Throughput**: $\approx 90 - 110\text{ MB/s}$.

**ENGINEERING INFERENCE**:
1. Uncompressed 720p60 YUV420 requires ~83 MB/s, which marginally fits within Gigabit Ethernet under near-ideal conditions.
2. Uncompressed 1080p60 requires ~187 MB/s, which exceeds 1 GbE by $1.7\times$.
3. Uncompressed 4K60 requires ~746 MB/s, which exceeds 1 GbE by $6.8\times$.
4. Uncompressed 8K60 requires ~2.99 GB/s, which exceeds 1 GbE by $27\times$.
5. **Conclusion**: Real-time streaming of uncompressed 4K and 8K over 1 GbE is a physical impossibility. Therefore, the system implements **offline batch frame/tile processing**, transferring frames sequentially as bandwidth permits, and explicitly documents this limitation without fabricating real-time capabilities.

---

## 2. System Level Architectural Breakdown

```
+---------------------------------------------------------------------------------+
|                                 HOST LAPTOP                                     |
|  +-------------------------------------+  +----------------------------------+  |
|  |           OFFLINE WEBSITE           |  |          LOCAL BACKEND           |  |
|  |     (HTML5 / CSS / Vanilla JS)      |  |             (Python)             |  |
|  | - Video Picker & File Inspector    |  | - Flask REST & Static Host       |  |
|  | - Resolution Selector (240p, 144p)  |  | - Video Container Demux/Decode   |  |
|  | - Real-time Status & Telemetry      |  | - Binary Packet Protocol Engine  |  |
|  | - Side-by-Side Synchronized Player  |  | - Metric Engine (PSNR, SSIM)     |  |
|  +------------------^------------------+  +-----------------^----------------+  |
+---------------------|---------------------------------------|-------------------+
                      | HTTP / JSON                           | TCP Socket
                      v                                       v (1 GbE Link)
+---------------------------------------------------------------------------------+
|                        ZEDBOARD (ZYNQ-7000 XC7Z020)                             |
|                                                                                 |
|  [ PROCESSING SYSTEM (PS) ]                                                     |
|  +---------------------------------------------------------------------------+  |
|  |  ARM Cortex-A9 Dual-Core Processor (@ 667 MHz)                           |  |
|  |  - TCP/IP Stack & Socket Server (LWIP / Linux Socket)                     |  |
|  |  - Accelerator DMA Ring Buffer Management                                |  |
|  |  - AXI-Lite Control & Status Registers (Resolution, QP, Start, IRQ)       |  |
|  +--------------------------------------^------------------------------------+  |
|                                         | AXI-HP0 (64-bit DMA Bus)              |
|                                         v                                       |
|  +---------------------------------------------------------------------------+  |
|  |  512 MB DDR3 Synchronous DRAM (Shared Frame / Tile Memory Pool)           |  |
|  +--------------------------------------^------------------------------------+  |
|                                         | AXI-Stream via AXI DMA / VDMA         |
|  [ PROGRAMMABLE LOGIC (PL) ]            v                                       |
|  +---------------------------------------------------------------------------+  |
|  |  CUSTOM HARDWARE VIDEO ACCELERATOR PIPELINE                               |  |
|  |                                                                           |  |
|  |  +----------------+    +----------------+    +-------------------------+  |  |
|  |  |   AXI-Stream   |--->|  RGB-to-YUV420 |--->|  Polyphase / Bilinear   |  |  |
|  |  |   Input FIFO   |    | Color Converter|    |   Streaming Scaler      |  |  |
|  |  +----------------+    +----------------+    | (Down to 240p / 144p)   |  |  |
|  |                                              +------------+------------+  |  |
|  |                                                           |               |  |
|  |                                                           v (BRAM Buffers)|  |
|  |  +----------------+    +----------------+    +------------+------------+  |  |
|  |  |  CAVLC Entropy |<---|   QP Scaled    |<---|   4x4 Forward Integer   |  |  |
|  |  |    Encoder     |    |   Quantizer    |    |  Transform (H.264)      |  |  |
|  |  +-------+--------+    +----------------+    +-------------------------+  |  |
|  |          |                                                                |  |
|  |          v                                                                |  |
|  |  +----------------+    +----------------+    +-------------------------+  |  |
|  |  |  NAL Bitstream |--->|   AXI-Stream   |--->|  DMA Return to PS DDR3  |  |  |
|  |  |    Packer      |    |  Output FIFO   |    |  & Ethernet Tx to Host  |  |  |
|  |  +----------------+    +----------------+    +-------------------------+  |  |
|  +---------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------+
```

---

## 3. The Core Optimization: Scaling Before Compression

### 3.1 Mathematical Data Reduction
A critical flaw in naive accelerator proposals is attempting full-resolution transform coding on 8K or 4K pixels before downsizing.

Let input be 8K UHD ($7680 \times 4320 = 33,177,600$ pixels).  
Target resolution is 240p widescreen ($426 \times 240 = 102,240$ pixels).

$$\text{Data Reduction Ratio} = \frac{33,177,600}{102,240} \approx 324.5\times$$

**ENGINEERING INFERENCE**:
By streaming input pixels through a pipelined spatial downscaler first, the compression core (4x4 transform, quantization, CAVLC) processes **$324\times$ fewer pixels**. This allows the complex entropy encoding hardware to easily sustain line-rate performance on the modest XC7Z020 FPGA fabric without stalling.

---

## 4. Codec Trade-Off Analysis & Selection

| Codec | Compression Efficiency | PL Resource Complexity | XC7Z020 Feasibility | Browser Playback Support | Project Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **H.264 Baseline / Intra** | Good (~20-50x) | Medium (~12-20k LUTs) | **Excellent** | **Native HTML5 `<video>`** | **SELECTED** |
| **H.265 / HEVC** | High (+30% vs H.264) | Extreme (>45k LUTs) | Very Low (Too large for Z020) | Partial / Inconsistent | Rejected |
| **AV1** | High | Extreme (>60k LUTs) | Impossible on Z020 | Emerging | Rejected |
| **VVC / H.266** | Maximum | Extreme | Impossible on Z020 | None natively in browsers | Rejected |
| **JPEG XS** | Moderate (~10x) | Low/Medium | Good | Requires custom WASM decoder | Rejected for output |
| **Motion JPEG** | Low (~5-10x) | Very Low | Excellent | High | Insufficient compression |

**PROPOSED DESIGN**: **H.264 Constrained Baseline / Intra-coded architecture with CAVLC**. It provides the optimal balance of FPGA resource fit on the XC7Z020 and instant, zero-dependency browser playback in HTML5 video tags.

---

## 5. Two-Track Architecture Plan

### Track A: Operational Production System (Primary)
- **Host**: Python multi-threaded daemon with OpenCV demuxer, binary packet serializer, and Flask local web server.
- **Hardware Controller**: Hardened Dual ARM Cortex-A9 in Zynq PS.
- **Data Movement**: AXI DMA transferring raw planar YUV frames into PL AXI4-Stream FIFOs.
- **Accelerator**: Verilog RTL implementing Downscaler + 4x4 Integer Transform + Quantizer + CAVLC + NAL encapsulation.

### Track B: Research Contribution (Experimental Soft CPU Integration)
- **Architecture**: A compact RISC-V soft processor (PicoRV32, ~1,500 LUTs) embedded in PL logic.
- **Custom Instruction Extension**:
  - `VCONFIG (imm, rs1)`: Program resolution, stride, and QP parameters.
  - `VBLK (rs1, rs2, rs3)`: Issue hardware block execution command, passing input pointer, output pointer, and quantization offset directly in registers.
  - `VSTATUS (rd)`: Read hardware pipeline performance counters (cycle count, busy status, byte count).
- **Academic Merit**: Quantifiable architectural comparison between standard memory-mapped MMIO register dispatch vs. tightly-coupled custom ISA execution cycles per frame.
