<#
.SYNOPSIS
    Switch the machine-wide VirtualBox COM ProgIDs between MuMu Player and
    Oracle VirtualBox, with a complete, verifiable, reversible backup.

.DESCRIPTION
    MuMu Player (MuMuVMM, 6.1.36_OSE) and Oracle VirtualBox 7.2 both register
    the same three version-independent ProgIDs and their ".1" counterparts:

        VirtualBox.VirtualBox
        VirtualBox.VirtualBoxClient
        VirtualBox.Session

    Only one owner can be active per machine, because the ProgID -> CLSID map
    lives in HKLM\SOFTWARE\Classes and is machine-wide.

    What this script changes:
      * the default (CLSID) value of the six ProgID keys above;
      * in Oracle mode only: removes the 64-bit InprocServer32 under
        CLSID\{B1A7...} (the x86 eNSP VBox52.dll shim that makes 64-bit COM
        fail with 0x800700C1) and ensures LocalServer32 -> VBoxSVC.exe.

    What this script never changes:
      * HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7...} (the 32-bit eNSP
        view). It is exported read-only into every backup and hashed before
        and after each run; any drift aborts the run.
      * HKLM\SOFTWARE\Oracle\VirtualBox Version/VersionExt/InstallDir values
        (the eNSP 5.2.44 disguise).
      * MuMu files, MuMu user data, VirtualBox VMs.

    Every run creates logs\vbox-com-mode-backup-<stamp>\ with one .reg export
    per key plus manifest.json. -Restore replays a manifest exactly, including
    deleting keys that did not exist when the snapshot was taken.

.PARAMETER Mode
    MuMu   - point the six ProgIDs at MuMuVMM and verify 6.1.36_OSE.
    Oracle - point the six ProgIDs at Oracle VirtualBox 7.2 and verify 7.2.16.

.PARAMETER Restore
    Restore a snapshot created by this script (default: the newest one with a
    manifest.json). The current state is snapshotted first, so a restore can
    itself be undone.

.PARAMETER BackupDir
    Snapshot directory used by -Restore. Defaults to the newest manifest.

.PARAMETER RestartMuMuService
    MuMu mode only: restart the MuMuRemoteService Windows service after the
    switch. Not required for COM (COM resolves the ProgID on every
    activation), so it is opt-in to avoid interrupting remote/ADB sessions.

.PARAMETER SkipComTest
    Skip the out-of-process COM activation test. Registry read-back and the
    eNSP 32-bit fingerprint check still run.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-VBoxComMode.ps1 -Mode MuMu

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-VBoxComMode.ps1 -Mode Oracle

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-VBoxComMode.ps1 -Restore

.NOTES
    Requires an elevated 64-bit Windows PowerShell. The script relaunches
    itself through UAC (and through Sysnative if started from 32-bit
    PowerShell, because a 32-bit process would otherwise write the
    WOW6432Node view).
#>
[CmdletBinding(DefaultParameterSetName = 'Mode')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Mode')]
    [ValidateSet('MuMu', 'Oracle')]
    [string]$Mode,

    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$BackupDir,

    [switch]$RestartMuMuService,

    [switch]$SkipComTest,

    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$script:ParameterSetName = $PSCmdlet.ParameterSetName

$ProjectRoot = Split-Path -Parent $PSScriptRoot
# The desktop bridge releases scripts to %LOCALAPPDATA%\eNSP-VBox7-Bridge\scripts.
# Prefer that cache root's logs directory when present so the host can tail
# transcripts; fall back to the project tree when run from the repo directly.
$BridgeLogsRoot = Join-Path $env:LOCALAPPDATA 'eNSP-VBox7-Bridge\logs'
if ((Test-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)) -and
    ((Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)) -eq 'eNSP-VBox7-Bridge')) {
    $LogsRoot = $BridgeLogsRoot
} else {
    $LogsRoot = Join-Path $ProjectRoot 'logs'
}
if (-not (Test-Path -LiteralPath $LogsRoot)) {
    New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null
}

$ClsidVirtualBoxOracle = '{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}'
$ClsidClientOracle     = '{DD3FC71D-26C0-4FE1-BF6F-67F633265BBA}'
$ClsidSessionOracle    = '{3C02F46D-C9D2-4F11-A384-53F0CF917214}'

$ClsidVirtualBoxMuMu = '{23cd1535-edaa-4f21-a4ab-45d97fd1d58b}'
$ClsidClientMuMu     = '{85e56ead-33d4-410d-9130-2f2c0fb6a532}'
$ClsidSessionMuMu    = '{b0fe7a06-cdc7-4ece-9c43-5dfd8bdd179c}'

