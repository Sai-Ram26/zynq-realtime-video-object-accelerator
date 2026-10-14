# System Requirements Specification: Offline FPGA Video Compression Accelerator

**Document Version:** 1.0.0  
**Target Hardware:** Avnet ZedBoard (AMD/Xilinx Zynq-7000 XC7Z020-1CLG484C)  
**Host Environment:** Windows Laptop (Completely Offline Operation)

---

## 1. Functional Requirements

### 1.1 Video Ingestion & Formatting
- **REQ-F1 (FACT)**: The system shall accept video container files (MP4, MKV, AVI) via local file selection in the offline browser dashboard.
- **REQ-F2 (ENGINEERING INFERENCE)**: The host laptop application shall perform container demuxing and decoding using OpenCV/FFmpeg into raw uncompressed planar video frames (YUV 4:2:0 / YUV 4:4:4). The FPGA does not decode arbitrary complex container formats.
- **REQ-F3 (FACT)**: Supported input resolutions:
  - 720p (1280×720)
  - 1080p (1920×1080)
  - 4K UHD (3840×2160)
  - 8K UHD (7680×4320)
- **REQ-F4 (FACT)**: Supported target output resolutions:
  - 240p (426×240 for 16:9 widescreen, or 320×240 for 4:3)
  - 144p (256×144 for 16:9 widescreen)

### 1.2 FPGA Hardware Acceleration Pipeline
- **REQ-F5 (PROPOSED DESIGN)**: The FPGA programmable logic (PL) shall implement the primary computational workload:
  1. **Color Space Conversion**: Fixed-point RGB to YUV (or chroma subsampling).
  2. **Streaming Scaler**: Bilinear / polyphase spatial downsampling from input dimension to 240p or 144p.
  3. **Block Segmentation**: Formation of 4×4 luminance and chrominance blocks.
  4. **Integer Transform**: Standard H.264 4×4 forward integer Discrete Cosine Transform (DCT) approximation:
     $$W = H \cdot X \cdot H^T$$
  5. **Quantization**: Programmable QP (0 to 51) hardware quantizer.
  6. **Entropy Coding**: Context-Adaptive Variable-Length Coding (CAVLC) generating compliant bitstream tokens.
  7. **Bitstream Packing**: Output NAL unit formatting (SPS, PPS, Slice Header, Slice Data).

### 1.3 Communication & Transport
- **REQ-F6 (FACT)**: Communication between the laptop and the ZedBoard shall use Gigabit Ethernet over TCP/IP.
- **REQ-F7 (PROPOSED DESIGN)**: A framed binary protocol shall encapsulate commands, configuration registers, video metadata, frame payload chunks, and status responses (`docs/protocol.md`).
- **REQ-F8 (ENGINEERING INFERENCE)**: 8K video processing shall be handled in offline tile/frame chunks to conform with the physical 1 GbE transfer limit (~125 MB/s theoretical, ~90-110 MB/s practical).

### 1.4 Web Dashboard & User Experience
- **REQ-F9 (FACT)**: The user interface shall be a completely offline web application running on `localhost:5000`.
- **REQ-F10 (FACT)**: No cloud services, external CDN dependencies, or AI/ML inference libraries shall be used.
- **REQ-F11 (PROPOSED DESIGN)**: The UI shall present:
  - File picker displaying filename, source resolution, duration, and file size.
  - Target resolution selector (`240p`, `144p`).
  - Processing controls (`START`, `PAUSE/CANCEL`).
  - Real-time hardware status indicators: FPGA Connection (`CONNECTED`/`DISCONNECTED`), Ethernet link status, transfer throughput (MB/s), processing FPS, latency, and hardware utilization.
  - Side-by-side synchronized video players:
    - **LEFT**: Original uploaded video.
    - **RIGHT**: FPGA-processed & compressed video.
  - Objective quality comparison: PSNR (dB), SSIM, compression ratio, file size reduction, and processing duration.
  - Download button for the output video.

---

## 2. Non-Functional & Architecture Constraints

### 2.1 Hardware Resource Budget (XC7Z020)
| Resource | Available on XC7Z020 | Target Acceleration Budget | Status |
| :--- | :--- | :--- | :--- |
| **Logic Cells** | 85,000 | < 45,000 | Feasible |
| **LUTs** | 53,200 | < 30,000 | Feasible |
| **Flip-Flops (FF)** | 106,400 | < 40,000 | Feasible |
| **DSP48E1 Slices** | 220 | < 40 (utilized pragmatically) | Feasible |
| **Block RAM (BRAM36)**| 140 (4.9 Mb) | < 80 | Feasible |
| **DDR3 Memory** | 512 MB | Frame Buffers / DMA rings | Feasible |

### 2.2 Security & Offline Integrity
- **REQ-NF1**: HTTP services bind exclusively to `127.0.0.1` (localhost).
- **REQ-NF2**: Strict input sanitization on uploaded video containers and packet boundaries to prevent buffer overflows or malformed memory writes.
- **REQ-NF3**: Checksums (CRC32/Adler32) over packet payloads for link integrity validation.
