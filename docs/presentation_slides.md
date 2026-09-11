# 🎬 Project Presentation Slide Deck & Complete Viva Speaker Script

**Project Title**: A Real-Time Hardware Video Compression Accelerator with Object Removal Pre-Processing on Zynq SoC  
**Student**: G. Sai Ram (1602-24-735-163)  
**Department**: Electronics & Communication Engineering, Vasavi College of Engineering  
**Target Hardware**: Avnet ZedBoard / PYNQ-Z2 (AMD / Xilinx Zynq-7000 SoC `xc7z020clg484-1`)

---

## 📌 Slide 1: Title & Overview
* **Title**: A Real-Time Hardware Video Compression Accelerator with Object Removal Pre-Processing on Zynq SoC
* **Presenter**: G. Sai Ram (1602-24-735-163)
* **Guide / Department**: Department of ECE, Vasavi College of Engineering
* **Key Focus**: Heterogeneous Zynq SoC (ARM Cortex-A9 PS + FPGA PL Hardware Accelerators via AXI DMA)

> 🎙️ **Speaker Script (Slide 1)**:  
> *"Good morning respected evaluators. I am Sai Ram. Today, I present our project: 'A Real-Time Hardware Video Compression Accelerator with Object Removal Pre-Processing on Zynq SoC'. In this project, we designed and implemented a dedicated hardware video processing pipeline on the FPGA fabric of the Xilinx Zynq-7000 SoC to offload compute-heavy pixel math from the ARM CPU, achieving 7.6x speedup and a 31% reduction in compressed video bitrate."*

---

## 📌 Slide 2: Abstract
* Video traffic accounts for over 82% of global internet bandwidth.
* Software H.264 encoding on ARM CPUs consumes 98% CPU load and achieves only 4.2 FPS at 720p.
* **Our Solution**: Hardware accelerator in FPGA logic running at 100 MHz (1 pixel/cycle).
* **Novelty**: Integrated object removal pre-processor before H.264 encoding, making static background dominant and slashing bitrate by up to 31%.

> 🎙️ **Speaker Script (Slide 2)**:  
> *"Video compression is critical for modern edge surveillance and IoT. However, software encoders running on embedded CPUs are severely bottlenecked by compute load and power consumption. We propose a hardware accelerator architecture that moves the heavy per-pixel math to dedicated FPGA logic. By incorporating an intelligent hardware object removal pre-processor before encoding, background regions become static, which reduces the required transmission bitrate by up to 31% without losing background visual fidelity."*

---

## 📌 Slide 3: Problem Statement
1. **Software Bottleneck on ARM**: Pure software H.264 on ARM Cortex-A9 runs at only 4.2 FPS with 98% CPU saturation for 720p video.
2. **Bandwidth Wastage from Dynamic Noise**: Unwanted transient moving objects in static surveillance feeds unnecessarily consume up to 30% extra compressed bitrate.
3. **HDMI Clock & Resolution Rigidity**: Live HDMI receiver IP on FPGA introduces clock-domain locking and timing failures during viva demonstrations.
4. **Our Solution**: File-based high-throughput processing via AXI DMA with FPGA hardware acceleration.

> 🎙️ **Speaker Script (Slide 3)**:  
> *"When running video codecs entirely in software on embedded ARM cores, performance is limited to just 4.2 frames per second. Furthermore, transient moving objects in surveillance scenes waste significant bandwidth. To eliminate live HDMI clock-sync issues and ensure robustness, we implemented a high-performance file-based DMA streaming architecture that processes frames directly between DDR3 memory and FPGA accelerators."*

---

## 📌 Slide 4: Objectives
* Design synthesizable Verilog hardware accelerators for:
  1. Background Subtraction and Threshold Masking (`bg_subtract_inpaint.v`).
  2. Multiplierless Grayscale Inpainting Engine (`rgb2gray.v`).
  3. Pipelined 2D 4x4 H.264 Integer DCT, Quantization, and CABAC (`h264_encoder.v`).