$ProgIdNames = @(
    'VirtualBox.VirtualBox'
    'VirtualBox.VirtualBox.1'
    'VirtualBox.VirtualBoxClient'
    'VirtualBox.VirtualBoxClient.1'
    'VirtualBox.Session'
    'VirtualBox.Session.1'
)

$ProgIdTargets = [ordered]@{
    'VirtualBox.VirtualBox'          = @{ MuMu = $ClsidVirtualBoxMuMu; Oracle = $ClsidVirtualBoxOracle }
    'VirtualBox.VirtualBox.1'        = @{ MuMu = $ClsidVirtualBoxMuMu; Oracle = $ClsidVirtualBoxOracle }
    'VirtualBox.VirtualBoxClient'    = @{ MuMu = $ClsidClientMuMu;     Oracle = $ClsidClientOracle }
    'VirtualBox.VirtualBoxClient.1'  = @{ MuMu = $ClsidClientMuMu;     Oracle = $ClsidClientOracle }
    'VirtualBox.Session'             = @{ MuMu = $ClsidSessionMuMu;    Oracle = $ClsidSessionOracle }
    'VirtualBox.Session.1'           = @{ MuMu = $ClsidSessionMuMu;    Oracle = $ClsidSessionOracle }
}

$Ensp32ClsidKey = "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\$ClsidVirtualBoxOracle"
$Ensp32Key = "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\$ClsidVirtualBoxOracle\InprocServer32"

$SnapshotTargets = @()
foreach ($name in $ProgIdNames) {
    $SnapshotTargets += [pscustomobject]@{ Path = "HKLM\SOFTWARE\Classes\$name"; Role = 'ProgId' }
}
foreach ($clsid in @($ClsidVirtualBoxOracle, $ClsidClientOracle, $ClsidSessionOracle)) {
    $SnapshotTargets += [pscustomobject]@{ Path = "HKLM\SOFTWARE\Classes\CLSID\$clsid"; Role = 'OracleClsid64' }
}
$SnapshotTargets += [pscustomobject]@{ Path = $Ensp32ClsidKey; Role = 'Ensp32ReadOnly' }

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-SelfArgumentList([bool]$MarkElevated) {
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $PSCommandPath)
    )
    if ($script:ParameterSetName -eq 'Restore') {
        $arguments += '-Restore'
        if ($BackupDir) { $arguments += @('-BackupDir', ('"{0}"' -f $BackupDir)) }
    } else {
        $arguments += @('-Mode', $Mode)
    }
    if ($RestartMuMuService) { $arguments += '-RestartMuMuService' }
    if ($SkipComTest) { $arguments += '-SkipComTest' }
    if ($MarkElevated) { $arguments += '-Elevated' }
    return $arguments
}

function ConvertTo-ProviderPath([string]$NativePath) {
    if ($NativePath -match '^HKLM\\(.+)$') { return ('HKLM:\{0}' -f $Matches[1]) }
    if ($NativePath -match '^HKCU\\(.+)$') { return ('HKCU:\{0}' -f $Matches[1]) }
    throw "Unsupported registry path: $NativePath"
}

function Get-RegDefault([string]$ProviderPath) {
    if (-not (Test-Path -LiteralPath $ProviderPath)) { return $null }
    $item = Get-Item -LiteralPath $ProviderPath
    if ($item.GetValueNames() -contains '') {
        return [string]$item.GetValue('', $null, 'DoNotExpandEnvironmentNames')
    }
    return $null
}

function Get-RegValue([string]$ProviderPath, [string]$Name) {
    if (-not (Test-Path -LiteralPath $ProviderPath)) { return $null }
    $item = Get-Item -LiteralPath $ProviderPath
    if ($item.GetValueNames() -contains $Name) {
        return [string]$item.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    }
    return $null
}

function Get-CurrentMode {
    $value = Get-RegDefault 'HKLM:\SOFTWARE\Classes\VirtualBox.VirtualBox\CLSID'
    if ($value -eq $ClsidVirtualBoxMuMu) { return 'MuMu' }
    if ($value -eq $ClsidVirtualBoxOracle) { return 'Oracle' }
    return 'Unknown'
}

function Invoke-RegExe {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    # reg.exe writes localized success messages to stderr. With
    # ErrorActionPreference=Stop that would become a terminating error even
    # when the exit code is 0, so native calls always run with Continue.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & reg.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($output | Out-String)
    }
}

