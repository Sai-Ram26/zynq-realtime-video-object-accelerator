# Stage 2 Engineering Report: Spatial 8x8 Inpainting Engine & Line Buffering

## 1. Executive Summary
Stage 2 implements the spatial 8x8 line-buffered inpainting engine (`rtl/inpainting_8x8.v`) integrated with the Stage 1 front-end (`rtl/stage2_core_top.v`). The subsystem replaces moving foreground objects detected by the background subtraction unit with smooth background approximations generated from unmasked spatial neighbors in an 8x8 pixel sliding window.

---

## 2. Microarchitecture & Line Buffer Topology

### 2.1 7-Line Dual-Port BRAM Buffer
To process incoming pixels in raster order without external frame buffer roundtrips, the inpainting engine instantiates 7 dual-port line buffers:
- **Line Width**: Parameterized (e.g. 64 / 1280 / 1920 pixels).
- **Line Buffers 0–6**: Store luminance and foreground mask bits for 7 previous horizontal scanlines.
- **Current Stream**: Represents line 8 of the sliding window.

### 2.2 8x8 Spatial Tap Matrix
At each clock cycle when `pixel_valid_in == 1`:
1. The 8 vertical samples from the current column and the 7 line buffer read outputs shift into an 8x8 register array.
2. The center pixel is evaluated at tap `[3][3]`.
3. If `mask[3][3] == 1` (foreground object), the engine computes the sum and count of all unmasked neighbors ($mask == 0$) across the 64-pixel neighborhood.
4. An integer division approximate $\mu = \text{Sum} / \text{Count}$ substitutes the corrupted center tap, restoring the background seamlessly.

---

## 3. RTL Components
| Module | File | Function |
| :--- | :--- | :--- |
| `inpainting_8x8` | `rtl/inpainting_8x8.v` | 8x8 sliding window line buffer & neighbor average inpainter |
| `stage2_core_top` | `rtl/stage2_core_top.v` | Stage 1 Core + Stage 2 Inpainting integration top wrapper |
| `tb_stage2_core` | `tb/tb_stage2_core.sv` | Automated self-checking SystemVerilog testbench |

---

## 4. Verification Results
Automated simulation executed via Icarus Verilog (`iverilog -g2012`) with `vvp`:
- **Test 1**: Reset and quiescent state verification $\to$ **PASS**
- **Test 2**: Continuous raster stream through RGB2YUV, BgSub, and line buffers $\to$ **PASS**
- **Test 3**: Inpaint reconstruction verification $\to$ **PASS** (center hole replaced with neighbor background average)

**Stage 2 Verification Status: 3/3 TESTS PASSED (100% SUCCESS)**
