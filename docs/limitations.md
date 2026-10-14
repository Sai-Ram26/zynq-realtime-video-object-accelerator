# System Limitations & Engineering Constraints

**Document Purpose:** Explicit disclosure of physical, architectural, and toolchain boundaries.  
**Philosophy:** No fabrication; all claims must be mathematically and experimentally defensible.

---

## 1. Physical Hardware & Interface Limitations

### 1.1 Gigabit Ethernet Bandwidth Bottleneck
- **FACT**: The ZedBoard features a 10/100/1000 Mbps Ethernet interface (Marvell 88E1510 PHY).
- **CONSEQUENCE**: Theoretical maximum uncompressed throughput is 125 MB/s (~100 MB/s under practical TCP stack overhead).
- **LIMITATION**: Real-time transmission of uncompressed 4K60 (~746 MB/s) or 8K60 (~2.99 GB/s) is physically impossible over this link.
- **SYSTEM RESOLUTION**: All 4K and 8K workflows operate in **offline chunked processing mode**. The system does NOT claim real-time 8K performance.

### 1.2 On-Chip FPGA Fabric Limits (XC7Z020)
- **FACT**: The XC7Z020 provides 53,200 LUTs, 106,400 FFs, 140 36Kb Block RAMs, and 220 DSP48E1 slices.
- **CONSEQUENCE**: Full modern video codecs (such as complete H.265 Main Profile with 35 intra modes + CABAC + motion estimation, or AV1) require >60k-100k LUTs and multi-gigabyte memory bandwidth, which exceeds the XC7Z020 capacity.
- **LIMITATION**: The FPGA accelerator implements **Constrained H.264 Baseline Intra-Coding (4x4 Integer Transform, Quantization, CAVLC)**. It does not implement Inter-Frame Motion Estimation in the first prototype.

### 1.3 Memory Architecture
- **FACT**: The ZedBoard contains 512 MB DDR3 memory with a peak bandwidth of ~4.26 GB/s.
- **LIMITATION**: While 512 MB is sufficient for multi-frame buffering at 1080p and tiled 4K/8K chunks, line-buffer architecture in on-chip BRAM is strictly required to avoid memory bus saturation during high-throughput downscaling.

---

## 2. Browser & Environment Boundaries

### 2.1 Browser Network Sandbox
- **FACT**: W3C standards strictly prohibit client-side web browsers from opening raw TCP/UDP sockets to external IP addresses.
- **CONSEQUENCE**: A web browser cannot communicate directly with the ZedBoard PHY.
- **SYSTEM RESOLUTION**: A local Python backend daemon runs on `localhost:5000`, mediating between HTTP/WebSocket from the browser and TCP over Ethernet to the ZedBoard.

### 2.2 Host Video Parsing Boundary
- **FACT**: Video container formats (MP4, MKV) contain intricate metadata, moov atoms, track headers, and variable-length packet descriptors.
- **LIMITATION**: Implementing a full MP4 demuxer in Verilog RTL would waste thousands of LUTs without adding research value.
- **SYSTEM RESOLUTION**: The host laptop decodes input MP4 containers into uncompressed planar YUV frames; the FPGA performs the computationally heavy spatial downscaling, 4x4 transform, quantization, and entropy encoding.
