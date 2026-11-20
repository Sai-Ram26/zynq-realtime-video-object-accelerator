import os
import uuid
import cv2
from flask import Flask, send_from_directory, request, jsonify
from movie_host import process_and_stream_movie

app = Flask(__name__, static_folder='web', static_url_path='')
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(BASE_DIR, 'web')
UPLOADS_DIR = os.path.join(BASE_DIR, 'uploads')
OUTPUTS_DIR = os.path.join(BASE_DIR, 'outputs')
BOARD_IP = os.environ.get('ZEDBOARD_IP', '192.168.1.50')
BOARD_PORT = int(os.environ.get('ZEDBOARD_PORT', '5001'))
os.makedirs(UPLOADS_DIR, exist_ok=True)
os.makedirs(OUTPUTS_DIR, exist_ok=True)

sessions = {}

@app.route('/')
def index():
    return send_from_directory(WEB_DIR, 'index.html')

@app.route('/<path:path>')
def static_files(path):
    return send_from_directory(WEB_DIR, path)

def check_board_connection():
    """Check whether the ARM TCP service is reachable at the configured board address."""
    import socket
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.3)
        res = sock.connect_ex((BOARD_IP, BOARD_PORT))
        if res == 0:
            sock.close()
            return True, [f"Ethernet ({BOARD_IP}:{BOARD_PORT})"]
        sock.close()
    except Exception:
        pass
    return False, []

@app.route('/api/detect_fpga')
def detect_fpga():
    detected, details = check_board_connection()
    return jsonify({
        "physical_detected": detected,
        "details": details,
        "ethernet_ip": BOARD_IP,
        "tcp_port": BOARD_PORT,
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

    board_detected, _details = check_board_connection()
    force_sim = data.get('force_simulation', False)
    use_offline = force_sim or (not board_detected)

    out_filename = f"{session_id}_compressed.mp4"
    out_path = os.path.join(OUTPUTS_DIR, out_filename)
    sess['status'] = 'processing'
    sess['progress'] = 10
    proc_ok = process_and_stream_movie(
        input_movie=sess['filepath'],
        target_res=target_res,
        qp=qp,
        board_ip=BOARD_IP,
        board_port=BOARD_PORT,
        output_mp4=out_path,
        offline_mode=use_offline
    )
    if not proc_ok or not os.path.exists(out_path):
        sess['status'] = 'error'
        return jsonify({
            "error": "PROCESSING_FAILED",
            "message": "The compression engine did not return a valid compressed video."
        }), 502
    sess['status'] = 'completed'
    sess['progress'] = 100
    sess['output_url'] = f"/outputs/{out_filename}"
    return jsonify({
        "status": "completed",
        "mode": "simulation" if use_offline else "fpga",
        "output_url": sess['output_url']
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
