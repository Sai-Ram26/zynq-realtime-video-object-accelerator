"""
Mock ZedBoard Hardware TCP Socket Server
Simulates the ARM PS + FPGA Accelerator socket endpoint on port 5000.
Implements docs/protocol.md specification byte-for-byte.
"""
import socket
import threading
import time
import sys
import os
import numpy as np

# Ensure repository root is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from host.protocol import packet as proto

DEFAULT_PORT = 5000
PL_CLOCK_MHZ = 100

class MockZedboardServer:
    def __init__(self, host="127.0.0.1", port=DEFAULT_PORT):
        self.host = host
        self.port = port
        self.running = False
        self.sock = None
        self.thread = None
        self.total_bytes_processed = 0
        self.frames_processed = 0

    def start(self):
        self.running = True
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((self.host, self.port))
        self.sock.listen(5)
        self.thread = threading.Thread(target=self._server_loop, daemon=True)
        self.thread.start()
        print(f"[Mock ZedBoard] Server listening on {self.host}:{self.port} (TCP)")

    def stop(self):
        self.running = False
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass

    def _server_loop(self):
        while self.running:
            try:
                client_sock, client_addr = self.sock.accept()
                client_thread = threading.Thread(
                    target=self._client_handler,
                    args=(client_sock, client_addr),
                    daemon=True
                )
                client_thread.start()
            except Exception:
                break

    def _client_handler(self, client_sock, client_addr):
        active_target_w = 426
        active_target_h = 240
        active_qp = 28

        while self.running:
            try:
                pkt = proto.VideoPacket.unpack_from_socket(client_sock)
                if pkt.packet_type == proto.CMD_PING:
                    resp = proto.VideoPacket(
                        packet_type=proto.RSP_PONG,
                        payload=b"ZEDBOARD_ARM_PS_OK",
                        seq_num=pkt.seq_num
                    )
                    client_sock.sendall(resp.pack())

                elif pkt.packet_type == proto.CMD_CONFIG:
                    active_target_w = pkt.width
                    active_target_h = pkt.height
                    active_qp = pkt.qp
                    resp = proto.VideoPacket(
                        packet_type=proto.RSP_CONFIG_ACK,
                        payload=b"CONFIG_ACCEPTED",
                        seq_num=pkt.seq_num,
                        width=active_target_w,
                        height=active_target_h,
                        qp=active_qp
                    )
                    client_sock.sendall(resp.pack())

                elif pkt.packet_type == proto.CMD_STATUS:
                    # Telemetry payload: Clock (MHz), LUTs, BRAM, DSP, Processed frames
                    telemetry = f"CLK={PL_CLOCK_MHZ};LUT=17024;BRAM=34;DSP=24;FRAMES={self.frames_processed}"
                    resp = proto.VideoPacket(
                        packet_type=proto.RSP_STATUS,
                        payload=telemetry.encode("utf-8"),
                        seq_num=pkt.seq_num
                    )
                    client_sock.sendall(resp.pack())

                elif pkt.packet_type == proto.DATA_FRAME_IN:
                    # Process frame data
                    self.total_bytes_processed += len(pkt.payload)
                    self.frames_processed += 1
                    
                    # Hardware processing simulation:
                    # Echoes compressed payload back with target dimensions
                    resp = proto.VideoPacket(
                        packet_type=proto.DATA_FRAME_OUT,
                        payload=pkt.payload,
                        flags=pkt.flags,
                        seq_num=pkt.seq_num,
                        frame_id=pkt.frame_id,
                        tile_id=pkt.tile_id,
                        width=active_target_w,
                        height=active_target_h,
                        pixel_format=proto.FMT_H264_NAL,
                        qp=active_qp
                    )
                    client_sock.sendall(resp.pack())

                elif pkt.packet_type == proto.CMD_RESET:
                    self.frames_processed = 0
                    resp = proto.VideoPacket(
                        packet_type=proto.RSP_CONFIG_ACK,
                        payload=b"RESET_COMPLETE",
                        seq_num=pkt.seq_num
                    )
                    client_sock.sendall(resp.pack())

            except (ConnectionError, ValueError):
                break
        
        try:
            client_sock.close()
        except Exception:
            pass

if __name__ == "__main__":
    server = MockZedboardServer()
    server.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        server.stop()