function Export-RegKey([string]$NativePath, [string]$File) {
    $providerPath = ConvertTo-ProviderPath $NativePath
    if (-not (Test-Path -LiteralPath $providerPath)) { return $false }
    $result = Invoke-RegExe @('export', $NativePath, $File, '/y')
    if ($result.ExitCode -ne 0) {
        throw "reg export failed: $NativePath (exit $($result.ExitCode)): $($result.Output)"
    }
    if (-not (Test-Path -LiteralPath $File)) {
        throw "reg export did not create $File."
    }
    if ((Get-Item -LiteralPath $File).Length -eq 0) {
        throw "reg export created empty file: $NativePath."
    }
    return $true
}

function Get-EnspFingerprint {
    $inprocKey = "$Ensp32Key"
    $fingerprint = [ordered]@{
        KeyExists      = Test-Path -LiteralPath (ConvertTo-ProviderPath $Ensp32ClsidKey)
        InprocServer32 = Get-RegDefault (ConvertTo-ProviderPath $inprocKey)
        ThreadingModel = Get-RegValue (ConvertTo-ProviderPath $inprocKey) 'ThreadingModel'
        Version32      = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox' -Name Version -ErrorAction SilentlyContinue).Version
        Version64      = (Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -Name Version -ErrorAction SilentlyContinue).Version
        KeySha256      = $null
    }
    $temp = Join-Path $env:TEMP ('ensp32-{0}.reg' -f [guid]::NewGuid().ToString('N'))
    try {
        if (Export-RegKey $Ensp32ClsidKey $temp) {
            $fingerprint.KeySha256 = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
        }
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
    return $fingerprint
}

function Get-OracleDirectory {
    $installDir = (Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -Name InstallDir -ErrorAction SilentlyContinue).InstallDir
    if ($installDir) { $installDir = $installDir.TrimEnd('\') }
    if (-not $installDir -or -not (Test-Path -LiteralPath (Join-Path $installDir 'VBoxSVC.exe'))) {
        $installDir = $null
        foreach ($candidate in @('D:\Program Files\Oracle\VirtualBox', 'C:\Program Files\Oracle\VirtualBox')) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'VBoxSVC.exe')) { $installDir = $candidate; break }
        }
    }
    if (-not $installDir) { throw 'Oracle VirtualBox was not found (VBoxSVC.exe missing).' }
    return $installDir
}

function Get-MuMuServerPath {
    $localServer = Get-RegDefault "HKLM:\SOFTWARE\Classes\CLSID\$ClsidVirtualBoxMuMu\LocalServer32"
    if (-not $localServer) {
        throw "MuMu COM server is not registered: CLSID\$ClsidVirtualBoxMuMu\LocalServer32 missing."
    }
    return $localServer.Trim('"')
}

function Get-MuMuState {
    $service = Get-Service -Name 'MuMuRemoteService' -ErrorAction SilentlyContinue
    $processes = @(Get-Process -Name 'MuMuVMMSVC', 'MuMuNxService', 'MuMuNxMain', 'MuMuNxLauncher', 'MuMuPlayer' -ErrorAction SilentlyContinue)
    $state = [ordered]@{
        RemoteServiceStatus  = if ($service) { [string]$service.Status } else { 'NotInstalled' }
        RemoteServiceStartup = if ($service) { [string]$service.StartType } else { $null }
        Processes            = @($processes | ForEach-Object { '{0}({1})' -f $_.ProcessName, $_.Id })
    }
    try {
        $server = Get-MuMuServerPath
        $state.ServerPath = $server
        if (Test-Path -LiteralPath $server) {
            $state.ServerVersion = (Get-Item -LiteralPath $server).VersionInfo.FileVersion
        }
    } catch {
        $state.ServerPath = $null
        $state.ServerError = $_.Exception.Message
    }
    return $state
}

function Assert-MuMuRegistration {
    $server = Get-MuMuServerPath
    if (-not (Test-Path -LiteralPath $server)) {
        throw "MuMu COM server file is missing: $server. Repair MuMu (keep user data) and retry."
    }
    foreach ($clsid in @($ClsidClientMuMu, $ClsidSessionMuMu)) {
        $inproc = Get-RegDefault "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
        if (-not $inproc) {
            throw "MuMu CLSID $clsid missing 64-bit InprocServer32; MuMu COM registration incomplete."
        }
        if (-not (Test-Path -LiteralPath $inproc.Trim('"'))) {
            throw "MuMu CLSID $clsid points to missing DLL: $inproc"
        }
    }
}

