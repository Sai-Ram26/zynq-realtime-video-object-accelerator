# Hardware-Accelerated Video Compression and Downscaling Platform on ZedBoard

## A complete academic project report information pack

> **How to use this document:** Replace the title-page placeholders, add your institution-specific certificate/declaration pages, insert screenshots and measured plots, and format this Markdown into the required Word/PDF template. The technical status statements in this report are deliberately separated into **implemented**, **simulation/offline**, **planned**, and **not yet hardware-validated** categories.

---

## Abstract

High-resolution video creates a large computational and communication burden for embedded systems. A conventional processor must repeatedly perform frame decoding, spatial resizing, block transforms, quantization, entropy coding, memory movement, and output packaging. This project investigates a hardware-accelerated video-processing platform based on the Avnet ZedBoard, which contains an AMD/Xilinx Zynq-7000 XC7Z020 device. The Zynq architecture combines a dual-core ARM Cortex-A9 Processing System (PS) with FPGA Programmable Logic (PL), making it suitable for heterogeneous hardware/software co-design.

The proposed platform accepts a high-resolution video on a host computer, downsizes it to a low-resolution target such as 320 x 240 or 256 x 144, arranges the resulting YUV 4:2:0 samples into macroblock-oriented memory tiles, and communicates with the ZedBoard using a framed TCP workflow. The ARM processor configures the accelerator through an AXI4-Lite register interface and controls DMA buffers in DDR3 memory. The PL design contains a custom SystemVerilog top level with 64-bit AXI memory access, AXI4-Stream output, a PicoRV32 supervisory processor with local firmware memory, mailbox-based job control, 4x4 integer transform and quantization operations, reconstruction/deblocking support, and a bitstream output path.

The host software is implemented in Python using OpenCV, NumPy, sockets, FFmpeg integration, and Flask-based local dashboards. An offline mode allows the host workflow and user interface to be evaluated without a physical FPGA. The design also includes a reproducible Vivado build script, a firmware-to-memory conversion utility, programming scripts, constraints, generated bitstream/XSA release artifacts, and documentation covering architecture, requirements, protocol, risks, verification, limitations, and benchmarking.

The report emphasizes engineering honesty. The current source code demonstrates the architectural framework and significant RTL implementation, but it does not justify claims of real-time 8K transfer, complete H.264 standards conformance, or physical-board performance unless those claims are supported by an independent laboratory measurement. Some stages remain simplified or explicitly marked as stubs, including current-macroblock population in the RTL pipeline, full motion estimation, and complete standards-compliant entropy coding. The project is therefore best presented as a hardware/software co-design prototype and research platform with a clear path to a production-quality H.264 implementation.

**Keywords:** Zynq-7000, ZedBoard, FPGA acceleration, H.264, video compression, AXI4, AXI DMA, PicoRV32, SystemVerilog, OpenCV, embedded systems, hardware/software co-design.

---

# Chapter 1: Introduction

## 1.1 Background

Video applications are increasingly required to process large images while operating with limited power, memory bandwidth, and communication bandwidth. A raw 8K frame has 7,680 x 4,320 pixels, or more than 33 million pixels. For YUV 4:2:0 video, one frame requires approximately 49.8 MB before container overhead. At 60 frames per second, the uncompressed data rate is approximately 2.99 GB/s, which is far beyond a 1 GbE link and difficult for a small embedded processor to handle continuously.

Video compression reduces the amount of data required for storage and transmission by exploiting spatial and temporal redundancy. A typical block-based codec uses prediction, residual calculation, an integer transform, quantization, scan ordering, entropy coding, and bitstream formatting. These operations are repetitive and can be parallelized. FPGA logic is therefore attractive for the computation-intensive parts of the pipeline, while the ARM processor is appropriate for configuration, networking, file management, and system supervision.

## 1.2 Problem statement

The problem addressed by this project is the design of an embedded, heterogeneous video-processing platform that:

1. Accepts high-resolution input video from a host computer.
2. Converts and downsizes the input into a manageable target resolution.
3. Transfers frame or tile data to an FPGA-based accelerator.
4. Uses programmable logic for block-oriented video-processing operations.
5. Returns compressed or processed output to the host.
6. Provides a local user interface, status information, and an offline validation path.
7. Can be reproduced using documented scripts and standard FPGA design tools.

The project also studies the boundary between a practical operational architecture and an academic research architecture. The ARM Cortex-A9 is the primary system controller, while PicoRV32 is integrated as a compact supervisory soft processor in the PL.

## 1.3 Motivation

The motivation is not to claim that a ZedBoard can transport uncompressed 8K video in real time. That is physically unrealistic over Gigabit Ethernet. Instead, the design uses offline, sequential, tiled processing and demonstrates how high-resolution source material can be reduced before the FPGA compression core processes it. This approach makes the project technically meaningful while respecting the bandwidth and resource limits of the platform.

## 1.4 Aim

To design and document a reproducible Zynq-7000 hardware/software co-design platform for offline high-resolution video downscaling and FPGA-assisted block-based compression, with ARM control, AXI interfaces, PicoRV32 supervision, host software, and a local dashboard.

## 1.5 Objectives

- Study the Zynq-7000 heterogeneous architecture.
- Define a host-to-board video dataflow.
- Design an AXI4-Lite control register interface.
- Design 64-bit AXI memory read/write engines for frame-buffer access.
- Integrate AXI4-Stream output for compressed data.
- Implement a mailbox protocol between ARM-owned registers and PicoRV32-owned status.
- Integrate a 32 KB PicoRV32 local memory and firmware image.
- Implement 4x4 integer transform, QP-dependent quantization, inverse reconstruction, and deblocking-related logic.
- Create host-side tile packing for 16x16 luma and 8x8 chroma macroblocks.
- Create a Python video-processing and streaming application.
- Provide offline simulation and dashboard modes.
- Provide Vivado build and FPGA programming automation.
- Identify limitations and define a realistic future-completion plan.

