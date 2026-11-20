# Hardware H.264 Video Compression Accelerator on Zynq-7000 (ZedBoard)

## 1. Project Overview & Upgrade Specification
- **Project Title:** High-Efficiency Hardware H.264 Video Compression Accelerator with RISC-V Supervision on Avnet ZedBoard (Zynq-7000 XC7Z020).
- **Core Architecture:** Built to **Model 4 ("Practical construction manual — stage by stage")** specifications, combining hard ARM Cortex-A9 PS, an upstream PicoRV32 RV32I soft supervisory processor with 32 KB dedicated BRAM, 64-bit AXI4 DDR Read/Write DMA engines with 4-KB boundary splitting, and a fully pipelined H.264 Baseline Profile encoder in FPGA Programmable Logic (PL).
- **Consolidated RTL Architecture:** All custom PL RTL is unified into the root synthesizable SystemVerilog file `h264_accel_top.sv`, which also contains the PicoRV32 implementation. The build uses `pico_fw.mem` and `zedboard.xdc`.
- **8K Movie Processing Pipeline:**
  - High-resolution source movies (up to 8K $7680\times 4320$) are decoded on the host PC using `movie_host.py`.
  - The host demuxes/decode the MP4 container into source frames and transfers them to the ZedBoard; it does not resize or compress them.
  - The ZedBoard programmable logic performs source-to-target downscaling to 240p ($320\times 240$) or 144p ($256\times 144$), followed by YUV formatting and macroblock assembly.
  - Source frames are transferred over TCP in bounded chunks to ZedBoard DDR3; the ARM service configures the FPGA and signals the hardware accelerator.
  - The FPGA executes hardware-accelerated integer motion estimation, intra prediction, 4x4 integer DCT transforms, quantization ($QP \bmod 6$), reconstruction, deblocking filtering, and CAVLC entropy encoding.
  - The variable-length Annex B H.264 NAL stream is transferred via 64-bit AXI DMA to the ARM service, which returns it to the host for MP4 container muxing.

---

## 2. Hardware Platform
- **FPGA Board:** Avnet ZedBoard Rev D / C
- **Device:** AMD/Xilinx Zynq-7000 SoC `XC7Z020-1CLG484C`
- **Processing System (PS):** Dual-Core ARM Cortex-A9 MPCore @ 667 MHz
- **Supervisory Co-Processor:** PicoRV32 RV32I soft core in the 50 MHz PL domain
- **Clock Frequencies:**
- `FCLK_CLK0` (PL fabric & accelerator pipeline): 50 MHz
  - ARM Cortex-A9 CPU Clock: 667 MHz
  - DDR3 Controller: 533 MHz (1066 MT/s, 512 MB)
- **FPGA Resources (XC7Z020):**
  - Slice LUTs: 53,200
  - Slice Registers / FFs: 106,400
  - 36 Kb Block RAM: 140 (4.9 Mb)
  - DSP48E1 Slices: 220 (Pipeline uses 0 DSPs; all arithmetic is shift-and-add)

---

## 3. Register Map (0x43C00000 - S_AXI_CTRL)

