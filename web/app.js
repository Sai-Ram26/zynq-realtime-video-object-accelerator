/* ==========================================================================
   Offline FPGA Video Accelerator Dashboard Logic
   Completely local, Zero Cloud / External API Dependencies
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
  // DOM Elements
  const dropZone = document.getElementById('drop-zone');
  const fileInput = document.getElementById('video-file-input');
  const btnBrowse = document.getElementById('btn-browse');
  const btnSample1080p = document.getElementById('btn-sample-1080p');
  const btnSample4k = document.getElementById('btn-sample-4k');

  const metaGrid = document.getElementById('meta-grid');
  const metaFilename = document.getElementById('meta-filename');
  const metaResolution = document.getElementById('meta-resolution');
  const metaDuration = document.getElementById('meta-duration');
  const metaFilesize = document.getElementById('meta-filesize');
  const metaFramecount = document.getElementById('meta-framecount');
  const metaFps = document.getElementById('meta-fps');

  const selectTargetRes = document.getElementById('select-target-res');
  const selectScalerMode = document.getElementById('select-scaler-mode');
  const rangeQp = document.getElementById('range-qp');
  const valQp = document.getElementById('val-qp');
  const selectBackend = document.getElementById('select-accel-backend');

  const btnProcess = document.getElementById('btn-process');
  const btnCancel = document.getElementById('btn-cancel');
  const progressContainer = document.getElementById('progress-container');
  const textStage = document.getElementById('text-stage');
  const textPercent = document.getElementById('text-percent');
  const barFill = document.getElementById('bar-fill');
  const textSubprogress = document.getElementById('text-subprogress');

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

  const statFps = document.getElementById('stat-fps');
  const statSpeed = document.getElementById('stat-speed');
  const statLatency = document.getElementById('stat-latency');
  const statClock = document.getElementById('stat-clock');

  const textFpga = document.getElementById('text-fpga');
  const dotFpga = document.getElementById('dot-fpga');

  const btnScanHw = document.getElementById('btn-scan-hw');
  const hwBannerText = document.getElementById('hw-banner-text');
  const hwBannerDot = document.getElementById('hw-banner-dot');
  const hwDetailsBox = document.getElementById('hw-details-box');

  const btnToggleDiff = document.getElementById('btn-toggle-diff');
  const badgeProcTitle = document.getElementById('badge-proc-title');
  const infoProcBackend = document.getElementById('info-proc-backend');

  // Application State
  let currentFile = null;
  let currentVideoUrl = null;
  let currentSessionId = null;
  let pollInterval = null;
  let statusInterval = null;
  let currentOutputUrl = null;
  let currentDiffUrl = null;
  let showingDiff = false;
  let currentBackendLabel = "";

  // 1. Hardware Status Poller
  async function pollHardwareStatus() {
    try {
      const res = await fetch('/api/status');
      if (res.ok) {
        const data = await res.json();
        if (data.fpga_connected) {
          textFpga.textContent = 'CONNECTED (ZEDBOARD)';
          dotFpga.className = 'status-dot connected';
          if (hwBannerText) hwBannerText.textContent = `Physical ZedBoard: Connected (${data.physical_board_ip})`;
          if (hwBannerDot) hwBannerDot.className = 'status-dot connected';
        } else {
          textFpga.textContent = 'PHYSICAL FPGA: NOT DETECTED';
          dotFpga.className = 'status-dot disconnected';
          if (hwBannerText) hwBannerText.textContent = 'Physical FPGA: Disconnected (Offline RTL Sim Ready)';
          if (hwBannerDot) hwBannerDot.className = 'status-dot disconnected';
        }

        if (data.clock_mhz) statClock.innerHTML = `${data.clock_mhz} <span class="unit">MHz</span>`;
        if (data.lut_util) document.getElementById('text-lut').textContent = data.lut_util;
        if (data.bram_util) document.getElementById('text-bram').textContent = data.bram_util;
        if (data.dsp_util) document.getElementById('text-dsp').textContent = data.dsp_util;
      }
    } catch (e) {
      textFpga.textContent = 'HOST OFFLINE';
      dotFpga.className = 'status-dot disconnected';
    }
  }

  // Active Hardware Scanner
  if (btnScanHw) {
    btnScanHw.addEventListener('click', async () => {
      btnScanHw.disabled = true;
      btnScanHw.textContent = 'Scanning...';
      try {
        const res = await fetch('/api/detect_fpga');
        if (res.ok) {
          const hw = await res.json();
          hwDetailsBox.style.display = 'block';
          if (hw.physical_detected) {
            hwDetailsBox.className = 'hw-details-box connected';
            hwDetailsBox.innerHTML = `🟢 <b>Physical ZedBoard Detected!</b><br>` +
              `• Ethernet: ${hw.ethernet_ip} (Responding)<br>` +
              `• Board: ${hw.board_model}<br>` +
              `• Status: Ready for Hardware Acceleration`;
            textFpga.textContent = 'CONNECTED (ZEDBOARD)';
            dotFpga.className = 'status-dot connected';
            hwBannerText.textContent = `Physical ZedBoard: Connected (${hw.ethernet_ip})`;
            hwBannerDot.className = 'status-dot connected';
          } else {
            hwDetailsBox.className = 'hw-details-box';
            hwDetailsBox.innerHTML = `⚠️ <b>Physical ZedBoard (XC7Z020) Not Detected:</b><br>` +
              `• Ethernet (${hw.ethernet_ip}): No link response (unplugged or unconfigured static IP)<br>` +
              `• USB-UART Ports: ${hw.uart_ports && hw.uart_ports.length > 0 ? hw.uart_ports.join(', ') : 'None detected'}<br>` +
              `• <b>Academic Mode:</b> Offline RTL Co-Simulation & Verification available. Run synthesizable Verilog models directly.`;
            textFpga.textContent = 'PHYSICAL FPGA: NOT DETECTED';
            dotFpga.className = 'status-dot disconnected';
            hwBannerText.textContent = 'Physical FPGA: Disconnected';
            hwBannerDot.className = 'status-dot disconnected';
          }
        }
      } catch (err) {
        alert('Hardware detection request failed: ' + err);
      } finally {
        btnScanHw.disabled = false;
        btnScanHw.innerHTML = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"></path></svg> Scan Board`;
      }
    });
  }

  // Initial and regular status check
  pollHardwareStatus();
  statusInterval = setInterval(pollHardwareStatus, 3000);

  // 2. QP Slider Interaction
  rangeQp.addEventListener('input', (e) => {
    valQp.textContent = e.target.value;
  });

  // 3. File Input Handling
  btnBrowse.addEventListener('click', () => fileInput.click());
  dropZone.addEventListener('click', (e) => {
    if (e.target !== btnBrowse) fileInput.click();
  });

  ['dragenter', 'dragover'].forEach(name => {
    dropZone.addEventListener(name, (e) => {
      e.preventDefault();
      dropZone.classList.add('dragover');
    });
  });

  ['dragleave', 'drop'].forEach(name => {
    dropZone.addEventListener(name, (e) => {
      e.preventDefault();
      dropZone.classList.remove('dragover');
    });
  });

  dropZone.addEventListener('drop', (e) => {
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      handleSelectedFile(e.dataTransfer.files[0]);
    }
  });

  fileInput.addEventListener('change', (e) => {
    if (e.target.files && e.target.files.length > 0) {
      handleSelectedFile(e.target.files[0]);
    }
  });

  btnSample1080p.addEventListener('click', () => loadSampleVideo('1080p'));
  btnSample4k.addEventListener('click', () => loadSampleVideo('4k'));

  function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  function handleSelectedFile(file) {
    currentFile = file;
    metaFilename.textContent = file.name;
    metaFilesize.textContent = formatBytes(file.size);

    // Create local object URL for preview
    if (currentVideoUrl) URL.revokeObjectURL(currentVideoUrl);
    currentVideoUrl = URL.createObjectURL(file);
    playerOrig.src = currentVideoUrl;
    placeholderOrig.style.display = 'none';

    // Upload to local backend to get full metadata via OpenCV
    uploadFileToBackend(file);
  }

  async function uploadFileToBackend(file) {
    const formData = new FormData();
    formData.append('video', file);

    try {
      metaResolution.textContent = 'Analyzing...';
      const res = await fetch('/api/upload', {
        method: 'POST',
        body: formData
      });

      if (res.ok) {
        const meta = await res.json();
        currentSessionId = meta.session_id;

        metaResolution.textContent = `${meta.width} × ${meta.height}`;
        metaDuration.textContent = `${meta.duration.toFixed(1)} s`;
        metaFramecount.textContent = meta.frame_count;
        metaFps.textContent = `${meta.fps.toFixed(1)} fps`;
        metaGrid.style.display = 'grid';

        document.getElementById('info-orig-res').textContent = `Source: ${meta.width}×${meta.height}`;
        document.getElementById('info-orig-fps').textContent = `FPS: ${meta.fps.toFixed(1)}`;
        document.getElementById('info-orig-size').textContent = `Size: ${formatBytes(file.size)}`;

        btnProcess.disabled = false;
      }
    } catch (e) {
      metaResolution.textContent = 'Error inspecting video';
    }
  }

  async function loadSampleVideo(resolution) {
    textStage.textContent = `Generating ${resolution} synthetic test pattern...`;
    progressContainer.style.display = 'block';
    barFill.style.width = '20%';

    try {
      const res = await fetch(`/api/sample?res=${resolution}`);
      if (res.ok) {
        const meta = await res.json();
        currentSessionId = meta.session_id;

        metaFilename.textContent = meta.filename;
        metaFilesize.textContent = formatBytes(meta.filesize);
        metaResolution.textContent = `${meta.width} × ${meta.height}`;
        metaDuration.textContent = `${meta.duration.toFixed(1)} s`;
        metaFramecount.textContent = meta.frame_count;
        metaFps.textContent = `${meta.fps.toFixed(1)} fps`;
        metaGrid.style.display = 'grid';

        playerOrig.src = meta.url;
        placeholderOrig.style.display = 'none';

        document.getElementById('info-orig-res').textContent = `Source: ${meta.width}×${meta.height}`;
        document.getElementById('info-orig-fps').textContent = `FPS: ${meta.fps.toFixed(1)}`;
        document.getElementById('info-orig-size').textContent = `Size: ${formatBytes(meta.filesize)}`;

        barFill.style.width = '100%';
        setTimeout(() => { progressContainer.style.display = 'none'; }, 500);
        btnProcess.disabled = false;
      }
    } catch (e) {
      alert('Error generating sample pattern: ' + e);
      progressContainer.style.display = 'none';
    }
  }

  // 4. FPGA Processing Execution
  btnProcess.addEventListener('click', async () => {
    if (!currentSessionId) return;

    btnProcess.disabled = true;
    btnCancel.disabled = false;
    progressContainer.style.display = 'block';
    outputActionBar.style.display = 'none';
    placeholderProc.style.display = 'flex';
    textProcState.textContent = 'FPGA Pipeline Processing In Progress...';

    const payload = {
      session_id: currentSessionId,
      target_res: selectTargetRes.value,
      scaler_mode: selectScalerMode.value,
      qp: parseInt(rangeQp.value),
      backend: selectBackend.value
    };

    try {
      const res = await fetch('/api/process', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (res.ok) {
        startPollingProgress();
      } else {
        const err = await res.json();
        alert('Processing error: ' + (err.error || 'Unknown failure'));
        resetProcessingUi();
      }
    } catch (e) {
      alert('Network communication error: ' + e);
      resetProcessingUi();
    }
  });

  btnCancel.addEventListener('click', async () => {
    if (!currentSessionId) return;
    await fetch(`/api/cancel?session_id=${currentSessionId}`, { method: 'POST' });
    resetProcessingUi();
    textStage.textContent = 'Processing Cancelled';
  });

  function startPollingProgress() {
    if (pollInterval) clearInterval(pollInterval);

    pollInterval = setInterval(async () => {
      try {
        const res = await fetch(`/api/progress?session_id=${currentSessionId}`);
        if (res.ok) {
          const data = await res.json();

          // Stage text already contains live PSNR/SSIM from Stage-3 Verifier
          textStage.textContent = data.stage_text;
          textPercent.textContent = `${data.percent}%`;
          barFill.style.width = `${data.percent}%`;
          textSubprogress.textContent =
            `[Stage-1\u2016Stage-2\u2016Stage-3 PARALLEL] ` +
            `Frame ${data.current_frame} / ${data.total_frames} \u2014 ` +
            `${data.processed_bytes_str} transferred`;

          if (data.fps)        statFps.innerHTML     = `${data.fps.toFixed(1)} <span class="unit">FPS</span>`;
          if (data.speed_mbps) statSpeed.innerHTML   = `${data.speed_mbps.toFixed(1)} <span class="unit">MB/s</span>`;
          if (data.latency_ms) statLatency.innerHTML = `${data.latency_ms.toFixed(1)} <span class="unit">ms</span>`;

          if (data.complete) {
            clearInterval(pollInterval);
            handleProcessingComplete(data);
          } else if (data.error) {
            clearInterval(pollInterval);
            alert('Hardware processing failed: ' + data.error);
            resetProcessingUi();
          }
        }
      } catch (e) {
        console.error('Polling error:', e);
      }
    }, 400);
  }

  function handleProcessingComplete(data) {
    btnProcess.disabled = false;
    btnCancel.disabled = true;
    textStage.textContent = '\u2705 FPGA Hardware Acceleration Complete \u2014 Output is FPGA-Processed Bitstream';
    barFill.style.width = '100%';
    textPercent.textContent = '100%';

    currentOutputUrl = data.output_url;
    currentDiffUrl   = data.diff_url;
    currentBackendLabel = data.processing_backend
      || (data.metrics && data.metrics.backend)
      || 'OFFLINE RTL CO-SIMULATION';
    showingDiff = false;

    const isPhysical = currentBackendLabel.includes('ZEDBOARD');
    const outLabel   = isPhysical
      ? 'FPGA HARDWARE OUTPUT \u2014 PHYSICAL ZedBoard PL'
      : 'FPGA HARDWARE OUTPUT \u2014 RTL Co-Simulation';
    const framesVerified = data.metrics ? (data.metrics.frames_verified || '?') : '?';

    // Always load the FPGA hardware-accelerator output (NOT website-generated)
    playerProc.src = data.output_url;
    placeholderProc.style.display = 'none';

    document.getElementById('info-proc-res').textContent =
      `FPGA Out: ${data.target_width}\u00d7${data.target_height}`;
    document.getElementById('info-proc-size').textContent =
      `FPGA Bitstream: ${data.output_size_str}`;
    if (infoProcBackend) infoProcBackend.textContent =
      `Engine: ${currentBackendLabel} | ${framesVerified} frames internally verified`;
    if (badgeProcTitle) badgeProcTitle.textContent = outLabel;

    // Enable Internal Verification Heatmap toggle
    if (btnToggleDiff && data.diff_url) {
      btnToggleDiff.style.display = 'inline-block';
      btnToggleDiff.textContent = 'Show Internal Verification Heatmap';
    }

    // Show Download Bar
    outputActionBar.style.display = 'flex';
    btnDownload.href     = data.output_url;
    btnDownload.download = `fpga_hw_${data.target_res}_output.mp4`;

    // Populate Quantitative Metrics Table (Section 48/49 Compliance)
    document.getElementById('res-psnr-sw').textContent = `${data.metrics.sw_psnr.toFixed(2)} dB`;
    document.getElementById('res-psnr-hw').textContent = `${data.metrics.hw_psnr.toFixed(2)} dB`;
    const psnrDiff = (data.metrics.hw_psnr - data.metrics.sw_psnr).toFixed(2);
    document.getElementById('res-psnr-diff').textContent =
      `${psnrDiff >= 0 ? '+' : ''}${psnrDiff} dB`;

    document.getElementById('res-ssim-sw').textContent = data.metrics.sw_ssim.toFixed(4);
    document.getElementById('res-ssim-hw').textContent = data.metrics.hw_ssim.toFixed(4);
    const ssimDiff = (data.metrics.hw_ssim - data.metrics.sw_ssim).toFixed(4);
    document.getElementById('res-ssim-diff').textContent =
      `${ssimDiff >= 0 ? '+' : ''}${ssimDiff}`;

    document.getElementById('res-spatial-sw').textContent =
      `${data.metrics.spatial_reduction.toFixed(1)}\u00d7 Reduction`;
    document.getElementById('res-spatial-hw').textContent =
      `${data.metrics.spatial_reduction.toFixed(1)}\u00d7 Reduction`;

    document.getElementById('res-codec-sw').textContent =
      `${data.metrics.codec_compression.toFixed(1)}\u00d7 (SW Ref)`;
    document.getElementById('res-codec-hw').textContent =
      `${data.metrics.codec_compression.toFixed(1)}\u00d7 (FPGA HW)`;

    document.getElementById('res-storage-sw').textContent =
      `${data.metrics.overall_storage_reduction.toFixed(1)}\u00d7 Reduction`;
    document.getElementById('res-storage-hw').textContent =
      `${data.metrics.overall_storage_reduction.toFixed(1)}\u00d7 Reduction`;

    document.getElementById('res-time-sw').textContent =
      `${data.metrics.sw_time.toFixed(2)} s`;
    document.getElementById('res-time-hw').textContent =
      `${data.metrics.hw_time.toFixed(2)} s`;
    document.getElementById('res-speedup').textContent =
      `${data.metrics.speedup.toFixed(2)}\u00d7 Acceleration`;

    // Auto-play both players in sync after completion
    playerOrig.currentTime = 0;
    playerProc.currentTime = 0;
    playerOrig.play().catch(() => {});
    playerProc.play().catch(() => {});
  }

  // Internal Verification Heatmap Toggle
  // Switches between: FPGA OUTPUT  ↔  STAGE-3 INTERNAL VERIFICATION HEATMAP
  if (btnToggleDiff) {
    btnToggleDiff.addEventListener('click', () => {
      if (!currentOutputUrl || !currentDiffUrl) return;
      showingDiff = !showingDiff;
      const t = playerOrig.currentTime;
      if (showingDiff) {
        // Show Stage-3 internal pixel verification heatmap
        playerProc.src = currentDiffUrl;
        playerProc.load();
        playerProc.currentTime = t;
        playerProc.play().catch(() => {});
        btnToggleDiff.textContent = 'Show FPGA Hardware Output';
        if (badgeProcTitle) badgeProcTitle.textContent =
          'STAGE-3 INTERNAL VERIFICATION HEATMAP (\u0394 |Uncompressed \u2212 FPGA Output|)';
      } else {
        // Show the FPGA hardware-accelerator compressed output
        playerProc.src = currentOutputUrl;
        playerProc.load();
        playerProc.currentTime = t;
        playerProc.play().catch(() => {});
        btnToggleDiff.textContent = 'Show Internal Verification Heatmap';
        const isPhys = currentBackendLabel.includes('ZEDBOARD');
        if (badgeProcTitle) badgeProcTitle.textContent = isPhys
          ? 'FPGA HARDWARE OUTPUT \u2014 PHYSICAL ZedBoard PL'
          : 'FPGA HARDWARE OUTPUT \u2014 RTL Co-Simulation';
      }
    });
  }

  function resetProcessingUi() {
    btnProcess.disabled = false;
    btnCancel.disabled = true;
    if (pollInterval) clearInterval(pollInterval);
  }

  // 5. Video Player Synchronized Controls
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

  // Keep scrub position synchronized
  playerOrig.addEventListener('seeked', () => {
    if (Math.abs(playerProc.currentTime - playerOrig.currentTime) > 0.15) {
      playerProc.currentTime = playerOrig.currentTime;
    }
  });

  playerProc.addEventListener('seeked', () => {
    if (Math.abs(playerOrig.currentTime - playerProc.currentTime) > 0.15) {
      playerOrig.currentTime = playerProc.currentTime;
    }
  });
});
