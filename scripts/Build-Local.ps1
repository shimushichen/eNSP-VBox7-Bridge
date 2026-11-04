[CmdletBinding()]
param(
    [string]$VSVars32,
    [string]$SourceDir,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot 'build\local-x86'

if (-not $SourceDir) {
    $candidate = Join-Path $ProjectRoot 'third_party\ensp-vbox-shim\src'
    $required = 'vbox52_proxy.cpp','vbox52_thunks.asm','spoof_thunks.cpp','imachine_entries.asm','vbox52.def'
    if (($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $candidate $_)) }).Count -eq 0) {
        $SourceDir = $candidate
    } else {
        $SourceDir = Join-Path $ProjectRoot 'third_party\ensp-vbox-shim\src'
    }
}
if (-not (Test-Path -LiteralPath $SourceDir)) { throw "Source directory not found: $SourceDir" }
$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path

function Find-VcVars32 {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "vcvars32.bat not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }

    $candidates = @(
        'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat',
        'D:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat'
    )
    $found = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($found) { return $found }

    $vsRoots = @(
        'C:\Program Files\Microsoft Visual Studio',
        'C:\Program Files (x86)\Microsoft Visual Studio',
        'D:\Program Files\Microsoft Visual Studio'
    )
    foreach ($root in $vsRoots) {
        if (Test-Path -LiteralPath $root) {
            $found = Get-ChildItem -LiteralPath $root -Filter vcvars32.bat -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
            if ($found) { return $found }
        }
    }
    throw 'No vcvars32.bat found. Install Visual Studio Build Tools with MSVC x86, Windows SDK, and MASM.'
}

if ($Clean -and (Test-Path -LiteralPath $BuildDir)) {
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
$vcvars = Find-VcVars32 $VSVars32
$source = $SourceDir.Replace("'", "''")
$build = $BuildDir.Replace("'", "''")

# Execute only the compiler commands after vcvars32 initializes the x86 environment.
# No download, installation, registry, service, or eNSP operation is performed here.
$batch = @"
call "$vcvars"
if errorlevel 1 exit /b 10
cd /d "$build"
ml.exe /nologo /c /coff /Cx /Fo"vbox52_thunks.obj" "$source\vbox52_thunks.asm"
if errorlevel 1 exit /b 20
ml.exe /nologo /c /coff /Cx /Fo"imachine_entries.obj" "$source\imachine_entries.asm"
if errorlevel 1 exit /b 21
cl.exe /nologo /c /O2 /GS- /Fo"vbox52_proxy.obj" "$source\vbox52_proxy.cpp"
if errorlevel 1 exit /b 30
cl.exe /nologo /c /O2 /GS- /Fo"spoof_thunks.obj" "$source\spoof_thunks.cpp"
if errorlevel 1 exit /b 31
link.exe /nologo /dll /out:"VBox52.dll" /def:"$source\vbox52.def" vbox52_proxy.obj vbox52_thunks.obj spoof_thunks.obj imachine_entries.obj ole32.lib oleaut32.lib psapi.lib advapi32.lib
if errorlevel 1 exit /b 40
dumpbin.exe /headers "VBox52.dll" > "VBox52.headers.txt"
if errorlevel 1 exit /b 50
dumpbin.exe /exports "VBox52.dll" > "VBox52.exports.txt"
if errorlevel 1 exit /b 51
"@

$temp = Join-Path $BuildDir 'build-x86.cmd'
Set-Content -LiteralPath $temp -Value $batch -Encoding ASCII
& cmd.exe /d /s /c "`"$temp`""
if ($LASTEXITCODE -ne 0) { throw "x86 build failed with exit code $LASTEXITCODE. See $BuildDir." }

$dll = Join-Path $BuildDir 'VBox52.dll'
$hash = Get-FileHash -LiteralPath $dll -Algorithm SHA256
$VendorDir = Join-Path $ProjectRoot 'vendor'
New-Item -ItemType Directory -Force -Path $VendorDir | Out-Null
Copy-Item -LiteralPath $dll -Destination (Join-Path $VendorDir 'VBox52.dll') -Force
Write-Host "Built: $dll"
Write-Host "Vendor copy: $(Join-Path $VendorDir 'VBox52.dll')"
Write-Host "Source: $SourceDir"
Write-Host "SHA256: $($hash.Hash)"
Write-Host "Exports: $(Join-Path $BuildDir 'VBox52.exports.txt')"
