# ZedBoard FPGA – Complete Step-by-Step Guide
## H.264 Video Compression Accelerator (G. Sai Ram, 1602-24-735-163)

---

## PART 1 – What Files Are in the Project

After cleanup, the project has **one clean pipeline** – no object removal:

```
mini_project/
├── rtl/
│   ├── compression/          ← H.264 encoder pipeline (8 files)
│   │   ├── block_assembler_4x4.v   Raster pixels → 4×4 blocks
│   │   ├── intra_pred_4x4.v        H.264 intra prediction
│   │   ├── macroblock_skip.v       Sparse block skipping
│   │   ├── dct_4x4.v               Multiplierless 4×4 integer DCT
│   │   ├── quant.v                  Quantization (forward)
│   │   ├── cavlc.v                  CAVLC entropy coding
│   │   ├── cabac.v                  (CABAC stub, not wired in top)
│   │   └── h264_encoder.v           Encoder core (wires 1–5 above)
│   └── top/
│       └── video_accelerator_top.v  ← TOP MODULE  (AXI-Lite + AXI-Stream)
├── vivado/
│   ├── bd_zedboard_setup.tcl        ← Vivado automation script
│   └── zedboard_constraints.xdc     ← Pin constraints (ZedBoard)
├── vitis/
│   └── src/
│       ├── main.c                   ARM bare-metal application
│       ├── dma_driver.c/h           AXI DMA helper
│       └── xvideo_accel.c/h         Accelerator register driver
└── tb/
    ├── tb_video_accelerator.v        Main testbench (ALL TESTS PASS)
    ├── tb_dct_4x4.v                  DCT unit test
    └── run_sim.bat                   Simulation launcher
```

---

## PART 2 – Running Simulation on Your PC (Icarus Verilog)

### 2.1 Install Icarus Verilog (one-time)
1. Go to: http://bleyer.org/icarus/
2. Download the Windows installer → install it
3. Add `C:\iverilog\bin` to your Windows **PATH**
   - Search "Environment Variables" in Start menu
   - Edit "Path" under System variables → New → `C:\iverilog\bin`
4. Open a new CMD window, type: `iverilog -V`  — should show version

### 2.2 Run the simulation
Open CMD, navigate to the project folder, then:
```cmd
cd C:\Users\GudideniTejaVamseeKa\Desktop\mini_project
tb\run_sim.bat
```

Expected output:
```
=== TEST 1: AXI4-Lite Register Write/Read ===
[PASS] WIDTH = 16
[PASS] QP = 28
[PASS] CTRL = 0x05
=== TEST 2: Pixel Stream & H.264 Pipeline ===
[PASS] Received 8 H.264 bitstream words
=== TEST 3: Performance Counter ===
[PASS] Pixel counter = 256
=== ALL TESTS PASSED ===
```

---

## PART 3 – Vivado: Creating the FPGA Project

> **What you need:** Vivado 2020.2 or later (free WebPACK edition works for xc7z020).
> Download: https://www.xilinx.com/support/download.html

### Step 1 – Open Vivado
Launch Vivado → click **"Tcl Console"** tab at the bottom.

### Step 2 – Run the setup script
In the Tcl Console, type exactly:
```tcl
cd C:/Users/GudideniTejaVamseeKa/Desktop/mini_project/vivado
source bd_zedboard_setup.tcl
```
This will automatically:
- Create project for `xc7z020clg484-1` (ZedBoard)
- Import all 9 RTL source files from `rtl/compression/` and `rtl/top/`
- Build the block design (Zynq PS + AXI DMA + your accelerator)
- Validate the design

### Step 3 – Run Synthesis
In Vivado: **Flow menu → Run Synthesis**
- This converts your Verilog into FPGA logic (LUTs, FFs)
- Wait: ~5–10 minutes
- Should complete with 0 errors

### Step 4 – Run Implementation
**Flow menu → Run Implementation**
- Places and routes the design on the chip
- Wait: ~10–15 minutes
- Should complete with 0 errors

### Step 5 – Generate Bitstream
**Flow menu → Generate Bitstream**
- Creates the `.bit` file that programs the FPGA
- Wait: ~5 minutes

