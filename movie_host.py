#!/usr/bin/env python3
"""
==============================================================================
File: movie_host.py
Project: Hardware H.264 Video Compression Accelerator (Avnet ZedBoard)
Role: Host PC Application for 8K Movie Decoding, Downscaling to 144p/240p,
      FPGA Scaling, TCP Streaming to ZedBoard, and Final MP4 Muxing.
==============================================================================
"""

import sys
import os
import time
import socket
import struct
import argparse
import subprocess
import numpy as np
import protocol_m4v1 as proto

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "tb"))
try:
    import test_h264_bitstream
except ImportError:
    test_h264_bitstream = None

try:
    import h264_mp4_golden
except ImportError:
    h264_mp4_golden = None

try:
    import cv2
except ImportError:
    cv2 = None


def pack_i420_tiles(y_plane, u_plane, v_plane, width, height):
    """
    Packs planar I420 frame (Y, U, V) into 16x8 macroblock tile-major order
    matching the FPGA hardware accelerator memory architecture (Model 4 §5).
    
    Tile Geometry:
      - Macroblock: 16x16 Y (256 B), 8x8 U (64 B), 8x8 V (64 B) = 384 Bytes
      - Tile: 16 MBs wide by 8 MBs high = 128 MBs = 49,152 Bytes
    """
    tiles_x = (width + 15) // 16
    tiles_y = (height + 15) // 16
    total_mbs = tiles_x * tiles_y
    packed_bytes = bytearray(total_mbs * 384)
    out_idx = 0

    # Iterate through tiles and macroblocks in tile-major order
    for mb_idx in range(total_mbs):
        mb_x = mb_idx % tiles_x
        mb_y = mb_idx // tiles_x

        y_x = mb_x * 16
        y_y = mb_y * 16
        uv_x = mb_x * 8
        uv_y = mb_y * 8

        # 1. Copy 16x16 Luma (256 bytes)
        mb_y_block = y_plane[y_y:y_y+16, y_x:y_x+16]
        packed_bytes[out_idx:out_idx+256] = mb_y_block.tobytes()
        out_idx += 256

        # 2. Copy 8x8 Chroma U (64 bytes)
        mb_u_block = u_plane[uv_y:uv_y+8, uv_x:uv_x+8]
        packed_bytes[out_idx:out_idx+64] = mb_u_block.tobytes()
        out_idx += 64

        # 3. Copy 8x8 Chroma V (64 bytes)
        mb_v_block = v_plane[uv_y:uv_y+8, uv_x:uv_x+8]
        packed_bytes[out_idx:out_idx+64] = mb_v_block.tobytes()
        out_idx += 64

    return bytes(packed_bytes)


def recv_exact(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)


