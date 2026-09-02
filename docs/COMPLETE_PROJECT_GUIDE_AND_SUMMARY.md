# 🚀 Complete Project Master Guide & Architecture Blueprint

**Project Title**: Real-Time Hardware Video Compression Accelerator with Object Removal on Zynq-7000 SoC  
**Student**: G. Sai Ram (1602-24-735-163)  
**Target Hardware**: Avnet ZedBoard (AMD / Xilinx Zynq-7000 SoC `xc7z020clg484-1`)  
**Created On**: Sunday, August 23, 2026  
**Hardware Delivery Target**: Thursday, August 27, 2026  

---

## 1. Project Goal & System Flow

```
[ Laptop: Input Video / Webcam ]
         │ (OpenCV decodes frames into raw bytes)
         ▼ (Gigabit Ethernet UDP / UART)
[ ZedBoard: 512 MB DDR3 RAM ]
         │ (AXI DMA MM2S Stream - 1 pixel/cycle)
         ▼
[ FPGA Fabric (PL) Hardware Accelerator ]
   ├── Stage 1: RGB888 to Grayscale [Y = (77R + 150G + 29B) >> 8] (0 DSPs)
   ├── Stage 2: Background Subtraction & Masking [|Y_curr - Y_bg| > Threshold]
   ├── Stage 3: Inpainting / Object Removal [Cleaned_Y = Mask ? Y_bg : Y_curr]
   ├── Stage 4: 2D 4x4 H.264 Integer Transform / DCT (Butterfly Shift-Add)
   └── Stage 5: Quantization & 32-bit Level Packing (Zero-Copy Burst)
         │
         ▼ (AXI DMA S2MM Stream back to DDR3)
[ Cleaned & Compressed Video Buffer ]
         │ (Transmitted over Ethernet UDP)
         ▼
[ Laptop: OpenCV cv2.imshow() Live Output Display ]
```

---

## 2. Processor Roles: ARM Cortex-A9 vs. PicoRV32

| Component | Architecture & Type | Role in the Project |
| :--- | :--- | :--- |
| **ARM Cortex-A9** | **Hard Processing System (PS)**<br>Dual-Core @ 667 MHz with NEON & FPU | • Master system controller (runs C/C++ firmware in Vitis).<br>• Manages DDR3 RAM buffers and AXI DMA engine.<br>• Communicates with Laptop over Ethernet/UART sockets.<br>• Dynamically updates Threshold and Quantization (QP) via AXI4-Lite. |
| **PicoRV32** | **Soft RISC-V Core in PL**<br>Synthesized on FPGA logic (~1,500 LUTs) | • Embedded real-time coprocessor inside the video pipeline.<br>• Computes local block variance & adaptive thresholding per tile.<br>• Encodes compressed stream headers (CAVLC/Huffman) without interrupting the ARM CPU. |

---

## 3. Hardware Accelerator vs. Software Accelerator

* **Software Accelerator (on ARM Cortex-A9)**: Written in C/C++ inside Xilinx Vitis, compiled with `-O3 -mfpu=neon` SIMD vectorization. Serves as our reference benchmark (~45 ms/frame).
* **Hardware Accelerator (on FPGA PL)**: Dedicated pipelined Verilog RTL using pure shift-add operations processing **1 pixel per clock cycle** at 100 MHz (~5 ms/frame, giving a **~9x Speedup** with ultra-low power).

---

## 4. Required Software Tools Checklist

1. **Xilinx Vivado ML Standard (WebPACK)**: FPGA RTL design, Block Design, synthesis, implementation, and bitstream generation. *(Free)*
2. **Xilinx Vitis Unified Platform**: C/C++ firmware for ARM Cortex-A9 and AXI DMA driver. *(Included with Vivado)*
3. **Python 3.10+ (with NumPy, OpenCV, Matplotlib)**:
   ```bash
   pip install opencv-python numpy matplotlib scipy
   ```
   *Used on laptop to decode video, send raw frames to ZedBoard, and display output in real-time.*
4. **RISC-V Toolchain (`riscv32-unknown-elf-gcc`)**: Compiles firmware for PicoRV32 soft-core.
5. **Serial Terminal (PuTTY / Tera Term)**: Monitors ZedBoard UART debug logs (Baud rate: `115200`).

---

## 5. Day-by-Day Implementation Roadmap (Sunday $\to$ Thursday)

| Phase & Day | Focus Area | Key RTL / Code Files |
| :--- | :--- | :--- |
| **Phase 1 (Sun – Mon)** | **Video Compression** | • Multiplierless 2D $4\times4$ H.264 Integer DCT: [`rtl/compression/dct_4x4.v`](file:///d:/mini_project2/rtl/compression/dct_4x4.v)<br>• Quantization & high-frequency elimination. |
| **Phase 2 (Tuesday)** | **Object Removal & Inpainting** | • Pipelined Grayscale Converter: [`rtl/object_removal/rgb2gray.v`](file:///d:/mini_project2/rtl/object_removal/rgb2gray.v)<br>• Subtraction & Mask Inpainter: [`rtl/object_removal/bg_subtract_inpaint.v`](file:///d:/mini_project2/rtl/object_removal/bg_subtract_inpaint.v) |
| **Phase 3 (Wednesday)** | **RAM Memory & Bandwidth Optimization** | • 32-bit Word Packing (4 pixels per AXI word, 75% RAM bandwidth saving).<br>• On-chip BRAM Line Buffers for zero redundant DDR3 access. |
| **Phase 4 (Thursday)** | **Board Arrival & Hardware Run** | • Run [`vivado/bd_zedboard_setup.tcl`](file:///d:/mini_project2/vivado/bd_zedboard_setup.tcl) in Vivado.<br>• Program ZedBoard bitstream & stream video live from laptop. |

---

## 6. Curated YouTube Learning Resources

* **Zynq Architecture & Vivado/Vitis DMA**:
  * [Vipin K Menon - Image Processing on Zynq (FPGAs) Playlist](https://www.youtube.com/watch?v=Xkpu8BXi3aI&list=PLXff6ca_l7VqB8hE_t2TjC6fM_25n_z-T) *(Must Watch!)*
  * [FPGAs for Beginners - Zynq PS & PL Integration](https://www.youtube.com/@FPGAsforBeginners)
* **Video Compression & DCT**:
  * [Branch Education - How Video Compression Works (3D Animated)](https://www.youtube.com/watch?v=QoZ8Lw2bY0s)
  * [Reducible - The Discrete Cosine Transform (DCT)](https://www.youtube.com/watch?v=Q2aEzeMD4jh)
* **FPGA Image Processing Verilog**:
  * [Mohammad Sadri - FPGA Image Processing Series](https://www.youtube.com/results?search_query=Mohammad+Sadri+FPGA+Image+Processing)
* **OpenCV & Socket Streaming**:
  * [freeCodeCamp - OpenCV Python Full Course](https://www.youtube.com/watch?v=oXlwWbU8l2o)
  * [Tech With Tim - Python Sockets Networking](https://www.youtube.com/watch?v=3QiPPX-KeSc)
