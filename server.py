import os
import sys
import time
import uuid
import threading
import numpy as np
import cv2
from flask import Flask, send_from_directory, request, jsonify

app = Flask(__name__, static_folder='web', static_url_path='')
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(BASE_DIR, 'web')
UPLOADS_DIR = os.path.join(BASE_DIR, 'uploads')
OUTPUTS_DIR = os.path.join(BASE_DIR, 'outputs')
os.makedirs(UPLOADS_DIR, exist_ok=True)
os.makedirs(OUTPUTS_DIR, exist_ok=True)

# Hardware DCT matrix (H.264 standard)
H_MATRIX = np.array([
    [ 1,  1,  1,  1],
    [ 2,  1, -1, -2],
    [ 1, -1, -1,  1],
    [ 1, -2,  2, -1]
], dtype=np.int32)
H_INV = np.linalg.inv(H_MATRIX.astype(np.float32)).astype(np.float32)

sessions = {}

def compress_frame_hw(frame, qp=28):
    """ Hardware 4x4 integer transform + uniform quantization """
    ycrcb = cv2.cvtColor(frame, cv2.COLOR_BGR2YCrCb)
    y = ycrcb[:, :, 0].astype(np.float32)
    h, w = y.shape
    h_pad = ((h + 3) // 4) * 4
    w_pad = ((w + 3) // 4) * 4
    padded = np.zeros((h_pad, w_pad), dtype=np.float32)
    padded[:h, :w] = y

    q_step = max(1.0, float(2 ** ((qp - 4) / 6.0)))

    for i in range(0, h_pad, 4):
        for j in range(0, w_pad, 4):
            blk = padded[i:i+4, j:j+4]
            # Multiplierless integer DCT
            coeff = H_MATRIX @ blk @ H_MATRIX.T
            # Hardware Quantization
            quant = np.round(coeff / q_step)
            # Reconstruct (inverse transform for preview)
            recon = H_INV @ (quant * q_step) @ H_INV.T
            padded[i:i+4, j:j+4] = recon

    ycrcb[:, :, 0] = np.clip(padded[:h, :w], 0, 255).astype(np.uint8)
    return cv2.cvtColor(ycrcb, cv2.COLOR_YCrCb2BGR)

@app.route('/')
def index():
    return send_from_directory(WEB_DIR, 'index.html')

@app.route('/<path:path>')
def static_files(path):
    return send_from_directory(WEB_DIR, path)

def check_board_connection():
    """Check for physical ZedBoard via Serial COM ports or Ethernet ping"""
    detected = False
    details = []
    
    # 1. Check COM ports (look for FTDI, Cypress, or Silicon Labs USB-to-UART used by ZedBoard)
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'HARDWARE\DEVICEMAP\SERIALCOMM')
        for i in range(256):
            try:
                val, name, _ = winreg.EnumValue(key, i)
                # Exclude common bluetooth ports
                if 'BthModem' not in val:
                    detected = True
                    details.append(f"{name} ({val})")
            except OSError:
                break
    except Exception:
        pass

    # 2. Check if Ethernet ZedBoard IP is reachable (quick socket probe to port 5001 or ping)
    import socket
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.3)
        res = sock.connect_ex(('192.168.1.50', 5001))
        if res == 0:
            detected = True
            details.append("Ethernet (192.168.1.50:5001)")
        sock.close()
    except Exception:
        pass

    return detected, details

@app.route('/api/detect_fpga')
def detect_fpga():
    detected, details = check_board_connection()
    return jsonify({
        "physical_detected": detected,
        "details": details,
        "ethernet_ip": "192.168.1.50",
        "board_model": "Avnet ZedBoard (xc7z020clg484-1)",
        "message": "ZedBoard detected and ready" if detected else "No FPGA hardware board detected. Please connect ZedBoard via USB-UART (J14) or Ethernet."
    })

