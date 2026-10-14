# Benchmark Methodology & Experimental Measurement Protocol

**Measurement Standard:** Empirical, non-fabricated hardware & software profiling  
**Artifact Directory:** `results/`

---

## 1. Measured Experimental Metrics

To ensure scientific defensibility, every performance claim is backed by actual measurements logged by automated benchmarking scripts:

| Metric Name | Measurement Tool / Source | Unit | Formula / Method |
| :--- | :--- | :--- | :--- |
| **Transfer Throughput** | Python Socket Timer / Wireshark | MB/s | $\text{Payload Bytes} / \Delta t_{\text{transfer}}$ |
| **FPGA Processing FPS** | Hardware Performance Counter Register | Frames/sec | $f_{\text{clk}} / \text{Clock Cycles per Frame}$ |
| **End-to-End Latency** | Host High-Resolution Timestamp | Milliseconds | $t_{\text{display\_ready}} - t_{\text{frame\_sent}}$ |
| **Peak Signal-to-Noise (PSNR)** | OpenCV / NumPy Image Comparator | dB | $10 \cdot \log_{10}(255^2 / \text{MSE})$ |
| **Structural Similarity (SSIM)** | SciPy / Scikit-Image Model | Index (0..1) | Wang et al. 2004 formulation |
| **Spatial Resolution Ratio** | Dimension Calculator | Ratio ($X\times$) | $(W_{\text{in}} \cdot H_{\text{in}}) / (W_{\text{out}} \cdot H_{\text{out}})$ |
| **Codec Compression Ratio** | File Size Comparator | Ratio ($X\times$) | $\text{Raw YUV Size} / \text{Compressed Bitstream Size}$ |
| **Overall Storage Reduction** | End-to-End Size Ratio | Ratio ($X\times$) | $\text{Input File Size} / \text{Output File Size}$ |

---

## 2. Experimental Data Table Format

```
+---------------------------------------------------------------------------------------------------------+
| Test Case | Input Res | Output Res | Decim. | Output Size | PSNR (dB) | SSIM  | FPGA Time | FPS (Meas.) |
+-----------+-----------+------------+--------+-------------+-----------+-------+-----------+-------------+
| TM-01     | 720p      | 240p       | 9.0x   | Logged      | Logged    | Logged| Logged    | Logged      |
| TM-02     | 720p      | 144p       | 25.0x  | Logged      | Logged    | Logged| Logged    | Logged      |
| TM-03     | 1080p     | 240p       | 20.3x  | Logged      | Logged    | Logged| Logged    | Logged      |
| TM-04     | 1080p     | 144p       | 56.2x  | Logged      | Logged    | Logged| Logged    | Logged      |
| TM-05     | 4K UHD    | 240p       | 81.1x  | Logged      | Logged    | Logged| Logged    | Logged      |
| TM-06     | 4K UHD    | 144p       | 225.0x | Logged      | Logged    | Logged| Logged    | Logged      |
| TM-07     | 8K UHD    | 240p       | 324.5x | Logged      | Logged    | Logged| Logged    | Logged      |
| TM-08     | 8K UHD    | 144p       | 900.0x | Logged      | Logged    | Logged| Logged    | Logged      |
+---------------------------------------------------------------------------------------------------------+
```

---

## 3. Automated Benchmark Execution

The benchmark script `host/tests/benchmark_suite.py` iterates across test videos at all 8 matrix configurations, executing the full pipeline against both the software golden reference and the FPGA hardware (or mock server), automatically writing structured CSV and JSON outputs to `results/benchmark_results.json`.
