# Stage 7 Engineering Report: AXI4-Lite Slave & ACP Cache Coherency Interface

## 1. Executive Summary
Stage 7 provides the hardware interface bridging the ARM Cortex-A9 Processing System (PS) and the FPGA Programmable Logic (PL) accelerator core (`rtl/axi_lite_slave.v`, `rtl/axi_video_soc_v1_0.v`). It features an AXI4-Lite slave memory-mapped at base address `0x43C00000` alongside AXI ACP (Accelerator Coherency Port) sideband signals establishing hardware-enforced L2 cache coherency.

---

## 2. Register Map Specification (Base `0x43C00000`)

| Byte Offset | Register | Access | Bitfields / Description |
| :---: | :--- | :---: | :--- |
| `0x00` | `CR_CONTROL` | R/W | `[0]`: `reg_start` pulse; `[1]`: `soft_reset`; `[2]`: `perf_enable` |
| `0x04` | `CR_INSTRUCTION` | R/W | `[6:0]`: Opcode (`0x0B`); `[14:12]`: `funct3` (`0..4`); `[31:15]`: Reserved |
| `0x08` | `CR_RS1_DATA` | R/W | `[31:0]`: Base source buffer address in host DDR memory |
| `0x0C` | `CR_CONFIG` | R/W | `[5:0]`: Quantization Parameter `QP` (0–51); `[15:8]`: Threshold `t_thresh` |
| `0x10` | `CR_PIXEL_IN` | R/W | `[7:0]`: R; `[15:8]`: G; `[23:16]`: B; `[31]`: `pixel_valid` pulse |
| `0x14` | `CR_Y_BG` | R/W | `[7:0]`: Background reference luminance sample |
| `0x18` | `SR_STATUS` | RO | `[0]`: `pe_busy`; `[1]`: `nal_valid`; `[2]`: `inpaint_active`; `[3]`: `fg_mask` |
| `0x1C` | `SR_Y_INPAINTED` | RO | `[7:0]`: Real-time inpainted luminance output |
| `0x20` | `SR_NAL_WORD` | RO | `[31:0]`: 32-bit compressed H.264 NAL word |
| `0x24` | `SR_TOT_CYCLES` | RO | `[31:0]`: Elapsed performance clock cycles |
| `0x28` | `SR_ACT_CYCLES` | RO | `[31:0]`: Active compute cycles |
| `0x2C` | `SR_STL_CYCLES` | RO | `[31:0]`: Pipeline stall cycles |
| `0x30` | `SR_PIXEL_CNT` | RO | `[31:0]`: Processed pixels counter |
| `0x34` | `SR_INP_EVENTS` | RO | `[31:0]`: Inpainted pixels counter |
| `0x38` | `SR_NAL_CNT` | RO | `[31:0]`: Emitted compressed NAL words |

---

## 3. ACP Cache Coherency Sideband Configuration

Connecting the accelerator to the Zynq-7000 SCU (Snoop Control Unit) via the 64-bit ACP interface eliminates software cache flushes and invalidations:
- `m_axi_acp_aruser[4:0] = 5'b11111` (Read transaction Inner Shareable, Cacheable)
- `m_axi_acp_awuser[4:0] = 5'b11111` (Write transaction Inner Shareable, Cacheable)
- `m_axi_acp_arcache[3:0] = 4'b1111` (Write-Back, Read & Write Allocate)
- `m_axi_acp_awcache[3:0] = 4'b1111` (Write-Back, Read & Write Allocate)

---

## 4. Verification Results (`tb/tb_stage7_axi.sv`)

```
================================================================
   STAGE 7: AXI4-LITE BUS PROTOCOL & ACP COHERENCY TESTBENCH
================================================================
[TEST 1] Verifying ACP Coherency Sidebands (ARUSER=5'h1F, ARCACHE=4'hF)... [PASS] ARUSER=11111, ARCACHE=1111, AWUSER=11111, AWCACHE=1111
[TEST 2] AXI Write and Read-back on CR_CONFIG (Offset 0x0C)... [PASS] rd_data=0x00002d18 (QP=24, Thresh=45)
[TEST 3] AXI Write & Read-back on CR_INSTRUCTION (Offset 0x04)... [PASS] rd_data=0x0000200b (Custom RISC-V V_INPAINT)
[TEST 4] AXI Write CR_CONTROL perf_enable=1 (Offset 0x00)... [PASS] CR_CONTROL=0x00000004 (perf_enable asserted)
[TEST 5] AXI Stream Pixel Transaction via CR_PIXEL_IN... [PASS] Total cycles counter incremented via AXI: 21
[TEST 6] AXI Read SR_STATUS (Offset 0x18)... [PASS] SR_STATUS=0x00000000 (Bus responder valid)
================================================================
   STAGE 7 TEST SUMMARY: 6 PASSED, 0 FAILED
   STATUS: ALL STAGE 7 TESTS PASSED SUCCESSFULLY!
================================================================
```
