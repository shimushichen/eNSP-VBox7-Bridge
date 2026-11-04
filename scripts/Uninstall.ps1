[CmdletBinding()]
param([string]$EnspDir,[string]$VBoxDir)
$ErrorActionPreference='Stop'
$uninstallArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Install.ps1'),'-Uninstall')
if($EnspDir){$uninstallArgs += @('-EnspDir',$EnspDir)}
if($VBoxDir){$uninstallArgs += @('-VBoxDir',$VBoxDir)}
# Install.ps1 owns uninstall.log, including errors and the final result.
& powershell.exe @uninstallArgs
exit $LASTEXITCODE