### Step 6 – Export Hardware to Vitis
**File menu → Export → Export Hardware**
- Check Include Bitstream
- Save as: `C:\Users\GudideniTejaVamseeKa\Desktop\mini_project\vivado_project\zedboard_video_accel.xsa`

---

## PART 4 – Vitis: ARM Software (Bare-Metal)

> Vitis IDE comes bundled with Vivado. Open it from Start menu as **"Vitis"**.

### Step 1 – Create Platform Project
1. **File → New → Platform Project**
2. Name: `zedboard_platform`
3. Click **Browse** next to XSA file → select the `.xsa` you exported
4. OS: **standalone** (bare-metal)
5. Processor: **ps7_cortexa9_0**
6. Click Finish → click **Build** (hammer icon)

### Step 2 – Create Application Project
1. **File → New → Application Project**
2. Platform: select `zedboard_platform`
3. Name: `video_accel_app`
4. OS: standalone, Processor: ps7_cortexa9_0
5. Template: **"Empty Application"**
6. Finish

### Step 3 – Add Source Files
Right-click `video_accel_app/src` in Explorer → **Import Sources**
Add all files from:
```
mini_project/vitis/src/main.c
mini_project/vitis/src/dma_driver.c
mini_project/vitis/src/dma_driver.h
mini_project/vitis/src/xvideo_accel.c
mini_project/vitis/src/xvideo_accel.h
```

### Step 4 – Build the Application
Click **Build All** (hammer icon).
Should produce `video_accel_app.elf` with 0 errors.

---

## PART 5 – Programming the ZedBoard

### Hardware connections:
1. Connect ZedBoard USB-UART cable (J14) to your PC
2. Connect ZedBoard JTAG/USB cable (J17) to your PC
3. Power on ZedBoard (SW8 = 1)

### Step 1 – Program the Bitstream
In Vivado: **Tools → Open Hardware Manager → Open Target → Auto Connect**
Then: **Program Device** → select the `.bit` file → Program

### Step 2 – Run the ARM Application
In Vitis: right-click `video_accel_app` → **Run As → Launch on Hardware (Single Application Debug)**

You should see output on the UART terminal (use PuTTY at 115200 baud on the COM port):
```
ZedBoard H.264 Video Accelerator
Sending test frame...
H.264 bitstream words received: XX
Frame processing time: XX us
```

---

## PART 6 – AXI4-Lite Register Reference (for ARM software)

| Address | Name   | R/W | Description                              |
|---------|--------|-----|------------------------------------------|
| 0x00    | CTRL   | R/W | [0]=Enable  [1]=SoftReset  [2]=CompressEn |
| 0x04    | WIDTH  | R/W | Frame width in pixels (e.g. 320)         |
| 0x08    | HEIGHT | R/W | Frame height in pixels (e.g. 240)        |
| 0x0C    | QP     | R/W | H.264 QP value 0-51 (lower = better quality, more bits) |
| 0x10    | STATUS | R   | [0]=Busy  [1]=Done  [2]=IRQ pending      |
| 0x14    | PERF0  | R   | Total pixels processed                   |
| 0x18    | PERF1  | R   | Skipped blocks count                     |

Base address of the accelerator is set by Vivado Address Editor (typically `0x43C00000`).

---

## PART 7 – Signal Flow Summary

```
PC (Python script)
      |  raw grayscale video frames (bytes)
  ARM Cortex-A9 (PS)
      |  programs AXI DMA via AXI-Lite
  AXI DMA (MM2S)  <--  DDR RAM
      |  AXI4-Stream (pixels)
  [PL FPGA FABRIC]
  block_assembler_4x4  ->  h264_encoder (intra_pred + DCT + quant + CAVLC)
      |  AXI4-Stream (H.264 bitstream words)
  AXI DMA (S2MM)  -->  DDR RAM
      |  ARM reads back compressed data
  ARM Cortex-A9 (PS)
      |  sends over UART to PC
  PC (Python/Website)
      -> Display original + compressed video
```

---

## Quick-Reference Commands

| Task | Command |
|------|---------|
| Simulate (Icarus) | `tb\run_sim.bat` from project root |
| Build Vivado project | Source `vivado/bd_zedboard_setup.tcl` in Tcl Console |
| ZedBoard UART baud | 115200 |
| Target FPGA part | `xc7z020clg484-1` |
| Max PL clock | 100 MHz (from PS FCLK0) |