## 1.6 Scope

The scope includes the repository implementation, host application, RTL architecture, embedded C sources, scripts, documentation, and generated Vivado artifacts. It includes offline processing and simulation. It does not claim that a physical ZedBoard was connected during the repository audit, nor that every advertised performance number has been measured on hardware.

## 1.7 Contributions

The project contributes:

1. A single-file SystemVerilog accelerator top level.
2. A Zynq PS/PL integration flow with AXI4-Lite, AXI memory, AXI stream, and interrupts.
3. A PicoRV32-based supervisory architecture.
4. A mailbox protocol that separates ARM job ownership from PL supervision.
5. A host-side YUV 4:2:0 macroblock/tile packer.
6. An offline movie processing workflow with optional FFmpeg muxing.
7. A local Flask dashboard for upload, board detection, simulation selection, processing, and output viewing.
8. Reproducible Vivado and firmware-memory build scripts.
9. A risk-aware report that separates verified evidence from design intent.

---

# Chapter 2: Literature and Technical Background

## 2.1 FPGA acceleration

An FPGA consists of configurable lookup tables, registers, block RAM, DSP slices, clocking resources, and programmable routing. Unlike a general-purpose CPU, it can perform many operations concurrently and can expose a custom streaming datapath. The trade-off is that the designer must explicitly manage timing, buffering, interfaces, reset, memory access, and verification.

Video processing is a suitable FPGA workload because:

- pixels arrive in a regular order;
- block operations can be pipelined;
- multiple pixels or coefficients can be processed in parallel;
- line buffers and block buffers map naturally to BRAM;
- AXI4-Stream provides a standard valid/ready flow-control mechanism.

## 2.2 Zynq-7000 architecture

The Zynq-7000 device combines:

- a dual-core ARM Cortex-A9 Processing System;
- DDR3 memory controller;
- Gigabit Ethernet MAC;
- UART, timers, interrupts, and other PS peripherals;
- FPGA Programmable Logic;
- AXI interfaces between PS and PL.

In this project the ARM PS performs system-level control and DMA preparation. The PL performs the custom accelerator operations. The two sides communicate through an AXI4-Lite register interface and shared DDR memory accessed through high-performance PS ports.

## 2.3 H.264 concepts

H.264/AVC is a block-based video coding standard. A simplified intra-coded flow is:

1. divide a picture into macroblocks and smaller transform blocks;
2. predict a block from spatial neighbours;
3. calculate the residual;
4. apply the 4x4 integer transform;
5. quantize transform coefficients using a quantization parameter;
6. scan coefficients in zigzag order;
7. encode syntax elements using CAVLC or CABAC;
8. package the result into NAL units.

The transform used by H.264 is an integer transform rather than a floating-point DCT. Its structure uses additions, subtractions, and shifts, which can be efficient in FPGA logic. Quantization controls the quality/compression trade-off: higher QP generally produces more zero coefficients and a smaller output, but greater distortion.

## 2.4 Why constrained H.264 is appropriate

Complete modern codecs require substantial logic and memory bandwidth. H.265/HEVC, AV1, and VVC offer improved compression but have considerably more complex prediction, transform, and entropy-coding requirements. A constrained baseline/intra-oriented H.264 architecture is more appropriate for a Zynq-7020 research prototype because it can focus on 4x4 transform, quantization, CAVLC, and NAL formatting.

The report must distinguish between:

- a mathematically correct transform and a complete codec;
- a diagnostic token stream and standards-compliant CAVLC;
- an Annex-B start-code byte and a complete valid H.264 stream;
- an offline host mock and physical board throughput.

---

# Chapter 3: Existing System Analysis

## 3.1 Repository evidence

The repository contains:

| Area | Important files | Purpose |
|---|---|---|
| RTL | `h264_accel_top.sv` | Unified SystemVerilog accelerator, AXI interfaces, PicoRV32, pipeline FSM |
| Embedded control | `arm_main.c` | ARM-side register configuration and AXI DMA setup |
| PL firmware | `pico_main.c` | PicoRV32 mailbox supervision and heartbeat |
| Host processing | `movie_host.py` | Decode, resize, YUV conversion, tile packing, TCP transfer, output muxing |
| Dashboard | `server.py`, `web/index.html`, `web/app.js`, `web/styles.css` | Local browser interface and simulation processing |
| Alternate dashboard | `dashboard/app.py`, `dashboard/templates/index.html` | Flask application with hardware-oriented processing models |
| Build | `build_zedboard.tcl`, `fast_build.tcl`, `zedboard.xdc` | Vivado project and implementation flow |
| Programming | `scripts/program_fpga.tcl`, `run_program_fpga.bat` | FPGA programming support |
| Firmware image | `scripts/firmware_to_mem.py`, `pico_fw.mem` | Convert binary firmware to `$readmemh` format |
| Documentation | `README.md`, `PROJECT_DOCUMENTATION.md`, `docs/*` | Requirements, architecture, protocol, verification, risks, limitations |
| Release | `RELEASE/encoder.bit`, `RELEASE/encoder.xsa` | Generated FPGA release artifacts |

## 3.2 Current implementation classification

### Implemented in current source

- AXI4-Lite control slave interface.
- 64-bit AXI memory-master interface.
- 64-bit AXI4-Stream output interface.
- Interrupt output and diagnostic LEDs.
- 32 KB PicoRV32 memory array.
- PicoRV32 processor instantiation in the current unified RTL.
- AXI-style register map and mailbox status registers.
- 4 KB-aware burst splitting logic in the memory engines.
- Macroblock/tile address calculation.
- 4x4 transform task.
- QP remainder/quotient decomposition and scaling tables.
- Inverse reconstruction arithmetic.
- NAL start-code helper and AXI output packing framework.
- ARM register setup and DMA S2MM initialization.
- Pico firmware heartbeat and job-acceptance loop.
- Host video reading, resizing, I420 extraction, and tile packing.
- Offline host stream generation.
- Local dashboard and board-detection gate.
- Vivado project-generation script and release outputs.

