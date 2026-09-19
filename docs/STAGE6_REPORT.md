# Stage 6 Engineering Report: Hardware Performance Monitoring & Profiling

## 1. Executive Summary
Stage 6 incorporates a dedicated, zero-overhead 32-bit hardware performance monitoring engine (`rtl/perf_monitor.v`, `rtl/stage6_pipeline_top.v`) into the video processing pipeline. It tracks execution metrics in real-time, providing deterministic cycle counts, active computation intervals, stall delays, pixel counts, inpainting events, and compressed NAL output tallies.

---

## 2. Performance Counter Register Structure

All counters are 32-bit saturating registers gated by `perf_enable`:

| Register Name | Byte Offset | Description |
| :--- | :---: | :--- |
| `SR_TOT_CYCLES` | `0x24` | Total elapsed clock cycles while `perf_enable == 1` |
| `SR_ACT_CYCLES` | `0x28` | Total cycles where pipeline valid inputs or PE active |
| `SR_STL_CYCLES` | `0x2C` | Total cycles where pipeline or memory stalled |
| `SR_PIXEL_CNT` | `0x30` | Cumulative count of valid streamed video pixels |
| `SR_INP_EVENTS` | `0x34` | Cumulative count of spatial inpainting replacements |
| `SR_NAL_CNT` | `0x38` | Cumulative count of 32-bit compressed NAL words emitted |

---

## 3. Simulation & Measurement Verification (`tb/tb_stage6_perf.sv`)

Simulation executed on a 32x16 raster stream with a 4x4 (16-pixel) central intruder object:

```
================================================================
   STAGE 6: PERFORMANCE MONITOR READOUT & AUDIT TESTBENCH
================================================================
[TEST 1] Verifying counters inactive when perf_enable=0... [PASS] total_cycles=0, pixel_count=0
[TEST 2] Verifying pixel_count matches streamed pixels... [PASS] pixel_count=512 (exp 512)
[TEST 3] Verifying inpaint_events counter... [PASS] inpaint_events=16 (exp 16)
[TEST 4] Verifying total_cycles > active_cycles... [PASS] total_cycles=553, active_cycles=512
[TEST 5] Verifying compressed NAL words emitted... [PASS] nal_word_count=32 (compressed bitstream generated)
[TEST 6] Checking hardware status LED indicators... [PASS] led_status[6]=1 (Perf Monitor active)
================================================================
   STAGE 6 TEST SUMMARY: 6 PASSED, 0 FAILED
   STATUS: ALL STAGE 6 TESTS PASSED SUCCESSFULLY!
================================================================
```

### Analysis:
- **Streaming Efficiency**: $\frac{\text{Active Cycles}}{\text{Total Cycles}} = \frac{512}{553} = 92.58\%$ utilization during burst streaming.
- **Inpainting Precision**: Exactly 16 inpainting events detected, corresponding to the 4x4 intruder region.
- **Compression Throughput**: 32 32-bit NAL words produced for 32 4x4 blocks.
