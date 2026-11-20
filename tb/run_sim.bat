@echo off
REM =============================================================================
REM  run_sim.bat - Vivado simulation suite for the current ZedBoard accelerator
REM  Requires: AMD Vivado with xvlog, xelab, and xsim
REM  Usage: double-click or run from cmd
REM =============================================================================
setlocal

REM Ensure current working directory is the repository root
cd /d "%~dp0.."

echo =====================================================
echo  H.264 Video Accelerator Simulation Suite
echo =====================================================

set "VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin"
if not exist "%VIVADO_BIN%\xvlog.bat" if defined XILINX_VIVADO set "VIVADO_BIN=%XILINX_VIVADO%\bin"
if not exist "%VIVADO_BIN%\xvlog.bat" (
    echo [ERROR] Vivado simulation tools were not found.
    echo         Expected: %VIVADO_BIN%\xvlog.bat
    pause
    exit /b 1
)

set "PATH=C:\AMDDesignTools\2026.1\Vivado\tps\mingw\10.0.0\win64.o\nt\bin;C:\AMDDesignTools\2026.1\Vivado\tps\mingw\6.2.0\win64.o\nt\bin;C:\AMDDesignTools\2026.1\Vivado\bin\unwrapped\win64.o;%PATH%"

echo Compiling current RTL and stage testbenches...
call "%VIVADO_BIN%\xvlog.bat" -sv -work xil_defaultlib ^
    "%~dp0..\h264_accel_top.sv" ^
    "%~dp0..\rtl\video_scaler.sv" ^
    "%~dp0..\rtl\model4_yuv420_scaler.sv" ^
    "%~dp0..\rtl\model4_yuv420_source_frontend.sv" ^
    "%~dp0..\rtl\model4_yuv420_macroblock_packer.sv" ^
    "%~dp0..\rtl\model4_source_to_tiles.sv" ^
    "%~dp0..\rtl\model4_fmp4_muxer.sv" ^
    "%~dp0tb_stage2_pico.v" ^
    "%~dp0tb_stage3_mailbox.v" ^
    "%~dp0tb_stage4_ddr_engine.v" ^
    "%~dp0tb_video_scaler.sv" ^
    "%~dp0tb_model4_yuv420_scaler.sv" ^
    "%~dp0tb_model4_yuv420_source_frontend.sv" ^
    "%~dp0tb_model4_yuv420_macroblock_packer.sv" ^
    "%~dp0tb_model4_source_to_tiles.sv" ^
    "%~dp0tb_model4_fmp4_muxer.sv"
if errorlevel 1 goto :fail

for %%T in (stage2_pico stage3_mailbox stage4_ddr_engine video_scaler model4_yuv420_scaler model4_yuv420_source_frontend model4_yuv420_macroblock_packer model4_source_to_tiles model4_fmp4_muxer) do (
    echo.
    echo Running %%T...
    call "%VIVADO_BIN%\xelab.bat" xil_defaultlib.tb_%%T -s sim_%%T
    if errorlevel 1 goto :fail
    call "%VIVADO_BIN%\xsim.bat" sim_%%T -runall
    if errorlevel 1 goto :fail
)

echo.
echo All current RTL simulations passed.
call :cleanup
exit /b 0

:fail
echo.
echo RTL simulation suite failed.
call :cleanup
exit /b 1

:cleanup
if exist xsim.dir rmdir /s /q xsim.dir
if exist xvlog.pb del /q xvlog.pb
if exist xelab.pb del /q xelab.pb
for %%F in (sim_stage2_pico.wdb sim_stage3_mailbox.wdb sim_stage4_ddr_engine.wdb) do if exist %%F del /q %%F
endlocal