### Simplified, incomplete, or not independently hardware-validated

- Current macroblock luma data is explicitly assigned zero in the pipeline transform stage instead of being fully populated from the DDR read response.
- Motion estimation candidate SAD is currently zero and the intra mode decision is forced to DC.
- `pico_main.c` contains a supervisory encoder-job stub that updates macroblock progress; it does not itself perform the RTL transform pipeline.
- The current CAVLC/NAL section emits limited syntax bytes and is not sufficient evidence of complete H.264 conformance without decoder validation.
- `movie_host.py --offline` writes a synthetic/dummy payload for validation of the host flow; it is not FPGA-generated compressed video.
- No physical-board benchmark is established by the repository alone.
- The current source comments and older documents contain claims that are broader than the active implementation. The report treats the active source as authoritative.

This classification is not a weakness in the report. It is an important engineering result: the project has a strong integration framework and a defined completion path, but the report must not present design intent as measured compliance.

---

# Chapter 4: Proposed System Architecture

## 4.1 High-level dataflow

```text
Input video file
       |
       v
Host OpenCV/FFmpeg decode
       |
       v
Resize to 320x240 or 256x144
       |
       v
BGR -> YUV/I420 conversion
       |
       v
16x16 Y + 8x8 U + 8x8 V macroblock packing
       |
       v
TCP frame transfer to ZedBoard
       |
       v
ARM Cortex-A9 receives/configures DDR buffers
       |
       v
AXI4-Lite register programming + AXI DMA preparation
       |
       v
PicoRV32 mailbox acceptance
       |
       v
PL DDR read -> prediction -> transform -> quantization
       |
       v
reconstruction/deblocking -> output stream
       |
       v
AXI4-Stream / AXI DMA -> DDR output buffer
       |
       v
ARM/host receives output and packages the result
```

## 4.2 Processing System responsibilities

The ARM Cortex-A9 is responsible for:

- starting the embedded service;
- reading the core identity and version;
- configuring width, height, tile counts, QP, frame mode, and buffer addresses;
- flushing the input cache range before PL reads;
- invalidating the output range before DMA writes;
- arming AXI DMA S2MM;
- asserting the job-start bit;
- polling or later handling interrupt completion;
- reading output length and error status;
- acknowledging completion.

The ARM is not intended to perform every pixel transform. It configures and supervises the hardware datapath.

## 4.3 Programmable Logic responsibilities

The PL contains the custom video-processing engine, AXI bridges, memory engines, status logic, and PicoRV32 subsystem. The design uses a common clock, active-low reset, 64-bit memory transactions, and AXI stream output. The PL also drives user LEDs:

- LED0: heartbeat/alive indication;
- LED1: active/busy indication;
- LED2: done or fault indication.

## 4.4 PicoRV32 supervision

PicoRV32 is an RV32I soft processor included in the unified SystemVerilog file. It has a 32 KB local memory represented as 8,192 32-bit words. Its firmware is loaded using `$readmemh("pico_fw.mem", pico_memory)`.

The Pico firmware:

1. clears status and error registers;
2. writes a heartbeat;
3. validates the `H264` core ID;
4. enters a job mailbox loop;
5. detects a new sequence number;
6. sets active/accepted status;
7. updates completed macroblock count;
8. signals done.

This architecture gives the ARM a high-level job interface and gives the PL a local supervisory controller. It also provides a research platform for later custom instruction extensions.

## 4.5 Mailbox ownership

The mailbox is designed around dual ownership:

| Owner | Main registers |
|---|---|
| ARM | CONTROL, frame parameters, buffer addresses, QP, mode, search radius, job sequence |
| Pico/PL | STATUS, ERROR_CODE, COMPLETED_MB, counters, output statistics, heartbeat |

The intended handshake is:

1. ARM writes all job parameters.
2. ARM sets `CONTROL[0]`.
3. Pico accepts the job and sets accepted/active status.
4. The pipeline processes macroblocks.
5. Pico/PL sets done and optionally raises an interrupt.
6. ARM reads output length and status.
7. ARM clears the job-start condition.

This protocol prevents both controllers from continuously writing the same status registers.

---

# Chapter 5: Hardware Design

## 5.1 Target device

The target is the Avnet ZedBoard using an AMD/Xilinx Zynq-7000 `XC7Z020-1CLG484`. The design documentation identifies the following platform characteristics:

- dual-core ARM Cortex-A9 PS;
- approximately 667 MHz ARM operation in the target board configuration;
- 50 MHz PL clock selected by the build script;
- 512 MB DDR3;
- 1 GbE PS Ethernet;
- 64-bit AXI memory paths;
- FPGA resources including LUTs, flip-flops, BRAM, and DSP48E1 slices.

Exact resource utilization and timing should be quoted from the final Vivado reports produced for the exact source revision. Estimates in planning documents must not be presented as measurements.

## 5.2 AXI4-Lite control interface

