"""
sim/golden_reference.py
=======================
Project: High-Efficiency Zynq SoC Video Accelerator Architecture
Description: Cycle-Exact Python Golden Reference Model.
             Covers all 5 hardware processing stages:
               Stage 1: RGB888 -> YUV420 Color Conversion
               Stage 2: Temporal Background Subtraction & Mask Generation
               Stage 3: Spatial 8x8 Inpainting
               Stage 4: 4x4 Integer DCT + Quantization
               Stage 5: CAVLC Entropy Encoding Header Analysis
             Used by sim_runner.py to validate RTL correctness.
"""

import numpy as np
import os

# ---------------------------------------------------------------------------
# Stage 1: Fixed-Point RGB888 -> YUV420 Color Converter
# ---------------------------------------------------------------------------
def rgb2yuv_golden(r, g, b):
    """Bit-accurate fixed-point RGB->YUV as implemented in rgb2yuv.v (shift-add)."""
    y = int(np.clip((77 * int(r) + 150 * int(g) + 29 * int(b)) >> 8, 0, 255))
    u = int(np.clip((-43 * int(r) - 85 * int(g) + 128 * int(b) + 32768) >> 8, 0, 255))
    v = int(np.clip((128 * int(r) - 107 * int(g) - 21 * int(b) + 32768) >> 8, 0, 255))
    return y, u, v

# ---------------------------------------------------------------------------
# Stage 2: Temporal Background Subtraction & Motion Mask Generator
# ---------------------------------------------------------------------------
def bg_sub_golden(y_curr, y_bg, t_thresh):
    """Bit-accurate temporal frame subtraction as implemented in bg_sub.v."""
    diff = abs(int(y_curr) - int(y_bg))
    mask = 1 if diff > int(t_thresh) else 0
    return diff, mask

# ---------------------------------------------------------------------------
# Stage 3: Spatial 8x8 Line-Buffered Inpainting Engine
# ---------------------------------------------------------------------------
def inpaint_8x8_golden(y_frame, mask_frame, line_width):
    """
    8x8 sliding window spatial inpainting golden model.
    For each pixel where mask=1, replace with average of unmasked 8x8 neighbors.
    """
    rows, cols = y_frame.shape
    y_out = y_frame.copy().astype(np.int32)
    inpaint_count = 0
    for r in range(rows):
        for c in range(cols):
            if mask_frame[r, c] == 1:
                # 8x8 window centered at (r, c)
                r0, r1 = max(0, r - 3), min(rows, r + 5)
                c0, c1 = max(0, c - 3), min(cols, c + 5)
                window_y    = y_frame[r0:r1, c0:c1]
                window_mask = mask_frame[r0:r1, c0:c1]
                unmasked = window_y[window_mask == 0]
                if len(unmasked) > 0:
                    y_out[r, c] = int(np.mean(unmasked))
                    inpaint_count += 1
    return y_out.astype(np.uint8), inpaint_count

# ---------------------------------------------------------------------------
# Stage 4: 4x4 Integer DCT + Quantization
# ---------------------------------------------------------------------------
H_DCT = np.array([
    [1,  1,  1,  1],
    [2,  1, -1, -2],
    [1, -1, -1,  1],
    [1, -2,  2, -1]
], dtype=np.int32)

def dct4x4_golden(block_4x4):
    """H.264 4x4 Integer DCT: Cf = H * X * H^T"""
    X = block_4x4.astype(np.int32)
    return (H_DCT @ X @ H_DCT.T).astype(np.int32)

def quantize_golden(dct_block, qp):
    """QP-based shift quantization: Z = sign(C) * (|C| >> qshift)."""
    qshift = (qp >> 1) + 2
    result = np.zeros_like(dct_block)
    for r in range(4):
        for c in range(4):
            v = int(dct_block[r, c])
            if v >= 0:
                result[r, c] = v >> qshift
            else:
                result[r, c] = -((-v) >> qshift)
    return result.astype(np.int32)

# ---------------------------------------------------------------------------
# Stage 5: CAVLC Syntax Element Analysis
# ---------------------------------------------------------------------------
ZIG_ZAG_ORDER = [
    (0,0),(0,1),(1,0),(2,0),(1,1),(0,2),(0,3),(1,2),
    (2,1),(3,0),(3,1),(2,2),(1,3),(2,3),(3,2),(3,3)
]

