/* ==========================================================================
   Minimalistic Video Compression Controller with Hardware Board Detection
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
  const dropZone = document.getElementById('drop-zone');
  const fileInput = document.getElementById('video-file-input');
  const rangeQp = document.getElementById('range-qp');
  const valQp = document.getElementById('val-qp');
  const selectTargetRes = document.getElementById('select-target-res');
  const btnProcess = document.getElementById('btn-process');
  const progressContainer = document.getElementById('progress-container');
  const textStage = document.getElementById('text-stage');
  const textPercent = document.getElementById('text-percent');
  const barFill = document.getElementById('bar-fill');

  const metaGrid = document.getElementById('meta-grid');
  const metaFilename = document.getElementById('meta-filename');
  const metaResolution = document.getElementById('meta-resolution');
  const metaDuration = document.getElementById('meta-duration');
  const metaFramecount = document.getElementById('meta-framecount');

  const playerOrig = document.getElementById('player-original');
  const playerProc = document.getElementById('player-processed');
  const placeholderOrig = document.getElementById('placeholder-original');
  const placeholderProc = document.getElementById('placeholder-processed');
  const textProcState = document.getElementById('text-processed-state');

  const btnSyncPlay = document.getElementById('btn-sync-play');
  const btnSyncPause = document.getElementById('btn-sync-pause');
  const btnSyncRestart = document.getElementById('btn-sync-restart');
  const outputActionBar = document.getElementById('output-action-bar');
  const btnDownload = document.getElementById('btn-download');

  // Hardware board status elements
  const boardStatusDot = document.getElementById('board-status-dot');
  const boardStatusText = document.getElementById('board-status-text');
  const btnRecheckBoard = document.getElementById('btn-recheck-board');
  const boardAlert = document.getElementById('board-alert');
  const alertTitle = document.getElementById('alert-title');
  const alertDesc = document.getElementById('alert-desc');
  const checkSimMode = document.getElementById('check-simulation-mode');

  let currentSessionId = null;
  let isBoardConnected = false;

  function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  // Check hardware board status
  async function checkBoardStatus() {
    boardStatusText.textContent = 'Detecting Board...';
    try {
      const res = await fetch('/api/detect_fpga');
      if (res.ok) {
        const data = await res.json();
        isBoardConnected = !!data.physical_detected;
        updateBoardUI(data);
      } else {
        isBoardConnected = false;
        updateBoardUI({ physical_detected: false, message: 'Server connection error' });
      }
    } catch (err) {
      isBoardConnected = false;
      updateBoardUI({ physical_detected: false, message: 'Could not connect to detection service' });
    }
    updateProcessButtonState();
  }

  function updateBoardUI(data) {
    const simAllowed = checkSimMode && checkSimMode.checked;

    if (data.physical_detected) {
      boardStatusDot.className = 'status-dot connected';
      boardStatusText.textContent = 'ZedBoard Connected';
      boardAlert.className = 'board-alert connected';
      alertTitle.textContent = 'ZedBoard FPGA Detected';
      alertDesc.textContent = `Hardware online: ${data.details.join(', ') || data.board_model}. Ready for DMA acceleration.`;
    } else if (simAllowed) {
      boardStatusDot.className = 'status-dot simulated';
      boardStatusText.textContent = 'Simulation Mode Active';
      boardAlert.className = 'board-alert simulated';
      alertTitle.textContent = 'Host Golden Model Simulation';
      alertDesc.textContent = 'FPGA hardware is offline. Running software verification model on host CPU.';
    } else {
      boardStatusDot.className = 'status-dot disconnected';
      boardStatusText.textContent = 'Board Disconnected';
      boardAlert.className = 'board-alert';
      alertTitle.textContent = 'FPGA Board Not Detected';
      alertDesc.textContent = 'Connect ZedBoard via USB-UART or Ethernet, or enable Host Simulation Mode below to test.';
    }
  }

  function updateProcessButtonState() {
    const simAllowed = checkSimMode && checkSimMode.checked;
    const canRun = currentSessionId && (isBoardConnected || simAllowed);
    btnProcess.disabled = !canRun;
    if (!currentSessionId) {
      btnProcess.title = 'Select and upload a video first';
    } else if (!isBoardConnected && !simAllowed) {
      btnProcess.title = 'FPGA board not connected. Connect ZedBoard or enable simulation mode.';
    } else {
      btnProcess.title = 'Ready to compress';
    }
  }

  // Periodic board polling every 5s & on-demand re-check
  btnRecheckBoard.addEventListener('click', checkBoardStatus);
  if (checkSimMode) {
    checkSimMode.addEventListener('change', () => {
      checkBoardStatus();
    });
  }
  setInterval(checkBoardStatus, 5000);
  checkBoardStatus();

  // QP Slider
  rangeQp.addEventListener('input', (e) => {
    valQp.textContent = e.target.value;
  });

  // Upload trigger
  dropZone.addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', (e) => {
    if (e.target.files && e.target.files[0]) {
      handleFile(e.target.files[0]);
    }
  });

  dropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropZone.classList.add('drag-over');
  });

  dropZone.addEventListener('dragleave', () => {
    dropZone.classList.remove('drag-over');
  });

  dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.classList.remove('drag-over');
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      handleFile(e.dataTransfer.files[0]);
    }
  });

  function handleFile(file) {
    metaFilename.textContent = file.name;
    const url = URL.createObjectURL(file);
    playerOrig.src = url;
    playerOrig.style.display = 'block';
    placeholderOrig.style.display = 'none';

    // Reset processed side & download bar when a new file is loaded
    playerProc.style.display = 'none';
    playerProc.src = '';
    placeholderProc.style.display = 'flex';
    textProcState.textContent = 'Awaiting board detection & compression';
    outputActionBar.style.display = 'none';
    btnDownload.removeAttribute('href');

    uploadFile(file);
  }

  async function uploadFile(file) {
    const formData = new FormData();
    formData.append('video', file);

    try {
      metaResolution.textContent = 'Inspecting...';
      const res = await fetch('/api/upload', {
        method: 'POST',
        body: formData
      });

      if (res.ok) {
        const data = await res.json();
        currentSessionId = data.session_id;

        metaResolution.textContent = `${data.width} × ${data.height}`;
        metaDuration.textContent = `${data.duration.toFixed(1)} s`;
        metaFramecount.textContent = data.frame_count;
        metaGrid.style.display = 'grid';

        document.getElementById('info-orig-res').textContent = `Source: ${data.width}×${data.height}`;
        document.getElementById('info-orig-fps').textContent = `FPS: ${data.fps.toFixed(1)}`;
        document.getElementById('info-orig-size').textContent = `Size: ${formatBytes(file.size)}`;

        updateProcessButtonState();
      }
    } catch (err) {
      metaResolution.textContent = 'Error reading file';
    }
  }

  // Process / Compress
  btnProcess.addEventListener('click', async () => {
    if (!currentSessionId) {
      alert('Please select and upload a video file first.');
      return;
    }

    const simAllowed = checkSimMode && checkSimMode.checked;
    if (!isBoardConnected && !simAllowed) {
      alert('Cannot start compression: FPGA ZedBoard is not detected.\n\nPlease connect the ZedBoard via USB-UART or Ethernet, or enable "Host Simulation Mode" if testing offline.');
      return;
    }

    btnProcess.disabled = true;
    progressContainer.style.display = 'block';
    barFill.style.width = '10%';
    textStage.textContent = isBoardConnected ? 'Streaming frames to FPGA via AXI DMA...' : 'Compressing video via host model...';
    textPercent.textContent = '10%';

    const progressTimer = setInterval(async () => {
      try {
        const pres = await fetch(`/api/progress?session_id=${currentSessionId}`);
        if (pres.ok) {
          const pdata = await pres.json();
          barFill.style.width = `${pdata.progress}%`;
          textPercent.textContent = `${pdata.progress}%`;
        }
      } catch (e) {}
    }, 400);

    try {
      const res = await fetch('/api/process', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_id: currentSessionId,
          target_resolution: selectTargetRes.value,
          qp: parseInt(rangeQp.value),
          allow_simulation: simAllowed
        })
      });

      clearInterval(progressTimer);

      if (res.ok) {
        const result = await res.json();
        barFill.style.width = '100%';
        textPercent.textContent = '100%';
        textStage.textContent = 'Compression complete!';

        // Display the FPGA accelerated output video alongside the input video
        playerProc.src = result.output_url;
        playerProc.style.display = 'block';
        placeholderProc.style.display = 'none';

        document.getElementById('info-proc-res').textContent = `Output: ${selectTargetRes.value}`;
        document.getElementById('info-proc-fps').textContent = `Throughput: ${result.fps} FPS`;

        // Only show download button now that hardware/sim compression has completed!
        btnDownload.href = result.output_url;
        outputActionBar.style.display = 'block';
      } else {
        const errData = await res.json();
        textStage.textContent = errData.message || 'Error during processing';
        alert('Processing Error: ' + (errData.message || 'Board not connected'));
      }
    } catch (err) {
      clearInterval(progressTimer);
      textStage.textContent = 'Error during processing';
    } finally {
      updateProcessButtonState();
    }
  });

  // Sync Video Controls (plays input video and FPGA output video synchronously)
  btnSyncPlay.addEventListener('click', () => {
    playerOrig.play();
    playerProc.play();
  });

  btnSyncPause.addEventListener('click', () => {
    playerOrig.pause();
    playerProc.pause();
  });

  btnSyncRestart.addEventListener('click', () => {
    playerOrig.currentTime = 0;
    playerProc.currentTime = 0;
    playerOrig.play();
    playerProc.play();
  });
});