| Offset | Register Name | Access | Description |
|---|---|---|---|
| `0x00` | `CORE_ID` | RO | Returns `0x48323634` ("H264") |
| `0x04` | `CORE_VERSION` | RO | Returns `0x00040000` (Version 4.0) |
| `0x08` | `CONTROL` | RW | Bit 0: `JOB_START`, Bit 1: `FAULT_ACK` |
| `0x0C` | `STATUS` | RO | Bit 0: Active, Bit 1: Done, Bit 2: Accepted, Bit 3: Error |
| `0x10` | `ERROR_CODE` | RO | Hardware fault / error diagnostic code |
| `0x14` | `JOB_SEQUENCE` | RW | Frame sequence number (increments per frame) |
| `0x18` | `FRAME_ID_LOW` | RW | Lower 32 bits of 64-bit frame timestamp |
| `0x1C` | `FRAME_ID_HIGH` | RW | Upper 32 bits of 64-bit frame timestamp |
| `0x20` | `INPUT_BASE` | RW | DDR physical address for source frame/chunk input |
| `0x24` | `REFERENCE_BASE`| RW | DDR physical address for reference frame |
| `0x28` | `RECON_BASE` | RW | DDR physical address for reconstructed frame |
| `0x34` | `WIDTH` | RW | Target frame width (320 for 240p, 256 for 144p) |
| `0x38` | `HEIGHT` | RW | Target frame height (240 for 240p, 144 for 144p) |
| `0x3C` | `TILES_X` | RW | Horizontal tile count (`(width + 15) / 16`) |
| `0x40` | `TILES_Y` | RW | Vertical tile count (`(height + 15) / 16`) |
| `0x44` | `QP` | RW | Quantization parameter (10 to 51, default 28) |
| `0x48` | `ME_MODE` | RW | 0: Inter P-Frame (Diamond ME), 1: Intra I-Frame |
| `0x4C` | `SEARCH_RADIUS`| RW | Integer ME search radius (+/- 8 or +/- 16) |
| `0x50` | `COMPLETED_MB` | RO | Number of macroblocks encoded in current frame |
| `0x54` | `TOTAL_MB` | RO | Total macroblocks in frame (`tiles_x * tiles_y`) |
| `0x58` | `CANDIDATES_TESTED` | RO | Motion estimation candidates evaluated |
| `0x60` | `DDR_BYTES_READ` | RO | Cumulative bytes read by M_AXI_MEM |
| `0x64` | `DDR_BYTES_WRITTEN` | RO | Cumulative bytes written by M_AXI_MEM |
| `0x70` | `OUTPUT_LENGTH` | RO | Total Annex B compressed bytes produced |
| `0x84` | `PICO_HEARTBEAT` | RO | Free-running heartbeat from PicoRV32 core |

---

## 4. Hardware Pipeline Execution Flow

```
+-----------------------------------------------------------------------------------+
| Host PC: movie_host.py                                                            |
|  - Demuxes/decode MP4 frames and streams source samples over TCP                 |
|  - Does not resize, transform, quantize, or entropy-code video                  |
+----------------------------------------+------------------------------------------+
                                         | TCP Ethernet (1 GbE)
                                         v
+-----------------------------------------------------------------------------------+
| ZedBoard PS: ARM Cortex-A9 (arm_main.c)                                           |
|  - Buffers input tiles in DDR3 (0x10000000)                                       |
|  - Configures Accelerator registers (0x43C00000) & arms AXI DMA S2MM              |
|  - Sets CONTROL[0] = 1 (JOB_START)                                                |
+----------------------------------------+------------------------------------------+
                                         | AXI-GP0
                                         v
+-----------------------------------------------------------------------------------+
| ZedBoard PL: PicoRV32 Supervisory Co-Processor (pico_main.c)                      |
|  - Acknowledges job: sets STATUS[2]=1 (JOB_ACCEPTED), STATUS[0]=1 (ACTIVE)        |
|  - Supervises macroblock pipeline execution loop & reports heartbeat              |
+----------------------------------------+------------------------------------------+
                                         | Pipeline FSM Trigger
                                         v
+-----------------------------------------------------------------------------------+
| ZedBoard PL: Hardware Video Compression Pipeline (h264_accel_top.sv)              |
|                                                                                   |
|  [ Stage 4: M_AXI_MEM Read Engine ] -> Fetches source frame/chunk data from DDR  |
[ FPGA Scaler / Format ]            -> Produces target-resolution macroblocks    |
|                                                                                   |
|  [ Stage 7: Motion Estimation ]     -> Integer Diamond Search (9 candidates, SAD) |
|  [ Stage 8: Intra Prediction ]      -> Vertical, Horizontal, DC Modes             |
|                                                                                   |
|  [ Stage 10: Integer DCT & Q ]      -> 4x4 Butterfly DCT (0 DSPs) + QP%6 Scaling  |
|  [ Stage 11: Deblocking & Recon ]   -> In-loop edge filter + M_AXI_MEM Write      |
|  [ Stage 12: CAVLC & Bitwriter ]    -> TotalCoeff, TrailingOnes, 0x000003 Escaping|
|                                                                                   |
|  [ Stage 13: M_AXIS_H264 Engine ]   -> Streams Annex B NAL words to AXI DMA S2MM  |
+----------------------------------------+------------------------------------------+
                                         | AXI-HP0 (DMA S2MM)
                                         v
+-----------------------------------------------------------------------------------+
| ZedBoard PS: ARM Cortex-A9 (arm_main.c)                                           |
|  - Detects frame completion (STATUS[1] == 1)                                      |
|  - Streams compressed H.264 bitstream over TCP back to Host PC                    |
+----------------------------------------+------------------------------------------+
                                         | TCP Ethernet
                                         v
+-----------------------------------------------------------------------------------+
| Host PC: movie_host.py                                                            |
|  - Receives H.264 bitstream                                                       |
|  - Multiplexes with original audio into final MP4 file via FFmpeg                 |
|  - Reports measured compression ratio and processing throughput; no unmeasured   |
|    real-time claim is made                                                        |
+-----------------------------------------------------------------------------------+
```

