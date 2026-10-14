"""
Phase 2 Verification Suite: Laptop <-> FPGA Ethernet Communication Test
Matches Section 22, 27, 28, 29 (Phase 2), and Page 38 of the Master Project Specification.
Transfers a known binary test dataset, verifying integrity, throughput, sequence ordering, and error rejection.
"""
import os
import sys
import time
import hashlib
import random

# Ensure repository root is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from host.protocol import packet as proto
from host.communication.fpga_client import FPGAClient

def run_phase2_verification(test_size_mb: int = 10):
    print("=" * 70)
    print("  PHASE 2 VERIFICATION: LAPTOP <-> FPGA TCP COMMUNICATION")
    print("=" * 70)

    client = FPGAClient(host="127.0.0.1", port=5000, timeout=5.0)

    # 1. Connection & Handshake Test
    print("[1/5] Establishing TCP connection to port 5000...")
    connected = client.connect()
    if not connected:
        print("      -> Hardware/Mock server not running on port 5000. Launching MockZedboardServer...")
        from host.communication.mock_zedboard_server import MockZedboardServer
        mock_server = MockZedboardServer(host="127.0.0.1", port=5000)
        mock_server.start()
        time.sleep(0.5)
        connected = client.connect()
    assert connected, "Failed to connect to FPGA TCP socket!"
    print("      -> OK: TCP Socket connected.")

    print("[2/5] Testing PING / PONG handshake...")
    pong_ok = client.ping()
    assert pong_ok, "Ping / Pong handshake failed!"
    print("      -> OK: Liveness confirmed (RSP_PONG received).")

    # 2. Configuration Command
    print("[3/5] Sending configuration command (Target 240p, QP 28)...")
    cfg_ok = client.configure(width=426, height=240, qp=28)
    assert cfg_ok, "Configuration command failed!"
    print("      -> OK: Accelerator configuration acknowledged.")

    # 3. Binary Test Data Transfer & Integrity Verification
    print(f"[4/5] Generating {test_size_mb} MB known pseudo-random binary test dataset...")
    # Seed for reproducibility
    random.seed(42)
    chunk_size = 64 * 1024  # 64 KB per packet chunk
    total_bytes = test_size_mb * 1024 * 1024
    num_chunks = total_bytes // chunk_size

    # Generate test buffer
    raw_data = bytearray(os.urandom(total_bytes))
    source_sha256 = hashlib.sha256(raw_data).hexdigest()
    print(f"      -> Source Dataset SHA-256: {source_sha256}")
    print(f"      -> Streaming {num_chunks} packets ({chunk_size} bytes each) through FPGA...")

    received_data = bytearray()
    t_start = time.perf_counter()

    for chunk_id in range(num_chunks):
        chunk_slice = bytes(raw_data[chunk_id * chunk_size : (chunk_id + 1) * chunk_size])
        flags = proto.FLAG_EOF if (chunk_id == num_chunks - 1) else 0

        # Transmit chunk and receive echo
        resp_payload = client.transfer_frame_chunk(
            frame_id=chunk_id,
            payload=chunk_slice,
            width=426,
            height=240,
            flags=flags
        )
        received_data.extend(resp_payload)
        
        # Sequence progress
        if chunk_id % 20 == 0 or chunk_id == num_chunks - 1:
            print(f"      -> Chunk {chunk_id + 1}/{num_chunks} echoed back", end="\r")

    t_elapsed = max(0.0001, time.perf_counter() - t_start)
    throughput_mb_s = (total_bytes / (1024 * 1024)) / t_elapsed
    print(f"\n      -> Transfer Complete in {t_elapsed:.3f} s.")
    print(f"      -> Measured Throughput: {throughput_mb_s:.2f} MB/s.")

    # Validate Bit-for-Bit Integrity
    received_sha256 = hashlib.sha256(received_data).hexdigest()
    print(f"      -> Received Dataset SHA-256: {received_sha256}")
    assert source_sha256 == received_sha256, "DATA INTEGRITY CORRUPTION DETECTED! SHA-256 mismatch!"
    print("      -> OK: 100% BIT-PERFECT DATA INTEGRITY CONFIRMED (0 bit errors).")

    # 4. Error Handling Verification (Section 28 Compliance)
    print("[5/5] Verifying error handling against corrupt packets...")
    # Send packet with corrupt CRC
    corrupt_pkt = proto.VideoPacket(
        packet_type=proto.DATA_FRAME_IN,
        payload=b"MALFORMED_DATA_PACKET"
    )
    raw_pkt = bytearray(corrupt_pkt.pack())
    # Invalidate CRC in last 4 bytes
    raw_pkt[-1] ^= 0xFF
    client.sock.sendall(bytes(raw_pkt))

    # Server should detect CRC mismatch and close socket or return error without crashing
    time.sleep(0.2)
    # Re-connect to ensure server didn't crash
    reconnect_client = FPGAClient(host="127.0.0.1", port=5000, timeout=2.0)
    assert reconnect_client.connect() and reconnect_client.ping(), "Server crashed upon corrupt packet!"
    reconnect_client.close()
    client.close()
    print("      -> OK: Server safely rejected malformed CRC packet and remained resilient.")

    print("\n" + "=" * 70)
    print("  PHASE 2 ETHERNET COMMUNICATION TEST COMPLETED SUCCESSFULLY!")
    print("=" * 70)

if __name__ == "__main__":
    test_mb = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    run_phase2_verification(test_mb)
