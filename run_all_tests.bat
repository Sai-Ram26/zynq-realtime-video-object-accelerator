@echo off
setlocal enabledelayedexpansion

echo ======================================================================
echo   ZYNQ-7000 VIDEO ACCELERATOR - COMPLETE AUTOMATED VERIFICATION SUITE
echo   Runs: RTL Simulations (Icarus Verilog), Host Pipeline, Comm, & Benchmarks
echo ======================================================================

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

set PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;%LOCALAPPDATA%\Programs\iverilog\app\bin;%LOCALAPPDATA%\Programs\iverilog\app\gtkwave\bin;%PATH%

echo.
echo ======================================================================
echo   PART 1: 8-STAGE RTL PIPELINE VERIFICATION (tb\run_sim.bat)
echo ======================================================================
call tb\run_sim.bat
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] RTL Simulation suite failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ======================================================================
echo   PART 2: FPGA HARDWARE IP SIMULATION TESTBENCHES
echo ======================================================================
echo [*] Running tb_video_accelerator_top.v...
iverilog -g2012 -o sim_top.vvp fpga/rtl/rgb2yuv.v fpga/rtl/streaming_scaler.v fpga/rtl/block_assembler_4x4.v fpga/rtl/dct_4x4.v fpga/rtl/quant.v fpga/rtl/cavlc.v fpga/rtl/axis_fifo.v fpga/rtl/axi_lite_regs.v fpga/rtl/riscv_custom_video_decoder.v fpga/rtl/video_accelerator_top.v fpga/simulation/tb_video_accelerator_top.v
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )
vvp sim_top.vvp
del sim_top.vvp

echo.
echo [*] Running tb_riscv_custom_isa.v...
iverilog -g2012 -o sim_riscv.vvp fpga/rtl/riscv_custom_video_decoder.v fpga/simulation/tb_riscv_custom_isa.v
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )
vvp sim_riscv.vvp
del sim_riscv.vvp

echo.
echo [*] Running tb_streaming_scaler.v...
iverilog -g2012 -o sim_scaler.vvp fpga/rtl/streaming_scaler.v fpga/simulation/tb_streaming_scaler.v
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )
vvp sim_scaler.vvp
del sim_scaler.vvp

echo.
echo [*] Running tb_axi_lite_regs.v...
iverilog -g2012 -o sim_regs.vvp fpga/rtl/axi_lite_regs.v fpga/simulation/tb_axi_lite_regs.v
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )
vvp sim_regs.vvp
del sim_regs.vvp

echo.
echo [*] Running tb_axis_fifo.v...
iverilog -g2012 -o sim_fifo.vvp fpga/rtl/axis_fifo.v fpga/simulation/tb_axis_fifo.v
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )
vvp sim_fifo.vvp
del sim_fifo.vvp

echo.
echo ======================================================================
echo   PART 3: HOST LAPTOP AND ETHERNET PROTOCOL TESTBENCHES
echo ======================================================================
echo [*] Running Phase 2 TCP Communication and Error Rejection Test...
python host\tests\test_phase2_comm.py 5
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )

echo.
echo [*] Running Phase 1 Offline Web Application and Parallel Pipeline Test...
python host\tests\test_phase1.py
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )

echo.
echo ======================================================================
echo   PART 4: 8-PRIMARY RESOLUTION CONVERSION BENCHMARK MATRIX (TM-01 to TM-08)
echo ======================================================================
python host\tests\benchmark_suite.py
if %ERRORLEVEL% NEQ 0 ( pause & exit /b %ERRORLEVEL% )

echo.
echo ======================================================================
echo   ALL SYSTEM TESTS AND BENCHMARKS PASSED 100%!
echo ======================================================================
pause
