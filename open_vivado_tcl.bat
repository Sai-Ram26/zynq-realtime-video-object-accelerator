@echo off
REM ==============================================================================
REM Open Vivado TCL Shell inside D:\mini_project2 using Vivado from C: drive
REM Fixes: RDI_DATADIR and TCL_LIBRARY environment variables
REM ==============================================================================

set "XILINX_VIVADO=C:\AMDDesignTools\2026.1\Vivado"
set "RDI_DATADIR=C:\AMDDesignTools\2026.1\data;C:\AMDDesignTools\2026.1\Vivado\data"
set "TCL_LIBRARY=C:\AMDDesignTools\2026.1\tps\tcl\tcl8.6"
set "PATH=C:\AMDDesignTools\2026.1\Vivado\bin;C:\AMDDesignTools\2026.1\Vivado\lib\win64.o;%PATH%"

cd /d "D:\mini_project2"

echo ==============================================================================
echo Vivado 2026.1 Environment Initialized Successfully
echo Working Directory: %CD%
echo ==============================================================================
echo.

"C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode tcl
