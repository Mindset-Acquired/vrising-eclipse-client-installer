@echo off
setlocal
cd /d "%~dp0"
echo ==============================================
echo   V Rising Player UI - Install (EclipsePlus)
echo ==============================================
echo.
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Install -Ui eclipseplus
echo.
echo Done. Press any key to close.
pause >nul