function Assert-OracleRegistration([string]$OracleDir) {
    foreach ($file in @('VBoxSVC.exe', 'VBoxC.dll', 'VBoxManage.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $OracleDir $file))) {
            throw "Oracle VirtualBox incomplete: $OracleDir\$file missing."
        }
    }
    foreach ($clsid in @($ClsidClientOracle, $ClsidSessionOracle)) {
        $inproc = Get-RegDefault "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
        if (-not $inproc) {
            throw "Oracle CLSID $clsid missing 64-bit InprocServer32; repair VirtualBox 7.2 install."
        }
        if (-not (Test-Path -LiteralPath $inproc.Trim('"'))) {
            throw "Oracle CLSID $clsid points to missing DLL: $inproc"
        }
    }
}

function Stop-MuMuComServer {
    $processes = @(Get-Process -Name 'MuMuVMMSVC' -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        Write-Host ("  Stopping MuMuVMMSVC.exe (PID {0}) before switching to Oracle mode..." -f $process.Id)
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
    }
    if ($processes.Count -gt 0) { Start-Sleep -Milliseconds 500 }
}

function Restart-MuMuWindowsService {
    $service = Get-Service -Name 'MuMuRemoteService' -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Warning 'MuMuRemoteService is not installed; skipped.'
        return
    }
    Write-Host '  Restarting MuMuRemoteService...'
    Restart-Service -Name 'MuMuRemoteService' -Force -ErrorAction Stop
    Write-Host ("  MuMuRemoteService：{0}" -f (Get-Service -Name 'MuMuRemoteService').Status)
}

function Set-ProgIdClsid([string]$ProgId, [string]$Clsid) {
    $key = "HKLM:\SOFTWARE\Classes\$ProgId\CLSID"
    $current = Get-RegDefault $key
    if ($current -eq $Clsid) {
        Write-Host ("  [unchanged] {0} -> {1}" -f $ProgId, $Clsid)
        return $false
    }
    if (-not (Test-Path -LiteralPath $key)) {
        New-Item -Path $key -Force | Out-Null
    }
    Set-Item -LiteralPath $key -Value $Clsid -Force
    Write-Host ("  [set]   {0} -> {1} (was: {2})" -f $ProgId, $Clsid, $current)
    return $true
}

function New-BackupSnapshot([string]$Purpose, [string]$Prefix = 'vbox-com-mode-backup') {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $directory = Join-Path $LogsRoot ("{0}-{1}" -f $Prefix, $stamp)
    $suffix = 1
    while (Test-Path -LiteralPath $directory) {
        $directory = Join-Path $LogsRoot ("{0}-{1}-{2}" -f $Prefix, $stamp, $suffix)
        $suffix++
    }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null

    $entries = @()
    foreach ($target in $SnapshotTargets) {
        $file = Join-Path $directory (($target.Path -replace '[\\{}]', '_') + '.reg')
        $existed = Export-RegKey $target.Path $file
        $entry = [ordered]@{
            Path         = $target.Path
            Role         = $target.Role
            Existed      = [bool]$existed
            ExportFile   = if ($existed) { Split-Path -Leaf $file } else { $null }
            DefaultValue = if ($existed) { Get-RegDefault (ConvertTo-ProviderPath $target.Path) } else { $null }
        }
        $entries += [pscustomobject]$entry
    }

    $enspFile = Join-Path $directory 'ensp32-readonly.reg'
    $enspExported = Export-RegKey $Ensp32ClsidKey $enspFile
    $enspHash = if ($enspExported) { (Get-FileHash -LiteralPath $enspFile -Algorithm SHA256).Hash } else { $null }

    $oracleInstallDir = $null
    $oracleFileVersion = $null
    try {
        $oracleInstallDir = Get-OracleDirectory
        $oracleFileVersion = (Get-Item -LiteralPath (Join-Path $oracleInstallDir 'VBoxSVC.exe')).VersionInfo.FileVersion
    } catch {
        $oracleInstallDir = $null
        $oracleFileVersion = $null
    }

    $manifest = [ordered]@{
        SchemaVersion = 1
        CreatedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        CreatedBy     = "$env:USERDOMAIN\$env:USERNAME"
        Computer      = $env:COMPUTERNAME
        Purpose       = $Purpose
        ModeBefore    = Get-CurrentMode
        Keys          = $entries
        Ensp32        = [ordered]@{
            Path           = $Ensp32ClsidKey
            ExportFile     = if ($enspExported) { 'ensp32-readonly.reg' } else { $null }
            Sha256         = $enspHash
            InprocServer32 = Get-RegDefault (ConvertTo-ProviderPath $Ensp32Key)
            ThreadingModel = Get-RegValue (ConvertTo-ProviderPath $Ensp32Key) 'ThreadingModel'
            Version32      = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox' -Name Version -ErrorAction SilentlyContinue).Version
            Version64      = (Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -Name Version -ErrorAction SilentlyContinue).Version
        }
        Oracle        = [ordered]@{
            InstallDir = $oracleInstallDir
            Version    = $oracleFileVersion
        }
        MuMu          = Get-MuMuState
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'manifest.json') -Encoding UTF8
    return [pscustomobject]@{ Directory = $directory; Manifest = $manifest }
}

