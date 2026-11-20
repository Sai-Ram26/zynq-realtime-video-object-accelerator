@echo off
setlocal
cd /d "%~dp0"

echo ================================================================
echo   ZYNQ-7000 VIDEO ACCELERATOR - CURRENT VALIDATION SUITE
echo ================================================================

call tb\run_sim.bat
if errorlevel 1 exit /b 1

python -m py_compile server.py movie_host.py dashboard\app.py
if errorlevel 1 (
    echo [FAIL] Python syntax validation failed.
    exit /b 1
)

echo.
echo Python syntax validation passed.
echo All available automated checks passed.
endlocal
exit /b 0
