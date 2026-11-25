@echo off
rem Double-click to install the Saints Row The Third UI API Mod. Extra options are passed on, e.g.:
rem   install.bat -Examples      (adds a demo page)      install.bat -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
