@echo off
setlocal
cd /d "%~dp0"
echo [1/2] Deploying local VBox52.dll. UAC may appear.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" %*
if errorlevel 1 goto install_failed
echo [2/2] Registering base VMs for the current user.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\RegisterVM.ps1" %*
if errorlevel 1 goto vm_failed
echo Install completed. Run Check.bat to inspect the state.
pause
exit /b 0
:install_failed
echo Install failed. See logs\install.log.
pause
exit /b 1
:vm_failed
echo DLL deployment completed, but VM registration returned an error.
pause
exit /b 1
