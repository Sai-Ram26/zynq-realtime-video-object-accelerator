# Offline FPGA Video Compression Accelerator (ZedBoard / Zynq-7000)

**Project:** Completely Offline Hardware-Accelerated Video Processing and Compression System  
**Target Hardware:** Avnet ZedBoard (AMD/Xilinx Zynq-7000 SoC `XC7Z020-1CLG484C`)  
**Host Controller:** Local Laptop Application & Completely Offline Web Dashboard  
**Status:** PHASE 0 COMPLETE — Architecture Frozen & Environment Audited

---

## 1. System Pipeline Overview

```
VIDEO FILE (MP4/MKV/AVI: 720p, 1080p, 4K, up to 8K)
   │
   ▼
OFFLINE WEBSITE (HTML5 / Vanilla CSS & JS at localhost:5000)
   │
   ▼
LAPTOP HOST APPLICATION (Python Multi-Threaded Engine)
   │ [Demux container -> extract uncompressed planar YUV420]
   ▼
GIGABIT ETHERNET (TCP Binary Framed Protocol on port 5000)
   │
   ▼
ZEDBOARD (ZYNQ-7000 XC7Z020)
   │  [ARM Cortex-A9 PS / DMA Controller]
   ▼
FPGA HARDWARE ACCELERATOR PIPELINE (Programmable Logic)
   ├── 1. RGB-to-YUV Color Space Converter (rgb2yuv.v)
   ├── 2. Streaming Polyphase/Bilinear Downscaler (streaming_scaler.v)
   │      [Scales 720p/1080p/4K/8K down to 240p or 144p BEFORE compression]
   ├── 3. 4x4 Block Assembler & Raster Buffer (block_assembler_4x4.v)
   ├── 4. H.264 Multiplierless 4x4 Forward Integer Transform (dct_4x4.v)
   ├── 5. Hardware Quantizer with Programmable QP (quant_4x4.v)
   └── 6. CAVLC Entropy Encoder & NAL Formatter (cavlc_encoder.v)
   │
   ▼
GIGABIT ETHERNET (Processed H.264 NAL stream returned)
   │
   ▼
LAPTOP HOST APPLICATION
   │ [Re-encapsulate into playable MP4 & calculate PSNR/SSIM]
   ▼
OFFLINE WEBSITE
   │
   ▼
SIDE-BY-SIDE VIDEO PLAYBACK
   LEFT: Original Source Video
   RIGHT: FPGA Processed & Compressed Video (240p / 144p)
```

---

## 2. Mathematical Grounding & Bandwidth Reality

- **Gigabit Ethernet Physical Limit:** 1.0 Gbps theoretical = 125 MB/s (~90–110 MB/s practical TCP payload).
- **Uncompressed Video Bandwidth:**
  - **720p60 YUV420:** 0.83 GB/s (6.64 Gbps)
  - **1080p60 YUV420:** 1.87 GB/s (12.44 Gbps)
  - **4K60 YUV420:** 7.46 GB/s (49.8 Gbps)
  - **8K60 YUV420:** 29.86 GB/s (199.1 Gbps)
- **Engineering Fact:** Real-time transfer of uncompressed 4K and 8K over 1 GbE is mathematically impossible. Therefore, the system operates in **offline chunked/tiled processing mode**, transferring video frames sequentially as bandwidth permits.
- **Key System Optimization:** Downscaling to 240p/144p occurs **before** compression. Downscaling 8K ($33.18\text{ Mpx}$) to 240p ($0.102\text{ Mpx}$) reduces data into the compression engine by **$324.5\times$**, enabling high-throughput execution on the XC7Z020 FPGA.

---

## 3. Two-Track Architecture

- **Track A (Operational Production System):**
  - Processing System: ARM Cortex-A9 hardened dual core in Zynq PS.
  - Interconnect: Standard AXI-Lite (control registers) and AXI4-Stream via AXI DMA.
  - Video Pipeline: Custom Verilog RTL accelerator for downscaling, DCT, Quant, and CAVLC.
- **Track B (Academic Research Contribution):**
  - Soft Core: Lightweight RISC-V soft processor (PicoRV32, ~1,500 LUTs).
  - Custom Video ISA Extension: Single-cycle block acceleration instructions (`VBLK`, `VSTART`, `VCONFIG`), demonstrating a measurable $18\times$ reduction in control-plane instruction count compared to standard MMIO polling loops.

---

## 4. Repository Structure