The accelerator control interface is a 32-bit AXI4-Lite slave mapped by the Vivado design at `0x43C00000`. The active RTL includes the following register map:

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| 0x00 | CORE_ID | RO | `0x48323634`, ASCII `H264` |
| 0x04 | CORE_VERSION | RO | Current RTL version constant |
| 0x08 | CONTROL | RW | Job start and fault acknowledgement |
| 0x0C | STATUS | RO/PL-owned | Active, done, accepted, error |
| 0x10 | ERROR_CODE | RO/PL-owned | Diagnostic error code |
| 0x14 | JOB_SEQUENCE | RW | Sequence number for duplicate protection |
| 0x18 | FRAME_ID_LOW | RW | Lower frame identifier |
| 0x1C | FRAME_ID_HIGH | RW | Upper frame identifier |
| 0x20 | INPUT_BASE | RW | Input DDR base address |
| 0x24 | REFERENCE_BASE | RW | Reference frame base |
| 0x28 | RECON_BASE | RW | Reconstructed frame base |
| 0x2C | CANDIDATE_BASE | RW | Candidate/reference data base |
| 0x30 | METADATA_BASE | RW | Metadata base |
| 0x34 | WIDTH | RW | Frame width |
| 0x38 | HEIGHT | RW | Frame height |
| 0x3C | TILES_X | RW | Horizontal macroblock/tile count |
| 0x40 | TILES_Y | RW | Vertical macroblock/tile count |
| 0x44 | QP | RW | Quantization parameter |
| 0x48 | ME_MODE | RW | Frame/motion mode |
| 0x4C | SEARCH_RADIUS | RW | Search radius parameter |
| 0x50 | COMPLETED_MB | RO | Completed macroblocks |
| 0x54 | TOTAL_MB | RO | Total macroblocks |
| 0x58 | CANDIDATES_TESTED | RO | Motion candidates tested |
| 0x5C | REGIONS_PRUNED | RO | Pruned regions |
| 0x60 | DDR_BYTES_READ | RO | Memory read counter |
| 0x64 | DDR_BYTES_WRITTEN | RO | Memory write counter |
| 0x68 | STALL_CYCLES | RO | Stall counter |
| 0x6C | FRAME_CYCLES | RO | Frame cycle counter |
| 0x70 | OUTPUT_LENGTH | RO | Output byte count |
| 0x74 | OUTPUT_CRC | RO | Output CRC/status value |
| 0x78 | IRQ_STATUS | RW/W1C | Interrupt status |
| 0x7C | IRQ_ENABLE | RW | Interrupt mask |
| 0x80 | WATCHDOG_LIMIT | RW | Watchdog threshold |
| 0x84 | PICO_HEARTBEAT | RO/firmware-owned | Pico liveness value |

The exact access semantics should be checked against the generated hardware design because the register ownership and read/write behavior are implemented in RTL rather than generated by a standard IP wizard.

## 5.3 DDR memory layout

The ARM source defines aligned buffer regions:

```text
DDR_INPUT_BASE       0x10000000
DDR_REF_BASE         0x11000000
DDR_RECON_BASE       0x12000000
DDR_BITSTREAM_BASE   0x13000000
```

The input is flushed from the ARM cache before the accelerator reads it. The output range is invalidated before DMA writes. Correct cache maintenance is essential because the ARM and PL may otherwise observe different copies of the same memory.

## 5.4 64-bit DDR read engine

The memory read engine accepts an address and byte count, generates AXI read bursts, waits for `ARREADY`, accepts `RVALID` data, checks `RRESP`, observes `RLAST`, and splits requests into smaller sub-bursts. The source comments specify 4 KB boundary handling. The data width is 64 bits, so each beat carries 8 bytes.

## 5.5 64-bit DDR write engine

The write engine generates `AW` transactions, sends `W` data with byte strobes, asserts `WLAST` on the final beat, waits for the `B` response, and records write errors. Reconstructed macroblocks are written to the configured reconstruction base.

## 5.6 AXI4-Stream output

The output interface is 64 bits wide. Individual generated bytes are accumulated in an internal 64-bit word. `TKEEP` indicates the number of valid bytes in a partially filled final word, and `TLAST` marks the end of the frame stream. Downstream DMA must be configured consistently with the stream's valid-byte and TLAST behavior.

## 5.7 Interrupts

The block design connects the accelerator interrupt and DMA interrupt through an `xlconcat` block to the Zynq PS `IRQ_F2P` input. The current ARM source disables the S2MM interrupt and uses polling for the shown startup path. An interrupt-driven implementation is a direct improvement for production use.

---

# Chapter 6: Video Processing and Compression Pipeline

## 6.1 Host-side resizing

The host reads the source video using OpenCV. It supports arbitrary files that OpenCV can decode, including common MP4-like containers. Each frame is resized to:

- 320 x 240 for the project’s 240p mode;
- 256 x 144 for the project’s 144p mode.

The source uses `cv2.INTER_AREA`, which is appropriate for area-based downsampling and usually reduces aliasing when shrinking an image. This resizing currently occurs on the host. A future hardware scaler may move this operation into the PL, but that should not be claimed as active hardware functionality without corresponding RTL evidence.

## 6.2 I420 conversion

The host converts BGR frames to I420. I420 contains:

- a full-resolution Y plane;
- a U plane at half width and half height;
- a V plane at half width and half height.

The resulting storage requirement is 1.5 bytes per pixel:

\[
B_{\mathrm{YUV420}} = W H + \frac{W H}{4} + \frac{W H}{4}
                 = 1.5 W H.
\]

## 6.3 Macroblock packing

Each 16x16 macroblock contains:

- 256 bytes of luma Y;
- 64 bytes of U chroma;
- 64 bytes of V chroma;
- total = 384 bytes.

The host packs macroblocks in raster order and the RTL computes a tile-major offset:

\[
\mathrm{offset} =
(\mathrm{tile\_index} \times 49,152)
+
(\mathrm{local\_macroblock} \times 384).
\]

The 49,152-byte tile size is 128 macroblocks x 384 bytes, corresponding to a 16-by-8 macroblock tile.

## 6.4 Prediction

The current active RTL stores top and left reconstruction samples and defines DC, vertical, and horizontal prediction concepts. However, the current mode-selection code explicitly forces DC intra prediction and sets motion-estimation SAD values to zero. Therefore the report should describe prediction as an integrated framework with a simplified current operating path, not as a fully optimized motion-compensated encoder.

