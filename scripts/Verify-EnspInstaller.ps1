[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'
$item = Get-Item -LiteralPath $Path -ErrorAction Stop
if (-not $item.PSIsContainer -and $item.Length -gt 0) {
    $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
} else {
    throw 'The installer path must be a non-empty file.'
}

$sig = Get-AuthenticodeSignature -LiteralPath $item.FullName
$version = $null
try { $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($item.FullName) } catch { }

[pscustomobject]@{
    Path = $item.FullName
    Size = $item.Length
    SHA256 = $hash
    ExpectedSHA256 = if ($ExpectedSha256) { $ExpectedSha256.ToUpperInvariant() } else { '<not supplied>' }
    HashMatches = if ($ExpectedSha256) { $hash -eq $ExpectedSha256.ToUpperInvariant() } else { '<not checked>' }
    AuthenticodeStatus = $sig.Status
    Signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '<none>' }
    FileDescription = if ($version) { $version.FileDescription } else { '<unavailable>' }
    FileVersion = if ($version) { $version.FileVersion } else { '<unavailable>' }
} | Format-List

Write-Host 'This command did not execute the installer or inspect/run embedded payloads.' -ForegroundColor Cyan