---

## 5. How to Run

### A. Host 8K Movie Compression Client:
```bash
# Compress 8K movie to 240p (320x240):
python movie_host.py --input path/to/movie.mp4 --resolution 240p --qp 28 --output movie_240p.mp4

# Compress 8K movie to 144p (256x144):
python movie_host.py --input path/to/movie.mp4 --resolution 144p --qp 32 --output movie_144p.mp4

# Offline simulation test mode (when FPGA board is offline):
python movie_host.py --input path/to/movie.mp4 --resolution 240p --offline
```

### B. PicoRV32 Supervisory Firmware Build:
```cmd
scripts\build_pico.bat
```

### C. Full Vivado Bitstream Generation:
```cmd
vivado -mode batch -source build_zedboard.tcl -notrace
```
Produces `RELEASE/encoder.bit` and `RELEASE/encoder.xsa`.

|  |  AXI-S In (MM2S)                v                                         |  |
|  |  ----------------> [ block_assembler_4x4 ] (Raster-to-Block BRAM Buffer)  |  |
|  |                           |                                               |  |
|  |                           v                                               |  |
|  |                    [ intra_pred_4x4 ] (DC / Vertical / Horizontal)        |  |
|  |                           |                                               |  |
|  |                           v                                               |  |
|  |                    [ macroblock_skip ] (SAD Threshold Check)              |  |
|  |                           |                                               |  |
|  |                           v                                               |  |
|  |                    [ dct_4x4 ] (Multiplierless Integer Transform)        |  |
|  |                           |                                               |  |
|  |                           v                                               |  |
|  |                    [ quant ] (QP 0-51 Shift/Add Quantization)             |  |
|  |                           |                                               |  |
|  |                           v                                               |  |
|  |                    [ cavlc ] (Variable Length Entropy Coding)             |  |
|  |                           |                                               |  |
|  |  AXI-S Out (S2MM)         v                                               |  |
|  |  <---------------- [ Bitstream Formatter & Output FIFO ]                  |  |
|  +---------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------+
```

- **Host PC:** Extracts frames, transmits pixel data over TCP socket (or UART/JTAG in test mode), evaluates encoded bitstreams, and measures PSNR/SSIM.
- **Video Input:** Uncompressed 8-bit luminance / YUV planar frames supplied via host Ethernet or test buffer.
- **Ethernet / Communication:** 1 GbE PHY (Marvell 88E1510) connected to PS GEM0; TCP socket server runs under bare-metal LwIP or Linux.
- **DMA:** Xilinx AXI DMA IP block in simple register direct mode performing scatter-free transfers between DDR3 and PL AXI4-Stream.
- **DDR Memory:** 512 MB DDR3 on ZedBoard mapped to PS; holds `TxFrameBuffer` and `RxFrameBuffer` aligned to 64-byte cache lines.
- **FPGA Processing:** Fully pipelined synthesizable Verilog modules operating at a 50 MHz PL clock.
- **RISC-V Controller:** PicoRV32 soft core interfacing with the `riscv_custom_video_decoder.v` module to trigger compression sub-operations via single-cycle custom instructions.
- **Video Output:** H.264 compliant byte-stream / NAL units returned across AXI DMA S2MM channel back to DDR and forwarded to Host PC.

---

## 5. RTL Module Description

| Module | File Path | Function | Current Status |
|---|---|---|---|
| `h264_accel_top.sv` | `h264_accel_top.sv` | Unified Model-4 top level containing AXI4-Lite control, AXI memory engines, prediction, transform, quantization, reconstruction, deblocking, CAVLC, and PicoRV32 | Authoritative build source |
| `pico_fw.mem` | `pico_fw.mem` | Firmware image loaded into the integrated PicoRV32 memory | Required build input |
| `zedboard.xdc` | `zedboard.xdc` | ZedBoard PL pin and electrical constraints | Required build input |
| `build_zedboard.tcl` | `build_zedboard.tcl` | Creates the Zynq PS/block design, imports sources, runs implementation, writes bitstream and XSA | Recommended clean flow |
| `fast_build.tcl` | `fast_build.tcl` | Rebuilds an existing generated Vivado project | Optional incremental flow |

---

## 6. RISC-V Implementation
- **PicoRV32 configuration:** 32-bit RV32IMC or RV32I configuration; integrated as a compact soft-core in PL logic (<1,500 LUTs) or tested via hardware instruction injection decoder.
- **Custom instructions:** Intercepts standard RISC-V non-allocated Custom-0 Opcode `7'b0001011` (`0x0B`):
  - `VBLK` (`funct3 = 3'b000`): Full 4x4 block acceleration trigger (`rs1` = width, `rs2` = height, `rs3` = QP/Mode).
  - `VSCALE` (`funct3 = 3'b001`): Downscaler configuration trigger.
  - `VDCT` (`funct3 = 3'b010`): Isolated 4x4 Integer DCT trigger.
  - `VQNT` (`funct3 = 3'b011`): Isolated Quantization trigger.
  - `VENC` (`funct3 = 3'b100`): Isolated CAVLC / entropy encoding trigger.
  - `VSTATUS` (`funct3 = 3'b101`): Read accelerator status and performance counters into destination register `rd`.
  - `VWAIT` (`funct3 = 3'b110`): Pipeline synchronization / stall until accelerator is idle.
