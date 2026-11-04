$ErrorActionPreference = 'SilentlyContinue'
$v = $null
try {
    $v = New-Object -ComObject 'VirtualBox.VirtualBox'
    Write-Output ("64-bit VirtualBox COM: " + $v.Version)
} catch {
    Write-Output ("64-bit VirtualBox COM: ERROR: " + $_.Exception.Message)
}
if ($v) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($v) }

$cls = 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}\InprocServer32'
$dll = (Get-ItemProperty $cls).'(default)'
Write-Output ("eNSP 32-bit InprocServer32: " + $dll)
Write-Output ("Oracle registry Version: " + (Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox').Version)

$svc = Get-Service MuMuRemoteService
if ($svc) { Write-Output ("MuMuRemoteService: " + $svc.Status + " / " + $svc.StartType) }
else { Write-Output 'MuMuRemoteService: not found' }