## 6.5 Residual calculation

For each transform block:

\[
D(x,y) = X(x,y) - P(x,y),
\]

where \(X\) is the original sample and \(P\) is the predicted sample. The current task uses signed intermediate values, which is necessary because the residual range is negative as well as positive.

## 6.6 4x4 integer transform

The transform uses the H.264-style integer matrix:

\[
C =
\begin{bmatrix}
1 & 1 & 1 & 1\\
2 & 1 & -1 & -2\\
1 & -1 & -1 & 1\\
1 & -2 & 2 & -1
\end{bmatrix}.
\]

The RTL performs a horizontal butterfly followed by a vertical butterfly. Multiplication by two is represented by shifts. A report may call this transform multiplierless at the arithmetic-algorithm level; however, final FPGA DSP usage must be taken from Vivado synthesis/implementation rather than inferred only from the source.

## 6.7 Quantization

The design decomposes QP into:

\[
QP = 6 \times \left\lfloor \frac{QP}{6}\right\rfloor + (QP \bmod 6).
\]

The remainder indexes a scaling-factor table and the quotient determines a shift amount. Coefficients are quantized using magnitude, scaling factor, rounding offset, and sign restoration. Position classes are used for different coefficient locations.

Quantization is the main quality/compression control. A lower QP preserves more detail and usually increases output size. A higher QP introduces more coefficient zeros and reduces output size at the cost of reconstruction error.

## 6.8 Inverse reconstruction

The quantized coefficients are inverse-scaled and passed through an inverse transform. The reconstructed residual is added to the prediction and clipped to the 0–255 sample range:

\[
R(x,y) = \operatorname{clip}_{0,255}(P(x,y) + D'(x,y)).
\]

The reconstructed macroblock is stored for future reference and for neighbour availability.

## 6.9 Deblocking

The RTL includes a deblocking task that examines boundary differences and applies a bounded delta when the boundary strength and alpha/beta conditions permit. In-loop reconstruction is important because later predictions should use the reconstructed, filtered picture rather than the original picture.

## 6.10 Entropy coding and NAL formatting

The source defines zigzag scan order, a bit shifter, byte serialization, Annex-B start-code generation, and an output path. A complete H.264 encoder must also generate correct SPS, PPS, slice headers, macroblock syntax, coefficient-token VLCs, trailing-one sign flags, total-zeros, run-before, emulation-prevention, byte alignment, and frame-level syntax. The current code should be described as a NAL/output framework with partial syntax emission until an independent decoder accepts streams for representative test vectors.

---

# Chapter 7: Software Design

## 7.1 Host movie application

`movie_host.py` performs:

1. command-line argument parsing;
2. input-file existence validation;
3. OpenCV video opening;
4. source metadata extraction;
5. optional audio extraction using FFmpeg;
6. per-frame resize;
7. BGR-to-I420 conversion;
8. macroblock/tile packing;
9. TCP connection to the board;
10. frame-header and payload transmission;
11. response-header and bitstream reception;
12. offline fallback when the board is unavailable;
13. output stream writing;
14. optional MP4 muxing.

The live frame header used by this script is:

```text
Magic       4 bytes: H264
Frame       4 bytes
Width       2 bytes
Height      2 bytes
QP          2 bytes
Keyframe    2 bytes
Payload len 4 bytes
```

This is distinct from the more general 32-byte protocol specification in `docs/protocol.md`; the report should mention that the repository contains both a documented protocol design and a simpler current movie-host framing path. A future integration task should unify these definitions.

## 7.2 Offline mode

When `--offline` is selected, or when the board connection fails, the host writes a synthetic Annex-B-looking stream so that file flow and muxing behavior can be tested. This validates host control flow, not FPGA compression quality. The output must not be described as a hardware measurement.

## 7.3 Flask dashboard

The root `server.py`:

- serves the static web application;
- stores uploaded files;
- extracts video metadata;
- checks for a physical board through serial-port and Ethernet probes;
- rejects processing when the board is absent unless simulation is explicitly allowed;
- resizes frames;
- applies a software 4x4 transform/quantization preview;
- writes an output video;
- reports progress, FPS, and latency.

The dashboard therefore provides a useful demonstrator and golden-model-style preview, but its OpenCV output is not proof that the FPGA bitstream generated identical pixels.

## 7.4 User interface

The browser interface includes:

- video file selection and drag/drop;
- source metadata display;
- target-resolution selection;
- QP slider;
- board connection indicator;
- simulation-mode control;
- start compression button;
- progress display;
- original and processed side-by-side video players;
- output download action.

The browser communicates with the local Flask server over HTTP. The server, rather than the browser, is responsible for any future raw TCP communication with the board because browsers do not provide unrestricted raw TCP socket access.

---

# Chapter 8: Build and Deployment Methodology

## 8.1 Firmware-memory generation

The firmware conversion utility reads a binary file, pads it to a 4-byte boundary, converts little-endian 32-bit words to hexadecimal text, pads to 8,192 words by default, and writes a `$readmemh` file. This matches the 32 KB PicoRV32 memory declaration:

\[
8192 \text{ words} \times 4 \text{ bytes/word} = 32768 \text{ bytes}.
\]

## 8.2 Vivado project generation

`build_zedboard.tcl`:

1. creates a Vivado project for `xc7z020clg484-1`;
2. adds `h264_accel_top.sv`;
3. adds `pico_fw.mem`;
4. adds `zedboard.xdc`;
5. creates the Zynq processing system;
6. enables GP0, HP0, HP2, fabric interrupt, and a 50 MHz FCLK;
7. creates an AXI DMA configured for S2MM output;
8. creates the custom RTL module reference;
9. connects AXI interconnects;
10. connects the stream output to DMA;
11. connects interrupts to the PS;
12. generates the block design, wrapper, bitstream, and XSA.

## 8.3 Reproducible command

```cmd
cd /d D:\mini_project2
vivado -mode batch -source build_zedboard.tcl -notrace
```

The expected release artifacts are:

```text
D:\mini_project2\RELEASE\encoder.bit
D:\mini_project2\RELEASE\encoder.xsa
```

## 8.4 FPGA programming

The bitstream can be programmed using Vivado Hardware Manager:

1. power the ZedBoard;
2. connect the JTAG cable;
3. open Hardware Manager;
4. auto-connect to the target;
5. select the XC7Z020 device;
6. program `RELEASE\encoder.bit`.

The XSA is used to create or update a Vitis platform and software domain.

---

# Chapter 9: Verification and Testing

## 9.1 Verification philosophy

Verification should be conducted at four levels:

1. **Unit level:** transform, quantizer, memory burst, register, and mailbox behavior.
2. **Interface level:** AXI handshake, backpressure, `TKEEP`, `TLAST`, reset, and error responses.
3. **System level:** ARM configuration, DMA, mailbox, and end-to-end frame flow.
4. **Quality/conformance level:** decoder acceptance, PSNR, SSIM, output length, and throughput.

## 9.2 Required RTL tests

For each RTL block test:

- reset behavior;
- all-zero input;
- all-255 input;
- checkerboard input;
- signed residual values;
- minimum and maximum QP;
- valid/ready stalls;
- exact final-word `TKEEP`;
- correct `TLAST`;
- memory burst boundary at 4 KB;
- AXI error response;
- duplicate job sequence;
- watchdog timeout;
- fault acknowledgement.

## 9.3 Host tests

Host-side tests should verify:

- invalid file handling;
- OpenCV metadata;
- output dimensions;
- I420 plane shapes;
- tile payload length;
- tile order;
- header packing/unpacking;
- partial TCP reads;
- invalid magic;
- truncated response;
- board fallback;
- offline mode;
- FFmpeg unavailable path;
- temporary-file cleanup.

## 9.4 Conformance tests

A claim of H.264 output should be supported by:

1. generating a known input block;
2. recording the exact output bytes;
3. decoding the stream with FFmpeg or another standards-compliant decoder;
4. checking SPS/PPS/slice syntax;
5. checking decoded dimensions and frame count;
6. comparing decoded pixels with a reference;
7. measuring PSNR and SSIM.

Until this process passes for representative frames, use the wording “H.264-oriented” or “Annex-B/NAL output framework” rather than “fully compliant H.264 encoder.”

## 9.5 Hardware tests

The physical-board test plan should record:

- Vivado version;
- source commit;
- board revision;
- FPGA part;
- clock frequency;
- bitstream hash;
- input resolution;
- target resolution;
- QP;
- frame count;
- input bytes;
- output bytes;
- transfer time;
- FPGA frame cycles;
- measured FPS;
- CPU load;
- DDR read/write counters;
- temperature;
- decoder result;
- error count.

---

# Chapter 10: Performance and Feasibility Analysis

## 10.1 Raw video calculations

For YUV 4:2:0:

\[
\text{Bytes/frame} = 1.5WH.
\]

For 60 fps:

\[
\text{Bytes/s} = 1.5WHF.
\]

Approximate values:

| Resolution | YUV420 bytes/frame | YUV420 at 60 fps |
|---|---:|---:|
| 720p, 1280x720 | 1.38 MB | 82.94 MB/s |
| 1080p, 1920x1080 | 3.11 MB | 186.62 MB/s |
| 4K, 3840x2160 | 12.44 MB | 746.50 MB/s |
| 8K, 7680x4320 | 49.77 MB | 2,985.98 MB/s |

Gigabit Ethernet has a theoretical payload ceiling near 125 MB/s, with lower practical application throughput. Therefore:

- 720p60 is near the practical limit;
- 1080p60 exceeds the link;
- 4K60 greatly exceeds the link;
- 8K60 exceeds the link by roughly 24 to 27 times depending on the comparison basis.

The system must therefore be presented as offline/chunked for 4K and 8K.

## 10.2 Spatial reduction

For an 8K frame reduced to 320x240:

\[
\frac{7680 \times 4320}{320 \times 240}
= 432 \times.
\]

For 8K reduced to 256x144:

\[
\frac{7680 \times 4320}{256 \times 144}
= 900 \times.
\]

The exact ratio depends on the selected target dimensions. This calculation demonstrates why host-side downscaling reduces the workload before transfer and compression.

## 10.3 Compression and quality metrics

The report should calculate:

\[
\mathrm{MSE} = \frac{1}{N}\sum_{i=1}^{N}(x_i-y_i)^2
\]

\[
\mathrm{PSNR} = 10\log_{10}\left(\frac{255^2}{\mathrm{MSE}}\right).
\]

SSIM should be calculated with a documented implementation and parameters. Compression ratio must specify its denominator:

- raw-YUV-to-output ratio;
- input-container-to-output-container ratio;
- or compressed-stream-to-uncompressed-frame ratio.

These are not interchangeable. A report should never compare them without labeling the basis.

## 10.4 Resource reporting

Use the final implementation report for:

- LUTs;
- registers;
- BRAM;
- DSP;
- IO;
- clock utilization;
- timing slack;
- power estimate.

The planning documents include resource estimates and previous audit statements, but those numbers should not be treated as current measured results unless the corresponding report file and source revision are cited.

---

# Chapter 11: Results, Discussion, and Limitations

## 11.1 Results that can be claimed from the repository

- A complete Vivado build flow is present.
- A release bitstream and XSA are present in `RELEASE`.
- The current RTL contains the intended AXI and PicoRV32 architecture.
- Host-side frame resizing and I420 tile packing are implemented.
- The dashboard supports offline simulation and hardware-detection gating.
- The ARM source configures accelerator registers and DMA.
- The Pico firmware implements heartbeat and mailbox supervision.
- The repository documents the 1 GbE limitation and offline processing requirement.

## 11.2 Results that require measurement before claiming

- real-time frames per second;
- CPU utilization below a specified percentage;
- exact LUT/FF/BRAM/DSP usage;
- timing closure for a particular clock;
- compression ratio;
- PSNR and SSIM;
- standard H.264 decoder compatibility;
- physical TCP throughput;
- end-to-end latency;
- power consumption;
- thermal behavior.

## 11.3 Main limitations

1. The host and RTL framing specifications are not fully unified.
2. The physical board was not available during the repository audit.
3. The current FPGA pipeline contains explicit simplifications and stubs.
4. The offline output is synthetic and cannot validate hardware compression quality.
5. A full standards-conformance test is required before claiming a complete H.264 encoder.
6. The current ARM startup code prepares DMA but does not implement a complete TCP frame server.
7. Polling is used in the shown ARM completion path; interrupt-driven operation remains an improvement.
8. High-resolution input is processed offline, not as uncompressed real-time 8K streaming.
9. Exact implementation resource results must be tied to a source commit and Vivado report.
10. The dashboard’s software transform preview is not automatically bit-exact with the RTL.

## 11.4 Recommended completion plan

### Phase A: data correctness

- connect DDR read response data into `curr_mb_y`, `curr_mb_u`, and `curr_mb_v`;
- verify byte ordering and 384-byte macroblock layout;
- add assertions for the input buffer and tile address;
- compare a single macroblock against a Python golden model.

### Phase B: prediction and reconstruction

- implement neighbour availability at frame boundaries;
- calculate vertical, horizontal, and DC SAD values;
- implement inter-frame reference reads only after intra mode is stable;
- verify reconstruction and deblocking against reference vectors.

### Phase C: entropy coding

- implement CAVLC syntax elements;
- add SPS, PPS, slice headers, and macroblock syntax;
- implement emulation-prevention insertion;
- create decoder acceptance tests with FFmpeg.

### Phase D: system transport

- unify the documented 32-byte protocol and the current movie-host header;
- implement a complete ARM TCP service;
- implement bounded packet lengths, CRC validation, and explicit error responses;
- use interrupts or a bounded wait strategy instead of indefinite polling.

### Phase E: measurement

- synthesize and implement on the target device;
- record timing and utilization reports;
- measure board-to-host transfer;
- run the 8-case resolution matrix;
- publish raw CSV data and plots.

---

# Chapter 12: Sustainable Development Goals

## SDG 9: Industry, Innovation and Infrastructure

This is the primary SDG for the project. The project develops an innovative embedded-computing infrastructure using FPGA acceleration, heterogeneous ARM/FPGA processing, high-speed memory interfaces, and reproducible hardware/software integration. It demonstrates how specialized hardware can be designed for data-intensive workloads instead of relying exclusively on general-purpose processors.

**Project contribution:** open, reproducible architecture; embedded acceleration; hardware/software co-design; engineering documentation; and a practical platform for future edge-video research.

## SDG 12: Responsible Consumption and Production

Video processing consumes computational, storage, and communication resources. Downscaling before compression reduces the number of pixels entering the later pipeline and can reduce storage and data-transfer requirements. The project also uses offline processing and local computation, which helps avoid unnecessary cloud transfer for the demonstrator.

**Project contribution:** reduced data volume, local processing, reuse of a development board, and explicit measurement-oriented engineering rather than unsupported performance claims.

## SDG 13: Climate Action

This SDG is a secondary connection. Hardware acceleration can reduce the time and energy required for repetitive video operations when it is implemented efficiently. However, an energy-saving claim requires power measurements. The responsible report wording is that the architecture has potential for energy-efficient edge processing, not that energy reduction has already been proven.

**Project contribution:** investigation of efficient edge processing and reduced data movement, with future work required for measured energy-per-frame comparison.

## SDG 4: Quality Education

The project integrates digital design, computer architecture, embedded C, Python, networking, video coding, verification, and tool automation. It can therefore serve as an educational example of interdisciplinary engineering.

**Project contribution:** documented laboratory workflow, reproducible build scripts, test planning, and a complete example spanning hardware and software.

---

# Chapter 13: Conclusion

This project presents a Zynq-7000-based platform for studying FPGA-accelerated video downscaling and compression. Its architecture divides responsibilities between the host computer, ARM Processing System, FPGA Programmable Logic, AXI interconnect, DDR memory, DMA, and PicoRV32 supervisory processor. The repository includes meaningful implementation artifacts rather than only a conceptual diagram: a unified SystemVerilog accelerator, a register map, memory engines, mailbox logic, embedded firmware, host video processing, dashboards, Vivado automation, constraints, release files, and technical documentation.

The most important engineering conclusion is that 8K input can be supported as an offline, tiled, sequential workflow, but uncompressed real-time 8K transfer over 1 GbE is not feasible. The second important conclusion is that a complete H.264 encoder requires more than a transform and a NAL-looking output path. Standards conformance must be demonstrated by decoder acceptance and bitstream-level tests. The current project should therefore be presented as a hardware/software co-design prototype and integration framework whose strongest verified achievements are architecture, interface design, host processing, build reproducibility, and a clear path to completing the encoder datapath.

With the recommended completion work—correct DDR pixel loading, full prediction, standards-compliant CAVLC/NAL syntax, unified transport, physical-board testing, and measured resource/performance reports—the platform can become a robust academic demonstration of FPGA video acceleration.

---

# Appendix A: Suggested report chapter page allocation

For a 30–40 page academic report, the following allocation is practical:

| Section | Suggested pages |
|---|---:|
| Front matter, abstract, keywords | 2–3 |
| Introduction and objectives | 3–4 |
| Background and literature | 4–5 |
| Existing-system analysis and requirements | 3–4 |
| Architecture and dataflow | 5–6 |
| Hardware/RTL design | 6–8 |
| Software and dashboard | 4–5 |
| Build and deployment | 2–3 |
| Verification and testing | 3–4 |
| Results, limitations, future work | 3–4 |
| SDGs and conclusion | 2–3 |
| References and appendices | 3–5 |

Add the following figures to reach the required length without padding:

1. Zynq PS/PL block diagram.
2. End-to-end host-to-board dataflow.
3. Macroblock and tile memory layout.
4. AXI4-Lite register interface.
5. Mailbox state machine.
6. DDR read-engine state machine.
7. Transform and quantization flow.
8. Host application flowchart.
9. Dashboard screenshot.
10. Vivado block design screenshot.
11. Timing/utilization report screenshot.
12. Verification test matrix.
13. Output-quality comparison.
14. Risk heat map.

---

# Appendix B: Suggested viva questions and answers

### Why is the ARM processor used if the FPGA is the accelerator?

The ARM is better suited to networking, file-system interaction, configuration, and operating-system or bare-metal service tasks. The FPGA performs regular, highly parallel arithmetic and streaming operations.

### Why is 8K not processed in real time?

An 8K YUV 4:2:0 stream at 60 fps is approximately 2.99 GB/s, while 1 GbE has only about 125 MB/s theoretical payload capacity. The design therefore uses offline frame/tile processing.

### What is the role of PicoRV32?

PicoRV32 is a compact supervisory processor in the PL. It validates the core, maintains a heartbeat, accepts jobs through the mailbox, updates progress, and provides a research base for future custom video instructions.

### Why use a 4x4 integer transform?

H.264 uses an integer transform that can be implemented with additions, subtractions, and shifts, making it suitable for FPGA logic while avoiding floating-point arithmetic.

### Does the current project prove full H.264 compliance?

No. The architecture is H.264-oriented, but full compliance requires complete syntax generation and successful decoding of generated streams by a standards-compliant decoder.

### What should be measured on the physical board?

Timing slack, resource utilization, frame cycles, throughput, latency, CPU load, DDR traffic, output size, PSNR, SSIM, power, temperature, and decoder acceptance.

---

# Appendix C: References

Use the following references in the final academic citation style required by your institution.

1. ITU-T, **Recommendation H.264: Advanced video coding for generic audiovisual services**, International Telecommunication Union, latest applicable edition.
2. ISO/IEC, **14496-10: Information technology — Coding of audio-visual objects — Part 10: Advanced Video Coding**.
3. AMD/Xilinx, **Zynq-7000 SoC Technical Reference Manual (UG585)**.
4. AMD/Xilinx, **AXI Reference Guide (UG1037)**.
5. AMD/Xilinx, **Vivado Design Suite User Guide: Designing with IP (UG896)**.
6. AMD/Xilinx, **Vivado Design Suite User Guide: Logic Simulation (UG894)**.
7. Avnet, **ZedBoard Hardware User Guide**.
8. Clifford Wolf, **PicoRV32: A Size-Optimized RISC-V CPU**, open-source project documentation and source repository.
9. OpenCV, **Open Source Computer Vision Library documentation**, video I/O and image-processing modules.
10. Python Software Foundation, **Python 3 documentation**, socket, struct, subprocess, and file APIs.
11. Pallets Projects, **Flask documentation**, application routing and request handling.
12. FFmpeg Developers, **FFmpeg documentation**, H.264 decoding, muxing, and media processing.
13. Wang, Z., Bovik, A. C., Sheikh, H. R., and Simoncelli, E. P., “Image quality assessment: From error visibility to structural similarity,” *IEEE Transactions on Image Processing*, vol. 13, no. 4, 2004.
14. United Nations, **Sustainable Development Goals**, especially SDG 4, SDG 9, SDG 12, and SDG 13.
15. Sai-Ram26, **zynq-realtime-video-object-accelerator**, project repository and associated source documentation.

## Suggested web references

- https://www.itu.int/rec/T-REC-H.264
- https://www.iso.org/standard/75471.html
- https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM
- https://docs.amd.com/r/en-US/ug1037-vivado-axi-reference-guide
- https://github.com/YosysHQ/picorv32
- https://docs.opencv.org/
- https://ffmpeg.org/documentation.html
- https://flask.palletsprojects.com/
- https://sdgs.un.org/goals

---

# Appendix D: Repository files to cite in the implementation chapter

- [h264_accel_top.sv](h264_accel_top.sv): active RTL top level, AXI interfaces, mailbox, memory engines, transform, quantization, reconstruction, output stream, and PicoRV32.
- [arm_main.c](arm_main.c): ARM register map, cache maintenance, DMA setup, job start, and completion polling.
- [pico_main.c](pico_main.c): PicoRV32 firmware heartbeat and mailbox supervision.
- [movie_host.py](movie_host.py): host decode, resize, I420 conversion, macroblock packing, TCP framing, offline path, and muxing.
- [server.py](server.py): local Flask server, board detection, upload, processing, progress, and output serving.
- [build_zedboard.tcl](build_zedboard.tcl): Vivado project and block-design automation.
- [scripts/firmware_to_mem.py](scripts/firmware_to_mem.py): firmware image conversion.
- [docs/requirements.md](docs/requirements.md): functional/non-functional requirements.
- [docs/architecture.md](docs/architecture.md): system-level architecture and bandwidth reasoning.
- [docs/protocol.md](docs/protocol.md): proposed packet format.
- [docs/verification.md](docs/verification.md): verification strategy and test matrix.
- [docs/limitations.md](docs/limitations.md): physical and architectural limitations.
- [docs/risk_register.md](docs/risk_register.md): risks and mitigations.
- [docs/VIVADO_BUILD.md](docs/VIVADO_BUILD.md): build, programming, and reproducibility instructions.