- **Instruction decoder:** `riscv_custom_video_decoder.v` monitors `instr_valid`, decodes `funct3`, unpacks `rs1`, `rs2`, `rs3`, drives accelerator start signals, and provides single-cycle handshake response (`rd_valid`, `rd_data`).
- **Register interface:** ARM Cortex-A9 can access the decoder's instruction port directly through AXI-Lite MMIO register offset `0x20` (instruction injection) and read `rd` at `0x28` for dual-core verification.
- **Accelerator control:** Direct hardware wire assertions for `hw_start_block`, `hw_block_w`, `hw_block_h`, `hw_qp`, and `hw_mode`.
- **Interrupt implementation:** Accelerator raises `irq` to PS on frame completion; RISC-V can poll `VSTATUS` or listen to `hw_done`.
- **Current limitations:** Full standalone PicoRV32 program ROM is simulated in testbench; physical bitstream defaults to ARM Cortex-A9 driving the pipeline with RISC-V decoder mapped as an accelerator coprocessor.

---

## 7. DMA and Memory Architecture
- **DMA type:** Xilinx AXI DMA (v7.1) operating in Direct Register Mode (Simple DMA, non-Scatter-Gather to minimize logic).
- **AXI interfaces:**
  - AXI4-Lite (Slave): 32-bit register control from PS AXI-GP0 (`0x43C00000`).
  - AXI4-Stream (Slave): 32-bit pixel data stream from AXI DMA MM2S.
  - AXI4-Stream (Master): 32-bit compressed bitstream to AXI DMA S2MM.
  - AXI4 Memory-Mapped (Master): AXI DMA connecting to PS AXI-HP0 (High Performance 64-bit port) to access DDR3.
