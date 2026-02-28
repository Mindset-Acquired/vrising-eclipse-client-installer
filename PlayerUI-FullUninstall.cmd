@echo off
setlocal
cd /d "%~dp0"
echo ==================================================
echo   V Rising Player UI - Full Uninstall
echo   (Eclipse + BepInEx runtime files)
echo ==================================================
echo.
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Uninstall -Full
echo.
echo Done. Press any key to close.
pause >nul
