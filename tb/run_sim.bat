@echo off
REM =============================================================================
REM  run_sim.bat  –  Icarus Verilog simulation suite for ZedBoard H.264 Accelerator
REM  Requires: iverilog and vvp on PATH
REM  Usage: double-click or run from cmd
REM =============================================================================
setlocal

REM Ensure current working directory is the repository root
cd /d "%~dp0.."

echo =====================================================
echo  H.264 Video Accelerator Simulation Suite
echo =====================================================

set RTL=rtl\compression
set TOP=rtl\top
set RISCV=rtl\riscv
set TB=tb

REM --- Source file list (all compression + top) ---
set SRCS=^
 %RTL%\block_assembler_4x4.v^
 %RTL%\intra_pred_4x4.v^
 %RTL%\macroblock_skip.v^
 %RTL%\dct_4x4.v^
 %RTL%\quant.v^
 %RTL%\cavlc.v^
 %RTL%\cabac.v^
 %RTL%\h264_encoder.v^
 %TOP%\video_accelerator_top.v

REM --- Check iverilog is installed ---
where iverilog >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] iverilog not found. Install Icarus Verilog from:
    echo         http://bleyer.org/icarus/
    echo         Then add it to PATH and re-run this script.
    pause
    exit /b 1
)

REM -----------------------------------------------------------------------
REM  Test 1: Full system AXI & H.264 pipeline testbench
REM -----------------------------------------------------------------------
echo.
echo [1/3] Compiling full system AXI & H.264 testbench...
iverilog -g2012 -Wall -o sim_top.vvp %SRCS% %TB%\tb_video_accelerator.v
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] Compile error in full system testbench
    goto :end
)
echo Running sim...
vvp sim_top.vvp
del sim_top.vvp 2>nul

REM -----------------------------------------------------------------------
REM  Test 2: Multiplierless 4x4 Integer DCT Core testbench
REM -----------------------------------------------------------------------
echo.
echo [2/3] Compiling DCT 4x4 testbench...
iverilog -g2012 -Wall -o sim_dct.vvp %RTL%\dct_4x4.v %TB%\tb_dct_4x4.v
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] Compile error in DCT testbench
    goto :end
)
echo Running sim...
vvp sim_dct.vvp
del sim_dct.vvp 2>nul

REM -----------------------------------------------------------------------
REM  Test 3: RISC-V Custom Video ISA Extension (Opcode 0x0B) testbench
REM -----------------------------------------------------------------------
echo.
echo [3/3] Compiling RISC-V Custom Video Instruction Decoder testbench...
iverilog -g2012 -Wall -o sim_riscv.vvp %RISCV%\riscv_custom_video_decoder.v %TB%\tb_riscv_custom_decoder.v
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] Compile error in RISC-V testbench
    goto :end
)
echo Running sim...
vvp sim_riscv.vvp
del sim_riscv.vvp 2>nul

:end
echo.
echo =====================================================
echo  Simulation suite complete.
echo =====================================================
endlocal
pause
