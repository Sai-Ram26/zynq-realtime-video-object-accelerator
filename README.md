# Real-Time Hardware Video Compression Accelerator with Object Removal on Zynq-7000 SoC

**Department of Electronics and Communication Engineering**  
**Vasavi College of Engineering (Autonomous), Hyderabad**  
**Student**: G. Sai Ram (Roll No: 1602-24-735-163)  
**Target Hardware**: Avnet ZedBoard (AMD / Xilinx Zynq-7000 SoC `xc7z020clg484-1`)  
**Repository**: [https://github.com/Sai-Ram26/zynq-realtime-video-object-accelerator.git](https://github.com/Sai-Ram26/zynq-realtime-video-object-accelerator.git)

---

## 1. System Architecture Overview

The **High-Efficiency Zynq SoC Real-Time Video Accelerator** provides hardware-accelerated video object detection, real-time spatial inpainting, integer DCT compression, and CAVLC entropy encoding tightly coupled to an ARM Cortex-A9 host processor.

```
       +-------------------------------------------------------+
       |               ARM Cortex-A9 PS Host                   |
       |  - Linux Userspace Device Driver (/dev/mem @ 0x43C00) |
       |  - Custom RISC-V Vector Instruction Dispatch (0x0B)    |
       +---------------------------+---------------------------+
                                   |
                AXI-GP0 Master     |     AXI-ACP Coherent Slave
             (Control Registers)   |      (Direct L2 Cache DMA)
                                   v
+-------------------------------------------------------------------------+
|                  Programmable Logic Accelerator Core (PL)               |
|                                                                         |
| +---------------------------------------------------------------------+ |
| | AXI4-Lite Slave Interface (axi_lite_slave.v @ 0x43C00000)           | |
| +---------------------------------------------------------------------+ |
|                                   |                                     |
|                                   v                                     |
| +---------------------------------------------------------------------+ |
| | Stage 1: Custom RISC-V Vector Decoder (custom_vector_decoder.v)     | |
| |          RGB888 to YUV420 Color Converter (rgb2yuv.v)               | |
| +---------------------------------+-----------------------------------+ |
|                                   |                                     |
|                                   v                                     |
| +---------------------------------------------------------------------+ |
| | Stage 2: Temporal Background Subtraction & Mask Gen (bg_sub.v)      | |
| +---------------------------------+-----------------------------------+ |
|                                   |                                     |
|                                   v                                     |
| +---------------------------------------------------------------------+ |
| | Stage 3: Spatial 8x8 Inpainting Engine (inpainting_8x8.v)           | |
| |          7 Dual-Port BRAM Line Buffers + Neighbor Average Tree      | |
| +---------------------------------+-----------------------------------+ |
|                                   |                                     |
|                                   v                                     |
| +---------------------------------------------------------------------+ |
| | Stage 4: Multiplierless 4x4 Integer DCT & Quant (dct_quant_4x4.v)   | |
| +---------------------------------+-----------------------------------+ |
|                                   |                                     |
|                                   v                                     |
| +---------------------------------------------------------------------+ |
| | Stage 5: CAVLC Entropy Encoder & NAL Serializer (cavlc_encoder.v)   | |
| +---------------------------------+-----------------------------------+ |
|                                   |                                     |
|                                   v                                     |
| +---------------------------------------------------------------------+ |
| | Stage 6: Hardware Performance Monitoring Engine (perf_monitor.v)    | |
| |          Total Cycles, Active Cycles, Stalls, Pixels, Inpaints, NAL | |
| +---------------------------------+-----------------------------------+ |
|                                   |                                     |
|                                   v                                     |
| +---------------------------------------------------------------------+ |
| | Stage 7: AXI Top & ACP Cache Coherency (axi_video_soc_v1_0.v)       | |
| +---------------------------------------------------------------------+ |
+-------------------------------------------------------------------------+
```

---

## 2. Directory Structure

```text
mini_project/
├── rtl/                                # Synthesizable Verilog RTL
│   ├── custom_vector_decoder.v         # Custom RISC-V vector instruction decoder (0x0B)
│   ├── rgb2yuv.v                       # Shift-add RGB888 to YUV420 converter (0 DSPs)
│   ├── bg_sub.v                        # Temporal background subtraction & motion mask
│   ├── inpainting_8x8.v                # 8x8 spatial inpainting engine with 7 BRAM line stores
│   ├── stage1_core_top.v               # Stage 1 integration top
│   ├── stage2_core_top.v               # Stage 2 integration top
│   ├── dct_quant_4x4.v                 # Multiplierless 4x4 integer DCT & quantization
│   ├── cavlc_encoder.v                 # CAVLC entropy encoder & NAL serializer
│   ├── perf_monitor.v                  # 32-bit hardware performance monitoring engine
│   ├── stage3_pipeline_top.v           # Full 5-stage synthesizable data pipeline top
│   ├── stage6_pipeline_top.v           # Stage 6 pipeline top with diagnostic LEDs
│   ├── axi_lite_slave.v                # AXI4-Lite slave register interface (0x43C00000)
│   ├── axi_video_soc_v1_0.v            # Top-level AXI SoC wrapper with ACP coherency
│   ├── object_removal/                 # Modular object removal cores
│   ├── compression/                    # Modular H.264 compression cores
│   └── riscv/                          # RISC-V PicoRV32 accel bridge
├── tb/                                 # Simulation Testbenches & Hex Stimuli
│   ├── run_sim.bat                     # Master 1-click test runner (all 8 stages)
│   ├── tb_stage1_core.sv               # Stage 1 SystemVerilog testbench
│   ├── tb_stage2_core.sv               # Stage 2 SystemVerilog testbench
│   ├── tb_stage3_pipeline.sv           # Stage 3 SystemVerilog testbench
│   ├── tb_stage6_perf.sv               # Stage 6 performance monitor testbench
│   ├── tb_stage7_axi.sv                # Stage 7 AXI & ACP testbench
│   └── test_vectors/                   # Golden test vectors (.hex)
├── sim/                                # Cycle-Exact Verification Harness
│   ├── golden_reference.py             # Cycle-exact Python golden reference model
│   ├── sim_runner.py                   # Automated 15-test verification suite (5 suites)
│   └── synth_analyzer.py               # Post-synthesis resource audit & STA verification
├── sw/                                 # Host Software Drivers
│   ├── zynq_video_driver.c             # C Linux /dev/mem memory-mapped driver
│   └── zynq_video_driver.py            # Python register emulation & PYNQ driver
├── constraints/                        # ZedBoard Physical & Timing Constraints
│   ├── stage5_synth_zedboard.xdc       # 100 MHz timing constraints & I/O delays
│   └── zedboard_physical.xdc           # ZedBoard physical pin mappings (LEDs, SWs, Clock)
├── scripts/                            # Vivado Automation Scripts
│   ├── run_vivado_synth.tcl            # Non-project batch synthesis script
│   └── build_bd.tcl                    # Block design automation for PS7 + ACP
├── dashboard/                          # Interactive Flask Web Dashboard
│   ├── app.py                          # Web application server
│   ├── templates/index.html            # Web UI
│   └── static/css/style.css            # Stylesheet
├── docs/                               # Comprehensive Engineering Reports
│   ├── STAGE1_REPORT.md ... STAGE8_REPORT.md
│   └── zynq_soc_video_accelerator_all_stages.md # Master engineering report
└── README.md
```

---

## 3. All 8 Stages Implementation & Verification Summary

| Stage | Subsystem | Implementation Details | Testbench / Harness | Status |
| :---: | :--- | :--- | :--- | :---: |
| **Stage 1** | Custom Vector Decoder & RGB2YUV | RISC-V custom opcode `0x0B`, funct3 0..4 decoding, shift-add RGB888 $\to$ YUV420 converter. | `tb/tb_stage1_core.sv` | **100% PASS** (3/3) |
| **Stage 2** | Spatial 8x8 Inpainting Engine | 7 dual-port BRAM line stores, 8x8 neighborhood tap window, arithmetic mean neighbor inpainting. | `tb/tb_stage2_core.sv` | **100% PASS** (3/3) |
| **Stage 3** | Full 5-Stage Streaming Pipeline | End-to-end data pipeline: RGB2YUV $\to$ BgSub $\to$ Inpaint $\to$ DCT/Quant $\to$ CAVLC NAL. | `tb/tb_stage3_pipeline.sv` | **100% PASS** (6/6) |
| **Stage 4** | Verification Harness & Golden Model | Cycle-exact golden models (`golden_reference.py`), 15 automated test vectors (`sim_runner.py`). | `sim/sim_runner.py` | **100% PASS** (23/23) |
| **Stage 5** | Synthesis Audit & Timing Constraints | Timing constraints (`stage5_synth_zedboard.xdc`), ZedBoard pinout (`zedboard_physical.xdc`). | `sim/synth_analyzer.py` | **100% PASS** (4/4) |
| **Stage 6** | Hardware Performance Monitoring | 32-bit hardware performance monitoring engine tracking cycles, stalls, pixels, and NAL words. | `tb/tb_stage6_perf.sv` | **100% PASS** (6/6) |
| **Stage 7** | AXI4-Lite & ACP Cache Coherency | AXI4-Lite slave (`0x43C00000`), ACP sidebands (`ARUSER=5'h1F`, `ARCACHE=4'hF`). | `tb/tb_stage7_axi.sv` | **100% PASS** (6/6) |
| **Stage 8** | Software Drivers & Final Sign-Off | Linux `/dev/mem` driver (`zynq_video_driver.c`), Python driver (`zynq_video_driver.py`). | `tb/run_sim.bat` | **100% PASS** (52/52) |

---

## 4. Hardware Resource Utilization & Timing Closure

Target Device: **AMD Xilinx Zynq-7000 APSoC (`xc7z020clg484-1`)** on the Avnet ZedBoard.

```text
========================================================================
   ZYNQ-7000 (xc7z020clg484-1) SYNTHESIS & TIMING AUDIT REPORT
========================================================================
Module / Sub-block         |     LUT |      FF |  BRAM |   DSP
------------------------------------------------------------------------
custom_vector_decoder      |     142 |      86 |     0 |     0
rgb2yuv                    |     418 |     216 |     0 |     0
bg_sub                     |     184 |      72 |     0 |     0
inpainting_8x8             |    1860 |    1120 |     7 |     0
dct_quant_4x4              |    2340 |    1480 |     0 |     0
cavlc_encoder              |    1280 |     890 |     0 |     0
perf_monitor               |     310 |     256 |     0 |     0
axi_lite_slave             |     450 |     340 |     0 |     0
------------------------------------------------------------------------
TOTAL POST-SYNTHESIS       |    6984 |    4460 |     7 |     0
ZYNQ XC7Z020 BUDGET        |   53200 |  106400 |   280 |   220
UTILIZATION %              |  13.13% |   4.19% | 2.50% | 0.00%
========================================================================
```

- **DSP Slices**: **0 DSP48E1** (100% Multiplierless Design Verified)
- **LUT Utilization**: **13.13%** (6,984 / 53,200)
- **Clock Frequency**: **100.0 MHz** ($T = 10.000\text{ ns}$)
- **Worst Negative Slack (WNS)**: **+2.400 ns** (Timing Constraints MET with 24% margin)
- **Worst Hold Slack (WHS)**: **+0.180 ns** (Hold Constraints MET)

---

## 5. Memory Map & Register Offsets (Base `0x43C00000`)

| Offset | Register Name | Access | Description |
| :---: | :--- | :---: | :--- |
| `0x00` | `CR_CONTROL` | R/W | `[0]` Start pulse, `[1]` Soft reset, `[2]` Performance monitor enable |
| `0x04` | `CR_INSTRUCTION` | R/W | 32-bit RISC-V custom vector instruction (Opcode `0x0B`) |
| `0x08` | `CR_RS1_DATA` | R/W | Source frame buffer base address in host DDR memory |
| `0x0C` | `CR_CONFIG` | R/W | `[5:0]` Quantization Parameter (QP), `[15:8]` Motion threshold |
| `0x10` | `CR_PIXEL_IN` | R/W | `[7:0]` R, `[15:8]` G, `[23:16]` B, `[31]` Pixel valid pulse |
| `0x14` | `CR_Y_BG` | R/W | `[7:0]` Background luminance reference value |
| `0x18` | `SR_STATUS` | RO | `[0]` PE busy, `[1]` NAL valid, `[2]` Inpaint active, `[3]` FG mask |
| `0x1C` | `SR_Y_INPAINTED` | RO | `[7:0]` Real-time inpainted luminance output |
| `0x20` | `SR_NAL_WORD` | RO | 32-bit compressed H.264 NAL word |
| `0x24` | `SR_TOT_CYCLES` | RO | Performance Counter: Total elapsed clock cycles |
| `0x28` | `SR_ACT_CYCLES` | RO | Performance Counter: Active processing cycles |
| `0x2C` | `SR_STL_CYCLES` | RO | Performance Counter: Pipeline stall cycles |
| `0x30` | `SR_PIXEL_CNT` | RO | Performance Counter: Processed pixels count |
| `0x34` | `SR_INP_EVENTS` | RO | Performance Counter: Inpainting events count |
| `0x38` | `SR_NAL_CNT` | RO | Performance Counter: Emitted compressed NAL words |

---

## 6. How to Run & Verify

### 1. Run Complete 8-Stage Automated Verification Suite
```cmd
tb\run_sim.bat
```
Executes:
1. Stage 1 RTL testbench (`tb_stage1_core.sv`)
2. Stage 2 RTL testbench (`tb_stage2_core.sv`)
3. Stage 3 RTL testbench (`tb_stage3_pipeline.sv`)
4. Stage 4 Python Golden Reference self-tests (`sim/golden_reference.py`)
5. Stage 4 15-Test comprehensive verification suite (`sim/sim_runner.py`)
6. Stage 5 Synthesis audit & static timing analysis (`sim/synth_analyzer.py`)
7. Stage 6 Hardware performance monitoring testbench (`tb_stage6_perf.sv`)
8. Stage 7 AXI4-Lite & ACP coherency testbench (`tb_stage7_axi.sv`)
9. Stage 8 Python software driver emulation (`sw/zynq_video_driver.py`)

### 2. Launch Interactive Web Dashboard
```powershell
python dashboard/app.py
# Open in browser: http://localhost:5000
```
