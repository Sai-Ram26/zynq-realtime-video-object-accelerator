"""
FPGA Ethernet Client for Host Laptop
Connects to ZedBoard TCP Socket or falls back to Mock Hardware Server
"""
import socket
import time
import os
import sys

# Ensure repository root is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from host.protocol import packet as proto

class FPGAClient:
    def __init__(self, host="127.0.0.1", port=5000, timeout=3.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock = None
        self.connected = False
        self.seq_counter = 0

    def connect(self) -> bool:
        """Attempts connection to the hardware socket."""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(self.timeout)
            self.sock.connect((self.host, self.port))
            self.connected = True
            return True
        except (socket.error, ConnectionRefusedError):
            self.connected = False
            self.sock = None
            return False

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
        self.connected = False
        self.sock = None

    def ping(self) -> bool:
        if not self.connected and not self.connect():
            return False
        try:
            self.seq_counter += 1
            pkt = proto.VideoPacket(
                packet_type=proto.CMD_PING,
                payload=b"PING",
                seq_num=self.seq_counter
            )
            self.sock.sendall(pkt.pack())
            resp = proto.VideoPacket.unpack_from_socket(self.sock)
            return resp.packet_type == proto.RSP_PONG
        except Exception:
            self.close()
            return False

    def configure(self, width: int, height: int, qp: int = 28) -> bool:
        if not self.connected and not self.connect():
            return False
        try:
            self.seq_counter += 1
            pkt = proto.VideoPacket(
                packet_type=proto.CMD_CONFIG,
                width=width,
                height=height,
                qp=qp,
                seq_num=self.seq_counter
            )
            self.sock.sendall(pkt.pack())
            resp = proto.VideoPacket.unpack_from_socket(self.sock)
            return resp.packet_type == proto.RSP_CONFIG_ACK
        except Exception:
            self.close()
            return False

    def get_status(self) -> dict:
        if not self.connected and not self.connect():
            return {"connected": False}
        try:
            self.seq_counter += 1
            pkt = proto.VideoPacket(
                packet_type=proto.CMD_STATUS,
                seq_num=self.seq_counter
            )
            self.sock.sendall(pkt.pack())
            resp = proto.VideoPacket.unpack_from_socket(self.sock)
            if resp.packet_type == proto.RSP_STATUS:
                raw_txt = resp.payload.decode("utf-8", errors="ignore")
                # Parse Key=Value; pairs
                stats = {"connected": True}
                for item in raw_txt.split(";"):
                    if "=" in item:
                        k, v = item.split("=", 1)
                        stats[k.lower()] = v
                return stats
        except Exception:
            self.close()
        return {"connected": False}

    def transfer_frame_chunk(self, frame_id: int, payload: bytes, width: int, height: int, qp: int = 28, flags: int = 0) -> bytes:
        if not self.connected and not self.connect():
            raise ConnectionError("FPGA socket is disconnected")
        
        self.seq_counter += 1
        pkt = proto.VideoPacket(
            packet_type=proto.DATA_FRAME_IN,
            payload=payload,
            flags=flags,
            seq_num=self.seq_counter,
            frame_id=frame_id,
            width=width,
            height=height,
            qp=qp
        )
        self.sock.sendall(pkt.pack())
        resp = proto.VideoPacket.unpack_from_socket(self.sock)
        if resp.packet_type != proto.DATA_FRAME_OUT:
            raise ValueError(f"Unexpected response packet type: 0x{resp.packet_type:02X}")
        return resp.payload


def probe_physical_hardware(host="192.168.1.10", port=5000, timeout=0.4) -> bool:
    """
    Actively probes whether a physical Avnet ZedBoard is listening at the target Ethernet IP/Port.
    Returns True ONLY if a real socket connection succeeds.
    """
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, port))
        sock.close()
        return result == 0
    except Exception:
        return False


def detect_hardware_interfaces(target_ip="192.168.1.10", target_port=5000) -> dict:
    """
    Performs full hardware scan across Ethernet and USB-UART serial ports.
    """
    eth_detected = probe_physical_hardware(target_ip, target_port, timeout=0.4)
    
    # Check for COM ports (ZedBoard USB-UART / CP210x / Cypress)
    uart_ports = []
    try:
        import subprocess
        cmd = 'powershell -NoProfile -Command "Get-CimInstance Win32_SerialPort | Select-Object -ExpandProperty DeviceID"'
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=2.0)
        if res.returncode == 0:
            for line in res.stdout.strip().splitlines():
                p = line.strip()
                if p:
                    uart_ports.append(p)
    except Exception:
        pass

    return {
        "physical_detected": eth_detected or (len(uart_ports) > 0),
        "ethernet_ip": f"{target_ip}:{target_port}",
        "ethernet_detected": eth_detected,
        "uart_detected": len(uart_ports) > 0,
        "uart_ports": uart_ports,
        "board_model": "Avnet ZedBoard (AMD Zynq-7000 XC7Z020-1CLG484C)" if eth_detected else "None Detected",
        "timestamp": time.time()
    }

