"""
Automated Test Harness for Phase 1: Offline Website & Host Video Pipeline
Tests local server, mock hardware socket, video ingestion, scaling, compression, and metrics.
"""
import urllib.request
import json
import time
import sys

BASE_URL = "http://127.0.0.1:8080"

def run_phase1_verification():
    print("=" * 70)
    print("  PHASE 1 VERIFICATION: OFFLINE WEBSITE & HOST VIDEO PIPELINE")
    print("=" * 70)

    # 1. Test Web Server Accessibility
    print(f"[1/5] Checking web server root ({BASE_URL})...")
    try:
        req = urllib.request.urlopen(f"{BASE_URL}/", timeout=2.0)
    except Exception:
        print("      -> Server not running. Starting background server daemon on port 8080...")
        import os
        import threading
        sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
        from host.server.app import app
        srv_thread = threading.Thread(target=lambda: app.run(host="127.0.0.1", port=8080, threaded=True, debug=False, use_reloader=False), daemon=True)
        srv_thread.start()
        time.sleep(2.0)
        req = urllib.request.urlopen(f"{BASE_URL}/", timeout=5.0)
    html = req.read().decode('utf-8')
    assert "ZYNQ-7000 VIDEO ACCELERATOR" in html, "Web root HTML title missing!"
    print("      -> OK: Offline HTML5 web application served successfully.")

    # 2. Test Hardware Status API
    print("[2/5] Testing /api/status endpoint...")
    req = urllib.request.urlopen(f"{BASE_URL}/api/status")
    status = json.loads(req.read().decode('utf-8'))
    print(f"      -> Status response: {status}")
    assert status.get("fpga_connected") is True or status.get("simulation_mode_available") is True, "Hardware / simulation engine not available!"
    print("      -> OK: Hardware telemetry reported (Physical or RTL Simulation).")

    # 3. Test Synthetic 1080p Video Generation
    print("[3/5] Requesting synthetic 1080p test video (/api/sample?res=1080p)...")
    req = urllib.request.urlopen(f"{BASE_URL}/api/sample?res=1080p")
    sample_meta = json.loads(req.read().decode('utf-8'))
    session_id = sample_meta["session_id"]
    print(f"      -> Generated: {sample_meta['width']}x{sample_meta['height']}, "
          f"{sample_meta['frame_count']} frames, Session: {session_id}")
    assert sample_meta["width"] == 1920 and sample_meta["height"] == 1080, "1080p dimension error!"
    print("      -> OK: 1080p source video prepared.")

    # 4. Trigger Video Processing (1080p -> 240p Downscaling + Compression)
    print("[4/5] Initiating FPGA processing (1080p -> 240p, QP=28)...")
    payload = json.dumps({
        "session_id": session_id,
        "target_res": "240p",
        "scaler_mode": "bilinear",
        "qp": 28
    }).encode('utf-8')

    post_req = urllib.request.Request(
        f"{BASE_URL}/api/process",
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    res = json.loads(urllib.request.urlopen(post_req).read().decode('utf-8'))
    assert res.get("status") == "processing_started", "Processing start failed!"
    print("      -> OK: Pipeline worker thread launched.")

    # 5. Poll Progress until Completion
    print("[5/5] Polling pipeline progress...")
    complete = False
    data = None
    for _ in range(60):
        time.sleep(0.5)
        prog_req = urllib.request.urlopen(f"{BASE_URL}/api/progress?session_id={session_id}")
        data = json.loads(prog_req.read().decode('utf-8'))
        stage_txt = str(data.get('stage_text', '')).encode('ascii', errors='replace').decode('ascii')
        print(f"      -> Progress: {data.get('percent')}% | {stage_txt} "
              f"| FPS: {data.get('fps', 0):.1f} | Speed: {data.get('speed_mbps', 0):.1f} MB/s", end="\r")
        if data.get("complete"):
            complete = True
            break
        if data.get("error"):
            raise RuntimeError(f"Processing error: {data.get('error')}")

    print("\n")
    assert complete, "Processing did not complete within timeout!"
    print(f"      -> SUCCESS: Processed video generated: {data.get('output_url')}")
    print(f"      -> Target Output: {data.get('target_width')}x{data.get('target_height')}")
    print(f"      -> File Size: {data.get('output_size_str')}")
    print(f"      -> PSNR (FPGA): {data['metrics']['hw_psnr']:.2f} dB")
    print(f"      -> SSIM (FPGA): {data['metrics']['hw_ssim']:.4f}")
    print(f"      -> Spatial Reduction: {data['metrics']['spatial_reduction']:.1f}x")
    print(f"      -> Overall Storage Reduction: {data['metrics']['overall_storage_reduction']:.1f}x")

    print("\n" + "=" * 70)
    print("  ALL PHASE 1 ACCEPTANCE CRITERIA VERIFIED AND PASSED!")
    print("=" * 70)

if __name__ == "__main__":
    run_phase1_verification()
