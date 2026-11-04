@echo off
setlocal
cd /d "%~dp0"
echo Restoring original eNSP files and registry values. UAC may appear.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1" %*
set "rc=%errorlevel%"
if not "%rc%"=="0" echo Uninstall failed. See logs\install.log.
if "%rc%"=="0" echo Uninstall completed. eNSP, VirtualBox, and registered VMs were kept.
pause
exit /b %rc%