function Remove-RegKey([string]$NativePath) {
    $providerPath = ConvertTo-ProviderPath $NativePath
    if (-not (Test-Path -LiteralPath $providerPath)) { return }
    $result = Invoke-RegExe @('delete', $NativePath, '/f')
    if ($result.ExitCode -ne 0 -and (Test-Path -LiteralPath $providerPath)) {
        throw "reg delete failed: $NativePath (exit $($result.ExitCode)): $($result.Output)"
    }
}

function Invoke-ComProbe {
    $probeScript = @'
$ErrorActionPreference = "Stop"
$result = @()
foreach ($progId in @("VirtualBox.VirtualBox", "VirtualBox.VirtualBoxClient", "VirtualBox.Session")) {
    $entry = [ordered]@{ ProgId = $progId; Ok = $false; Version = $null; ClientVersion = $null; Error = $null }
    try {
        $type = [Type]::GetTypeFromProgID($progId)
        if (-not $type) { throw "ProgID not registered" }
        $object = [Activator]::CreateInstance($type)
        $entry.Ok = $true
        $entry.Version = [string]$object.version
        if ($progId -eq "VirtualBox.VirtualBoxClient") {
            $entry.ClientVersion = [string]$object.VirtualBox.version
        }
    } catch {
        $entry.Error = $_.Exception.Message
    }
    $result += [pscustomobject]$entry
}
$result | ConvertTo-Json -Depth 4 -Compress
'@
    $temp = Join-Path $env:TEMP ('vbox-com-probe-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $temp -Value $probeScript -Encoding ASCII
    $output = $null
    $exitCode = 0
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -ExecutionPolicy Bypass -File $temp 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
    if ($exitCode -ne 0) {
        throw "64-bit COM probe process failed (exit $exitCode). Output: $($output | Out-String)"
    }
    try {
        return ($output | Out-String | ConvertFrom-Json)
    } catch {
        throw "Cannot parse 64-bit COM probe output: $($output | Out-String)"
    }
}

function Get-ExpectedVersion([string]$TargetMode) {
    if ($TargetMode -eq 'MuMu') {
        $server = Get-MuMuServerPath
        if (-not (Test-Path -LiteralPath $server)) { throw "MuMu server file not found: $server" }
        $version = (Get-Item -LiteralPath $server).VersionInfo.FileVersion
    } else {
        $server = Join-Path (Get-OracleDirectory) 'VBoxSVC.exe'
        $version = (Get-Item -LiteralPath $server).VersionInfo.FileVersion
    }
    if (-not $version) { throw "Cannot read product version of $server." }
    return (($version -split '\.')[0..2] -join '.')
}

function Assert-ComVersion([string]$TargetMode) {
    $expected = Get-ExpectedVersion $TargetMode
    $probe = Invoke-ComProbe
    $virtualBox = $probe | Where-Object { $_.ProgId -eq 'VirtualBox.VirtualBox' }
    if (-not $virtualBox -or -not $virtualBox.Ok) {
        throw ("VirtualBox.VirtualBox activation failed: {0}" -f $(if ($virtualBox) { $virtualBox.Error } else { 'no result' }))
    }
    if (-not $virtualBox.Version) {
        throw 'VirtualBox.VirtualBox returned empty version string.'
    }
    if (-not $virtualBox.Version.StartsWith($expected)) {
        throw "VirtualBox.VirtualBox returned '$($virtualBox.Version)', expected '$expected*' ($TargetMode mode)."
    }
    $client = $probe | Where-Object { $_.ProgId -eq 'VirtualBox.VirtualBoxClient' }
    if (-not $client -or -not $client.Ok) {
        throw ("VirtualBox.VirtualBoxClient activation failed: {0}" -f $(if ($client) { $client.Error } else { 'no result' }))
    }
    if ($client.ClientVersion -and -not $client.ClientVersion.StartsWith($expected)) {
        throw "VirtualBoxClient.VirtualBox returned '$($client.ClientVersion)', expected '$expected*'."
    }
    $session = $probe | Where-Object { $_.ProgId -eq 'VirtualBox.Session' }
    if (-not $session -or -not $session.Ok) {
        throw ("VirtualBox.Session activation failed: {0}" -f $(if ($session) { $session.Error } else { 'no result' }))
    }
    Write-Host ("  COM check OK: VirtualBox.VirtualBox = {0}; VirtualBoxClient.VirtualBox = {1}" -f $virtualBox.Version, $client.ClientVersion)
    return $probe
}

function Invoke-SetMode([string]$TargetMode) {
    $before = Get-CurrentMode
    $enspBefore = Get-EnspFingerprint
    Write-Host "Current mode: $before"
    Write-Host "Target mode: $TargetMode"
    Write-Host ''

    $snapshot = New-BackupSnapshot -Purpose ("switch-{0}" -f $TargetMode)
    $script:ActiveBackup = $snapshot.Directory
    Write-Host "Backup: $($snapshot.Directory)"
    Write-Host ''

    $changed = 0
    if ($TargetMode -eq 'MuMu') {
        Assert-MuMuRegistration
        foreach ($name in $ProgIdNames) {
            if (Set-ProgIdClsid $name $ProgIdTargets[$name].MuMu) { $changed++ }
        }
        if ($RestartMuMuService) { Restart-MuMuWindowsService }
    } else {
        $runningUi = @(Get-Process -Name 'MuMuNxMain', 'MuMuNxLauncher', 'MuMuPlayer' -ErrorAction SilentlyContinue)
        if ($runningUi.Count -gt 0) {
            throw ("MuMu Player is running ({0}). Exit MuMu before switching to Oracle mode; HCL and MuMu cannot run simultaneously." -f (($runningUi | ForEach-Object { $_.ProcessName }) -join ', '))
        }
        Stop-MuMuComServer
        $oracleDir = Get-OracleDirectory
        Assert-OracleRegistration $oracleDir
        foreach ($name in $ProgIdNames) {
            if (Set-ProgIdClsid $name $ProgIdTargets[$name].Oracle) { $changed++ }
        }
        $inproc64Key = "HKLM:\SOFTWARE\Classes\CLSID\$ClsidVirtualBoxOracle\InprocServer32"
        if (Test-Path -LiteralPath $inproc64Key) {
            Remove-Item -LiteralPath $inproc64Key -Recurse -Force
            Write-Host '  [removed]   64-bit InprocServer32 (x86 VBox52.dll shim)'
            $changed++
        } else {
            Write-Host '  [unchanged]   64-bit InprocServer32 already absent'
        }
        $localServerKey = "HKLM:\SOFTWARE\Classes\CLSID\$ClsidVirtualBoxOracle\LocalServer32"
        $expectedLocalServer = '"{0}\VBoxSVC.exe"' -f $oracleDir
        $currentLocalServer = Get-RegDefault $localServerKey
        if ($currentLocalServer -ne $expectedLocalServer) {
            New-Item -Path $localServerKey -Force | Out-Null
            Set-Item -LiteralPath $localServerKey -Value $expectedLocalServer -Force
            Write-Host ("  [set]   LocalServer32 -> {0}" -f $expectedLocalServer)
            $changed++
        } else {
            Write-Host ("  [unchanged]   LocalServer32 -> {0}" -f $expectedLocalServer)
        }
    }

    Write-Host ''
    Write-Host 'Read-back:'
    foreach ($name in $ProgIdNames) {
        $actual = Get-RegDefault "HKLM:\SOFTWARE\Classes\$name\CLSID"
        $expected = $ProgIdTargets[$name][$TargetMode]
        Write-Host ("  {0} -> {1}" -f $name, $actual)
        if ($actual -ne $expected) {
            throw "Read-back verification failed: $name ('$actual' != '$expected')."
        }
    }

    $enspAfter = Get-EnspFingerprint
    if ($enspBefore.KeySha256 -and $enspAfter.KeySha256 -ne $enspBefore.KeySha256) {
        throw 'eNSP 32-bit WOW6432Node CLSID view changed during switch. Restore backup immediately.'
    }
    if ($enspAfter.InprocServer32 -notlike '*VBox52.dll') {
        throw "eNSP 32-bit InprocServer32 no longer points to VBox52.dll: $($enspAfter.InprocServer32)"
    }
    Write-Host ("  eNSP 32-bit view unchanged: {0} (SHA256 {1})" -f $enspAfter.InprocServer32, $enspAfter.KeySha256)

    $comResult = $null
    if (-not $SkipComTest) {
        Write-Host ''
        Write-Host 'COM activation test (64-bit):'
        $comResult = Assert-ComVersion $TargetMode
    } else {
        Write-Host 'COM activation test skipped (-SkipComTest).'
    }

    $modeAfter = Get-CurrentMode
    $mumuState = Get-MuMuState
    $summary = [ordered]@{
        Timestamp      = (Get-Date).ToString('o')
        Action         = $TargetMode
        ModeBefore     = $before
        ModeAfter      = $modeAfter
        ChangedValues  = $changed
        Backup         = $snapshot.Directory
        ComProbe       = $comResult
        Ensp32Before   = $enspBefore
        Ensp32After    = $enspAfter
        MuMuState      = $mumuState
        ExitCode       = 0
    }
    $summaryPath = Join-Path $LogsRoot ('set-vbox-mode-{0}-{1}.json' -f $TargetMode.ToLowerInvariant(), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    Write-Host ''
    Write-Host '=== RESULT ==='
    Write-Host ("Mode before: {0}" -f $before)
    Write-Host ("Mode after: {0}" -f $modeAfter)
    Write-Host ("Changed: {0} value(s)" -f $changed)
    Write-Host ("Backup: {0}" -f $snapshot.Directory)
    Write-Host ("Summary: {0}" -f $summaryPath)
    Write-Host ("MuMu: service={0}, processes={1}" -f $mumuState.RemoteServiceStatus, ($mumuState.Processes -join ', '))
}

function Resolve-BackupDirectory([string]$Requested) {
    if ($Requested) {
        if (-not (Test-Path -LiteralPath $Requested)) { throw "Backup directory not found: $Requested" }
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    $candidates = @(Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'vbox-com-mode-backup-*' -or $_.Name -like 'hcl-com-backup-*' } |
        Sort-Object LastWriteTime -Descending)
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate.FullName 'manifest.json')) { return $candidate.FullName }
    }
    foreach ($candidate in $candidates) {
        if (Get-ChildItem -LiteralPath $candidate.FullName -Filter '*.reg' -ErrorAction SilentlyContinue) { return $candidate.FullName }
    }
    throw 'No usable backup directory found under logs\\.'
}