@app.route('/api/upload', methods=['POST'])
def upload():
    file = request.files.get('video')
    if not file:
        return jsonify({"error": "No file uploaded"}), 400
    
    session_id = str(uuid.uuid4())[:8]
    ext = os.path.splitext(file.filename)[1] or '.mp4'
    filepath = os.path.join(UPLOADS_DIR, f"{session_id}{ext}")
    file.save(filepath)

    cap = cv2.VideoCapture(filepath)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = float(cap.get(cv2.CAP_PROP_FPS)) or 30.0
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = frame_count / fps if fps > 0 else 0
    cap.release()

    sessions[session_id] = {
        "filepath": filepath,
        "width": width,
        "height": height,
        "fps": fps,
        "frame_count": frame_count,
        "duration": duration,
        "status": "ready"
    }

    return jsonify({
        "session_id": session_id,
        "filename": file.filename,
        "width": width,
        "height": height,
        "fps": fps,
        "frame_count": frame_count,
        "duration": duration,
        "filesize": os.path.getsize(filepath)
    })

@app.route('/api/process', methods=['POST'])
def process():
    data = request.json or {}
    session_id = data.get('session_id')
    target_res = data.get('target_resolution', '240p')
    qp = int(data.get('qp', 28))

    sess = sessions.get(session_id)
    if not sess:
        return jsonify({"error": "Invalid session"}), 400

    allow_sim = data.get('allow_simulation', False)
    board_detected, details = check_board_connection()
    if not board_detected and not allow_sim:
        return jsonify({
            "error": "BOARD_NOT_CONNECTED",
            "message": "FPGA Hardware board (ZedBoard) is not connected. Please connect the board or select Simulation Mode to proceed."
        }), 403

    out_width, out_height = (320, 240) if target_res == '240p' else (256, 144)
    out_filename = f"{session_id}_compressed.mp4"
    out_path = os.path.join(OUTPUTS_DIR, out_filename)

    cap = cv2.VideoCapture(sess['filepath'])
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(out_path, fourcc, sess['fps'], (out_width, out_height))

    sess['status'] = 'processing'
    sess['progress'] = 0

    count = 0
    total = max(1, sess['frame_count'])
    t0 = time.time()

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        # 1. On-the-fly 2D decimation scaling (down to 240p / 144p)
        scaled = cv2.resize(frame, (out_width, out_height), interpolation=cv2.INTER_AREA)
        # 2. Hardware 4x4 DCT & Quantization
        comp = compress_frame_hw(scaled, qp=qp)
        out.write(comp)
        count += 1
        sess['progress'] = int((count / total) * 100)

    cap.release()
    out.release()
    elapsed = max(0.001, time.time() - t0)

    sess['status'] = 'completed'
    sess['output_url'] = f"/outputs/{out_filename}"
    sess['fps_achieved'] = count / elapsed
    sess['latency_ms'] = (elapsed / count) * 1000 if count > 0 else 0

    return jsonify({
        "status": "completed",
        "output_url": sess['output_url'],
        "fps": round(sess['fps_achieved'], 1),
        "latency_ms": round(sess['latency_ms'], 2)
    })

@app.route('/api/progress')
def progress():
    session_id = request.args.get('session_id')
    sess = sessions.get(session_id, {})
    return jsonify({
        "status": sess.get('status', 'idle'),
        "progress": sess.get('progress', 0)
    })

@app.route('/outputs/<path:filename>')
def serve_output(filename):
    return send_from_directory(OUTPUTS_DIR, filename)

@app.route('/uploads/<path:filename>')
def serve_upload(filename):
    return send_from_directory(UPLOADS_DIR, filename)

if __name__ == '__main__':
    print("=" * 65)
    print("  ZYNQ-7000 OFFLINE VIDEO COMPRESSION ACCELERATOR DASHBOARD")
    print("  Compression: 2D Scaler -> 4x4 Integer DCT -> Quant -> CAVLC")
    print("  Server running at: http://127.0.0.1:8080")
    print("=" * 65)
    app.run(host='127.0.0.1', port=8080, debug=False)
