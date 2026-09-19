# Stage 3 Engineering Report: Full 5-Stage Synthesizable Data Pipeline

## 1. Executive Summary
Stage 3 establishes the end-to-end synthesizable hardware pipeline (`rtl/stage3_pipeline_top.v`), integrating color space conversion, temporal background subtraction, spatial inpainting, 4x4 integer discrete cosine transform (DCT), quantization, and CAVLC entropy encoding into a unified streaming data plane.

---

## 2. Pipeline Stages

```
RGB888 In --> [Stage 1: RGB2YUV] --> [Stage 2: BgSub] --> [Stage 3: Inpainting 8x8]
                                                                  |
                                                                  v
Compressed <-- [Stage 5: CAVLC + NAL] <-- [Stage 4: DCT + Quant 4x4]
NAL Words
```

### Stage 1: Fixed-Point RGB888 to YUV420 Converter (`rgb2yuv.v`)
- Multiplierless shift-add integer implementation:
  $$Y = (77R + 150G + 29B) \gg 8$$
  $$U = (-43R - 85G + 128B + 32768) \gg 8$$
  $$V = (128R - 107G - 21B + 32768) \gg 8$$
- Fixed 2-stage pipelined latency with saturation clipping $[0, 255]$.

### Stage 2: Temporal Background Subtraction (`bg_sub.v`)
- Real-time absolute luminance difference: $\Delta = |Y_{\text{curr}} - Y_{\text{bg}}|$.
- Foreground motion mask generation: `mask = (diff > t_thresh) ? 1'b1 : 1'b0`.

### Stage 3: Spatial 8x8 Inpainting Engine (`inpainting_8x8.v`)
- 7 dual-port BRAM line stores forming an 8x8 neighborhood tap window.
- Inpainting trigger: when `mask[3][3] == 1`, center pixel replaced with arithmetic mean of unmasked spatial neighbors.

### Stage 4: 4x4 Integer DCT and Quantization (`dct_quant_4x4.v`)
- H.264/AVC 4x4 integer transform core butterfly network ($C_f = H \cdot X \cdot H^T$):
  $$H = \begin{pmatrix} 1 & 1 & 1 & 1 \\ 2 & 1 & -1 & -2 \\ 1 & -1 & -1 & 1 \\ 1 & -2 & 2 & -1 \end{pmatrix}$$
- 100% multiplierless using shift-add arithmetic.
- QP-based frequency quantization: $qshift = (QP \gg 1) + 2$.

### Stage 5: CAVLC Entropy Encoder & NAL Serializer (`cavlc_encoder.v`)
- 4x4 Zig-zag scanning array order.
- Syntax element calculation: `TotalCoeff` (total non-zero coefficients) and `TrailingOnes` (up to 3 high-frequency $\pm 1$ values).
- Byte-aligned NAL stream serialization with standard H.264 start-code prefix `0x00000001`.

---

## 3. Verification & Testbench Results
Executed automated SystemVerilog testbench `tb/tb_stage3_pipeline.sv` on a 32x16 video raster:
- **Test 1**: Reset and quiescent state check $\to$ **PASS**
- **Test 2**: 512-pixel frame streaming through all 5 stages $\to$ **PASS**
- **Test 3a**: Hardware performance monitor pixel counter ($N = 512$) $\to$ **PASS**
- **Test 3b**: Inpainting counter ($16$ corrupted pixels restored) $\to$ **PASS**
- **Test 4**: Compressed NAL word emission ($128$ NAL words produced) $\to$ **PASS**
- **Test 5**: TotalCoeff non-zero coefficient propagation $\to$ **PASS**

**Stage 3 Verification Status: 6/6 TESTS PASSED (100% SUCCESS)**
