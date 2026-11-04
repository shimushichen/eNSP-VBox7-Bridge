[CmdletBinding()]
param(
    [switch]$Check,
    [string]$EnspDir,
    [string]$VBoxDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$BaseVms = @('AR_Base', 'WLAN_AC_Base', 'WLAN_AD_Base', 'WLAN_AP_Base', 'WLAN_SAP_Base')

function Find-Ensp([string]$Override) {
    if ($Override) {
        $path = $Override.TrimEnd('\')
        if (Test-Path -LiteralPath (Join-Path $path 'vboxserver')) { return $path }
        throw "Invalid eNSP directory: $Override"
    }
    @('D:\Program Files\Huawei\eNSP', 'D:\Software\Huawei\eNSP', 'C:\Program Files\Huawei\eNSP', 'C:\Program Files (x86)\Huawei\eNSP') |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ 'vboxserver') } | Select-Object -First 1
}

function Find-VBoxManage([string]$Override) {
    if ($Override) {
        $candidate = Join-Path $Override.TrimEnd('\') 'VBoxManage.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        throw "Invalid VirtualBox directory: $Override"
    }
    @('D:\Program Files\Oracle\VirtualBox', 'D:\Software\Oracle\VirtualBox', (Join-Path $env:ProgramFiles 'Oracle\VirtualBox')) |
        ForEach-Object { Join-Path $_ 'VBoxManage.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Select-VBoxFile([string]$Directory) {
    Get-ChildItem -LiteralPath $Directory -Filter '*.vbox' -File -ErrorAction SilentlyContinue |
        Sort-Object { $_.Name.Length }, Name |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match '<Machine\s' } |
        Select-Object -First 1 -ExpandProperty FullName
}

function Normalize-Path([string]$Path) {
    if (-not $Path) { return '' }
    (($Path.Trim() -replace '\\+', '\').TrimEnd('\')).ToLowerInvariant()
}

function Get-RegisteredNames([string]$VBoxManage) {
    $names = @{}
    foreach ($line in (& $VBoxManage list vms 2>$null)) {
        if ($line -match '^"([^"]+)"\s+\{[0-9a-fA-F-]+\}') { $names[$Matches[1]] = $true }
    }
    $names
}

function Get-RegisteredConfig([string]$VBoxManage, [string]$Name) {
    foreach ($line in (& $VBoxManage showvminfo $Name --machinereadable 2>$null)) {
        if ($line -match '^CfgFile="(.*)"$') { return $Matches[1] }
    }
    $null
}

function Get-VMState([string]$VBoxManage, [string]$Name) {
    foreach ($line in (& $VBoxManage showvminfo $Name --machinereadable 2>$null)) {
        if ($line -match '^VMState="([^"]+)"$') { return $Matches[1] }
    }
    ''
}

function Has-LinkSnapshot([string]$VBoxManage, [string]$Name) {
    $snapshot = "${Name}_Link"
    foreach ($line in (& $VBoxManage snapshot $Name list --machinereadable 2>$null)) {
        if ($line -match '^SnapshotName(?:-[0-9]+)?="([^"]+)"$' -and $Matches[1] -eq $snapshot) { return $true }
    }
    $false
}

function Ensure-LinkSnapshot([string]$VBoxManage, [string]$Name, [switch]$WhatIf) {
    $snapshot = "${Name}_Link"
    if (Has-LinkSnapshot $VBoxManage $Name) { return 'present' }
    $state = Get-VMState $VBoxManage $Name
    if (-not $state) { return 'missing-vm' }
    if ($state -ne 'poweroff') { return "skip-$state" }
    if ($WhatIf) { return 'would-create' }
    $saved = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $null = & $VBoxManage snapshot $Name take $snapshot 2>$null
    } finally {
        $ErrorActionPreference = $saved
    }
    if (Has-LinkSnapshot $VBoxManage $Name) { return 'created' }
    'failed'
}

function Report-Snapshot([string]$Name, [string]$Result) {
    switch -Wildcard ($Result) {
        'present' { return }
        'would-create' { Write-Host "${Name}: missing ${Name}_Link; would create in normal mode" -ForegroundColor Yellow }
        'created' { Write-Host "${Name}: created ${Name}_Link" -ForegroundColor Green }
        'skip-*' { Write-Warning "${Name}: missing snapshot; VM state is $($Result.Substring(5))" }
        'missing-vm' { Write-Warning "${Name}: VM registration not found" }
        'failed' { Write-Warning "${Name}: failed to create ${Name}_Link" }
    }
}

$ensp = Find-Ensp $EnspDir
$vboxManage = Find-VBoxManage $VBoxDir
if (-not $ensp) { throw 'Classic eNSP was not found.' }
if (-not $vboxManage) { throw 'VBoxManage.exe was not found.' }

$registered = Get-RegisteredNames $vboxManage
$vboxRoot = Join-Path $ensp 'vboxserver'
$registeredCount = 0
$reregisteredCount = 0
$snapshotCount = 0
$warningCount = 0

foreach ($name in $BaseVms) {
    $directory = Join-Path $vboxRoot $name
    if (-not (Test-Path -LiteralPath $directory)) { Write-Host "${name}: template missing; skipped"; continue }
    $target = Select-VBoxFile $directory
    if (-not $target) { Write-Warning "${name}: no valid .vbox template"; $warningCount++; continue }

    $isRegistered = $registered.ContainsKey($name)
    $current = if ($isRegistered) { Get-RegisteredConfig $vboxManage $name } else { $null }
    $pathMatches = $current -and (Test-Path -LiteralPath $current) -and (Normalize-Path $current) -eq (Normalize-Path $target)

    if ($isRegistered -and $pathMatches) {
        Write-Host "${name}: registered and path is valid"
    } elseif ($isRegistered) {
        $state = Get-VMState $vboxManage $name
        if ($state -and $state -ne 'poweroff') { Write-Warning "${name}: stale path but VM is $state; skipped"; $warningCount++; continue }
        if ($Check) {
            Write-Host "${name}: stale path; would re-register $target" -ForegroundColor Yellow
            $reregisteredCount++
        } else {
            $null = & $vboxManage unregistervm $name 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Warning "${name}: unregister failed"; $warningCount++; continue }
            $null = & $vboxManage registervm $target 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Warning "${name}: register failed"; $warningCount++; continue }
            Write-Host "${name}: re-registered" -ForegroundColor Green
            $reregisteredCount++
        }
    } else {
        if ($Check) {
            Write-Host "${name}: not registered; would register $target" -ForegroundColor Yellow
            $registeredCount++
        } else {
            $null = & $vboxManage registervm $target 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Warning "${name}: register failed"; $warningCount++; continue }
            Write-Host "${name}: registered" -ForegroundColor Green
            $registeredCount++
        }
    }

    $snapshotResult = Ensure-LinkSnapshot $vboxManage $name -WhatIf:$Check
    Report-Snapshot $name $snapshotResult
    if ($snapshotResult -eq 'created' -or $snapshotResult -eq 'would-create') { $snapshotCount++ }
    if ($snapshotResult -eq 'failed' -or $snapshotResult -eq 'missing-vm' -or $snapshotResult -like 'skip-*') { $warningCount++ }
}

Write-Host "`nRegistered VMs:"
& $vboxManage list vms 2>$null | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host "  $_" }
$mode = if ($Check) { 'check' } else { 'reconcile' }
$color = if ($warningCount) { 'Yellow' } else { 'Green' }
Write-Host "`n$mode complete: registered=$registeredCount reregistered=$reregisteredCount snapshots=$snapshotCount warnings=$warningCount" -ForegroundColor $color
Write-Host 'This script never deletes disks, VMs, or existing snapshots; -Check is read-only.' -ForegroundColor Cyan
if ($warningCount) { exit 2 }
exit 0
