<#
.SYNOPSIS
  Launch HCL 5.10.3 in Oracle VirtualBox 7.2 mode, with the HCL VBox72
  compatibility shim applied to the win32com gen_py cache.

.DESCRIPTION
  This is the "switch mode" workflow requested for the MuMu + HCL coexistence:

    1. Back up the current HCL gen_py cache.
    2. Append scripts\hcl-vbox72-shim.py to the cache if not already present.
    3. Switch the machine-wide VirtualBox ProgIDs to Oracle 7.2.
    4. Start HCL.
    5. When HCL exits: restore the gen_py cache and switch back to MuMu.

  The 32-bit eNSP CLSID view is never touched by Set-VBoxComMode.ps1.
  Do not run HCL and MuMu at the same time.

.PARAMETER HclDir
  HCL application directory containing SimwareClient.exe. Defaults to the
  extracted portable copy E:\HCL_5.10.3\app.

.PARAMETER HclExe
  Executable to start. Defaults to SimwareClient.exe (asInvoker). Use
  "H3C Cloud Lab.exe" only if you need the admin launcher.

.PARAMETER KeepShim
  Leave the gen_py shim in place after HCL exits. By default the pre-run
  cache is restored.

.PARAMETER Elevated
  Internal: marks that this invocation is already running elevated.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Use-HCL.ps1

.NOTES
  The script self-elevates via UAC when started unelevated. The final state
  is always MuMu mode unless the script is killed before its finally block.
#>
[CmdletBinding()]
param(
    [string]$HclDir = 'E:\HCL_5.10.3\app',
    [string]$HclExe = 'SimwareClient.exe',
    [string]$EnspDir,
    [string]$VBoxDir,
    [switch]$KeepShim,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
# Match Set-VBoxComMode.ps1: write logs to the bridge cache when released there.
$BridgeRoot = Join-Path $env:LOCALAPPDATA 'eNSP-VBox7-Bridge'
if ((Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)) -eq 'eNSP-VBox7-Bridge') {
    $LogsRoot = Join-Path $BridgeRoot 'logs'
} else {
    $LogsRoot = Join-Path $ProjectRoot 'logs'
}
$ModeScript = Join-Path $PSScriptRoot 'Set-VBoxComMode.ps1'
$ShimPath = Join-Path $PSScriptRoot 'hcl-vbox72-shim.py'
$Marker = 'VESPERASH_HCL_VBOX72_SHIM_V1'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $LogsRoot "hcl-session-$Stamp.log"
$BackupDir = Join-Path $LogsRoot 'gen_py_backup'

function Find-HclDir([string]$Preferred) {
    $candidates = @(
        $Preferred,
        'E:\HCL_5.10.3\app',
        'C:\Program Files (x86)\HCL',
        'C:\Program Files\HCL',
        'C:\Program Files (x86)\HCL\HCL',
        'C:\Program Files\HCL\HCL'
    ) | Where-Object { $_ } | Select-Object -Unique
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'SimwareClient.exe')) { return (Resolve-Path $c).Path }
    }
    throw 'HCL SimwareClient.exe not found. Specify -HclDir.'
}

function Get-GenPyFile {
    $dir = Join-Path $env:TEMP 'gen_py\3.8'
    if (-not (Test-Path $dir)) { return $null }
    Get-ChildItem $dir -Filter 'D7569351-*.py' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Stop-HclProcesses {
    Get-Process SimwareClient, SimwareWrapper, SimwareMultiCC, QtWebEngineProcess -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Self-elevate like Set-VBoxComMode.ps1 does, instead of #Requires, so that
# a cancelled UAC prompt produces a clear message rather than a raw exit 1.
if (-not (Test-IsAdmin)) {
    if ($Elevated) {
        Write-Host 'ERROR: UAC elevation failed or was cancelled.'
        exit 1
    }
    Write-Host 'Requesting administrator elevation...'
    $self = (Resolve-Path $PSCommandPath).Path
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $self), '-Elevated')
    if ($HclDir) { $arguments += @('-HclDir', ('"{0}"' -f $HclDir)) }
    if ($HclExe -ne 'SimwareClient.exe') { $arguments += @('-HclExe', ('"{0}"' -f $HclExe)) }
    if ($EnspDir) { $arguments += @('-EnspDir', ('"{0}"' -f $EnspDir)) }
    if ($VBoxDir) { $arguments += @('-VBoxDir', ('"{0}"' -f $VBoxDir)) }
    if ($KeepShim) { $arguments += '-KeepShim' }
    $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $proc.ExitCode
}

