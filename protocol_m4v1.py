"""
==============================================================================
File: protocol_m4v1.py
Project: Model-4 Hardware H.264 Video Compression Accelerator (ZedBoard)
Specification: Fixed 64-byte big-endian M4V1 protocol for Host-Zynq communication
==============================================================================
"""

import struct
import zlib

MAGIC_M4V1 = b"M4V1"
PROTOCOL_VERSION = 1

# Message Types
MSG_JOB_BEGIN     = 1
MSG_FRAME_BEGIN   = 2
MSG_FRAME_DATA    = 3
MSG_FRAME_END     = 4
MSG_JOB_END       = 5
MSG_ACK           = 6
MSG_ERROR         = 7
MSG_OUTPUT_DATA   = 8
MSG_OUTPUT_END    = 9

# Output Profile IDs
PROFILE_144P      = 1  # 256x144 visible
PROFILE_240P      = 2  # 426x240 visible

# Scaler Filter IDs
FILTER_BILINEAR   = 1  # Fixed-point separable bilinear

# Aspect Policy IDs
ASPECT_CENTERED_BARS = 1  # Preserve aspect ratio with centered letterbox/pillarbox

# Color Range IDs
COLOR_RANGE_LIMITED = 1  # Limited/TV range (Y: 16..235, UV: 16..240, bar Y=16, UV=128)
COLOR_RANGE_FULL    = 2  # Full/PC range (Y: 0..255, UV: 0..255, bar Y=0, UV=128)

# Pixel Formats
PIXEL_FORMAT_I420 = 1

# 64-byte header format:
# magic: 4s (0)
# protocol_version: H (4)
# message_type: H (6)
# sequence_number: I (8)
# frame_id: I (12)
# width: I (16)
# height: I (20)
# pixel_format: H (24)
# flags: H (26)
# pts: Q (28)
# duration: I (36)
# payload_length: I (40)
# frame_total_bytes: I (44)
# payload_crc32: I (48)
# frame_crc32: I (52)
# timebase_num: I (56)
# timebase_den: I (60)
# Total = 64 bytes exactly
HEADER_STRUCT_FORMAT = "!4sHHIIIIHHQIIIIIII"
HEADER_SIZE = struct.calcsize(HEADER_STRUCT_FORMAT)
assert HEADER_SIZE == 64, f"Header size must be exactly 64 bytes, got {HEADER_SIZE}"

def crc32_iso_hdlc(data: bytes) -> int:
    """CRC-32/ISO-HDLC (reflected polynomial 0xEDB88320, init 0xFFFFFFFF, final XOR 0xFFFFFFFF)"""
    return zlib.crc32(data) & 0xFFFFFFFF

def derive_output_dimensions(profile_id: int):
    """Derive visible output dimensions from profile ID"""
    if profile_id == PROFILE_144P:
        return 256, 144
    elif profile_id == PROFILE_240P:
        return 426, 240
    else:
        raise ValueError(f"Unknown profile ID: {profile_id}. Must be 1 (144p) or 2 (240p).")

def pack_header(
    message_type: int,
    sequence_number: int = 0,
    frame_id: int = 0,
    width: int = 0,
    height: int = 0,
    pixel_format: int = PIXEL_FORMAT_I420,
    flags: int = 0,
    pts: int = 0,
    duration: int = 0,
    payload_length: int = 0,
    frame_total_bytes: int = 0,
    payload_crc32: int = 0,
    frame_crc32: int = 0,
    timebase_num: int = 1,
    timebase_den: int = 90000,
) -> bytes:
    return struct.pack(
        HEADER_STRUCT_FORMAT,
        MAGIC_M4V1,
        PROTOCOL_VERSION,
        message_type,
        sequence_number,
        frame_id,
        width,
        height,
        pixel_format,
        flags,
        pts,
        duration,
        payload_length,
        frame_total_bytes,
        payload_crc32,
        frame_crc32,
        timebase_num,
        timebase_den,
    )

def unpack_header(data: bytes):
    if len(data) != HEADER_SIZE:
        raise ValueError(f"Expected 64 bytes for header, got {len(data)}")
    fields = struct.unpack(HEADER_STRUCT_FORMAT, data)
    magic = fields[0]
    if magic != MAGIC_M4V1:
        raise ValueError(f"Invalid magic: {magic}, expected {MAGIC_M4V1}")
    return {
        "magic": fields[0],
        "protocol_version": fields[1],
        "message_type": fields[2],
        "sequence_number": fields[3],
        "frame_id": fields[4],
        "width": fields[5],
        "height": fields[6],
        "pixel_format": fields[7],
        "flags": fields[8],
        "pts": fields[9],
        "duration": fields[10],
        "payload_length": fields[11],
        "frame_total_bytes": fields[12],
        "payload_crc32": fields[13],
        "frame_crc32": fields[14],
        "timebase_num": fields[15],
        "timebase_den": fields[16],
    }

def pack_job_begin_payload(
    output_profile_id: int = PROFILE_240P,
    scaler_filter_id: int = FILTER_BILINEAR,
    aspect_policy_id: int = ASPECT_CENTERED_BARS,
    input_color_range_id: int = COLOR_RANGE_LIMITED,
) -> bytes:
    """16-byte payload for JOB_BEGIN: 4 big-endian uint32s"""
    return struct.pack("!IIII", output_profile_id, scaler_filter_id, aspect_policy_id, input_color_range_id)

def unpack_job_begin_payload(payload: bytes):
    if len(payload) != 16:
        raise ValueError(f"JOB_BEGIN payload must be exactly 16 bytes, got {len(payload)}")
    profile_id, filter_id, aspect_id, color_id = struct.unpack("!IIII", payload)
    out_w, out_h = derive_output_dimensions(profile_id)
    return {
        "output_profile_id": profile_id,
        "scaler_filter_id": filter_id,
        "aspect_policy_id": aspect_id,
        "input_color_range_id": color_id,
        "output_width": out_w,
        "output_height": out_h,
    }

def pack_job_begin_ack_payload(output_profile_id: int, output_width: int, output_height: int) -> bytes:
    """12-byte payload for JOB_BEGIN ACK: 3 big-endian uint32s"""
    return struct.pack("!III", output_profile_id, output_width, output_height)

def unpack_job_begin_ack_payload(payload: bytes):
    if len(payload) != 12:
        raise ValueError(f"JOB_BEGIN ACK payload must be exactly 12 bytes, got {len(payload)}")
    profile_id, out_w, out_h = struct.unpack("!III", payload)
    return {
        "output_profile_id": profile_id,
        "output_width": out_w,
        "output_height": out_h,
    }
