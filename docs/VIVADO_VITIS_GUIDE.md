# ZedBoard FPGA – Complete Architecture & Setup Guide
## Real-Time H.264 Video Compression Accelerator
**Author:** G. Sai Ram (Roll No: 1602-24-735-163)  
**Institution:** Vasavi College of Engineering (Autonomous), Hyderabad  
**Target Hardware:** Avnet ZedBoard (AMD/Xilinx Zynq-7000 SoC `xc7z020clg484-1`)

---

## 1. System Architecture Overview

This project provides a complete dual-layer architecture:
1. **Physical ZedBoard Implementation:**
   - **Processing System (PS):** Dual-Core ARM Cortex-A9 running bare-metal C firmware ([`vitis/src/`](file:///c:/Users/GudideniTejaVamseeKa/Desktop/mini_project/vitis/src)) to configure registers via AXI4-Lite and manage high-speed DDR3 frame transfers via AXI DMA.
   - **Programmable Logic (PL):** Pipelined H.264 Baseline Compression Accelerator running at 100 MHz in FPGA fabric.
   - **ZedBoard Physical I/O:** 8 on-board LEDs (`LD0`–`LD7`) for real-time status diagnostics, and 8 slide switches (`SW0`–`SW7`) for direct hardware QP tuning (0–51).
2. **Academic Research Contribution (Custom RISC-V ISA Extension):**
   - Synthesizable RISC-V Custom-0 Opcode (`0x0B`) Instruction Decoder ([`rtl/riscv/riscv_custom_video_decoder.v`](file:///c:/Users/GudideniTejaVamseeKa/Desktop/mini_project/rtl/riscv/riscv_custom_video_decoder.v)) implementing dedicated video instructions (`VBLK`, `VSCALE`, `VDCT`, `VQNT`, `VENC`, `VSTATUS`, `VWAIT`).

```
                    +------------------------------------+
                    |        HOST LAPTOP (Offline)       |
                    |   Web Dashboard (HTML5/Flask/OpenCV)|
                    +-----------------+------------------+
                                      | Gigabit Ethernet / USB-UART
                                      v
  ============================= ZEDBOARD =============================
  +------------------------------------------------------------------+
  |  PROCESSING SYSTEM (PS) - Hard Silicon                           |
  |    - Dual ARM Cortex-A9 @ 667 MHz                                 |
  |    - 512 MB DDR3 Memory Controller                                |
  |    - Gigabit Ethernet MAC & USB-UART Controller (MIO Pins)        |
  |    - FCLK0 (100 MHz Clock Generator)                             |
  +---------------------------------+--------------------------------+
                                    | AXI Interconnect & AXI DMA
                                    v
  +------------------------------------------------------------------+
  |  PROGRAMMABLE LOGIC (PL) - FPGA Fabric                           |
  |                                                                  |
  |  +------------------------------------------------------------+  |
  |  |  H.264 Video Compression Accelerator Core                  |  |
  |  |   - AXI4-Lite Register Bank (0x43C00000)                   |  |
  |  |   - 4x4 Line-Buffer Block Assembler                        |  |
  |  |   - H.264 Intra-Prediction (Vertical, Horizontal, DC)      |  |
  |  |   - Multiplierless 4x4 Integer DCT (0 DSP slices)          |  |
  |  |   - Quantization Engine (Configurable QP 0-51)             |  |
  |  |   - CAVLC / CABAC Entropy Coding Bitstream Generator       |  |
  |  +------------------------------------------------------------+  |
  |                                                                  |
  |  +------------------------------------------------------------+  |
  |  |  RISC-V Custom ISA Extension Coprocessor (Opcode 0x0B)     |  |
  |  |   - Instructions: VBLK, VSCALE, VDCT, VQNT, VENC, VSTATUS   |  |
  |  +------------------------------------------------------------+  |
  |                                                                  |
  |  +-------------------------+      +---------------------------+  |
  |  | Switches SW[5:0] (QP)   |      | LEDs LD[7:0] (Diagnostics)|  |
  |  +-------------------------+      +---------------------------+  |
  +------------------------------------------------------------------+
  ====================================================================
```

---

## 2. Explanation of ZedBoard Constraints (`vivado/zedboard_constraints.xdc`)

### Why doesn't the constraint file need clock, DDR, or Ethernet pins?
On a standard FPGA (like Spartan or Artix), every pin must be declared in `.xdc`.
However, on **Zynq-7000 SoC (ZedBoard)**:
- **Clocks (`FCLK_CLK0`), DDR3 Memory, Ethernet, and UART** are physically hardwired inside the Zynq Processing System (PS).
- When you use the official ZedBoard preset (`em.avnet.com:zed:part0:1.4`) in Vivado, Vivado **automatically constrains all internal MIO and DDR pins in silicon**.
- The `.xdc` constraint file is strictly needed for **physical Programmable Logic (PL) pins**:
  - `SW[7:0]` (Bank 35, 2.5V LVCMOS)
  - `LD[7:0]` (Bank 33, 3.3V LVCMOS)
  - Timing clock specification (`create_clock` @ 100 MHz)

### Physical ZedBoard Hardware Diagnostic Mapping

#### On-Board LEDs (`LD0`–`LD7`):
* **`LD0` (T22):** Accelerator Active / Processing busy
* **`LD1` (T21):** Block Compressed pulse (blinks every 4&times;4 block encoded)
* **`LD2` (U22):** AXI4-Stream Slave Active (receiving raw pixels from DMA)
* **`LD3` (U21):** AXI4-Stream Master Active (streaming H.264 bitstream to DMA)
* **`LD4` (V22):** Core Enabled (AXI-Lite `CTRL[0]` = 1)
* **`LD5` (W22):** Compression Pipeline Enabled (AXI-Lite `CTRL[2]` = 1)
* **`LD6` (U19):** Frame-complete Interrupt line (`IRQ`)
* **`LD7` (U14):** **Clock Heartbeat** &mdash; Toggles at ~1.5 Hz continuously, proving FPGA fabric is powered and running!

#### On-Board Slide Switches (`SW0`–`SW7`):
* **`SW[5:0]`:** **Hardware QP Override (0 to 51)**  
  *If switches are set to 0, QP is taken from the ARM register (default 28). If you flip any switch `SW[5:0]`, the hardware immediately uses the switch value as the quantization parameter, allowing physical real-time video quality tuning on the board!*
* **`SW[6]`:** Bypass mode
* **`SW[7]`:** Diagnostic freeze

---

## 3. Running Pre-Synthesis Simulation (One-Click)

You can run the full test suite on your laptop before opening Vivado.

### Running with Icarus Verilog:
Double-click [`tb/run_sim.bat`](file:///c:/Users/GudideniTejaVamseeKa/Desktop/mini_project/tb/run_sim.bat) or run in terminal:
```cmd
cd c:\Users\GudideniTejaVamseeKa\Desktop\mini_project
tb\run_sim.bat
```

The script automatically executes all 3 testbenches:
1. **Full Video Accelerator Testbench (`tb_video_accelerator.v`)**:
   - AXI4-Lite Register write/read tests (`WIDTH`, `QP`, `CTRL`).
   - AXI4-Stream raw pixel streaming (256 pixels) into pipeline.
   - H.264 CAVLC compressed bitstream output verification.
   - Hardware performance counter verification.
2. **2D 4&times;4 Integer DCT Testbench (`tb_dct_4x4.v`)**:
   - Multiplierless butterfly integer transform verification.
3. **RISC-V Custom ISA Extension Testbench (`tb_riscv_custom_decoder.v`)**:
   - Decodes opcode `0x0B` for `VBLK`, `VQNT`, `VSTATUS`, `VWAIT`.
   - Validates non-interference with standard instructions.

---

## 4. Vivado Block Design & Bitstream Generation

### Automated Setup (Recommended):
1. Launch **Vivado 2020.2** (or later).
2. In the Vivado **Tcl Console** at the bottom, type:
   ```tcl
   source c:/Users/GudideniTejaVamseeKa/Desktop/mini_project/vivado/bd_zedboard_setup.tcl
   ```
3. The script automatically:
   - Creates the project targeting `xc7z020clg484-1` (ZedBoard).
   - Imports all RTL files from `rtl/compression`, `rtl/top`, and `rtl/riscv`.
   - Configures the Zynq-7000 Processing System with board presets.
   - Configures AXI DMA in Direct Register Mode.
   - Instantiates `video_accelerator_top` and wires AXI-Lite and AXI-Stream buses.
   - Connects LEDs and switches to external ports.
   - Generates the HDL wrapper and attaches `zedboard_constraints.xdc`.
4. Click **Generate Bitstream** (in the Flow Navigator on the left).
5. Once complete, export hardware:
   **File &rarr; Export &rarr; Export Hardware &rarr; Include Bitstream &rarr; Export as `system_bd_wrapper.xsa`**.

---

## 5. Vitis Embedded Software Setup

1. Launch **Xilinx Vitis IDE**.
2. Select workspace (e.g. `c:/Users/GudideniTejaVamseeKa/Desktop/mini_project/vitis_workspace`).
3. Click **Create Platform Project**:
   - Point to the exported `system_bd_wrapper.xsa`.
   - Processor: `ps7_cortexa9_0`, OS: `standalone` (bare-metal).
4. Click **Create Application Project**:
   - Name: `video_accelerator_demo`.
   - Template: **Empty Application (C)**.
5. In the Project Explorer, right-click `video_accelerator_demo/src`:
   - Click **Import Sources...**
   - Import all files from [`vitis/src/`](file:///c:/Users/GudideniTejaVamseeKa/Desktop/mini_project/vitis/src):
     - `main.c`
     - `dma_driver.c` / `dma_driver.h`
     - `xvideo_accel.c` / `xvideo_accel.h`
6. Click **Build Project** (Ctrl+B).

---

## 6. Testing on the Physical ZedBoard

1. Connect the **PROG** micro-USB cable (J17) to your PC for JTAG programming.
2. Connect the **UART** micro-USB cable (J14) to your PC for serial output.
3. Power on the ZedBoard (switch SW8).
4. Open a serial terminal (PuTTY or Tera Term) at **115200 baud, 8N1** on the ZedBoard COM port.
5. In Vitis, right click `video_accelerator_demo` &rarr; **Run As &rarr; Launch Hardware (Single Application Debug)**.
6. Look at the ZedBoard:
   - `LD7` starts blinking (~1.5 Hz heartbeat).
   - `LD4` and `LD5` turn on (accelerator initialized).
   - Serial terminal prints:
     ```
     ====================================================
       ZedBoard Real-Time H.264 Video Compression SoC
       Vasavi College of Engineering - G. Sai Ram
     ====================================================
     [INFO] Resetting AXI DMA & Accelerator...
     [INFO] Configuring Frame: 640x480, Initial QP: 28
     [INFO] Initiating AXI DMA MM2S Transfer (Input Pixels)...
     [INFO] AXI DMA S2MM Reception Completed!
     [PASS] Received 1200 H.264 Bitstream Words.
     [PERF] Frame Compression Time: 3.82 ms (261.7 FPS equiv)
     ```
   - Flip switch `SW[0]` to change QP and watch `LD1` blink as compressed blocks flow!
