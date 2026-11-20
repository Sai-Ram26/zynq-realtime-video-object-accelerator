#!/usr/bin/env python3
"""
Test script for H.264 Baseline IDR bitstream generation and verification.
Tests both 144p (256x144) and 240p (426x240) profile syntax.
Verifies with OpenCV VideoCapture.
"""

import sys
import os
import cv2
import numpy as np

def ue(val):
    val_plus_1 = val + 1
    bits = bin(val_plus_1)[2:]
    return '0' * (len(bits) - 1) + bits

def se(val):
    if val <= 0:
        return ue(-2 * val)
    else:
        return ue(2 * val - 1)

def bits_to_bytes(bitstr):
    # Pad to byte boundary with rbsp_trailing_bits: '1' then '0's
    bitstr += '1'
    if len(bitstr) % 8 != 0:
        bitstr += '0' * (8 - (len(bitstr) % 8))
    raw = bytearray()
    for i in range(0, len(bitstr), 8):
        raw.append(int(bitstr[i:i+8], 2))
    
    # Emulation prevention (insert 0x03 after 0x00 0x00 if next byte <= 0x03)
    ebsp = bytearray()
    zero_cnt = 0
    for b in raw:
        if zero_cnt >= 2 and b <= 3:
            ebsp.append(3)
            zero_cnt = 0
        ebsp.append(b)
        if b == 0:
            zero_cnt += 1
        else:
            zero_cnt = 0
    return bytes(ebsp)

def build_sps(width, height, crop_right=0):
    # NAL header: forbidden_zero_bit=0, nal_ref_idc=3, nal_unit_type=7 -> 0x67
    mb_w = (width + 15) // 16
    mb_h = (height + 15) // 16
    
    # SPS syntax for Constrained Baseline Profile
    b = ""
    # profile_idc = 66 (Baseline)
    b += f"{66:08b}"
    # constraint_set0..5_flag (1,1,0,0,0,0), reserved_zero_2bits = 00 -> 0xC0
    b += "11000000"
    # level_idc = 30 (supports 720x480 / 720x576)
    b += f"{30:08b}"
    # seq_parameter_set_id = 0
    b += ue(0)
    # log2_max_frame_num_minus4 = 0 (frame_num uses 4 bits)
    b += ue(0)
    # pic_order_cnt_type = 0
    b += ue(0)
    # log2_max_pic_order_cnt_lsb_minus4 = 0 (POC uses 4 bits)
    b += ue(0)
    # max_num_ref_frames = 1
    b += ue(1)
    # gaps_in_frame_num_value_allowed_flag = 0
    b += "0"
    # pic_width_in_mbs_minus1
    b += ue(mb_w - 1)
    # pic_height_in_map_units_minus1
    b += ue(mb_h - 1)
    # frame_mbs_only_flag = 1
    b += "1"
    # direct_8x8_inference_flag = 0
    b += "0"
    # frame_cropping_flag
    if crop_right > 0:
        b += "1"
        b += ue(0)           # crop_left
        b += ue(crop_right)  # crop_right
        b += ue(0)           # crop_top
        b += ue(0)           # crop_bottom
    else:
        b += "0"
    # vui_parameters_present_flag = 0
    b += "0"
    
    ebsp = bits_to_bytes(b)
    return b"\x00\x00\x00\x01\x67" + ebsp

def build_pps():
    # NAL header: 0x68 (type 8, nal_ref_idc 3)
    b = ""
    # pic_parameter_set_id = 0
    b += ue(0)
    # seq_parameter_set_id = 0
    b += ue(0)
    # entropy_coding_mode_flag = 0 (CAVLC)
    b += "0"
    # bottom_field_pic_order_in_frame_present_flag = 0
    b += "0"
    # num_slice_groups_minus1 = 0
    b += ue(0)
    # num_ref_idx_l0_default_active_minus1 = 0
    b += ue(0)
    # num_ref_idx_l1_default_active_minus1 = 0
    b += ue(0)
    # weighted_pred_flag = 0
    b += "0"
    # weighted_bipred_idc = 0
    b += "00"
    # pic_init_qp_minus26 = 0 (QP=26 baseline)
    b += se(0)
    # pic_init_qs_minus26 = 0
    b += se(0)
    # chroma_qp_index_offset = 0
    b += se(0)
    # deblocking_filter_control_present_flag = 1
    b += "1"
    # constrained_intra_pred_flag = 0
    b += "0"
    # redundant_pic_cnt_present_flag = 0
    b += "0"
    
    ebsp = bits_to_bytes(b)
    return b"\x00\x00\x00\x01\x68" + ebsp

