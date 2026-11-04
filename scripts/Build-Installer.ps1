[CmdletBinding()]
param(
  [string]$Configuration = 'Release',
  [string]$Dotnet = 'dotnet'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

# Prefer a repo-local SDK when the machine has only the .NET runtime.
if ($Dotnet -eq 'dotnet') {
  $localDotnet = Join-Path (Split-Path -Parent $Root) '.dotnet\dotnet.exe'
  if (Test-Path -LiteralPath $localDotnet) { $Dotnet = $localDotnet }
}

$Project = Join-Path $Root 'src\Installer.csproj'
$PublishDir = Join-Path $Root 'build\installer-publish'
$Dist = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force -Path $PublishDir, $Dist | Out-Null

& $Dotnet publish $Project --configuration $Configuration --output $PublishDir
if ($LASTEXITCODE -ne 0) { throw ".NET 发布失败，退出码 $LASTEXITCODE" }

$Name = 'eNSP-VBox7-Bridge-Installer.exe'
$Built = Join-Path $PublishDir $Name
$Exe = Join-Path $Dist $Name
Copy-Item -LiteralPath $Built -Destination $Exe -Force

$Hash = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
$Manifest = [pscustomobject]@{
  Path            = $Name
  Length          = (Get-Item -LiteralPath $Exe).Length
  SHA256          = $Hash
  Runtime         = '.NET 8 self-contained + WebView2 Runtime'
  EmbeddedDllHash = (Get-FileHash -LiteralPath (Join-Path $Root 'vendor\VBox52.dll') -Algorithm SHA256).Hash
  Utc             = (Get-Date).ToUniversalTime().ToString('o')
}
$Manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Dist 'manifest.json') -Encoding UTF8

$Checksum = "$Hash  $Name"
Set-Content -LiteralPath (Join-Path $Dist 'SHA256SUMS.txt') -Value $Checksum -Encoding ASCII

Write-Host "Built $Exe"
Write-Host "SHA256 $Hash"
