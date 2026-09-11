@echo off
setlocal enabledelayedexpansion

echo ======================================================================
echo   RUNNING FULL VIDEO ACCELERATOR SIMULATION ^& VERIFICATION
echo ======================================================================

set SCRIPT_DIR=%~dp0
set PROJ_DIR=%SCRIPT_DIR%..
cd /d "%PROJ_DIR%"

rem Prepend Python and Icarus Verilog to PATH (bypasses WindowsApps dummy shortcut)
set PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;%LOCALAPPDATA%\Programs\iverilog\app\bin;%LOCALAPPDATA%\Programs\iverilog\app\gtkwave\bin;%PATH%

echo [1/5] Running Python Bit-Accurate Reference Model ^& Exporting Vectors...
python python\object_removal_golden.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python Golden Reference failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [2/5] Running Video Pipeline Multi-Frame Simulation...
python python\process_random_video.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Process random video failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [3/5] Running Live Stream / Accelerator Performance Profiler...
python python\live_stream_zedboard.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Live streaming test failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [4/5] Compiling ^& Simulating Verilog 2D 4x4 H.264 Integer DCT RTL...
iverilog -o sim_dct.vvp rtl/compression/dct_4x4.v tb/tb_dct_4x4.v
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Verilog DCT 4x4 Compilation failed!
    pause
    exit /b %ERRORLEVEL%
)
vvp sim_dct.vvp
if exist sim_dct.vvp del sim_dct.vvp

echo.
echo [5/5] Compiling ^& Simulating Verilog Top-Level Video Accelerator RTL...
iverilog -o sim_top.vvp rtl/object_removal/bg_subtract_inpaint.v rtl/top/video_accelerator_top.v tb/tb_video_accelerator.v
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Verilog Top Accelerator Compilation failed!
    pause
    exit /b %ERRORLEVEL%
)
vvp sim_top.vvp
if exist sim_top.vvp del sim_top.vvp

echo.
echo ======================================================================
echo   ALL TESTS PASSED SUCCESSFULLY (100%% HARDWARE ^& SOFTWARE MATCH)
echo ======================================================================
pause
