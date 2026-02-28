@echo off
setlocal
cd /d "%~dp0"
echo ==============================================
echo   V Rising Player UI - Uninstall (UI only)
echo ==============================================
echo.
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Uninstall
echo.
echo Done. Press any key to close.
pause >nul
