# Risk Register & Hardware Constraints Assessment

**Target Hardware:** Avnet ZedBoard (AMD/Xilinx Zynq-7000 XC7Z020)  
**Host System:** Windows 11 Enterprise  
**Document Classification:** Risk & Feasibility Audit

---

## 1. Identified Technical Risks & Mitigation Plan

| Risk ID | Category | Description | Severity | Probability | Mitigation Strategy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RSK-01** | Hardware | **ZedBoard Physical Hardware Not Connected**: Board is not currently plugged in via USB-UART or Ethernet. | High | High (Current) | Provide a fully compliant mock hardware server (`host/communication/mock_zedboard_server.py`) and standalone testbenches (`iverilog`) so software, dashboard, protocol, and RTL can be verified immediately offline. |
| **RSK-02** | Toolchain | **Vivado Not Installed on Workstation**: Local AMD Vivado license/installation is absent. | Medium | High (Current) | Use Icarus Verilog (`iverilog.exe` / `vvp.exe`) for simulation verification; generate clean, self-contained Vivado batch synthesis scripts (`scripts/run_vivado_synth.tcl`) for remote/lab execution. |
| **RSK-03** | Bandwidth | **8K Uncompressed Video Bandwidth**: Real-time 8K60 YUV420 (~24.88 GB/s) exceeds 1 GbE (~125 MB/s) by $27\times$. | Critical | 100% (Physical Fact) | Implement chunked offline file processing. Explicitly state that 8K processing is non-real-time. Never fabricate claims of real-time 8K uncompressed transfer over 1 GbE. |
| **RSK-04** | Algorithmic | **H.264 Stream Conformance**: Custom RTL generating non-compliant bitstreams fails in standard web browsers. | High | Medium | Constrain hardware encoder to H.264 Baseline Intra with valid SPS, PPS, and Slice headers; verify bitstreams directly with `cv2.VideoCapture` / FFmpeg decoder. |
| **RSK-05** | Resource | **RISC-V Soft CPU Consuming Excessive PL Resources**: A large 32-bit RISC-V core with cache could overwhelm the XC7Z020. | Medium | Medium | Keep RISC-V strictly on Track B (experimental research). Use an ultra-compact RV32I core (PicoRV32, ~1,500 LUTs) with tightly-coupled accelerator custom instructions (`VBLK`, `VSTART`), keeping ARM PS as Track A baseline. |
| **RSK-06** | Browser API | **Direct Browser-to-FPGA Hardware Access Restrictions**: Browsers restrict raw TCP/UDP sockets and direct hardware bus access. | High | 100% (Browser Fact) | Use a local Python host server acting as a bridge: Browser talks HTTP/WebSocket to `localhost`, Python daemon talks binary TCP to ZedBoard over Ethernet. |

---

## 2. Research Classification Audit on Prior Claims

- **CLAIM 1: "0-DSP Slices H.264/CAVLC"**  
  *Audit*: Multipliers can be implemented in LUTs (shift-and-add) or DSP48E1s. While a multiplierless 4x4 integer transform uses only shifts and adds, forcing 0 DSPs across the entire system unnecessarily wastes LUTs. DSP48s should be used where beneficial.
- **CLAIM 2: "1,357 LUT Total Utilization"**  
  *Audit*: Unverified estimate prior to actual synthesis of the complete pipeline (scaler + line buffers + transform + quantizer + CAVLC + AXI interfaces). Actual utilization must be reported only after synthesis.
- **CLAIM 3: "250 ns End-to-End Latency"**  
  *Audit*: Physical impossibility when including Ethernet serialization (~10-50 microseconds minimum per packet), TCP stack traversal, and frame buffering. Real latency is measured in milliseconds.