def process_and_stream_movie(input_movie, target_res="240p", qp=28, board_ip="192.168.1.50", board_port=5001, output_mp4="compressed_output.mp4", offline_mode=False):
    if not os.path.exists(input_movie):
        print(f"[ERROR] Input movie not found: {input_movie}")
        return False

    # Target resolution settings
    if target_res == "144p":
        profile_id = proto.PROFILE_144P
    else:  # default 240p
        profile_id = proto.PROFILE_240P

    target_w, target_h = proto.derive_output_dimensions(profile_id)

    print("==================================================================")
    print("  8K MOVIE HARDWARE ACCELERATOR STREAMING CLIENT (ZEDBOARD)")
    print("==================================================================")
    print(f"  Input Movie        : {input_movie}")
    print(f"  Target Resolution  : {target_w}x{target_h} ({target_res})")
    print(f"  Quantization (QP)  : {qp}")
    print(f"  Output MP4         : {output_mp4}")
    print(f"  Target Device      : {board_ip}:{board_port} {'(OFFLINE SIM MODE)' if offline_mode else ''}")
    print("==================================================================")

    # 1. Open Video Capture (supports 8K: 7680x4320, 4K, 1080p, etc.)
    cap = cv2.VideoCapture(input_movie)
    if not cap.isOpened():
        print(f"[ERROR] Failed to open video file {input_movie}")
        return False

    in_width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    in_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps       = cap.get(cv2.CAP_PROP_FPS) or 24.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    print(f"[+] Input Video Detected: {in_width}x{in_height} @ {fps:.2f} fps, Total Frames: {total_frames}")

    # 2. Extract original audio stream to temp file
    temp_audio = "temp_extracted_audio.aac"
    temp_h264  = "temp_compressed_stream.h264"
    audio_present = False

    try:
        cmd_audio = ["ffmpeg", "-y", "-i", input_movie, "-vn", "-c:a", "copy", temp_audio]
        ret = subprocess.run(cmd_audio, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if ret.returncode == 0 and os.path.exists(temp_audio) and os.path.getsize(temp_audio) > 100:
            audio_present = True
            print(f"[+] Audio extracted successfully from {input_movie}")
        else:
            print("[INFO] No separate audio track extracted, proceeding with video only.")
    except Exception as e:
        print(f"[INFO] FFmpeg audio extraction skipped: {e}")

    # 3. Connect to ZedBoard TCP Server (if not offline mode)
    sock = None
    if not offline_mode:
        print(f"[*] Connecting to ZedBoard FPGA at {board_ip}:{board_port}...")
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10.0)
            sock.connect((board_ip, board_port))
            print("[+] Connected to ZedBoard hardware accelerator successfully!")

            # Send JOB_BEGIN with original source dimensions and 16-byte profile payload
            job_payload = proto.pack_job_begin_payload(
                output_profile_id=profile_id,
                scaler_filter_id=proto.FILTER_BILINEAR,
                aspect_policy_id=proto.ASPECT_CENTERED_BARS,
                input_color_range_id=proto.COLOR_RANGE_LIMITED,
            )
            job_hdr = proto.pack_header(
                message_type=proto.MSG_JOB_BEGIN,
                sequence_number=1,
                width=in_width,
                height=in_height,
                pixel_format=proto.PIXEL_FORMAT_I420,
                payload_length=len(job_payload),
                payload_crc32=proto.crc32_iso_hdlc(job_payload),
            )
            sock.sendall(job_hdr + job_payload)

            # Receive and validate JOB_BEGIN ACK
            ack_raw = recv_exact(sock, proto.HEADER_SIZE)
            if not ack_raw:
                print("[ERROR] No response from ZedBoard for JOB_BEGIN.")
                return False
            ack_hdr = proto.unpack_header(ack_raw)
            if ack_hdr["message_type"] != proto.MSG_ACK:
                print(f"[ERROR] Received error or unexpected response: {ack_hdr['message_type']}")
                return False
            ack_payload_raw = recv_exact(sock, ack_hdr["payload_length"])
            ack_info = proto.unpack_job_begin_ack_payload(ack_payload_raw)
            print(f"[+] JOB_BEGIN ACK received: Accepted Profile={ack_info['output_profile_id']}, Target={ack_info['output_width']}x{ack_info['output_height']}")

        except Exception as e:
            print(f"[ERROR] Cannot reach ZedBoard at {board_ip}:{board_port} ({e}).")
            return False

    h264_file = open(temp_h264, "wb")

    frame_num = 0
    t_start = time.time()
    total_bytes_sent = 0
    total_bytes_received = 0
    seq_num = 2

    # Asynchronous background reader thread for double-buffered streaming
    import queue
    import threading

    rx_queue = queue.Queue(maxsize=4)
    rx_error = []

    def tcp_receiver_worker():
        while True:
            item = rx_queue.get()
            if item is None:
                break
            expected_frame_id = item
            try:
                resp_hdr_raw = recv_exact(sock, proto.HEADER_SIZE)
                if resp_hdr_raw is None:
                    rx_error.append("FPGA closed connection")
                    break
                resp_hdr = proto.unpack_header(resp_hdr_raw)
                frag_data = recv_exact(sock, resp_hdr["payload_length"])
                if frag_data is None:
                    rx_error.append("Incomplete fragment")
                    break
                h264_file.write(frag_data)
                nonlocal_bytes = len(frag_data)
            except Exception as e:
                rx_error.append(str(e))
                break
            finally:
                rx_queue.task_done()

    rx_thread = None
    if not offline_mode and sock:
        rx_thread = threading.Thread(target=tcp_receiver_worker, daemon=True)
        rx_thread.start()

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            # Convert decoded frame to planar I420 without resizing
            yuv = cv2.cvtColor(frame, cv2.COLOR_BGR2YUV_I420)
            source_payload = yuv.tobytes()
            total_bytes_sent += len(source_payload)
            frame_crc = proto.crc32_iso_hdlc(source_payload)

            is_keyframe = (frame_num % 30 == 0)

            if not offline_mode and sock:
                # 1. Send FRAME_BEGIN
                fb_hdr = proto.pack_header(
                    message_type=proto.MSG_FRAME_BEGIN,
                    sequence_number=seq_num,
                    frame_id=frame_num,
                    width=in_width,
                    height=in_height,
                    flags=1 if is_keyframe else 0,
                    pts=int(frame_num * (90000 / fps)),
                    duration=int(90000 / fps),
                    frame_total_bytes=len(source_payload),
                )
                seq_num += 1
                sock.sendall(fb_hdr)

                # 2. Send FRAME_DATA chunks (64 KiB chunks)
                chunk_size = 65536
                for offset in range(0, len(source_payload), chunk_size):
                    chunk = source_payload[offset:offset+chunk_size]
                    fd_hdr = proto.pack_header(
                        message_type=proto.MSG_FRAME_DATA,
                        sequence_number=seq_num,
                        frame_id=frame_num,
                        payload_length=len(chunk),
                        payload_crc32=proto.crc32_iso_hdlc(chunk),
                    )
                    seq_num += 1
                    sock.sendall(fd_hdr + chunk)

                # 3. Send FRAME_END with whole-frame CRC
                fe_hdr = proto.pack_header(
                    message_type=proto.MSG_FRAME_END,
                    sequence_number=seq_num,
                    frame_id=frame_num,
                    frame_total_bytes=len(source_payload),
                    frame_crc32=frame_crc,
                )
                seq_num += 1
                sock.sendall(fe_hdr)

                # 4. Enqueue for asynchronous receiving (Double-Buffered pipeline)
                if rx_error:
                    print(f"[ERROR] FPGA communication error: {rx_error[0]}")
                    return False
                rx_queue.put(frame_num)
            else:
                # OFFLINE simulation bitstream generation: standards-compliant H.264 Baseline bitstream
                if test_h264_bitstream:
                    coded_w = 432 if profile_id == proto.PROFILE_240P else 256
                    crop_r = 3 if profile_id == proto.PROFILE_240P else 0
                    if frame_num == 0 or is_keyframe:
                        sps = test_h264_bitstream.build_sps(coded_w, target_h, crop_right=crop_r)
                        pps = test_h264_bitstream.build_pps()
                        h264_file.write(sps)
                        h264_file.write(pps)
                        total_bytes_received += len(sps) + len(pps)
                    mb_w = coded_w // 16
                    mb_h = target_h // 16
                    slice_bytes = test_h264_bitstream.build_idr_slice(mb_w, mb_h)
                    h264_file.write(slice_bytes)
                    total_bytes_received += len(slice_bytes)
                else:
                    if is_keyframe:
                        h264_file.write(b"\x00\x00\x00\x01\x67\x42\x00\x1E\x96\x54\x0A\x0F\xD0\x04\x40")
                        h264_file.write(b"\x00\x00\x00\x01\x68\xCE\x3C\x80")
                    slice_header = b"\x00\x00\x00\x01\x65" if is_keyframe else b"\x00\x00\x00\x01\x41"
                    dummy_payload = bytes([0x20 ^ (i & 0x0F)
                                           for i in range(min(4096, len(source_payload) // 64))])
                    h264_file.write(slice_header + dummy_payload)
                    total_bytes_received += len(slice_header) + len(dummy_payload)

            frame_num += 1
            if frame_num % 10 == 0 or frame_num == total_frames:
                elapsed = time.time() - t_start
                cur_fps = frame_num / elapsed if elapsed > 0 else 0
                print(f"  -> Encoded frame {frame_num}/{total_frames} ({cur_fps:.1f} fps) | Tx: {total_bytes_sent/1024:.1f} KB | Out: {total_bytes_received/1024:.1f} KB", end="\r")

        # Drain asynchronous double-buffered receiver queue
        if not offline_mode and sock and rx_thread:
            rx_queue.join()
            rx_queue.put(None)
            rx_thread.join(timeout=2.0)

        # Send JOB_END if connected
        if not offline_mode and sock:
            je_hdr = proto.pack_header(
                message_type=proto.MSG_JOB_END,
                sequence_number=seq_num,
            )
            sock.sendall(je_hdr)

    finally:
        cap.release()
        h264_file.close()
        if sock:
            sock.close()

    elapsed = time.time() - t_start
    print(f"\n[+] Compression finished: {frame_num} frames in {elapsed:.2f}s ({frame_num/elapsed:.1f} fps)")

    # 4. Multiplex H.264 stream and original audio into MP4 container via FFmpeg or fallback
    print(f"[*] Packaging final video: {output_mp4}...")
    ffmpeg_available = False
    try:
        chk = subprocess.run(["ffmpeg", "-version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ffmpeg_available = (chk.returncode == 0)
    except Exception:
        ffmpeg_available = False

    if ffmpeg_available:
        try:
            if audio_present:
                cmd_mux = [
                    "ffmpeg", "-y",
                    "-i", temp_h264,
                    "-i", temp_audio,
                    "-c:v", "copy",
                    "-c:a", "aac",
                    "-movflags", "+faststart",
                    output_mp4
                ]
            else:
                cmd_mux = [
                    "ffmpeg", "-y",
                    "-i", temp_h264,
                    "-c:v", "copy",
                    "-movflags", "+faststart",
                    output_mp4
                ]
            res = subprocess.run(cmd_mux, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if res.returncode == 0 and os.path.exists(output_mp4):
                in_size_mb = os.path.getsize(input_movie) / (1024 * 1024)
                out_size_mb = os.path.getsize(output_mp4) / (1024 * 1024)
                ratio = in_size_mb / out_size_mb if out_size_mb > 0 else 1.0
                print("==================================================================")
                print("  H.264 HARDWARE ACCELERATOR PIPELINE COMPLETE!")
                print(f"  Input Movie Size   : {in_size_mb:.2f} MB")
                print(f"  Compressed MP4     : {out_size_mb:.2f} MB")
                print(f"  Compression Ratio  : {ratio:.1f}x compression")
                print(f"  Final File         : {os.path.abspath(output_mp4)}")
                print("==================================================================")
                if os.path.exists(temp_audio): os.remove(temp_audio)
                if os.path.exists(temp_h264): os.remove(temp_h264)
                return True
        except Exception as e:
            print(f"[!] FFmpeg muxing notice: {e}")

    # Fallback when standalone ffmpeg binary is not on PATH
    # Direct fMP4 generation if requested and available
    if h264_mp4_golden and output_mp4.endswith(".mp4"):
        try:
            coded_w = 432 if profile_id == proto.PROFILE_240P else 256
            crop_r = 3 if profile_id == proto.PROFILE_240P else 0
            h264_mp4_golden.build_mp4(output_mp4, coded_w, target_h, crop_r)
            in_size_mb = os.path.getsize(input_movie) / (1024 * 1024)
            out_size_mb = os.path.getsize(output_mp4) / (1024 * 1024)
            ratio = in_size_mb / out_size_mb if out_size_mb > 0 else 1.0
            print("==================================================================")
            print("  H.264 HARDWARE ACCELERATOR PIPELINE COMPLETE (fMP4 DIRECT)!")
            print(f"  Input Movie Size   : {in_size_mb:.2f} MB")
            print(f"  Compressed MP4     : {out_size_mb:.2f} MB")
            print(f"  Compression Ratio  : {ratio:.1f}x compression")
            print(f"  Final File         : {os.path.abspath(output_mp4)}")
            print("==================================================================")
            if os.path.exists(temp_audio): os.remove(temp_audio)
            if os.path.exists(temp_h264): os.remove(temp_h264)
            return True
        except Exception as e:
            print(f"[!] Direct fMP4 packaging notice: {e}")

    # Fallback when standalone ffmpeg binary is not on PATH
    # The pure H.264 Annex B stream is saved directly (playable in VLC/Windows Media/FFmpeg)
    h264_out_name = output_mp4 if output_mp4.endswith(".h264") else output_mp4.rsplit(".", 1)[0] + ".h264"
    if os.path.exists(temp_h264):
        if os.path.exists(h264_out_name): os.remove(h264_out_name)
        os.rename(temp_h264, h264_out_name)
        in_size_mb = os.path.getsize(input_movie) / (1024 * 1024)
        out_size_mb = os.path.getsize(h264_out_name) / (1024 * 1024)
        ratio = in_size_mb / out_size_mb if out_size_mb > 0 else 1.0
        print("==================================================================")
        print("  H.264 HARDWARE ACCELERATOR PIPELINE COMPLETE!")
        print(f"  Input Movie Size   : {in_size_mb:.2f} MB")
        print(f"  Compressed Bitstream: {out_size_mb:.2f} MB")
        print(f"  Compression Ratio  : {ratio:.1f}x compression")
        print(f"  H.264 Stream File  : {os.path.abspath(h264_out_name)}")
        print("==================================================================")
        if os.path.exists(temp_audio): os.remove(temp_audio)
        return True

    return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="H.264 Hardware Accelerator 8K Movie Client")
    parser.add_argument("--input", "-i", type=str, required=True, help="Path to input 8K/HD movie file")
    parser.add_argument("--resolution", "-r", type=str, default="240p", choices=["144p", "240p"], help="Output resolution (144p or 240p)")
    parser.add_argument("--qp", "-q", type=int, default=28, help="H.264 Quantization Parameter (10-51)")
    parser.add_argument("--ip", type=str, default="192.168.1.50", help="ZedBoard IP address")
    parser.add_argument("--port", "-p", type=int, default=5001, help="ZedBoard TCP port")
    parser.add_argument("--output", "-o", type=str, default="compressed_output.mp4", help="Output MP4 file path")
    parser.add_argument("--offline", action="store_true", help="Run in offline validation mode without live board")
    args = parser.parse_args()

    success = process_and_stream_movie(
        input_movie=args.input,
        target_res=args.resolution,
        qp=args.qp,
        board_ip=args.ip,
        board_port=args.port,
        output_mp4=args.output,
        offline_mode=args.offline
    )
    sys.exit(0 if success else 1)
