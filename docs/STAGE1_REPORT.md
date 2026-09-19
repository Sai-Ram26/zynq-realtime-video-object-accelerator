# STAGE 1 -- Minimum Working Core Verification Report

**Role**: Lead FPGA/RTL Engineer  
**Project Title**: High-Efficiency Zynq SoC Video Accelerator Architecture  
**Target Platform**: AMD Zynq-7000 APSoC (`xc7z020clg484-1`) on Avnet ZedBoard  
**Current Phase**: STAGE 1 -- Minimum Working Core Demonstration (**COMPLETED & VERIFIED**)  

---

## 1. Files Created & Project Structure

The synthesizable Verilog RTL, SystemVerilog testbench, cycle-exact simulation harness, and verification documentation for Stage 1:

* `rtl/custom_vector_decoder.v`: Synthesizable RISC-V Custom Opcode Interceptor (`0x0B`).
* `rtl/rgb2yuv.v`: Synthesizable 2-Stage Pipelined Fixed-Point RGB888 to YUV420 Converter.
* `rtl/bg_sub.v`: Synthesizable Temporal Background Subtraction & Motion Mask Generator.
* `rtl/stage1_core_top.v`: Stage 1 Core Integration Top Wrapper.
* `tb/tb_stage1_core.sv`: Automated Self-Checking SystemVerilog Testbench.
* `docs/STAGE1_REPORT.md`: Stage 1 Technical Verification Documentation.

---

## 2. Files Modified

* Clean, unified modular integration into workspace `rtl/` and `tb/`.

---

## 3. What the RTL Does

The Stage 1 Minimum Working Core implements the primary control-plane and front-end data-plane processing hardware:

1. **RISC-V Custom Opcode Interceptor (`custom_vector_decoder.v`)**:
   - Decodes the `funct3` bit-field:
     - `3'b000` = RGB2YUV
     - `3'b001` = Temporal Subtraction
     - `3'b010` = Inpainting
     - `3'b011` = DCT
     - `3'b100` = CAVLC
   - Latches physical memory base address from register `rs1`, asserts a single-cycle `pe_array_start` pulse, and sets the `pe_busy` status flag.
2. **Fixed-Point RGB888 to YUV420 Converter (`rgb2yuv.v`)**:
   - Computes:
     $$Y = (77 \cdot R + 150 \cdot G + 29 \cdot B) \gg 8$$
     $$U = (-43 \cdot R - 85 \cdot G + 128 \cdot B + 32768) \gg 8$$
     $$V = (128 \cdot R - 107 \cdot G - 21 \cdot B + 32768) \gg 8$$
   - Outputs 8-bit Luma ($Y$) and Chroma ($U, V$) values with saturation clipping.
3. **Temporal Frame Subtraction & Motion Mask Generator (`bg_sub.v`)**:
   - Compares $\Delta = |Y_{\text{curr}} - Y_{\text{bg}}|$ against a dynamic software threshold $T_{\text{thresh}}$ to produce a 1-bit `foreground_mask` ($1 = \text{Motion/Foreground}, 0 = \text{Static Background}$).
4. **Stage 1 Integration Top Wrapper (`stage1_core_top.v`)**:
   - Connects the control plane and data plane into a single synthesizable entity.

---

## 4. Test Cases & Verification Results

| Test Case Name | Inputs Driven | Expected Result | Actual Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Test 1: Custom Opcode 0x0B Interception** | `instruction = 0x0005050B`, `rs1_data = 0x10008000` | `target_op = 0`, `mem_addr = 0x10008000`, `pe_busy = 1` | `target_op = 0`, `mem_addr = 0x10008000`, `pe_busy = 1` | **PASS** |
| **Test 2A: Pure Red Background Match** | $R=255, G=0, B=0$, $Y_{\text{bg}}=77, T=30$ | $Y_{\text{out}}=76, \Delta=1$, `mask=0` | $Y_{\text{out}}=76, \Delta=1$, `mask=0` | **PASS** |
| **Test 2B: White Intruder Motion Detection** | $R=255, G=255, B=255$, $Y_{\text{bg}}=77, T=30$ | $Y_{\text{out}}=255, \Delta=178$, `mask=1` | $Y_{\text{out}}=255, \Delta=178$, `mask=1` | **PASS** |
| **Test 2C: Pure Green Background Match** | $R=0, G=255, B=0$, $Y_{\text{bg}}=150, T=30$ | $Y_{\text{out}}=149, \Delta=1$, `mask=0` | $Y_{\text{out}}=149, \Delta=1$, `mask=0` | **PASS** |
| **Test 2D: Shadow Motion Intruder Pixel** | $R=50, G=50, B=50$, $Y_{\text{bg}}=200, T=30$ | $Y_{\text{out}}=50, \Delta=150$, `mask=1` | $Y_{\text{out}}=50, \Delta=150$, `mask=1` | **PASS** |

**Verification Summary**: 5 / 5 Test Cases Passed (**100% Pass Rate**).

---

## 5. Expected vs. Actual Results

* **Color Extraction Precision**: Pure Red ($255, 0, 0$) yielded expected $Y = \lfloor (77 \cdot 255)/256 \rfloor = 76$. Actual RTL output: $Y = 76$.
* **Motion Mask Generation**: Pure White Intruder ($255, 255, 255$) against background $Y_{\text{bg}}=77$ with threshold $T=30$ yielded difference $\Delta = |255 - 77| = 178 > 30$. Expected `foreground_mask = 1`. Actual RTL output: `foreground_mask = 1`.

---

## 6. Waveform Signals to Inspect

In Vivado or GTKWave simulation (`sim_stage1_core.vcd`):
1. **Clock & Reset**: `clk` (100 MHz clock), `rst_n` (Active-low reset).
2. **Control Plane**: `instruction` (`32'h0005050B`), `insn_valid`, `pe_array_start`, `pe_busy`.
3. **Stream Input**: `pixel_valid_in`, `r_in`, `g_in`, `b_in`, `y_bg_in`, `t_thresh_in`.
4. **Stream Output**: `pixel_valid_out` (delayed by 2 clock pipeline cycles), `y_out`, `u_out`, `v_out`, `abs_diff_out`, `foreground_mask`.

---

## 7. Exact Commands / Tools Used

```bash
iverilog -g2012 -o sim_stage1_core.vvp rtl/custom_vector_decoder.v rtl/rgb2yuv.v rtl/bg_sub.v rtl/stage1_core_top.v tb/tb_stage1_core.sv
vvp sim_stage1_core.vvp
```