def cavlc_stats_golden(quant_block):
    """Compute TotalCoeff and TrailingOnes from quantized 4x4 block."""
    zig_zag = [int(quant_block[r, c]) for r, c in ZIG_ZAG_ORDER]
    total_coeff = sum(1 for x in zig_zag if x != 0)
    trailing_ones = 0
    for x in reversed(zig_zag):
        if x == 0:
            continue
        if x == 1 or x == -1:
            trailing_ones = min(trailing_ones + 1, 3)
        else:
            break
    return total_coeff, trailing_ones

# ---------------------------------------------------------------------------
# Self-Test: Verify golden model against known expected outputs
# ---------------------------------------------------------------------------
def run_self_tests():
    """Run golden model self-tests and print results."""
    pass_count = 0
    fail_count = 0
    print("=" * 60)
    print("[GOLDEN REFERENCE MODEL] Self-Test Suite")
    print("=" * 60)

    # Test 1: RGB->YUV Pure Red
    y, u, v = rgb2yuv_golden(255, 0, 0)
    label = "Pure Red RGB->YUV"
    if y == 76:
        print(f"[PASS] {label}: Y={y} (exp 76)")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: Y={y} (exp 76)")
        fail_count += 1

    # Test 2: RGB->YUV Pure White
    y, u, v = rgb2yuv_golden(255, 255, 255)
    label = "Pure White RGB->YUV"
    if y == 255:
        print(f"[PASS] {label}: Y={y} (exp 255)")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: Y={y} (exp 255)")
        fail_count += 1

    # Test 3: BgSub Background Match
    diff, mask = bg_sub_golden(76, 77, 30)
    label = "BgSub Background Match"
    if diff == 1 and mask == 0:
        print(f"[PASS] {label}: diff={diff} mask={mask}")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: diff={diff} mask={mask} (exp diff=1 mask=0)")
        fail_count += 1

    # Test 4: BgSub Intruder Detection
    diff, mask = bg_sub_golden(255, 77, 30)
    label = "BgSub Intruder Detection"
    if diff == 178 and mask == 1:
        print(f"[PASS] {label}: diff={diff} mask={mask}")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: diff={diff} mask={mask} (exp diff=178 mask=1)")
        fail_count += 1

    # Test 5: 4x4 DCT on flat block (all-100) -> DC = 1600, AC = 0
    flat = np.full((4, 4), 100, dtype=np.int32)
    dct = dct4x4_golden(flat)
    label = "DCT Flat Block (all=100)"
    if dct[0, 0] == 1600 and np.all(dct[1:, :] == 0) and np.all(dct[:, 1:] == 0):
        print(f"[PASS] {label}: DC={dct[0,0]} (exp 1600), all AC=0")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: DC={dct[0,0]} (exp 1600), AC non-zero detected")
        fail_count += 1

    # Test 6: 4x4 DCT Zero Block -> all zeros
    zero = np.zeros((4, 4), dtype=np.int32)
    dct = dct4x4_golden(zero)
    label = "DCT Zero Block"
    if np.all(dct == 0):
        print(f"[PASS] {label}: all coefficients = 0")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: non-zero coefficients in zero block")
        fail_count += 1

    # Test 7: Quantize QP=10 on all-400 DC-only block
    dc_block = np.zeros((4, 4), dtype=np.int32)
    dc_block[0, 0] = 400
    qblock = quantize_golden(dc_block, qp=10)
    label = "Quantize QP=10 DC=400"
    exp_dc = 400 >> ((10 >> 1) + 2)  # = 400 >> 7 = 3
    if qblock[0, 0] == exp_dc:
        print(f"[PASS] {label}: Q_DC={qblock[0,0]} (exp {exp_dc})")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: Q_DC={qblock[0,0]} (exp {exp_dc})")
        fail_count += 1

    # Test 8: CAVLC stats on zero block
    zero_q = np.zeros((4, 4), dtype=np.int32)
    tc, t1 = cavlc_stats_golden(zero_q)
    label = "CAVLC Zero Block Stats"
    if tc == 0 and t1 == 0:
        print(f"[PASS] {label}: total_coeff={tc} trailing_ones={t1}")
        pass_count += 1
    else:
        print(f"[FAIL] {label}: total_coeff={tc} trailing_ones={t1} (exp 0, 0)")
        fail_count += 1

    print("=" * 60)
    print(f"[GOLDEN MODEL SUMMARY] PASSED: {pass_count}  FAILED: {fail_count}")
    print(f"STATUS: {'ALL TESTS PASSED' if fail_count == 0 else 'SOME TESTS FAILED'}")
    print("=" * 60)
    return pass_count, fail_count

if __name__ == "__main__":
    run_self_tests()
