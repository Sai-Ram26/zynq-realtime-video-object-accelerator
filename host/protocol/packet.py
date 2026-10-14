"""
Binary Packet Protocol Implementation for FPGA Video Accelerator
Matches docs/protocol.md specification
"""
import struct
import zlib

MAGIC = 0x5A595641  # 'ZYVA'
PROTOCOL_VERSION = 1

# Packet Types
CMD_PING        = 0x01
RSP_PONG        = 0x02
CMD_CONFIG      = 0x03
RSP_CONFIG_ACK  = 0x04
DATA_FRAME_IN   = 0x05
DATA_FRAME_OUT  = 0x06
CMD_STATUS      = 0x07
RSP_STATUS      = 0x08
CMD_RESET       = 0x09
RSP_ERROR       = 0xFF

# Pixel Formats
FMT_RGB888      = 0x0001
FMT_YUV420      = 0x0002
FMT_H264_NAL    = 0x0003

# Flags
FLAG_EOF        = 0x0001
FLAG_LAST_TILE  = 0x0002
FLAG_ERROR      = 0x0004

# Header format: Big-Endian (>):
# I = uint32 (4) - MAGIC
# B = uint8  (1) - VERSION
# B = uint8  (1) - PACKET_TYPE
# H = uint16 (2) - FLAGS
# I = uint32 (4) - SEQ_NUM
# H = uint16 (2) - FRAME_ID
# H = uint16 (2) - TILE_ID
# H = uint16 (2) - WIDTH
# H = uint16 (2) - HEIGHT
# H = uint16 (2) - PIXEL_FORMAT
# H = uint16 (2) - QP_RESERVED
# I = uint32 (4) - PAYLOAD_LEN
# Total = 4 + 1 + 1 + 2 + 4 + 2 + 2 + 2 + 2 + 2 + 2 + 4 = 28 bytes? Wait!
# Let's count bytes:
# Offset 0x00: MAGIC (4)
# Offset 0x04: VERSION (1)
# Offset 0x05: PACKET_TYPE (1)
# Offset 0x06: FLAGS (2)
# Offset 0x08: SEQ_NUM (4)
# Offset 0x0C: FRAME_ID (2)
# Offset 0x0E: TILE_ID (2)
# Offset 0x10: WIDTH (2)
# Offset 0x12: HEIGHT (2)
# Offset 0x14: PIXEL_FORMAT (2)
# Offset 0x16: QP_RESERVED (2)
# Offset 0x18: PAYLOAD_LEN (4) -> ends at 0x1C (28 bytes)
# Let's add 4 reserved bytes at 0x1C to make header exactly 32 bytes aligned:
# Offset 0x1C: RESERVED_ALIGN (4)
HEADER_STRUCT = ">IBBHIHHHHHHII"
HEADER_SIZE = struct.calcsize(HEADER_STRUCT)  # exactly 32 bytes

assert HEADER_SIZE == 32, f"Header size must be 32 bytes, got {HEADER_SIZE}"


class VideoPacket:
    def __init__(self, packet_type, payload=b"", flags=0, seq_num=0,
                 frame_id=0, tile_id=0, width=0, height=0,
                 pixel_format=FMT_YUV420, qp=28):
        self.magic = MAGIC
        self.version = PROTOCOL_VERSION
        self.packet_type = packet_type
        self.flags = flags
        self.seq_num = seq_num
        self.frame_id = frame_id
        self.tile_id = tile_id
        self.width = width
        self.height = height
        self.pixel_format = pixel_format
        self.qp = qp
        self.payload = payload if isinstance(payload, bytes) else bytes(payload)
        self.payload_len = len(self.payload)

    def pack(self) -> bytes:
        """Serializes header + payload + 4-byte CRC32 trailer."""
        header = struct.pack(
            HEADER_STRUCT,
            self.magic,
            self.version,
            self.packet_type,
            self.flags,
            self.seq_num,
            self.frame_id,
            self.tile_id,
            self.width,
            self.height,
            self.pixel_format,
            self.qp,
            self.payload_len,
            0  # Reserved align
        )
        packet_without_crc = header + self.payload
        crc = zlib.crc32(packet_without_crc) & 0xFFFFFFFF
        return packet_without_crc + struct.pack(">I", crc)

    @classmethod
    def unpack_from_socket(cls, sock):
        """Reads exactly one complete packet (Header + Payload + CRC) from a stream socket."""
        def read_exact(n):
            buf = bytearray()
            while len(buf) < n:
                chunk = sock.recv(n - len(buf))
                if not chunk:
                    raise ConnectionError("Socket closed while awaiting packet bytes")
                buf.extend(chunk)
            return bytes(buf)

        header_bytes = read_exact(HEADER_SIZE)
        (magic, ver, p_type, flags, seq, frame_id, tile_id,
         w, h, fmt, qp, payload_len, _) = struct.unpack(HEADER_STRUCT, header_bytes)

        if magic != MAGIC:
            raise ValueError(f"Invalid packet magic: 0x{magic:08X} (expected 0x{MAGIC:08X})")

        payload = read_exact(payload_len) if payload_len > 0 else b""
        crc_bytes = read_exact(4)
        received_crc = struct.unpack(">I", crc_bytes)[0]

        expected_crc = zlib.crc32(header_bytes + payload) & 0xFFFFFFFF
        if received_crc != expected_crc:
            raise ValueError(f"CRC32 mismatch: got 0x{received_crc:08X}, expected 0x{expected_crc:08X}")

        pkt = cls(
            packet_type=p_type,
            payload=payload,
            flags=flags,
            seq_num=seq,
            frame_id=frame_id,
            tile_id=tile_id,
            width=w,
            height=h,
            pixel_format=fmt,
            qp=qp
        )
        return pkt
