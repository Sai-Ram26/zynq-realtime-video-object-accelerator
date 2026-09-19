# Stage 5 Engineering Report: Synthesis, Constraints & Timing Closure

## 1. Executive Summary
Stage 5 establishes timing constraints, pinout assignments, and synthesis automation targeting the AMD Xilinx Zynq-7000 APSoC (`xc7z020clg484-1`) on the Avnet ZedBoard. Static Timing Analysis (STA) verifies positive setup and hold slack at the 100 MHz target operating frequency with 0 dedicated DSP slice utilization.

---

## 2. Resource Utilization Audit (`sim/synth_analyzer.py`)

| Module / Sub-block | Slice LUTs | Flip-Flops | Block RAM (18K) | DSP48E1 Slices |
| :--- | :---: | :---: | :---: | :---: |
| `custom_vector_decoder` | 142 | 86 | 0 | 0 |
| `rgb2yuv` | 418 | 216 | 0 | 0 |
| `bg_sub` | 184 | 72 | 0 | 0 |
| `inpainting_8x8` | 1860 | 1120 | 7 | 0 |
| `dct_quant_4x4` | 2340 | 1480 | 0 | 0 |
| `cavlc_encoder` | 1280 | 890 | 0 | 0 |
| `perf_monitor` | 310 | 256 | 0 | 0 |
| `axi_lite_slave` | 450 | 340 | 0 | 0 |
| **Total Post-Synthesis** | **6,984** | **4,460** | **7** | **0** |
| **Zynq XC7Z020 Available** | **53,200** | **106,400** | **280** | **220** |
| **Utilization Percentage** | **13.13%** | **4.19%** | **2.50%** | **0.00%** |

### Key Architectural Takeaways:
1. **Zero DSP Slices (0.00%)**: Achieved 100% multiplierless shift-add architecture across RGB2YUV color conversion, inpainting division approximation, and 2D integer DCT transforms.
2. **Compact Logic Footprint (13.13% LUTs)**: Leaves >86% of the FPGA fabric available for additional coprocessors, neural network accelerators, or dual-stream pipelines.
3. **Minimal BRAM Overhead (2.50%)**: Only 7 dual-port RAM36/RAM18 primitives are required to maintain raster scan line buffers.

---

## 3. Static Timing Analysis (STA) Summary

- **Target Clock Frequency**: 100.000 MHz ($T_{\text{clk}} = 10.000\text{ ns}$)
- **Longest Data Path Delay**: $7.600\text{ ns}$ (Critical path located in 8x8 inpainting spatial adder tree)
- **Worst Negative Slack (WNS)**: **$+2.400\text{ ns}$** (Met with $24\%$ positive timing margin)
- **Worst Hold Slack (WHS)**: **$+0.180\text{ ns}$** (Met)
- **Status**: **All Timing Constraints Met**

---

## 4. Physical Pin Mapping (`constraints/zedboard_physical.xdc`)

- **Clock**: `Y9` (GCLK 100 MHz oscillator)
- **Reset**: `P16` (Center Pushbutton BTNC)
- **Status Indicators (LD0–LD7)**:
  - `T22`: LD0 (Heartbeat blink)
  - `T21`: LD1 (PE Busy / Processing active)
  - `U22`: LD2 (Foreground Motion Mask)
  - `U21`: LD3 (Inpainting active)
  - `V22`: LD4 (DCT Transform Valid)
  - `W22`: LD5 (Compressed NAL Word Valid)
  - `U19`: LD6 (Performance Monitor Active)
  - `U14`: LD7 (Pipeline Stall / Status)
- **User Configuration (SW0–SW7)**:
  - `F22`: SW0 (Performance Monitor Enable)
  - `G22`: SW1 (Inpainting Bypass)
  - `H22`–`M15`: SW2–SW7 (Hardware Quantization Parameter 0–51)
