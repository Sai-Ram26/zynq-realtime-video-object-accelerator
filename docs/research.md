# Research & Theoretical Analysis: FPGA Video Acceleration Architectures

**Document Status:** Research Foundations & Prior Art Survey  
**Classification Guide:** All assertions marked as FACT, SOURCE EVIDENCE, ENGINEERING INFERENCE, PROPOSED DESIGN, or SPECULATION.

---

## 1. Video Codec Evaluation for Zynq-7000 XC7Z020

### 1.1 Comparative Survey
- **H.264 / MPEG-4 AVC (FACT)**: Standardized in ITU-T H.264. Baseline profile supports 4x4 integer transform and CAVLC.
  - *SOURCE EVIDENCE*: Extensive FPGA literature demonstrates pipelined H.264 intra encoders achieving >100 MHz operating frequencies with ~12,000 to 20,000 LUTs (ScienceDirect, IEEE Xplore).
  - *ENGINEERING INFERENCE*: Highly feasible for XC7Z020 (53,200 LUTs). Native decoder support exists in 100% of modern web browsers.
- **H.265 / HEVC (FACT)**: Standardized in ITU-T H.265. Employs 35 intra prediction modes, CABAC entropy coding, and CTUs up to 64x64.
  - *SOURCE EVIDENCE*: Open-source Verilog HEVC encoders (e.g., GitHub open-hevc-encoder) require >45,000 LUTs, multiple clock domains, and deep pipelines.
  - *ENGINEERING INFERENCE*: Consumes >85% of XC7Z020 logic, leaving insufficient margin for scaling and system buses. Rejected for initial implementation.
- **AV1 & VVC / H.266 (FACT)**: Latest generation coding standards offering 30-50% bitrate reductions over HEVC.
  - *SOURCE EVIDENCE*: Research implementations indicate transform and entropy architectures consume massive logic resources (>60,000 LUTs) and require complex external memory access (Nature, AOMedia).
  - *ENGINEERING INFERENCE*: Completely impractical for the XC7Z020 fabric.
- **JPEG XS (ISO/IEC 21122) (FACT)**: Ultra-low latency, lightweight wavelet-based visually lossless codec designed for FPGA transmission.
  - *ENGINEERING INFERENCE*: Excellent for 10:1 studio mezzanine compression, but unsuitable for downscaling high-resolution video to ultra-low bitrates (240p/144p).

**PROPOSED DESIGN**: Implement **Constrained H.264 Intra-Only Encoder** (4x4 Integer DCT, QP-controlled Quantizer, CAVLC, and NAL packetizer).

---

## 2. Spatial Downscaling Algorithms

| Algorithm | Computational Complexity | Hardware Resource Footprint | Visual Quality (PSNR/SSIM) | FPGA Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| **Nearest-Neighbor / Decimation** | Minimal (skip counters) | Extremely low (<500 LUTs) | Poor (severe aliasing and jagged edges) | Fallback / debug only |
| **Area Averaging** | Low (accumulator + shift) | Low (~1,200 LUTs) | Good for integer scale factors ($2\times, 4\times$) | Secondary mode |
| **Bilinear / 2-Tap Filter** | Medium (multipliers / shifts) | Moderate (~2,500 LUTs, 2 BRAMs) | Very Good (smooth anti-aliasing) | **Primary baseline** |
| **Polyphase FIR (4-Tap+)** | High (filter banks + DSPs) | High (~6,000 LUTs, 8-16 DSPs) | Excellent (broadcast standard) | Future optimization |

---

## 3. CPU Architecture Research: Custom Video ISA Extensions

### 3.1 Hardened ARM Cortex-A9 vs. Soft RISC-V Core
- **ARM Cortex-A9 (FACT)**: Hard IP in Zynq PS running at 667 MHz with NEON SIMD and integrated Gigabit Ethernet MAC. Consumes 0 PL LUTs.
- **PicoRV32 Soft RISC-V (FACT)**: Small synthesizable RV32I core consuming ~1,500 LUTs.
- **Track B Research Contribution (PROPOSED DESIGN)**:
  Rather than attempting to run the entire video compression in soft-CPU software (which would yield <0.5 FPS), the RISC-V core is augmented with custom instruction extensions (`VBLK`, `VSTART`, `VCONFIG`) that initiate and synchronize hardware accelerator pipeline transactions in a single clock cycle.
  - Standard RISC-V MMIO dispatch: $\approx 18$ instructions per block (load base, offset, write control, polling loop).
  - Custom Instruction `VBLK`: $1$ instruction per block.
  - Quantifiable metric: $18\times$ reduction in control-plane instruction overhead.
