# Stage 4 Engineering Report: Verification Harness & Cycle-Exact Golden Reference

## 1. Executive Summary
Stage 4 provides an independent, cycle-exact Python verification harness that validates the Verilog RTL pipeline against mathematical and standards-compliant references across 5 distinct test suites comprising 15 automated test vectors.

---

## 2. Architecture of the Verification Engine

### 2.1 Python Golden Reference Model (`sim/golden_reference.py`)
- `rgb2yuv_golden(r, g, b)`: Bit-accurate fixed-point RGB to YUV420 color conversion.
- `bg_sub_golden(y_curr, y_bg, t_thresh)`: Exact temporal motion detection and mask generation.
- `inpaint_8x8_golden(y_frame, mask_frame, line_width)`: 8x8 spatial window sliding neighborhood reconstruction.
- `dct4x4_golden(block_4x4)`: H.264 4x4 integer discrete cosine transform matrix multiplication.
- `quantize_golden(dct_block, qp)`: QP-dependent scaling and dead-zone scalar quantization.
- `cavlc_stats_golden(quant_block)`: Zig-zag scan, TotalCoeff, and TrailingOnes syntax analysis.

### 2.2 15-Test Automated Suite (`sim/sim_runner.py`)
The suite evaluates both nominal operation and extreme corner cases:
- **Suite 1: Normal Processing Suite** (Test 01–03)
  - SMPTE Green color conversion, typical motion detection, 2x2 corrupted region inpainting.
- **Suite 2: Boundary Conditions Suite** (Test 04–07)
  - All-black input ($Y=0, U=128, V=128$), All-white input ($Y=255, U=128, V=128$), QP=51 extreme quantization, QP=0 finest quantization.
- **Suite 3: Edge Cases Suite** (Test 08–10)
  - Minimal motion detection ($\Delta = 1, T = 0$), 0% foreground mask pass-through, 100% full-frame occlusion fallback.
- **Suite 4: Custom Vector Instruction Decoding Suite** (Test 11–13)
  - RISC-V Opcode 0x0B with funct3 0..4 decoding, PE address latching (`0x10080000`), PE busy interlock arbitration.
- **Suite 5: Hardware Performance & Latency Suite** (Test 14–15)
  - 720p @ 60fps throughput headroom calculation ($1.81\times$ margin at 100 MHz), multiplierless shift-add equivalence audit (0 DSP).

---

## 3. Execution Summary

```
======================================================================
   ZYNQ SoC VIDEO ACCELERATOR - 15-TEST COMPREHENSIVE SUITE
======================================================================
[PASS] [Test 01] (Suite 1: Normal) RGB2YUV SMPTE Green -> Y=149 U=43 V=21
[PASS] [Test 02] (Suite 1: Normal) BgSub Motion Detection -> diff=110, mask=1
[PASS] [Test 03] (Suite 1: Normal) Spatial 8x8 Inpaint Reconstruction -> inpainted_pixels=4
[PASS] [Test 04] (Suite 2: Boundary) RGB2YUV Min Boundary (All Black) -> Y=0 U=128 V=128
[PASS] [Test 05] (Suite 2: Boundary) RGB2YUV Max Boundary (All White) -> Y=255 U=128 V=128
[PASS] [Test 06] (Suite 2: Boundary) Quantization Boundary QP=51 -> DC_Quant=0
[PASS] [Test 07] (Suite 2: Boundary) Quantization Boundary QP=0 -> DC_Quant=16 (exp 16)
[PASS] [Test 08] (Suite 3: Edge Cases) Minimal Detection (Diff=1, Thresh=0) -> diff=1, mask=1
[PASS] [Test 09] (Suite 3: Edge Cases) Zero Foreground Inpaint Pass-Through -> count=0
[PASS] [Test 10] (Suite 3: Edge Cases) 100% Occlusion Mask Fallback -> unmasked_fallback_count=0
[PASS] [Test 11] (Suite 4: Instruction Interception) RISC-V Opcode 0x0B & Funct3 Decoder -> 5/5 instructions decoded
[PASS] [Test 12] (Suite 4: Instruction Interception) PE Base Address Latching & Dispatch -> addr=0x10080000
[PASS] [Test 13] (Suite 4: Instruction Interception) PE Base Address Latching & Dispatch -> busy_stalled=True
[PASS] [Test 14] (Suite 5: Performance) 720p @ 60fps Real-Time Throughput Margin -> margin=1.81x at 100MHz
[PASS] [Test 15] (Suite 5: Performance) Multiplierless Shift-Add Equivalence (0 DSP) -> mult=7700, shift=7700
======================================================================
VERIFICATION RESULTS: 15/15 PASSED (100.0%)
STATUS: ALL 15 TESTS PASSED - 100% SUCCESS
======================================================================
```
