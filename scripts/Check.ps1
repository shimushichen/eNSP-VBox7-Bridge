[CmdletBinding()]
param(
    [string]$EnspDir,
    [string]$VBoxDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DllPath = Join-Path $ProjectRoot 'build\local-x86\VBox52.dll'
$ExpectedHash = 'AEA65CA5A8863A308DA482379D0C02965C5336F7B80A61087549874387B51204'
function Get-PEMachine([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<not found>' }
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 64 -or $b[0] -ne 0x4d -or $b[1] -ne 0x5a) { return '<not PE>' }
    $o = [BitConverter]::ToInt32($b, 0x3c)
    if ($o -lt 0 -or $o + 6 -gt $b.Length -or $b[$o] -ne 0x50 -or $b[$o+1] -ne 0x45) { return '<not PE>' }
    return ('0x{0:X4}' -f [BitConverter]::ToUInt16($b, $o + 4))
}

function Show-Value([string]$Name, $Value) {
    if ($null -eq $Value -or "$Value" -eq '') { $Value = '<not found>' }
    [pscustomobject]@{ Check = $Name; Value = "$Value" }
}

function Find-Ensp([string]$Override) {
    if ($Override) { return $Override.TrimEnd('\') }
    $roots = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like '*eNSP*' -and $p.InstallLocation) { $p.InstallLocation }
        } | Where-Object { $_ -and (Test-Path (Join-Path $_ 'tools')) } | Select-Object -First 1
        if ($hit) { return $hit.TrimEnd('\') }
    }
    foreach ($candidate in @(
        'C:\Program Files (x86)\Huawei\eNSP',
        'C:\Program Files\Huawei\eNSP',
        'D:\Program Files\Huawei\eNSP',
        'D:\Software\Huawei\eNSP'
    )) {
        if ($candidate -and (Test-Path (Join-Path $candidate 'tools'))) { return $candidate.TrimEnd('\') }
    }
    return $null
}

function Find-VBox([string]$Override) {
    if ($Override) { return $Override.TrimEnd('\') }
    foreach ($key in @('HKLM:\SOFTWARE\Oracle\VirtualBox','HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
        if (-not (Test-Path $key)) { continue }
        $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($p.InstallDir -and (Test-Path $p.InstallDir)) { return $p.InstallDir.TrimEnd('\') }
    }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Oracle\VirtualBox'),
        'D:\Program Files\Oracle\VirtualBox',
        'D:\Software\Oracle\VirtualBox'
    )) {
        if ($candidate -and (Test-Path (Join-Path $candidate 'VBoxManage.exe'))) { return $candidate.TrimEnd('\') }
    }
    return $null
}

$EnspDir = Find-Ensp $EnspDir
$VBoxDir = Find-VBox $VBoxDir
$rows = [System.Collections.Generic.List[object]]::new()
$rows.Add((Show-Value 'Project' $ProjectRoot))
$rows.Add((Show-Value 'Local DLL' $DllPath))
if (Test-Path $DllPath) {
    $h = Get-FileHash $DllPath -Algorithm SHA256
    $rows.Add((Show-Value 'Local DLL SHA256' $h.Hash))
    $rows.Add((Show-Value 'Local DLL hash match' ($h.Hash.ToUpperInvariant() -eq $ExpectedHash)))
    $rows.Add((Show-Value 'Local DLL PE machine' (Get-PEMachine $DllPath)))
    $rows.Add((Show-Value 'Local DLL size' ((Get-Item $DllPath).Length)))
}
$rows.Add((Show-Value 'eNSP directory' $EnspDir))
$clsid32 = $null
try { $clsid32 = (Get-ItemProperty 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}\InprocServer32' -ErrorAction Stop).'(default)' } catch {}
$rows.Add((Show-Value 'eNSP 32-bit CLSID target' $clsid32))
$rows.Add((Show-Value 'VirtualBox directory' $VBoxDir))
$clientPath = if ($EnspDir) { Join-Path $EnspDir 'eNSP_Client.exe' } else { $null }
$serverPath = if ($EnspDir) { Join-Path $EnspDir 'vboxserver\eNSP_VBoxServer.exe' } else { $null }
$rows.Add((Show-Value 'eNSP_Client PE machine' (Get-PEMachine $clientPath)))
$rows.Add((Show-Value 'eNSP_VBoxServer PE machine' (Get-PEMachine $serverPath)))

if ($VBoxDir) {
    $vbm = Join-Path $VBoxDir 'VBoxManage.exe'
    if (Test-Path $vbm) {
        try { $rows.Add((Show-Value 'VirtualBox version' ((& $vbm --version 2>$null | Select-Object -First 1).Trim()))) }
        catch { $rows.Add((Show-Value 'VirtualBox version' '<VBoxManage failed>')) }
    }
}

foreach ($key in @('HKLM:\SOFTWARE\Oracle\VirtualBox','HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
    $label = if ($key -like '*WOW6432Node*') { 'VirtualBox registry 32-bit' } else { 'VirtualBox registry 64-bit' }
    if (Test-Path $key) {
        $p = Get-ItemProperty $key
        $rows.Add((Show-Value "$label Version" $p.Version))
        $rows.Add((Show-Value "$label InstallDir" $p.InstallDir))
    } else { $rows.Add((Show-Value $label '<key not found>')) }
}

$hv = $null
try { $hv = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch {}
$rows.Add((Show-Value 'Hypervisor present' $hv.HypervisorPresent))
$rows.Add((Show-Value 'Firmware virtualization' $hv.VirtualizationFirmwareEnabled))

# Emit "Key: Value" lines (not Format-Table) so the desktop bridge can
# parse and translate every row reliably. Use Write-Output (stdout), not
# Write-Host, because the bridge redirects stdout only.
foreach ($row in $rows) {
    $value = "$($row.Value)"
    Write-Output ("{0}: {1}" -f $row.Check, $value)
}
Write-Output ''
Write-Output "This command is read-only. It does not write files, registry values, ACLs, services, or VM registrations."
