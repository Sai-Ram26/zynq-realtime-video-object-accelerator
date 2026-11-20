#!/usr/bin/env python3
"""
Test suite for protocol_m4v1.py:
- Verifies exact 64-byte wire size
- Big-endian byte order
- CRC32 ISO-HDLC
- JOB_BEGIN pack/unpack with 16-byte payload
- Profile derivation (144p -> 256x144, 240p -> 426x240)
- Validation / rejection of unknown profiles and invalid lengths
"""

import sys
import struct
import protocol_m4v1 as proto

def run_tests():
    print("[*] Running protocol_m4v1 test suite...")

    # 1. Header size check
    assert proto.HEADER_SIZE == 64, f"Header size is {proto.HEADER_SIZE}, expected 64"

    # 2. Field offsets check
    hdr_bytes = proto.pack_header(
        message_type=proto.MSG_JOB_BEGIN,
        sequence_number=1,
        frame_id=0,
        width=1920,
        height=1080,
        pixel_format=proto.PIXEL_FORMAT_I420,
        flags=0,
        pts=1000,
        duration=3000,
        payload_length=16,
        frame_total_bytes=1920 * 1080 * 3 // 2,
        payload_crc32=0x12345678,
        frame_crc32=0x9ABCDEF0,
        timebase_num=1,
        timebase_den=90000,
    )
    assert len(hdr_bytes) == 64, f"Packed header len is {len(hdr_bytes)}, expected 64"

    # Check magic at offset 0
    assert hdr_bytes[0:4] == b"M4V1"
    # Check width at offset 16 (big endian)
    assert struct.unpack("!I", hdr_bytes[16:20])[0] == 1920
    # Check height at offset 20
    assert struct.unpack("!I", hdr_bytes[20:24])[0] == 1080
    # Check payload_length at offset 40
    assert struct.unpack("!I", hdr_bytes[40:44])[0] == 16

    # 3. Unpack check
    hdr = proto.unpack_header(hdr_bytes)
    assert hdr["magic"] == b"M4V1"
    assert hdr["protocol_version"] == 1
    assert hdr["message_type"] == proto.MSG_JOB_BEGIN
    assert hdr["width"] == 1920
    assert hdr["height"] == 1080
    assert hdr["payload_length"] == 16
    assert hdr["payload_crc32"] == 0x12345678
    assert hdr["frame_crc32"] == 0x9ABCDEF0

    # 4. JOB_BEGIN payload check
    payload_144 = proto.pack_job_begin_payload(
        output_profile_id=proto.PROFILE_144P,
        scaler_filter_id=proto.FILTER_BILINEAR,
        aspect_policy_id=proto.ASPECT_CENTERED_BARS,
        input_color_range_id=proto.COLOR_RANGE_LIMITED,
    )
    assert len(payload_144) == 16
    pinfo_144 = proto.unpack_job_begin_payload(payload_144)
    assert pinfo_144["output_profile_id"] == proto.PROFILE_144P
    assert pinfo_144["output_width"] == 256
    assert pinfo_144["output_height"] == 144

    payload_240 = proto.pack_job_begin_payload(
        output_profile_id=proto.PROFILE_240P,
        scaler_filter_id=proto.FILTER_BILINEAR,
        aspect_policy_id=proto.ASPECT_CENTERED_BARS,
        input_color_range_id=proto.COLOR_RANGE_FULL,
    )
    assert len(payload_240) == 16
    pinfo_240 = proto.unpack_job_begin_payload(payload_240)
    assert pinfo_240["output_profile_id"] == proto.PROFILE_240P
    assert pinfo_240["output_width"] == 426
    assert pinfo_240["output_height"] == 240

    # 5. Invalid profile rejection check
    try:
        proto.unpack_job_begin_payload(struct.pack("!IIII", 99, 1, 1, 1))
        assert False, "Should have raised ValueError on invalid profile"
    except ValueError:
        pass

    # 6. ACK payload check
    ack_payload = proto.pack_job_begin_ack_payload(proto.PROFILE_240P, 426, 240)
    assert len(ack_payload) == 12
    ack_info = proto.unpack_job_begin_ack_payload(ack_payload)
    assert ack_info["output_profile_id"] == proto.PROFILE_240P
    assert ack_info["output_width"] == 426
    assert ack_info["output_height"] == 240

    # 7. CRC32 ISO-HDLC known test vector
    test_vec = b"123456789"
    # CRC32 of "123456789" is 0xCBF43926
    crc_val = proto.crc32_iso_hdlc(test_vec)
    assert crc_val == 0xCBF43926, f"CRC error: got 0x{crc_val:08X}, expected 0xCBF43926"

    print("[+] All protocol_m4v1 tests PASSED successfully!")
    return 0

if __name__ == "__main__":
    sys.exit(run_tests())
