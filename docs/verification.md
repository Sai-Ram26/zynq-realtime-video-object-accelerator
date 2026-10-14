# Verification Strategy & Test Matrix Specification

**Verification Level:** Rigorous Multi-Tier Simulation & Hardware-Software Co-Verification  
**Primary Simulator:** Icarus Verilog (`iverilog.exe` v12) + Python 3.11 Golden Reference

---

## 1. Verification Strategy

Every major RTL module requires independent, self-checking testbenches before system integration.

```
                      +-----------------------------+
                      |   Source Video / Test Data  |
                      +--------------+--------------+
                                     |
                    +----------------+----------------+
                    |                                 |
                    v                                 v
        +-----------------------+         +-----------------------+
        |  Python Golden Model  |         |   Verilog Simulation  |
        |  (Bit-Accurate Math)  |         |  (Icarus Verilog vvp) |
        +-----------+-----------+         +-----------+-----------+
                    |                                 |
                    +----------------+----------------+
                                     |
                                     v
                        +-------------------------+
                        | Bit-Accurate Comparator |
                        | - Zero Pixel Delta      |
                        | - Valid NAL Syntax      |
                        | - PSNR / SSIM Score     |
                        +-------------------------+
```

---

## 2. Eight-Primary Resolution Test Matrix

The system must successfully verify the 8 primary resolution conversion combinations:

| Test ID | Input Resolution | Input Frame Size | Output Resolution | Output Frame Size | Decimation Factor | Verification Goal |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TM-01** | **720p** ($1280 \times 720$) | 1.38 MB (YUV) | **240p** ($426 \times 240$) | 153.3 KB (YUV) | $9.0\times$ | Standard downscaling, valid H.264 stream |
| **TM-02** | **720p** ($1280 \times 720$) | 1.38 MB (YUV) | **144p** ($256 \times 144$) | 55.3 KB (YUV) | $25.0\times$ | Extreme downscaling, valid H.264 stream |
| **TM-03** | **1080p** ($1920 \times 1080$) | 3.11 MB (YUV) | **240p** ($426 \times 240$) | 153.3 KB (YUV) | $20.3\times$ | High-definition input scaling |
| **TM-04** | **1080p** ($1920 \times 1080$) | 3.11 MB (YUV) | **144p** ($256 \times 144$) | 55.3 KB (YUV) | $56.2\times$ | Ultra-low bitrate generation |
| **TM-05** | **4K UHD** ($3840 \times 2160$) | 12.44 MB (YUV) | **240p** ($426 \times 240$) | 153.3 KB (YUV) | $81.1\times$ | Ultra HD frame chunking and processing |
| **TM-06** | **4K UHD** ($3840 \times 2160$) | 12.44 MB (YUV) | **144p** ($256 \times 144$) | 55.3 KB (YUV) | $225.0\times$ | 4K thumbnail stream creation |
| **TM-07** | **8K UHD** ($7680 \times 4320$) | 49.77 MB (YUV) | **240p** ($426 \times 240$) | 153.3 KB (YUV) | $324.5\times$ | Offline tile/chunk processing verified |
| **TM-08** | **8K UHD** ($7680 \times 4320$) | 49.77 MB (YUV) | **144p** ($256 \times 144$) | 55.3 KB (YUV) | $900.0\times$ | Maximum spatial compression benchmark |

---

## 3. Mandatory RTL Verification Checklist

For each module in `fpga/rtl/`:
1. **Reset Behavior**: Verify all registers reset synchronously to zero upon `rst_n == 0`.
2. **Backpressure**: Verify data does not drop when downstream slave deasserts `ready` (`valid` held high).
3. **Corner Cases**: All-black frames (value 0), all-white frames (value 255), and alternating checkerboard patterns.
4. **Data Integrity**: Verify CRC32 matches on all transmitted and received packets.