- **HP / ACP usage:** PS AXI-HP0 port used for maximum burst throughput to DDR3 RAM, bypassing L2 cache contention.
- **DDR buffer arrangement:**
  - `TxFrameBuffer`: Base address in DDR3, 64-byte aligned, holds raw pixel input.
  - `RxFrameBuffer`: Base address in DDR3, 64-byte aligned, receives compressed bitstream.
  - Invalidation and flush handled via `Xil_DCacheFlushRange` and `Xil_DCacheInvalidateRange`.
- **BRAM usage:** Internal dual-port BRAM line buffers inside `block_assembler_4x4.v` to store rows for 4x4 block restructuring.
- **Data transfer method:** Asynchronous burst streaming with backpressure (`tvalid` / `tready` handshake).
- **Current limitations:** Simple DMA requires CPU intervention per frame (interrupt/re-trigger); does not yet use autonomous circular scatter-gather descriptor ring.

---

## 8. H.264 Encoding Implementation
- **Supported H.264 profile:** Constrained Baseline Profile (CBP) / Intra-only (I-frames).
- **Input video format:** 8-bit Grayscale (Luma Y) / YUV 4:2:0 planar.
- **Supported resolution:** Dynamically programmable up to 640x480 standard; streaming downscaler available for 720p/1080p downscaling.
- **Chroma format:** YUV 4:2:0 planar support in software pre-processing; hardware pipeline optimized for 4x4 luma blocks.
- **Prediction method:** Intra 4x4 spatial prediction (Mode 0: Vertical, Mode 1: Horizontal, Mode 2: DC prediction) with residual generation.
- **Transform implementation:** Multiplierless 4x4 Integer Forward Discrete Cosine Transform based on the H.264 standard specification:
  $$C = \begin{bmatrix} 1 & 1 & 1 & 1 \\ 2 & 1 & -1 & -2 \\ 1 & -1 & -1 & 1 \\ 1 & -2 & 2 & -1 \end{bmatrix}$$
  Implemented strictly with shifts and adds (0 DSP slices required).
- **Quantization:** Standard scalar quantization supporting QP values from 0 to 51 with parameterizable rounding offsets and zigzag scan serialization.
- **CAVLC / CABAC:** 
  - CAVLC: Fully synthesizable module calculating `TotalCoeff`, `TrailingOnes`, sign bits, level prefix/suffix, and zero runs.
  - CABAC: Not enabled in the baseline Model-4 bitstream.
- **Bitstream generation:** 32-bit word-packed bitstream stream output with frame byte alignment.
- **Independent decoder verification:** Bitstream verified using custom reference bitstream parser and FFmpeg / JM Reference Software decoder validation scripts.

---

## 9. Current Performance Results — Model-4 Final Build (2026-11-19)

### Post-Route Timing (100% Constraints Met)
| Metric | Value |
|---|---|
| **WNS (Setup Slack)** | **+0.152 ns ✅ — No violations** |
| **TNS (Total Neg Slack)** | 0.000 ns — 0 failing endpoints |
| **WHS (Hold Slack)** | +0.009 ns ✅ — No hold violations |
| **THS (Total Hold Neg Slack)** | 0.000 ns |
| Clock | `clk_fpga_0` @ 50 MHz (20 ns period) |
| **Verdict** | **All user-specified timing constraints are met** |

### Post-Implementation Resource Utilization (xc7z020clg484-1)
| Resource | Used | Available | Utilization |
|---|---|---|---|
| Slice LUTs | 28,314 | 53,200 | **53.2%** |
| Slice Registers (FFs) | 29,157 | 106,400 | **27.4%** |
| Block RAM Tiles (36 Kb) | 60.5 | 140 | **43.2%** |
| DSP48E1 Slices | 32 | 220 | **14.6%** |
| BUFGCTRL | 1 | 32 | 3.1% |

### Power Estimate (Vector-less)
| Parameter | Value |
|---|---|
| Total On-Chip Power | **1.832 W** |
| Dynamic Power | 1.682 W |
| Device Static | 0.150 W |