function Invoke-LegacyRestore([string]$Directory) {
    $regFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.reg' -ErrorAction SilentlyContinue)
    if ($regFiles.Count -eq 0) {
        throw "$Directory has no manifest.json and no .reg files; cannot restore."
    }
    Write-Warning 'No manifest.json found; performing legacy restore of the known seven keys only.'
    $legacyKeys = @(
        "HKLM\SOFTWARE\Classes\CLSID\$ClsidVirtualBoxOracle"
        'HKLM\SOFTWARE\Classes\VirtualBox.VirtualBox'
        'HKLM\SOFTWARE\Classes\VirtualBox.VirtualBox.1'
        'HKLM\SOFTWARE\Classes\VirtualBox.VirtualBoxClient'
        'HKLM\SOFTWARE\Classes\VirtualBox.VirtualBoxClient.1'
        'HKLM\SOFTWARE\Classes\VirtualBox.Session'
        'HKLM\SOFTWARE\Classes\VirtualBox.Session.1'
    )
    foreach ($key in $legacyKeys) {
        $file = Join-Path $Directory (($key -replace '[\\{}]', '_') + '.reg')
        if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -eq 0) {
            Write-Warning "Legacy backup has no data for $key; key left unchanged."
            continue
        }
        Remove-RegKey $key
        $import = Invoke-RegExe @('import', $file)
        if ($import.ExitCode -ne 0) { throw "reg import failed: $file (exit $($import.ExitCode)): $($import.Output)" }
        Write-Host "  restored $key"
    }
}

