@echo off
setlocal
cd /d "%~dp0"

:menu
cls
echo ==============================================
echo   V Rising Player UI Toolkit Launcher
echo ==============================================
echo.
echo   1^) Install Eclipse (recommended)
echo   2^) Install EclipsePlus
echo   3^) Show Status
echo   4^) Uninstall UI only
echo   5^) Full uninstall (UI + BepInEx)
echo   0^) Exit
echo.
set /p choice=Select option: 

if "%choice%"=="1" goto install_eclipse
if "%choice%"=="2" goto install_eclipseplus
if "%choice%"=="3" goto status
if "%choice%"=="4" goto uninstall
if "%choice%"=="5" goto full_uninstall
if "%choice%"=="0" goto end
goto menu

:install_eclipse
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Install
goto done

:install_eclipseplus
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Install -Ui eclipseplus
goto done

:status
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Status
goto done

:uninstall
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Uninstall
goto done

:full_uninstall
powershell -ExecutionPolicy Bypass -File ".\player-ui-windows.ps1" -Action Uninstall -Full
goto done

:done
echo.
echo Press any key to return to menu...
pause >nul
goto menu

:end
endlocal
