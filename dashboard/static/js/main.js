// ==========================================================================
// ZEDBOARD VIDEO ACCELERATOR DASHBOARD - INTERACTIVE CONTROLLER
// Dual Mode: Automatic Background Subtraction & Interactive ROI Drawing
// ==========================================================================

document.addEventListener('DOMContentLoaded', () => {
    let currentFilename = 'sample_intruder.mp4';
    let currentMode = 'auto'; // 'auto' or 'manual'
    let snapshots = [];
    let isPlaying = false;
    let playbackInterval = null;
    let currentFrameIdx = 0;

    // ROI Drawing State
    let isDrawing = false;
    let startX = 0, startY = 0;
    let currentRect = null; // { x, y, w, h } in canvas display px
    let selectedRoi = null; // { x, y, w, h } in native video px
    let previewImage = null;
    let videoNativeW = 480;
    let videoNativeH = 320;

    // DOM Elements - Navigation & Modes
    const btnModeAuto = document.getElementById('btn-mode-auto');
    const btnModeManual = document.getElementById('btn-mode-manual');
    const roiPanel = document.getElementById('roi-panel');
    const threshGroup = document.getElementById('thresh-group');
    const btnPreviewFrame = document.getElementById('btn-preview-frame');
    const btnClearRoi = document.getElementById('btn-clear-roi');
    const roiStatusBadge = document.getElementById('roi-status-badge');
    const roiCoordsDisplay = document.getElementById('roi-coords');

    // DOM Elements - Controls & Sliders
    const dropZone = document.getElementById('drop-zone');
    const fileInput = document.getElementById('file-input');
    const fileNameDisplay = document.getElementById('file-name-display');
    const btnGenerateSample = document.getElementById('btn-generate-sample');
    const btnRunAccel = document.getElementById('btn-run-accel');
    const btnPlayPause = document.getElementById('btn-play-pause');
    const btnDownload = document.getElementById('btn-download');

    const threshSlider = document.getElementById('thresh-slider');
    const threshVal = document.getElementById('thresh-val');
    const qpSlider = document.getElementById('qp-slider');
    const qpVal = document.getElementById('qp-val');

    // DOM Elements - Viewport
    const screenWrapper = document.getElementById('screen-wrapper');
    const displayImg = document.getElementById('display-canvas');
    const roiCanvas = document.getElementById('roi-canvas');
    const ctx = roiCanvas ? roiCanvas.getContext('2d') : null;
    const placeholder = document.getElementById('screen-placeholder');
    const timelineSlider = document.getElementById('timeline-slider');
    const frameCounter = document.getElementById('frame-counter');

    // Metrics DOM
    const metricPsnr = document.getElementById('metric-psnr');
    const metricHwLatency = document.getElementById('metric-latency');
    const metricSavings = document.getElementById('metric-savings');
    const metricObjects = document.getElementById('metric-objects');
    const metricHwFps = document.getElementById('metric-hw-fps');
    const metricOffload = document.getElementById('metric-offload');

    // Slider Listeners
    threshSlider.addEventListener('input', (e) => threshVal.textContent = e.target.value);
    qpSlider.addEventListener('input', (e) => qpVal.textContent = e.target.value);

    // --------------------------------------------------------------------------
    // Mode Switching Logic
    // --------------------------------------------------------------------------
    btnModeAuto.addEventListener('click', () => setMode('auto'));
    btnModeManual.addEventListener('click', () => setMode('manual'));

    function setMode(mode) {
        currentMode = mode;
        if (mode === 'auto') {
            btnModeAuto.classList.add('active');
            btnModeManual.classList.remove('active');
            roiPanel.style.display = 'none';
            threshGroup.style.display = 'flex';
            roiCanvas.style.display = 'none';
            if (snapshots.length > 0) {
                displayImg.style.display = 'block';
            }
        } else {
            btnModeManual.classList.add('active');
            btnModeAuto.classList.remove('active');
            roiPanel.style.display = 'flex';
            threshGroup.style.display = 'none';
            stopAutoPlay();
            displayImg.style.display = 'none';
            roiCanvas.style.display = 'block';
            // If we don't have a preview yet, automatically fetch first frame
            if (!previewImage) {
                fetchFirstFrame();
            } else {
                redrawCanvas();
            }
        }
    }

    // --------------------------------------------------------------------------
    // File Upload Handling
    // --------------------------------------------------------------------------
    dropZone.addEventListener('click', () => fileInput.click());
    
    dropZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        dropZone.classList.add('dragover');
    });

    dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));

    dropZone.addEventListener('drop', (e) => {
        e.preventDefault();
        dropZone.classList.remove('dragover');
        if (e.dataTransfer.files.length > 0) {
            handleFileUpload(e.dataTransfer.files[0]);
        }
    });

    fileInput.addEventListener('change', (e) => {
        if (e.target.files.length > 0) {
            handleFileUpload(e.target.files[0]);
        }
    });

    function handleFileUpload(file) {
        fileNameDisplay.textContent = `Uploading: ${file.name}...`;
        const formData = new FormData();
        formData.append('video', file);

        fetch('/api/upload', {
            method: 'POST',
            body: formData
        })
        .then(res => res.json())
        .then(data => {
            if (data.status === 'success') {
                currentFilename = data.filename;
                fileNameDisplay.textContent = `Selected: ${file.name}`;
                fileNameDisplay.style.color = '#38bdf8';
                previewImage = null;
                selectedRoi = null;
                updateRoiBadge();
                if (currentMode === 'manual') {
                    fetchFirstFrame();
                }
            } else {
                alert('Upload error: ' + data.message);
            }
        })
        .catch(err => {
            console.error(err);
            alert('Upload failed.');
        });
    }

    // --------------------------------------------------------------------------
    // 1-Click Sample Video Generator
    // --------------------------------------------------------------------------
    btnGenerateSample.addEventListener('click', () => {
        btnGenerateSample.disabled = true;
        btnGenerateSample.textContent = 'Generating...';

        fetch('/api/generate_sample', { method: 'POST' })
        .then(res => res.json())
        .then(data => {
            currentFilename = 'sample_intruder.mp4';
            fileNameDisplay.textContent = 'Sample Surveillance Clip Loaded';
            fileNameDisplay.style.color = '#10b981';
            btnGenerateSample.disabled = false;
            btnGenerateSample.textContent = '⚡ Load Moving Intruder Sample';
            previewImage = null;
            selectedRoi = null;
            updateRoiBadge();
            if (currentMode === 'manual') {
                fetchFirstFrame();
            } else {
                runAccelerator();
            }
        })
        .catch(err => {
            console.error(err);
            btnGenerateSample.disabled = false;
            btnGenerateSample.textContent = '⚡ Load Moving Intruder Sample';
        });
    });

    // --------------------------------------------------------------------------
    // Preview First Frame & ROI Canvas Interaction
    // --------------------------------------------------------------------------
    btnPreviewFrame.addEventListener('click', fetchFirstFrame);
    btnClearRoi.addEventListener('click', clearRoi);

    function fetchFirstFrame() {
        btnPreviewFrame.disabled = true;
        btnPreviewFrame.textContent = 'Fetching Frame...';

        fetch('/api/get_first_frame', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ filename: currentFilename })
        })
        .then(res => res.json())
        .then(data => {
            btnPreviewFrame.disabled = false;
            btnPreviewFrame.textContent = '🖼️ Preview 1st Frame';

            if (data.status === 'success') {
                videoNativeW = data.video_width;
                videoNativeH = data.video_height;
                const img = new Image();
                img.onload = () => {
                    previewImage = img;
                    resizeCanvas();
                    redrawCanvas();
                    placeholder.style.display = 'none';
                    displayImg.style.display = 'none';
                    roiCanvas.style.display = 'block';
                };
                img.src = 'data:image/jpeg;base64,' + data.frame_b64;
            } else {
                alert('Error fetching frame: ' + data.message);
            }
        })
        .catch(err => {
            console.error(err);
            btnPreviewFrame.disabled = false;
            btnPreviewFrame.textContent = '🖼️ Preview 1st Frame';
        });
    }

    function resizeCanvas() {
        if (!roiCanvas || !screenWrapper) return;
        const rect = screenWrapper.getBoundingClientRect();
        roiCanvas.width = rect.width;
        roiCanvas.height = rect.height;
    }

    window.addEventListener('resize', () => {
        if (roiCanvas && previewImage) {
            resizeCanvas();
            redrawCanvas();
        }
    });

    function redrawCanvas() {
        if (!ctx || !previewImage) return;
        ctx.clearRect(0, 0, roiCanvas.width, roiCanvas.height);
        
        // Draw image scaled to canvas size maintaining aspect ratio
        ctx.drawImage(previewImage, 0, 0, roiCanvas.width, roiCanvas.height);

        // Draw overlay instructions if no box drawn
        if (!currentRect) {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.4)';
            ctx.fillRect(10, 10, 280, 32);
            ctx.fillStyle = '#38bdf8';
            ctx.font = '13px Inter, sans-serif';
            ctx.fillText('✏️ Click & drag rectangle over intruder', 18, 31);
        }

        // Draw rectangle if available
        if (currentRect) {
            ctx.fillStyle = 'rgba(244, 63, 94, 0.28)';
            ctx.fillRect(currentRect.x, currentRect.y, currentRect.w, currentRect.h);

            ctx.strokeStyle = '#f43f5e';
            ctx.lineWidth = 2;
            ctx.setLineDash([6, 4]);
            ctx.strokeRect(currentRect.x, currentRect.y, currentRect.w, currentRect.h);
            ctx.setLineDash([]);

            // Label tag on top of box
            ctx.fillStyle = '#f43f5e';
            ctx.fillRect(currentRect.x, Math.max(0, currentRect.y - 20), 100, 20);
            ctx.fillStyle = '#ffffff';
            ctx.font = 'bold 11px monospace';
            ctx.fillText('ERASE ROI', currentRect.x + 6, Math.max(14, currentRect.y - 6));
        }
    }

    function clearRoi() {
        currentRect = null;
        selectedRoi = null;
        updateRoiBadge();
        redrawCanvas();
    }

    function updateRoiBadge() {
        if (selectedRoi) {
            roiStatusBadge.textContent = `Ready (${selectedRoi.w}x${selectedRoi.h})`;
            roiStatusBadge.className = 'badge badge-roi ready';
            roiCoordsDisplay.textContent = `ROI: [ X: ${selectedRoi.x}, Y: ${selectedRoi.y}, W: ${selectedRoi.w}, H: ${selectedRoi.h} ]`;
        } else {
            roiStatusBadge.textContent = 'No Box Drawn';
            roiStatusBadge.className = 'badge badge-roi';
            roiCoordsDisplay.textContent = `ROI: [ X: --, Y: --, W: --, H: -- ]`;
        }
    }

    // Canvas Mouse Events for Rectangle Selection
    roiCanvas.addEventListener('mousedown', (e) => {
        if (!previewImage) return;
        const rect = roiCanvas.getBoundingClientRect();
        startX = e.clientX - rect.left;
        startY = e.clientY - rect.top;
        isDrawing = true;
        currentRect = null;
    });

    roiCanvas.addEventListener('mousemove', (e) => {
        if (!isDrawing || !previewImage) return;
        const rect = roiCanvas.getBoundingClientRect();
        const currentX = e.clientX - rect.left;
        const currentY = e.clientY - rect.top;

        const x = Math.min(startX, currentX);
        const y = Math.min(startY, currentY);
        const w = Math.abs(currentX - startX);
        const h = Math.abs(currentY - startY);

        currentRect = { x, y, w, h };
        redrawCanvas();
    });

    roiCanvas.addEventListener('mouseup', () => {
        if (!isDrawing) return;
        isDrawing = false;

        if (currentRect && currentRect.w > 6 && currentRect.h > 6) {
            // Scale canvas coordinates to native video resolution
            const scaleX = videoNativeW / roiCanvas.width;
            const scaleY = videoNativeH / roiCanvas.height;

            selectedRoi = {
                x: Math.round(currentRect.x * scaleX),
                y: Math.round(currentRect.y * scaleY),
                w: Math.round(currentRect.w * scaleX),
                h: Math.round(currentRect.h * scaleY)
            };
            updateRoiBadge();
            redrawCanvas();
        } else {
            currentRect = null;
            selectedRoi = null;
            updateRoiBadge();
            redrawCanvas();
        }
    });

    // --------------------------------------------------------------------------
    // Run Hardware Acceleration Pipeline (Supports Auto & Manual ROI)
    // --------------------------------------------------------------------------
    btnRunAccel.addEventListener('click', runAccelerator);

    function runAccelerator() {
        if (currentMode === 'manual' && !selectedRoi) {
            alert('Please click "Preview 1st Frame" and draw a box over the object to erase it!');
            return;
        }

        btnRunAccel.classList.add('btn-disabled');
        btnRunAccel.innerHTML = `<div class="spinner"></div> Streaming to FPGA...`;

        const endpoint = (currentMode === 'manual') ? '/api/process_roi' : '/api/process';
        const payload = (currentMode === 'manual') ? {
            filename: currentFilename,
            roi: selectedRoi,
            qp: parseInt(qpSlider.value)
        } : {
            filename: currentFilename,
            threshold: parseInt(threshSlider.value),
            qp: parseInt(qpSlider.value)
        };

        fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        })
        .then(res => res.json())
        .then(data => {
            btnRunAccel.classList.remove('btn-disabled');
            btnRunAccel.innerHTML = `🚀 Run FPGA Hardware Accelerator`;

            if (data.status === 'success') {
                snapshots = data.snapshots;
                updateMetrics(data.metrics);
                setupPlayback(data.clean_video_url);
            } else {
                alert('Processing Error: ' + data.message);
            }
        })
        .catch(err => {
            console.error(err);
            btnRunAccel.classList.remove('btn-disabled');
            btnRunAccel.innerHTML = `🚀 Run FPGA Hardware Accelerator`;
            alert('Processing pipeline error.');
        });
    }

    function updateMetrics(metrics) {
        metricPsnr.textContent = `${metrics.avg_psnr} dB`;
        metricHwLatency.textContent = `${metrics.hw_latency_ms} ms`;
        metricSavings.textContent = metrics.bitrate_savings;
        metricObjects.textContent = (metrics.total_objects_detected_px || metrics.total_removed_pixels || 0).toLocaleString();
        metricHwFps.textContent = `${metrics.hw_fps} FPS`;
        metricOffload.textContent = metrics.cpu_offload;
    }

    // --------------------------------------------------------------------------
    // Video / Snapshot Playback Controller
    // --------------------------------------------------------------------------
    function setupPlayback(cleanVideoUrl) {
        if (snapshots.length === 0) return;

        placeholder.style.display = 'none';
        roiCanvas.style.display = 'none';
        displayImg.style.display = 'block';

        timelineSlider.max = snapshots.length - 1;
        timelineSlider.value = 0;
        currentFrameIdx = 0;
        renderFrame(0);

        btnPlayPause.classList.remove('btn-disabled');
        btnDownload.classList.remove('btn-disabled');
        btnDownload.href = cleanVideoUrl;

        startAutoPlay();
    }

    function renderFrame(idx) {
        if (!snapshots[idx]) return;
        displayImg.src = 'data:image/jpeg;base64,' + snapshots[idx].img_b64;
        frameCounter.textContent = `Frame: ${snapshots[idx].frame_idx} / ${snapshots.length * 3}`;
        timelineSlider.value = idx;
    }

    timelineSlider.addEventListener('input', (e) => {
        stopAutoPlay();
        currentFrameIdx = parseInt(e.target.value);
        renderFrame(currentFrameIdx);
    });

    btnPlayPause.addEventListener('click', () => {
        if (isPlaying) {
            stopAutoPlay();
        } else {
            startAutoPlay();
        }
    });

    function startAutoPlay() {
        if (snapshots.length === 0) return;
        isPlaying = true;
        btnPlayPause.textContent = '⏸ Pause';
        clearInterval(playbackInterval);
        playbackInterval = setInterval(() => {
            currentFrameIdx = (currentFrameIdx + 1) % snapshots.length;
            renderFrame(currentFrameIdx);
        }, 120); // ~8.3 fps snapshot playback
    }

    function stopAutoPlay() {
        isPlaying = false;
        btnPlayPause.textContent = '▶ Play';
        clearInterval(playbackInterval);
    }
});