function Invoke-RestoreMode {
    $directory = Resolve-BackupDirectory $BackupDir
    Write-Host "Restore source: $directory"
    $enspBefore = Get-EnspFingerprint

    $preRestore = New-BackupSnapshot -Purpose 'pre-restore' -Prefix 'vbox-com-mode-prerestore'
    $script:ActiveBackup = $preRestore.Directory
    Write-Host "Safety backup: $($preRestore.Directory)"

    $manifestPath = Join-Path $directory 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Invoke-LegacyRestore $directory
        $enspAfter = Get-EnspFingerprint
        if ($enspBefore.KeySha256 -and $enspAfter.KeySha256 -ne $enspBefore.KeySha256) {
            throw 'eNSP 32-bit view changed during legacy restore.'
        }
        Write-Host ("Restored (legacy). Current mode: {0}" -f (Get-CurrentMode))
        return
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.Keys) {
        if ($entry.Existed) {
            $file = Join-Path $directory $entry.ExportFile
            if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -eq 0) {
                throw "Backup incomplete: $file missing. No changes made."
            }
        }
    }

    foreach ($entry in $manifest.Keys) {
        $providerPath = ConvertTo-ProviderPath $entry.Path
        if ($entry.Role -eq 'Ensp32ReadOnly') {
            Write-Host "  verified    $($entry.Path) (read-only; never written)"
            continue
        }
        if ($entry.Existed) {
            Remove-RegKey $entry.Path
            $import = Invoke-RegExe @('import', (Join-Path $directory $entry.ExportFile))
            if ($import.ExitCode -ne 0) { throw "reg import failed: $($entry.ExportFile) (exit $($import.ExitCode)): $($import.Output)" }
            if (-not (Test-Path -LiteralPath $providerPath)) {
                throw "Restore did not rebuild $($entry.Path)."
            }
            $default = Get-RegDefault $providerPath
            if ($null -ne $entry.DefaultValue -and $default -ne $entry.DefaultValue) {
                throw "Restore verification failed: $($entry.Path) ('$default' != '$($entry.DefaultValue)')."
            }
            Write-Host "  restored    $($entry.Path)"
        } else {
            Remove-RegKey $entry.Path
            if (Test-Path -LiteralPath $providerPath) { throw "Key should not exist after restore: $($entry.Path)" }
            Write-Host "  removed    $($entry.Path) (absent in snapshot)"
        }
    }

    $enspAfter = Get-EnspFingerprint
    if ($manifest.Ensp32.Sha256 -and $enspAfter.KeySha256 -ne $manifest.Ensp32.Sha256) {
        throw 'eNSP 32-bit WOW6432Node view does not match snapshot; restore failed.'
    }

    $modeAfter = Get-CurrentMode
    Write-Host ("Restored mode: {0} (snapshot was taken in {1})" -f $modeAfter, $manifest.ModeBefore)
    if ($manifest.ModeBefore -ne 'Unknown' -and $modeAfter -ne $manifest.ModeBefore) {
        throw "Restored mode '$modeAfter' does not match snapshot mode '$($manifest.ModeBefore)'."
    }
    if (-not $SkipComTest -and $modeAfter -in @('MuMu', 'Oracle')) {
        Write-Host 'COM activation test after restore:'
        $null = Assert-ComVersion $modeAfter
    }
    Write-Host 'Restore completed successfully.'
}

