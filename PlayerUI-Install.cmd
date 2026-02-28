@echo off
setlocal
cd /d "%~dp0"
echo ==============================================
echo   V Rising Player UI - Install (Eclipse)
echo ==============================================
echo.
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Install
echo.
echo Done. Press any key to close.
pause >nul
