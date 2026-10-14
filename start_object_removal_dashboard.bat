@echo off
echo ======================================================================
echo   STARTING REAL-TIME VIDEO ACCELERATOR OBJECT REMOVAL DASHBOARD
echo   Target Hardware: Avnet ZedBoard (Zynq-7000 SoC XC7Z020)
echo   Modes: Auto Detect (BG Subtraction) | Manual Draw ROI
echo ======================================================================

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

set PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;%PATH%

echo.
echo [*] Opening Dashboard in your Web Browser (http://127.0.0.1:5000)...
start "" cmd /c "timeout /t 2 /nobreak >nul && start http://127.0.0.1:5000"

echo [*] Launching Flask Dashboard Server...
python dashboard\app.py

echo.
echo [*] Server stopped.
pause