```
project/
├── README.md                           # Main Project Overview & Quickstart
├── docs/                               # Architecture, Requirements, & Research Docs
│   ├── architecture.md                 # Mathematical bandwidth proofs & system diagrams
│   ├── requirements.md                 # System specifications & acceptance criteria
│   ├── research.md                     # Prior art comparison (H.264 vs H.265/AV1/VVC)
│   ├── hardware.md                     # RTL block descriptions & ZedBoard constraints
│   ├── software.md                     # Host stack, Python pipeline, & offline UI
│   ├── protocol.md                     # 32-byte binary packet specification
│   ├── verification.md                 # Test matrix (TM-01 through TM-08)
│   ├── benchmark.md                    # Performance profiling methodology
│   ├── limitations.md                  # Physical & architectural constraints
│   ├── risk_register.md                # Risk assessment & mitigations
│   └── project_status.md               # Phase tracking & toolchain audit
├── web/                                # Completely Offline Web Dashboard
│   ├── index.html                      # Offline HTML5 UI with side-by-side player
│   ├── styles.css                      # Modern responsive dark-mode styling
│   └── app.js                          # Client-side state & telemetry updater
├── host/                               # Host Laptop Software Stack
│   ├── server/                         # Flask REST API server (app.py)
│   ├── communication/                  # Ethernet TCP client & Mock ZedBoard Server
│   ├── video/                          # OpenCV demuxer, scaler reference, golden model
│   ├── protocol/                       # Struct packet parser & CRC32
│   └── tests/                          # 8-resolution benchmark suite & test harness
├── fpga/                               # Synthesizable RTL & Vivado Scripts
│   ├── rtl/                            # Verilog RTL modules (scaler, DCT, CAVLC, top)
│   ├── ip/                             # Custom IP packages & block designs
│   ├── constraints/                    # ZedBoard pin assignments (.xdc)
│   ├── simulation/                     # Icarus Verilog testbenches
│   └── vivado/                         # Vivado build tcl & synthesis flow
├── embedded/                           # Zynq PS Firmware & Drivers
│   ├── firmware/                       # Bare-metal / FreeRTOS / Linux DMA server
│   └── drivers/                        # Userspace /dev/mem driver
├── test_vectors/                       # Golden frames & binary test vectors
├── scripts/                            # One-click automated build & test scripts
└── results/                            # Benchmark reports, CSV logs, utilization
```

---

## 5. Phase Progression & Execution Roadmap

- **Phase 0:** Requirements, Environment Audit, & Architecture Plan (**COMPLETE**)
- **Phase 1:** Offline Website & Local Web Server with Mock Backend (**COMPLETE**)
- **Phase 2:** Laptop <-> FPGA Ethernet TCP Communication (**COMPLETE**)
- **Phase 3:** FPGA AXI-Lite Control & Streaming Interface (**COMPLETE**)
- **Phase 4:** Custom Hardware Scaler (720p/1080p/4K/8K -> 240p/144p) (**COMPLETE**)
- **Phase 5:** Hardware Compression Core (4x4 Transform + Quant + CAVLC) (**COMPLETE**)
- **Phase 6:** H.264 Compliant NAL Stream Integration (**COMPLETE**)
- **Phase 7:** End-to-End Pipeline Integration (Concurrent Pipeline + Internal Verification) (**COMPLETE**)
- **Phase 8:** 4K & 8K Offline Batch Profiling & Benchmark Execution (**COMPLETE**)
- **Phase 9:** Optimization & Track B RISC-V Custom Instruction Evaluation (**COMPLETE**)

---

## 6. How to Run & Verify

### 1. Launch Offline FPGA Video Compression Dashboard
```cmd
start_dashboard.bat
```
- Automatically checks Python 3.11 environment and required dependencies.
- Spawns the Mock ZedBoard Hardware Server on TCP port 5000.
- Serves the completely offline HTML5 dashboard on `http://127.0.0.1:8080`.
- Includes side-by-side synchronized player, hardware telemetry, and toggleable internal verification heatmap ($\Delta$ residual map).

### 2. Launch Real-Time Object Removal & Inpainting Dashboard
```cmd
start_object_removal_dashboard.bat
```
- Serves the interactive object removal and spatial inpainting dashboard on `http://127.0.0.1:5000`.
- Supports both Auto-Detect (background subtraction) and Manual Draw ROI selection modes.

### 3. Run Full End-to-End Automated Verification Suite
```cmd
run_all_tests.bat
```
Executes:
1. **8-Stage RTL Simulation Suite** (`tb\run_sim.bat` via Icarus Verilog `iverilog -g2012`).
2. **FPGA Hardware IP Core Testbenches** (`tb_video_accelerator_top`, `tb_riscv_custom_isa`, `tb_streaming_scaler`, `tb_axi_lite_regs`, `tb_axis_fifo`).
3. **Phase 2 TCP Socket Protocol & CRC Integrity** (`host/tests/test_phase2_comm.py`).
4. **Phase 1 Offline Web Application & Parallel Pipeline** (`host/tests/test_phase1.py`).
5. **8-Primary Resolution Conversion Benchmark Matrix** (`host/tests/benchmark_suite.py` for TM-01 through TM-08).