def build_idr_slice(mb_w, mb_h, mb_modes=None):
    # NAL header: 0x65 (type 5, nal_ref_idc 3)
    b = ""
    # first_mb_in_slice = 0
    b += ue(0)
    # slice_type = 7 (all slices in picture are I-slice, 7 or 2)
    b += ue(7)
    # pic_parameter_set_id = 0
    b += ue(0)
    # frame_num = 0 (4 bits)
    b += f"{0:04b}"
    # idr_pic_id = 0
    b += ue(0)
    # pic_order_cnt_lsb = 0 (4 bits)
    b += f"{0:04b}"
    # no_output_of_prior_pics_flag = 0
    b += "0"
    # long_term_reference_flag = 0
    b += "0"
    # slice_qp_delta = 0
    b += se(0)
    # disable_deblocking_filter_idc = 0
    b += ue(0)
    # slice_alpha_c0_offset_div2 = 0
    b += se(0)
    # slice_beta_offset_div2 = 0
    b += se(0)

    total_mbs = mb_w * mb_h
    for mb_idx in range(total_mbs):
        row = mb_idx // mb_w
        col = mb_idx % mb_w
        # Safe intra mode based on neighbor availability:
        if row == 0 and col == 0:
            mode = 2 # DC only
        elif row == 0:
            mode = 1 # Horizontal (uses left)
        elif col == 0:
            mode = 0 # Vertical (uses top)
        else:
            mode = (row + col) % 3

        mb_type = 1 + (mode & 3)
        b += ue(mb_type)
        # H.264 clause 7.3.5: intra_chroma_pred_mode is required for all Intra MBs
        # 0 = DC chroma mode (always legal regardless of neighbors)
        b += ue(0)

    ebsp = bits_to_bytes(b)
    return b"\x00\x00\x00\x01\x65" + ebsp

def test_profile(name, width, height, crop_right=0):
    print(f"\n[*] Testing Profile {name}: {width}x{height} (crop_right={crop_right})")
    sps = build_sps(width, height, crop_right)
    pps = build_pps()
    mb_w = (width + 15) // 16
    mb_h = (height + 15) // 16
    
    # Generate test pattern of modes: DC, Horiz, Vert
    modes = []
    for row in range(mb_h):
        for col in range(mb_w):
            if row == 0 and col == 0:
                modes.append(2) # DC
            elif row == 0:
                modes.append(1) # Horiz
            elif col == 0:
                modes.append(0) # Vert
            else:
                modes.append((row + col) % 3)
    
    slice_data = build_idr_slice(mb_w, mb_h, modes)
    stream = sps + pps + slice_data
    
    test_file = f"test_{name}.h264"
    with open(test_file, "wb") as f:
        f.write(stream)
    
    print(f"    Bitstream size: {len(stream)} bytes (SPS={len(sps)}, PPS={len(pps)}, Slice={len(slice_data)})")
    
    # Verify with cv2.VideoCapture
    cap = cv2.VideoCapture(test_file)
    if not cap.isOpened():
        print(f"    [FAIL] OpenCV failed to open {test_file}")
        return False
    
    ret, frame = cap.read()
    cap.release()
    if not ret or frame is None:
        print(f"    [FAIL] OpenCV failed to decode frame from {test_file}")
        return False
    
    dec_h, dec_w = frame.shape[:2]
    expected_w = width - (crop_right * 2)
    expected_h = height
    print(f"    [PASS] Decoded successfully! Output shape: {dec_w}x{dec_h} (Expected {expected_w}x{expected_h})")
    
    if os.path.exists(test_file):
        os.remove(test_file)
    return True

if __name__ == "__main__":
    pass_144p = test_profile("144p", 256, 144, 0)
    pass_240p = test_profile("240p", 432, 240, 3) # 432 coded with crop_right=3 gives 426x240!
    
    if pass_144p and pass_240p:
        print("\n=======================================================")
        print("  ALL PROFILES DECODED SUCCESSFULLY WITH OPENCV / H.264!")
        print("=======================================================")
        sys.exit(0)
    else:
        print("\n[ERROR] Verification failed.")
        sys.exit(1)
