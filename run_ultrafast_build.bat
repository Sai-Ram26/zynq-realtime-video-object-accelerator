@echo off
echo ========================================================================
echo   ULTRA-FAST FPGA BUILD — ZedBoard H.264 Accelerator
echo   Skips re-synthesis + Quick placement + 4 threads
echo   Expected time: 5-15 minutes
echo ========================================================================
cd /d "%~dp0"
C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch -source ultrafast_build.tcl -notrace
echo.
echo Build complete. Check RELEASE\encoder.bit
pause
