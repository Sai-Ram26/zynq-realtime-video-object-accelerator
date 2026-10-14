@echo off
echo ======================================================================
echo   ZYNQ-7000 VIDEO ACCELERATOR - OFFLINE FPGA COMPRESSION DASHBOARD
echo   Target Hardware: Avnet ZedBoard (Zynq-7000 SoC XC7Z020)
echo   Host: Completely Offline (Zero Cloud / Zero External APIs)
echo ======================================================================

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

rem Ensure Python is in PATH
set PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;%PATH%

echo.
echo [*] Checking Python environment...
python --version
if errorlevel 1 (
    echo [!] ERROR: Python 3.11 not found. Please install Python 3.11 first.
    pause
    exit /b 1
)

echo.
echo [*] Checking required packages...
python -c "import flask, cv2, numpy; print('  -> flask, opencv, numpy: OK')"
if errorlevel 1 (
    echo [!] Installing missing dependencies...
    python -m pip install flask opencv-python numpy scipy pillow --quiet
)

echo.
echo [*] Starting Mock ZedBoard Hardware Server (TCP port 5000)...
echo [*] Starting Flask Web Dashboard Server (HTTP port 8080)...
echo.
echo [*] Dashboard will open at: http://127.0.0.1:8080
echo [*] Press Ctrl+C in this window to stop the server.
echo.

rem Open browser after a 2-second delay to allow Flask to start
start "" cmd /c "timeout /t 2 /nobreak >nul && start http://127.0.0.1:8080"

rem Launch the Flask backend (blocks until Ctrl+C)
python host\server\app.py

echo.
echo [*] Server stopped.
pause