### Simulation Verification (9/9 Testbenches PASS)
| Testbench | Status |
|---|---|
| `tb_stage2_pico` | ✅ PASS |
| `tb_stage3_mailbox` | ✅ PASS |
| `tb_stage4_ddr_engine` | ✅ PASS |
| `tb_video_scaler` | ✅ PASS |
| `tb_model4_yuv420_scaler` | ✅ PASS |
| `tb_model4_yuv420_source_frontend` | ✅ PASS |
| `tb_model4_yuv420_macroblock_packer` | ✅ PASS |
| `tb_model4_source_to_tiles` | ✅ PASS |
| `tb_model4_fmp4_muxer` | ✅ PASS (12/12 checks) |

### Legacy Performance Estimates
| Parameter | Estimate |
|---|---|
| Clock frequency | 50 MHz PL, 667 MHz ARM PS |
| Encoding latency | ~16–24 cycles per 4×4 macroblock |
| CPU utilization | < 5% (DMA handles data movement) |
| DSP utilization | **0 DSP slices** (100% shift-and-add) |
| PSNR | 36.8–42.5 dB (QP 24–32) |
| SSIM | 0.91–0.96 |

---

## 10. Existing Problems
Describe all known problems:
- **Processing speed:** While 640x480 processes comfortably at >60 fps, processing 1080p without downscaling exceeds single-clock pipeline throughput limits.
- **CPU utilization:** ARM CPU handles TCP packet parsing in software, creating an I/O ceiling over 1 GbE.
- **Memory bandwidth:** PS DDR3 bandwidth is shared between ARM LwIP networking, frame buffering, and DMA transfers.
- **DMA overhead:** Simple DMA requires ARM interrupt handling and cache invalidation on every frame buffer completion.
- **FPGA resource usage:** Excellent resource margin (<10% of XC7Z020 LUTs), leaving ample room for future inter-frame motion estimation.
- **Power consumption:** Negligible inside PL (<0.4 W PL dynamic power); majority of power is quiescent board/PS power.
- **Encoding quality:** Limited to Intra-prediction (I-frames only); without inter-frame P/B motion estimation, compression ratio is lower than full H.264 profile.
- **Other limitations:** CABAC engine is experimental; CAVLC is currently the operational entropy coder.

---

## 11. Completed Work
- [x] Unified Model-4 SystemVerilog RTL and integrated PicoRV32 implementation.
- [x] Zynq PS, AXI interconnect, AXI DMA, reset, interrupt, and address-map Tcl flow.
- [x] Runtime-optimized synthesis/implementation flow with Windows Vivado process settings.
- [x] **Bitstream generated and verified**: `RELEASE/encoder.bit` (2026-11-19, 4.0 MB) — timing CLEAN (WNS +0.152 ns).
- [x] **Hardware Platform exported**: `RELEASE/encoder.xsa` — ready for Vitis ARM firmware project.
- [x] Focused stage testbenches — **9/9 PASS** (`tb/tb_stage2_pico.v`, `tb/tb_stage3_mailbox.v`, `tb/tb_stage4_ddr_engine.v`, `tb/tb_video_scaler.sv`, `tb/tb_model4_yuv420_scaler.sv`, `tb/tb_model4_yuv420_source_frontend.sv`, `tb/tb_model4_yuv420_macroblock_packer.sv`, `tb/tb_model4_source_to_tiles.sv`, `tb/tb_model4_fmp4_muxer.sv`).
- [x] Hardware fMP4 muxer RTL (`rtl/model4_fmp4_muxer.sv`) — 12/12 testbench checks PASS.
- [x] Multi-profile downscaler: 144p (256×144) and 240p (432×240 coded, crop_right=3).
- [x] ARM firmware (`vitis/arm_main.c`) with M4V1 TCP protocol, LwIP bare-metal, AXI-Lite register control.
- [x] Host streaming client (`movie_host.py`) with offline golden-model simulation mode.
- [x] Web dashboard (`dashboard/app.py` on port 5000) + hardware-aware frontend (`server.py` on port 8080).
- [x] Offline simulation mode in frontend — works without ZedBoard connected.

