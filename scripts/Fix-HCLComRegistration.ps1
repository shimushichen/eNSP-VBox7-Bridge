<#
.SYNOPSIS
    Repair VirtualBox COM registration for HCL 5.10.3 on 64-bit Windows.

.DESCRIPTION
    HCL 5.10.3 is a 64-bit process and activates VirtualBox through the
    machine-wide ProgIDs VirtualBox.VirtualBox / VirtualBoxClient / Session.
    Two things break it on an eNSP + MuMu machine:

      1. The eNSP installer writes a 64-bit InprocServer32 under
         CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F} pointing at the x86
         VBox52.dll. 64-bit COM then fails with 0x800700C1.
      2. MuMu Player owns the six VirtualBox ProgIDs with its MuMuVMM CLSIDs,
         so HCL talks to MuMu 6.1.36_OSE instead of Oracle VirtualBox 7.2.

    This script is a compatibility wrapper around Set-VBoxComMode.ps1: it
    applies Oracle mode (removes the 64-bit x86 shim, points the six ProgIDs
    at Oracle VirtualBox 7.2, keeps LocalServer32 -> VBoxSVC.exe) and never
    touches the 32-bit WOW6432Node view used by eNSP.

    Every run creates a complete snapshot under
    logs\vbox-com-mode-backup-<stamp>\ (six ProgID keys, the three 64-bit
    Oracle CLSIDs, and a read-only eNSP 32-bit export). -Restore replays the
    newest snapshot exactly; older logs\hcl-com-backup-* directories are also
    accepted in legacy mode.

.PARAMETER Restore
    Undo the last Oracle-mode switch by restoring the newest snapshot.

.PARAMETER BackupDir
    Snapshot directory used by -Restore.

.PARAMETER SkipComTest
    Skip the COM activation test after switching (registry read-back and the
    eNSP 32-bit fingerprint check still run).

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Fix-HCLComRegistration.ps1

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Fix-HCLComRegistration.ps1 -Restore

.NOTES
    HCL 5.10.3 still uses the VirtualBox 5.x/6.0 vboxapi and will hit API
    differences (CreateMachine signature, AudioAdapter, GetMaxNetworkAdapters)
    even when it successfully connects to Oracle VirtualBox 7.2. This script
    fixes COM registration only; it does not make HCL 5.10.3 fully usable.
#>
[CmdletBinding(DefaultParameterSetName = 'Fix')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$BackupDir,

    [switch]$SkipComTest
)

$ErrorActionPreference = 'Stop'

$modeScript = Join-Path $PSScriptRoot 'Set-VBoxComMode.ps1'
if (-not (Test-Path -LiteralPath $modeScript)) {
    throw "Required script not found: $modeScript"
}

$parameters = @{}
if ($Restore) {
    Write-Host 'Fix-HCLComRegistration: restoring the newest VirtualBox COM snapshot ...'
    $parameters.Restore = $true
    if ($BackupDir) { $parameters.BackupDir = $BackupDir }
} else {
    Write-Host 'Fix-HCLComRegistration: switching VirtualBox COM to Oracle mode for HCL ...'
    $parameters.Mode = 'Oracle'
}
if ($SkipComTest) { $parameters.SkipComTest = $true }

& $modeScript @parameters
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 0 }
exit $exitCode