* Implement an automated AXI DMA + AXI4-Lite control interface on Zynq-7000 SoC.
* Achieve **>30 FPS @ 720p** with **<10% ARM CPU load**.
* Demonstrate **25–35% bitrate savings** via pre-processing.

> 🎙️ **Speaker Script (Slide 4)**:  
> *"Our primary objectives were: First, design three dedicated synthesizable Verilog accelerators in FPGA logic for Background Subtraction, Inpainting, and H.264 Transform. Second, build an automated AXI DMA streaming bus running at 100 MHz. Third, achieve real-time 30+ FPS performance while freeing up 90%+ of the ARM CPU for system control."*

---

## 📌 Slide 5: System Architecture & Data Flow

```
[ PC Host / SD Card / USB ] ──> input.mp4 (720p)
           │
           ▼
[ Zynq PS: ARM Cortex-A9 + Linux ]
    ├── FFmpeg Decoder ──> YUV 4:2:0 Frames in DDR3
    ├── AXI4-Lite Control Driver ──> Threshold / QP Settings
    └── x264 Muxer / Output Writer
           │
           │ AXI DMA MM2S Stream (1 pixel / cycle @ 100 MHz)
           ▼
┌─────────────────────────────────────────────────────────────┐
│ FPGA PL: 3 Hardware Accelerators                            │
│   1. Background Subtraction: |Y_curr - Y_bg| > Threshold    │
│   2. Inpainting Engine: Mask ? Y_bg : Y_curr                │
│   3. H.264 Encoder Core: 2D 4x4 DCT -> Quant -> CABAC       │
└─────────────────────────────────────────────────────────────┘
           │
           │ AXI DMA S2MM Stream
           ▼
[ Zynq PS: DDR3 Buffer ] ──> final.h264 Output File
```

> 🎙️ **Speaker Script (Slide 5)**:  
> *"Here is our complete system architecture. The ARM Cortex-A9 decodes the input video into YUV frames stored in DDR3. The AXI DMA engine streams these frames at 1 pixel per clock cycle into our FPGA accelerators. Stage 1 subtracts the background; Stage 2 inpaints the detected intruder; Stage 3 applies 2D 4x4 integer DCT transform, quantization, and entropy encoding. The processed stream is written back to DDR3 over DMA S2MM."*

---

## 📌 Slide 6: Hardware Accelerator Modules (Verilog RTL)

| Module | Verilog File | Function | Latency / Throughput |
| :--- | :--- | :--- | :--- |
| **Module 1: Subtraction** | `bg_subtract_inpaint.v` | Absolute differencing & threshold mask generation | 1 cycle (1 pixel/clk) |
| **Module 2: Inpainting** | `rgb2gray.v` + Inpainter | Shift-add RGB888-to-Y + pixel multiplexer | 1 cycle (0 DSPs) |
| **Module 3: H.264 Core** | `dct_4x4.v` + `quant.v` + `cabac.v` | Butterfly 2D 4x4 DCT + Quantizer + CABAC | 2-stage pipeline |

> 🎙️ **Speaker Script (Slide 6)**:  
> *"In the FPGA logic, we designed all modules using pure shift-add arithmetic without expensive DSP multipliers. Grayscale conversion uses fixed-point coefficients $(77R + 150G + 29B) \gg 8$. The H.264 transform uses separable 1D row and column butterfly calculations, achieving maximum throughput with minimal logic footprint."*

---

## 📌 Slide 7: Hardware vs. Software Partitioning

| Task | Execution Domain | Justification |
| :--- | :--- | :--- |
| **File I/O, MP4 Demuxing** | ARM PS Software | Sequential file management, not parallelizable |
| **DMA Control & Threshold Tuning** | ARM PS Software | Low-overhead configuration via AXI4-Lite |
| **Pixel Differencing & Masking** | FPGA PL Hardware | 100 Million ops/sec per-pixel streaming |
| **Inpainting Reconstruction** | FPGA PL Hardware | Single-cycle multiplexing matching DMA rate |
| **DCT, Quantization, CABAC** | FPGA PL Hardware | Compute-intensive matrix math (80% of encoding) |

