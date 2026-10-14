# Software Architecture & Host Stack Specification

**Host Environment:** Windows 11 / Linux (Python 3.11)  
**Operation Mode:** Completely Offline (Zero Cloud / Zero AI)

---

## 1. Software Stack Overview

```
+---------------------------------------------------------------------------------+
|                                 USER BROWSER                                    |
|                       http://localhost:5000 (Offline UI)                        |
|   +-------------------------------------------------------------------------+   |
|   |  - Video Ingestion: HTML5 File Input & Metadata Extraction              |   |
|   |  - Resolution Selector: 240p (426x240) / 144p (256x144)                 |   |
|   |  - Hardware Monitor: Connected Status, Throughput (MB/s), FPS, Latency  |   |
|   |  - Side-by-Side Synchronized HTML5 Video Players (Original vs FPGA)     |   |
|   |  - Quality Assessment Table: PSNR, SSIM, Bitrate, Compression Ratio     |   |
|   +------------------------------------+------------------------------------+   |
+----------------------------------------|----------------------------------------+
                                         | REST / JSON + Video Streaming
                                         v
+---------------------------------------------------------------------------------+
|                               PYTHON HOST SERVER                                |
|   +-------------------------------------------------------------------------+   |
|   |  `host/server/app.py` (Flask Web Backend)                                |   |
|   |  - Serves static offline frontend (`web/index.html`, CSS, JS)           |   |
|   |  - `/api/upload`: Stores source video and reads resolution/duration      |   |
|   |  - `/api/process`: Triggers video conversion & hardware acceleration    |   |
|   |  - `/api/status`: Queries hardware connection and frame progress        |   |
|   |  - `/api/metrics`: Calculates PSNR, SSIM, and compression statistics    |   |
|   +------------------------------------+------------------------------------+   |
|                                        |                                        |
|   +------------------------------------v------------------------------------+   |
|   |  `host/video/video_pipeline.py` (Video Demuxer & Assembler)             |   |
|   |  - OpenCV VideoCapture decodes arbitrary MP4/AVI/MKV containers         |   |
|   |  - Extracts planar YUV420 / RGB frames for the hardware accelerator     |   |
|   |  - Re-encapsulates FPGA compressed H.264 bitstream into playable MP4    |   |
|   +------------------------------------+------------------------------------+   |
|                                        |                                        |
|   +------------------------------------v------------------------------------+   |
|   |  `host/communication/fpga_client.py` (Binary Packet Transport)          |   |
|   |  - Connects to ZedBoard TCP Socket (Default: `192.168.1.10:5000`)        |   |
|   |  - Formats 32-byte binary protocol headers with CRC32 checksums         |   |
|   |  - Manages automatic fallback to Mock FPGA Server when hardware offline |   |
|   +-------------------------------------------------------------------------+   |
+---------------------------------------------------------------------------------+
```

---

## 2. Directory & Module Layout

- `host/server/app.py`: Flask HTTP application entry point.
- `host/video/video_pipeline.py`: Video frame ingestion, conversion, and playback synthesis.
- `host/communication/fpga_client.py`: TCP network client implementing `docs/protocol.md`.
- `host/communication/mock_zedboard_server.py`: Cycle-accurate software mock of the ZedBoard hardware server.
- `host/protocol/packet.py`: Python ctypes / struct definition of the 32-byte protocol header.
- `host/tests/test_pipeline.py`: Automated pytest / unit test suite for video processing and network protocol.
