# Real-Time Hardware Video Compression Accelerator with Object Removal on Zynq-7000 SoC

**Department of Electronics and Communication Engineering**  
**Vasavi College of Engineering (Autonomous)**  
**Student**: G. Sai Ram (1602-24-735-163)  
**Target Hardware**: Avnet ZedBoard (AMD / Xilinx Zynq-7000 SoC `xc7z020clg484-1`)

---

## 1. System Architecture Overview

```
                                  ZEDBOARD ZYNQ-7000 SoC
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  PROCESSING SYSTEM (PS): ARM Cortex-A9 @ 667 MHz                                       │
│    - Baremetal / FreeRTOS Firmware in Xilinx Vitis (main.c, dma_driver.c)             │
│    - Background Model Initializer & Frame Buffer Allocator (DDR3 SDRAM - 512 MB)       │
│    - Cache Management: Xil_DCacheFlushRange & Xil_DCacheInvalidateRange                │
│    - AXI4-Lite Control Driver (Threshold, Frame Dimensions, Soft Reset, Status)        │
└──────────────────────────────────────────┬─────────────────────────────────────────────┘
                                           │ AXI HP0 (High Performance 32-bit Memory)
                                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  PROGRAMMABLE LOGIC (PL): FPGA Hardware Acceleration Fabric                            │
│                                                                                        │
│    [AXI DMA MM2S] ───> [AXI4-Stream Video In]                                          │
│                                │                                                       │
│                                ▼                                                       │
│               [STAGE 1: Fixed-Point RGB to Grayscale]                                  │
│                 Y = (77*R + 150*G + 29*B) >> 8  (Zero DSPs)                            │
│                                │                                                       │
│                                ▼                                                       │
│               [STAGE 2: Background Subtraction & Masking]                              │
│                 Diff = |Y_curr - Y_bg|; Mask = (Diff > Threshold)                      │
│                                │                                                       │
│                                ▼                                                       │
│               [STAGE 3: Inpainting / Pixel Replacement]                                │
│                 Y_clean = Mask ? Y_bg : Y_curr (1 pixel / cycle throughput)            │
│                                │                                                       │
│                                ▼                                                       │
│               [STAGE 4: 2D 4x4 H.264 Integer Transform (DCT)]                          │
│                 W = H * X * H^T (Pure Shift-Add Butterfly Architecture)                │
│                                │                                                       │
│                                ▼                                                       │
│               [STAGE 5: Quantization & Level Packing]                                  │
│                 Z = (|W| * M(QP) + f) >> q_bits                                        │
│                                │                                                       │
│                                ▼                                                       │
│    [AXI DMA S2MM] <─── [AXI4-Stream Video Out]                                         │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Complete Directory Structure

```text
mini_project/
├── python/
│   ├── object_removal_golden.py    # Bit-accurate reference model & testbench vector generator
│   ├── process_random_video.py     # Multi-frame video simulator with moving intruder removal
│   └── live_stream_zedboard.py     # Live streaming client with real-time HUD (FPS, PSNR)
├── rtl/
│   ├── object_removal/
│   │   ├── rgb2gray.v              # Pipelined shift-add RGB888 to Y converter (0 DSPs)
│   │   └── bg_subtract_inpaint.v   # Difference detector, threshold mask & inpaint core
│   ├── compression/
│   │   └── dct_4x4.v               # Multiplierless 2D 4x4 H.264 Integer DCT core
│   └── top/
│       └── video_accelerator_top.v # AXI4-Lite + AXI4-Stream ZedBoard top-level IP
├── tb/
│   ├── tb_video_accelerator.v      # Self-checking automated testbench (100% bit-exact match)
│   ├── tb_dct_4x4.v                # Unit testbench for 2D 4x4 H.264 DCT
│   ├── test_vectors/               # Generated hex stimuli (.hex)
│   └── run_sim.bat                 # 1-Click Windows batch test runner (Python + Icarus Verilog)
├── vitis/
│   └── src/
│       ├── main.c                  # ARM Cortex-A9 firmware application & benchmarking
│       ├── xvideo_accel.h          # AXI4-Lite registers & driver prototypes
│       ├── xvideo_accel.c          # AXI4-Lite driver implementation
│       ├── dma_driver.h            # AXI DMA driver header
│       └── dma_driver.c            # AXI DMA simple transfer & cache management
├── vivado/
│   └── bd_zedboard_setup.tcl       # 1-Click automated Vivado Block Design builder
├── docs/
│   ├── COMPLETE_PROJECT_GUIDE_AND_SUMMARY.md # Master roadmap & YouTube tutorial list
│   ├── presentation_slides.md               # 10-slide presentation deck with speaker notes
│   └── project_handover_summary.md          # Project handover and progress log
└── README.md
```

---

## 3. How to Run & Verify

### Step 1: 1-Click Automated Full Suite Test
Double click or run from terminal:
```cmd
tb\run_sim.bat
```
This automatically runs:
1. Python Golden Reference & Test Vector Export
2. Multi-Frame Moving Object Removal Simulator
3. Live Streaming Accelerator Performance Profiler
4. Icarus Verilog 2D 4x4 H.264 Integer DCT RTL Simulation
5. Icarus Verilog Top-Level AXI Video Accelerator (100% Bit-Exact Match)

### Step 2: Individual Python Runs
```powershell
python python/object_removal_golden.py
python python/process_random_video.py
python python/live_stream_zedboard.py
```

### Step 3: 1-Click Vivado Block Design Generation
In Vivado Tcl Console:
```tcl
cd <project_path>/vivado
source bd_zedboard_setup.tcl
```
This automatically configures the Zynq Processing System, AXI DMA, interconnects, and connects the Video Accelerator IP.

### Step 4: Run Vitis ARM Firmware on ZedBoard
1. Export Hardware from Vivado (`.xsa`).
2. Open Vitis, create a new Application Project targeting `xc7z020clg484-1`.
3. Add the files from `vitis/src/` (`main.c`, `xvideo_accel.c`, `dma_driver.c`).
4. Build and Run on ZedBoard!
