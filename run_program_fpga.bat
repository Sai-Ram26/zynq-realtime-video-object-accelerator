@echo off
REM ==============================================================================
REM Program ZedBoard FPGA via Vivado Hardware Manager
REM Project: D:\mini_project2
REM Vivado : C:\AMDDesignTools\2026.1\Vivado
REM ==============================================================================

set "XILINX_VIVADO=C:\AMDDesignTools\2026.1\Vivado"
set "RDI_DATADIR=C:\AMDDesignTools\2026.1\data;C:\AMDDesignTools\2026.1\Vivado\data"
set "TCL_LIBRARY=C:\AMDDesignTools\2026.1\tps\tcl\tcl8.6"
set "PATH=C:\AMDDesignTools\2026.1\Vivado\bin;C:\AMDDesignTools\2026.1\Vivado\lib\win64.o;%PATH%"

cd /d "D:\mini_project2"

echo ==============================================================================
echo Programming ZedBoard FPGA via JTAG...
echo ==============================================================================

"C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode batch -source "D:/mini_project2/scripts/program_fpga.tcl" -notrace

echo.
echo ==============================================================================
echo Programming finished.
echo ==============================================================================
pause
