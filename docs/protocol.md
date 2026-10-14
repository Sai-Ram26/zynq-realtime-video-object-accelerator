# FPGA Binary Communication Protocol Specification

**Document Version:** 1.0.0  
**Transport:** Gigabit Ethernet (TCP/IP over port 5000)  
**Byte Order:** Big-Endian (Network Byte Order)

---

## 1. Packet Framing & Header Format

Every packet transmitted between the Host Laptop and the FPGA (or Mock Hardware Server) starts with a fixed 32-byte header, followed by an optional payload, followed by a 4-byte CRC32 trailer.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       MAGIC (0x5A595641)                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    VERSION    |  PACKET TYPE  |             FLAGS             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        SEQUENCE NUMBER                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|            FRAME ID           |            TILE ID            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|             WIDTH             |             HEIGHT            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          PIXEL FORMAT         |         RESERVED / QP         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         PAYLOAD LENGTH                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
|                        PAYLOAD DATA ...                       |
|                       (Variable Length)                       |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           CRC-32                              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 1.1 Header Fields Description

| Offset | Field | Type | Description |
| :--- | :--- | :--- | :--- |
| **0x00** | `MAGIC` | `uint32` | Protocol synchronization word: `0x5A595641` ("ZYVA" in ASCII: Zynq Video Accelerator). |
| **0x04** | `VERSION` | `uint8` | Protocol major/minor version (Current: `0x01`). |
| **0x05** | `PACKET_TYPE` | `uint8` | Control command or data stream identifier (see table below). |
| **0x06** | `FLAGS` | `uint16` | Bitmask: Bit 0 = End-of-Frame, Bit 1 = Last-Tile, Bit 2 = Error-Flag. |
| **0x08** | `SEQ_NUM` | `uint32` | Monotonically increasing packet sequence counter for packet loss detection. |
| **0x0C** | `FRAME_ID` | `uint16` | Video frame index (0 to 65535). |
| **0x0E** | `TILE_ID` | `uint16` | Spatial tile index (0 = Full frame, 1..N = Sub-tiles for 4K/8K tiling). |
| **0x10** | `WIDTH` | `uint16` | Source or target width in pixels (e.g., 1280, 1920, 3840, 7680, 426, 256). |
| **0x12** | `HEIGHT` | `uint16` | Source or target height in pixels (e.g., 720, 1080, 2160, 4320, 240, 144). |
| **0x14** | `PIXEL_FORMAT` | `uint16` | `0x0001` = RGB888, `0x0002` = YUV420 Planar, `0x0003` = H.264 NAL stream. |
| **0x16** | `QP_RESERVED` | `uint16` | Quantization parameter (0..51) for compression commands. |
| **0x18** | `PAYLOAD_LEN` | `uint32` | Exact length of subsequent payload in bytes ($0$ for header-only commands). |
| **Header + N** | `CRC32` | `uint32` | IEEE 802.3 32-bit CRC over header and payload. |

---

## 2. Packet Types & Command Opcodes

| Type Code | Name | Direction | Description |
| :--- | :--- | :--- | :--- |
| `0x01` | `CMD_PING` | Host $\to$ FPGA | Liveness handshake / echo request. |
| `0x02` | `RSP_PONG` | FPGA $\to$ Host | Handshake reply confirming connection & firmware version. |
| `0x03` | `CMD_CONFIG` | Host $\to$ FPGA | Configure accelerator: input/output resolution, scaling filter, QP. |
| `0x04` | `RSP_CONFIG_ACK` | FPGA $\to$ Host | Acknowledge configuration applied. |
| `0x05` | `DATA_FRAME_IN` | Host $\to$ FPGA | Frame or tile uncompressed pixel payload sent to FPGA. |
| `0x06` | `DATA_FRAME_OUT` | FPGA $\to$ Host | Processed, scaled, and compressed H.264 NAL bitstream returned. |
| `0x07` | `CMD_STATUS` | Host $\to$ FPGA | Query accelerator hardware performance counters & register status. |
| `0x08` | `RSP_STATUS` | FPGA $\to$ Host | Status payload containing hardware clock cycles, LUT/BRAM status, and temperature. |
| `0x09` | `CMD_RESET` | Host $\to$ FPGA | Software reset pulse for the PL video pipeline. |
| `0xFF` | `RSP_ERROR` | FPGA $\to$ Host | Error notification with error code (buffer overflow, invalid format, timeout). |
