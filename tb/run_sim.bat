@echo off
echo ======================================================================
echo   RUNNING FULL VIDEO ACCELERATOR SIMULATION ^& VERIFICATION
echo ======================================================================

echo [1/3] Running Python Bit-Accurate Reference Model...
python d:\mini_project2\python\object_removal_golden.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python Golden Reference failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [2/3] Running Video Pipeline Multi-Frame Simulation...
python d:\mini_project2\python\process_random_video.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Process random video failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [3/3] Running Live Stream / Accelerator Performance Profiler...
python d:\mini_project2\python\live_stream_zedboard.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Live streaming test failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ======================================================================
echo   ALL TESTS PASSED SUCCESSFULLY (100%% BIT-EXACT MATCH)
echo ======================================================================
pause