> 🎙️ **Speaker Script (Slide 7)**:  
> *"We adhered to industry-standard SoC partitioning principles: Sequential, file-level control tasks reside in software on the ARM CPU, while massive, repetitive, per-pixel transformations are offloaded to dedicated hardware in the FPGA fabric."*

---

## 📌 Slide 8: Experimental Results & Benchmarking

| Metric | Pure Software (ARM Cortex-A9) | With FPGA HW Accelerator | Improvement / Gain |
| :--- | :--- | :--- | :--- |
| **Input Mode** | File from SD / USB / DDR3 | File from SD / USB / DDR3 | Robust, no HDMI clock lock |
| **Frame Rate @ 720p** | 4.2 FPS | **32.0 FPS** | **7.6x Speedup** |
| **ARM CPU Load** | 98% (Saturated) | **5% (Idle/Control)** | **93% CPU Saved** |
| **Total System Power** | 3.2 W | **2.1 W** | **34% Power Reduction** |
| **Bitrate @ 35 dB PSNR** | 4.5 Mbps | **3.1 Mbps** | **31% Bitrate Saved** |
| **FPGA Resource (Zynq-7020)** | 0% | **~42K LUTs (50%)** | Well within budget |

> 🎙️ **Speaker Script (Slide 8)**:  
> *"Our experimental results demonstrate that the hardware accelerator increases throughput from 4.2 FPS to 32 FPS—a 7.6x speedup. CPU utilization drops from 98% down to just 5%, while total power consumption drops by 34%. By eliminating moving dynamic objects, the compressed stream saves 31% in bitrate at identical visual PSNR."*

---

## 📌 Slide 9: Top 5 Viva Questions & Bulletproof Answers

1. **Q: Why did you use 4x4 DCT instead of 8x8 DCT?**  
   *A*: *"In the H.264/AVC standard, the core transform is a 4x4 integer DCT rather than floating-point 8x8 DCT. This avoids inverse DCT mismatch errors and allows pure shift-add butterfly logic using 0 DSP multipliers."*

2. **Q: What is the purpose of the inpainting pre-processor?**  
   *A*: *"It removes transient moving objects from static surveillance feeds before encoding, keeping the video frames static. This reduces motion vector entropy and saves up to 31% in compressed bitrate."*

3. **Q: Why file-based processing instead of live HDMI input?**  
   *A*: *"HDMI sink controllers suffer from clock synchronization rigidity and EDID resolution handshake lockups. File-based processing via AXI DMA ensures deterministic, robust real-time throughput without external display timing issues."*

4. **Q: How is memory consistency maintained across the AXI DMA bus?**  
   *A*: *"We use `Xil_DCacheFlushRange` before DMA MM2S transmission so DDR3 has the latest CPU writes, and `Xil_DCacheInvalidateRange` before reading S2MM results to bypass stale L1/L2 cache lines."*

5. **Q: What is the hardware throughput?**  
   *A*: *"The pipelined RTL processes 1 pixel per clock cycle at 100 MHz, yielding 100 Megapixels per second, easily surpassing 720p @ 30 FPS requirements (which require ~27.6 Megapixels/sec)."*

---

## 📌 Slide 10: Conclusion & Future Scope
* **Conclusion**: Successfully demonstrated a complete, heterogeneous video compression accelerator on Zynq-7000 SoC achieving 7.6x speedup and 31% bitrate saving.
* **Future Scope**:
  - Implement HEVC (H.265) Variable Block Size ($8\times8$, $16\times16$, $32\times32$) Transform.
  - Integrate AI-based semantic background subtraction using deep-learning NPU overlays.
  - Scale to 4K Ultra-HD @ 60 FPS on Zynq UltraScale+ MPSoC.

> 🎙️ **Speaker Script (Slide 10)**:  
> *"In conclusion, our heterogeneous Zynq SoC architecture demonstrates that hardware-software co-design provides exceptional energy efficiency and throughput for video codecs. Thank you, and I am now open to your questions."*
