$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$HclDir = $null
foreach ($p in @('E:\HCL_5.10.3\app', 'C:\Program Files (x86)\HCL', 'C:\Program Files\HCL', 'C:\Program Files (x86)\HCL\HCL')) {
    if (Test-Path (Join-Path $p 'SimwareClient.exe')) { $HclDir = $p; break }
}
if (-not $HclDir) { throw 'HCL SimwareClient.exe not found.' }

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\eNSP-VBox7-Bridge'
New-Item -ItemType Directory -Force $startMenu | Out-Null

function New-Shortcut([string]$Path, [string]$Target, [string]$Arguments, [string]$WorkingDirectory, [string]$Description, [string]$Icon) {
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = $Target
    $lnk.Arguments = $Arguments
    $lnk.WorkingDirectory = $WorkingDirectory
    $lnk.Description = $Description
    if ($Icon) { $lnk.IconLocation = $Icon }
    $lnk.Save()
    Write-Host "Created: $Path"
}

$hclIcon = Join-Path $HclDir 'SimwareClient.exe'
New-Shortcut (Join-Path $desktop 'H3C Cloud Lab (eNSP Bridge).lnk') (Join-Path $ProjectRoot 'Use-HCL.bat') '' $ProjectRoot 'Launch HCL with Oracle VirtualBox 7.2 and restore MuMu on exit.' "$hclIcon,0"
New-Shortcut (Join-Path $startMenu 'H3C Cloud Lab (eNSP Bridge).lnk') (Join-Path $ProjectRoot 'Use-HCL.bat') '' $ProjectRoot 'Launch HCL with Oracle VirtualBox 7.2 and restore MuMu on exit.' "$hclIcon,0"

New-Shortcut (Join-Path $desktop 'eNSP Bridge Control.lnk') (Join-Path $ProjectRoot 'eNSPBridgeTool.bat') '' $ProjectRoot 'eNSP / HCL / MuMu VirtualBox mode control panel.' "$hclIcon,0"
New-Shortcut (Join-Path $startMenu 'eNSP Bridge Control.lnk') (Join-Path $ProjectRoot 'eNSPBridgeTool.bat') '' $ProjectRoot 'eNSP / HCL / MuMu VirtualBox mode control panel.' "$hclIcon,0"

New-Shortcut (Join-Path $desktop 'Restore MuMu.lnk') (Join-Path $ProjectRoot 'Restore-MuMu.bat') '' $ProjectRoot 'Restore MuMu as the VirtualBox COM owner.' "$hclIcon,0"
New-Shortcut (Join-Path $startMenu 'Restore MuMu.lnk') (Join-Path $ProjectRoot 'Restore-MuMu.bat') '' $ProjectRoot 'Restore MuMu as the VirtualBox COM owner.' "$hclIcon,0"

Write-Host "Shortcuts created in: $desktop"
Write-Host "Shortcuts created in: $startMenu"