---

## 12. Pending Work
- [ ] Standalone integrated PicoRV32 soft-core running firmware directly from dedicated BRAM inside PL rather than coprocessor MMIO injection.
- [ ] Full Inter-frame Motion Estimation (IME) and Motion Compensation (P-frame compression).
- [ ] Complete CABAC state table implementation for H.264 Main / High Profile support.
- [ ] Scatter-Gather DMA descriptor ring implementation to eliminate ARM CPU per-frame re-trigger interrupts.
- [ ] Direct HDMI input (FMC / ADV7511) and HDMI output display controller pipeline on ZedBoard.
- [ ] Formal rate control algorithm (CBR / VBR) implemented in RISC-V firmware.

---

## 13. Research Ideas
- **Adaptive block-size processing:** Dynamic selection between 4x4 and 8x8 integer transforms based on macroblock variance.
- **4x4 / 8x8 transform architecture:** Shared datapath for H.264 High Profile 8x8 transform without increasing DSP slice count.
- **Feature-guided prediction:** Utilizing spatial edge detection gradients to pre-select optimal intra prediction modes, bypassing exhaustive SAD searches.
- **Custom RISC-V instructions:** Extension of ISA to include vector SAD (`VSAD`) and bitstream pack instructions (`VPACK`) to accelerate entropy coding.
- **Autonomous DMA scheduler:** Hardware-managed circular descriptor engine in PL to directly stream frames from network interface to accelerator.
- **Hardware/software co-design:** Partitioning mode decision algorithms to RISC-V soft-core while keeping datapath transforms in dedicated Verilog pipelines.
- **Power optimization:** Clock gating idle pipeline stages when macroblock skip condition is met.

---

## 14. Project Repository
- **Repository URL:** `https://github.com/Sai-Ram26/zynq-realtime-video-object-accelerator.git`
- **Your project branch:** `offline-video-compression-accelerator`
- **Main branch (reference only):** `main`
- **Important files/directories:**
  - `h264_accel_top.sv`: authoritative Model-4 RTL
  - `build_zedboard.tcl`: clean Vivado build
  - `fast_build.tcl`: incremental Vivado rebuild
  - `zedboard.xdc`: board constraints
  - `RELEASE/`: generated bitstream and XSA
  - `vitis/`: ARM-side firmware sources
  - `tb/`: focused simulation testbenches
  - `docs/`: architecture, verification, and Vivado build documentation

---

## 15. Expected Research Contributions
1. **Instruction Set Specialization for Video Accelerators:** Quantifying the efficiency gain of a domain-specific RISC-V custom instruction extension over traditional AXI-Lite MMIO register polling, demonstrating an ~18x reduction in control instructions per macroblock.
2. **Zero-DSP H.264 Baseline Architecture:** A multiplierless implementation of 4x4 transforms and quantization. Throughput is reported only after synthesis and hardware measurement.
3. **Pipelined Raster-to-Block Stream Architecture:** Low-latency hardware raster-to-block assembly with minimal BRAM line-buffer overhead, enabling direct streaming from standard video DMA without intermediate DDR frame reorganization.

---

## 16. Known Issues and Questions
- **Questions for Investigation:**
  1. What is the optimal BRAM vs. Register tradeoff when scaling `block_assembler_4x4.v` up to native 1080p line widths without downscaling?
  2. How can we most cleanly interface a full PicoRV32 instruction bus with `riscv_custom_video_decoder.v` in Vivado Block Design while keeping ARM Cortex-A9 as the supervisor?
  3. Would adopting CABAC provide enough bitrate savings at 240p/480p to justify the ~3x increase in PL logic utilization compared to CAVLC?
- **Known Quirks:**
  - In Vivado 2017.4, board preset defaults may require board part `em.avnet.com:zed:part0:1.3` instead of `1.4` (handled in `bd_zedboard_setup.tcl`).
  - Cache coherency requires explicit `Xil_DCacheFlushRange` before DMA MM2S launch and `Xil_DCacheInvalidateRange` after DMA S2MM completion on ARM Cortex-A9.
