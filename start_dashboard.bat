@echo off
echo ======================================================================
echo   STARTING REAL-TIME VIDEO ACCELERATOR VERIFICATION DASHBOARD
echo   Target Hardware: Avnet ZedBoard (Zynq-7000 SoC)
echo ======================================================================

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

rem Ensure Python is in PATH
set PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;%PATH%

echo.
echo [*] Opening Dashboard in your Web Browser...
start "" "http://127.0.0.1:5000"

echo [*] Launching Flask Dashboard Server...
python dashboard\app.py

pause