# A 32-bit host would silently redirect HKLM:\SOFTWARE\Classes to WOW6432Node.
if (-not [Environment]::Is64BitProcess) {
    $nativePowerShell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $nativePowerShell)) {
        throw 'This script must run in 64-bit PowerShell; Sysnative PowerShell not found.'
    }
    Write-Host 'Re-launching in native 64-bit PowerShell...'
    $proc = Start-Process -FilePath $nativePowerShell -ArgumentList (New-SelfArgumentList $false) -Wait -PassThru
    exit $proc.ExitCode
}

if (-not (Test-IsAdmin)) {
    if ($Elevated) { throw 'UAC elevation failed or was cancelled.' }
    Write-Host 'Requesting administrator elevation...'
    $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $proc = Start-Process -FilePath $powerShellExe -ArgumentList (New-SelfArgumentList $true) -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$actionName = if ($script:ParameterSetName -eq 'Restore') { 'restore' } else { $Mode }
$transcriptPath = Join-Path $LogsRoot ("set-vbox-mode-{0}-{1}.log" -f $actionName.ToLowerInvariant(), $stamp)
Start-Transcript -Path $transcriptPath -Force | Out-Null

$script:ActiveBackup = $null
$exitCode = 0
try {
    Write-Host '=== Set-VBoxComMode ==='
    Write-Host ("Time: {0}" -f (Get-Date).ToString('o'))
    Write-Host ("User: {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    Write-Host ("Host: {0}" -f $env:COMPUTERNAME)
    Write-Host ("Action: {0}" -f $actionName)
    Write-Host ''

    if ($script:ParameterSetName -eq 'Restore') {
        Invoke-RestoreMode
    } else {
        Invoke-SetMode $Mode
    }
} catch {
    $exitCode = 1
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
    if ($script:ActiveBackup) {
        Write-Host ("Rollback backup: {0}" -f $script:ActiveBackup) -ForegroundColor Yellow
        Write-Host ("Rollback command: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -Restore -BackupDir `"{1}`"" -f $PSCommandPath, $script:ActiveBackup) -ForegroundColor Yellow
    }
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

exit $exitCode