New-Item -ItemType Directory -Force $BackupDir | Out-Null
Start-Transcript -Path $LogPath -Force | Out-Null
$origGenPy = $null
$backupGenPy = $null
$shimApplied = $false

try {
    if (-not (Test-Path $ModeScript)) { throw "Mode switch script missing: $ModeScript" }
    if (-not (Test-Path $ShimPath)) { throw "Shim file missing: $ShimPath" }
    $HclDir = Find-HclDir $HclDir
    $HclPath = Join-Path $HclDir $HclExe
    if (-not (Test-Path $HclPath)) { throw "HCL executable not found: $HclPath" }

    Write-Host "HCL dir: $HclDir"
    Write-Host "HCL exe: $HclPath"
    Write-Host "Log: $LogPath"

    # Make sure HCL has generated its 7.2 gen_py cache at least once.
    $genPy = Get-GenPyFile
    if (-not $genPy) {
        Write-Host 'gen_py cache not found; starting HCL once to generate it...'
        & $ModeScript -Mode Oracle
        if ($LASTEXITCODE -ne 0) { throw "Set-VBoxComMode -Mode Oracle failed (exit $LASTEXITCODE). See logs\set-vbox-mode-oracle-*.log" }
        $warm = Start-Process -FilePath $HclPath -WorkingDirectory $HclDir -PassThru
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline -and -not (Get-GenPyFile)) { Start-Sleep -Seconds 1 }
        Stop-HclProcesses
        $genPy = Get-GenPyFile
        if (-not $genPy) { throw 'HCL did not generate gen_py cache.' }
    }

    $origGenPy = $genPy.FullName
    $backupGenPy = Join-Path $BackupDir ($genPy.Name + '.' + $Stamp + '.bak')
    Copy-Item -LiteralPath $origGenPy -Destination $backupGenPy -Force
    Write-Host "gen_py backup: $backupGenPy"

    $text = Get-Content -LiteralPath $origGenPy -Raw
    if ($text -notmatch [regex]::Escape($Marker)) {
        Add-Content -LiteralPath $origGenPy -Value '' -Encoding UTF8
        Add-Content -LiteralPath $origGenPy -Value (Get-Content -LiteralPath $ShimPath -Raw -Encoding UTF8) -Encoding UTF8
        $shimApplied = $true
        Write-Host 'HCL VBox72 shim appended.'
    } else {
        Write-Host 'HCL VBox72 shim already present.'
    }

    Write-Host 'Switching VirtualBox COM to Oracle 7.2...'
    & $ModeScript -Mode Oracle
    if ($LASTEXITCODE -ne 0) { throw "Set-VBoxComMode -Mode Oracle failed (exit $LASTEXITCODE). See logs\set-vbox-mode-oracle-*.log" }

    Write-Host 'Starting HCL...'
    $hcl = Start-Process -FilePath $HclPath -WorkingDirectory $HclDir -PassThru
    Write-Host "HCL PID: $($hcl.Id)"
    Write-Host 'Close HCL normally (stop devices first); the script will restore eNSP mode automatically.'
    Wait-Process -Id $hcl.Id
    Write-Host 'HCL exited.'
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Stop-HclProcesses
    if ($shimApplied -and $backupGenPy -and (Test-Path $backupGenPy) -and -not $KeepShim) {
        Copy-Item -LiteralPath $backupGenPy -Destination $origGenPy -Force
        Write-Host 'gen_py cache restored.'
    }
    try {
        Write-Host 'Switching VirtualBox COM back to MuMu...'
        & $ModeScript -Mode MuMu
        if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: Set-VBoxComMode -Mode MuMu failed (exit $LASTEXITCODE). See logs\set-vbox-mode-mumu-*.log" }
        else { Write-Host 'Final mode: MuMu.' }
    } catch {
        Write-Host "WARNING: failed to restore MuMu mode: $($_.Exception.Message)"
    }
    Stop-Transcript | Out-Null
}
