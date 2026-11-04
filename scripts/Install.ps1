[CmdletBinding()]
param(
  [switch]$Uninstall,
  [switch]$Elevated,
  [string]$EnspDir,
  [string]$VBoxDir,
  [string]$GrantSid
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Split-Path -Parent $PSScriptRoot
$Dll=Join-Path $Root 'build\local-x86\VBox52.dll'
$ExpectedHash='AEA65CA5A8863A308DA482379D0C02965C5336F7B80A61087549874387B51204'
$logName='logs\install.log'; if($Uninstall){$logName='logs\uninstall.log'}
$LogPath=Join-Path $Root $logName
$Clsid='{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}'
$SpoofVersion='5.2.44'; $SpoofVersionExt='5.2.44r139111'
$VersionKeys=@('HKLM:\SOFTWARE\Oracle\VirtualBox','HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox'); $VersionValueNames=@('Version','VersionExt','InstallDir')
$Stamp=Join-Path $Root 'logs\install-state.json'
function Find-Ensp($p){ if($p){return $p.TrimEnd('\')}; @('D:\Program Files\Huawei\eNSP','D:\Software\Huawei\eNSP','C:\Program Files\Huawei\eNSP','C:\Program Files (x86)\Huawei\eNSP') | ?{Test-Path (Join-Path $_ 'tools')} | select -First 1 }
function Find-VBox($p){ if($p){return $p.TrimEnd('\')}; @('D:\Program Files\Oracle\VirtualBox','D:\Software\Oracle\VirtualBox',(Join-Path $env:ProgramFiles 'Oracle\VirtualBox')) | ?{Test-Path (Join-Path $_ 'VBoxManage.exe')} | select -First 1 }
$EnspDir=Find-Ensp $EnspDir; $VBoxDir=Find-VBox $VBoxDir
$operation='install'; if($Uninstall){$operation='uninstall'}; New-Item (Split-Path $LogPath) -ItemType Directory -Force|Out-Null; Set-Content -LiteralPath $LogPath -Value ("Operation: " + $operation) -Encoding UTF8
function Log($m){ $line="{0} {1}" -f (Get-Date).ToString('s'),$m; New-Item (Split-Path $LogPath) -ItemType Directory -Force|Out-Null; Add-Content -LiteralPath $LogPath -Value $line; Write-Host $m }
function Get-PEMachine([string]$Path){
  if(-not (Test-Path -LiteralPath $Path)){ return $null }
  $b=[IO.File]::ReadAllBytes($Path); if($b.Length -lt 64 -or $b[0] -ne 0x4d -or $b[1] -ne 0x5a){ return $null }
  $o=[BitConverter]::ToInt32($b,0x3c); if($o -lt 0 -or $o+6 -gt $b.Length -or $b[$o] -ne 0x50 -or $b[$o+1] -ne 0x45){ return $null }
  return ('0x{0:X4}' -f [BitConverter]::ToUInt16($b,$o+4))
}
function Assert-X86([string]$Path,[string]$Label){ $m=Get-PEMachine $Path; if($m -ne '0x014C'){ throw "$Label is not x86 PE (machine=$m): $Path" }; Log "$Label x86 OK" }
function Is-Admin { $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Reg-Snapshot($path){
  $exists=Test-Path $path; $p=if($exists){Get-ItemProperty $path -ErrorAction SilentlyContinue}; $k=if($exists){Get-Item $path -ErrorAction SilentlyContinue};
  [pscustomobject]@{Path=$path;Exists=$exists;DefaultPresent=if($k){$k.GetValueNames() -contains ''}else{$false};Default=if($k){$k.GetValue('',$null,'DoNotExpandEnvironmentNames')}else{$null};ThreadingModel=if($p){$p.ThreadingModel}else{$null}}
}
function Restore-Reg($s){
  if(-not $s){return}; if(-not $s.Exists){Remove-Item $s.Path -Recurse -Force -ErrorAction SilentlyContinue; return}
  New-Item $s.Path -Force|Out-Null
  if($s.DefaultPresent){Set-Item $s.Path -Value $s.Default -Force}
  else{Remove-ItemProperty $s.Path -Name '(default)' -ErrorAction SilentlyContinue}
  if($null -ne $s.ThreadingModel){New-ItemProperty $s.Path -Name ThreadingModel -Value $s.ThreadingModel -PropertyType String -Force|Out-Null}
  else{Remove-ItemProperty $s.Path -Name ThreadingModel -ErrorAction SilentlyContinue}
}
function Reg-ValueSnapshot($path,$name){
  $exists=Test-Path $path; $p=if($exists){Get-ItemProperty $path -ErrorAction SilentlyContinue}; $prop=if($p){$p.PSObject.Properties[$name]}; $present=$null -ne $prop; $value=if($present){$prop.Value}else{$null}
  [pscustomobject]@{Path=$path;Name=$name;Exists=$exists;Present=$present;Value=$value}
}
function Restore-RegValue($s){
  if(-not $s){return}; if(-not $s.Exists){return}
  New-Item $s.Path -Force|Out-Null
  if($s.Present){New-ItemProperty $s.Path -Name $s.Name -Value $s.Value -PropertyType String -Force|Out-Null}
  else{Remove-ItemProperty $s.Path -Name $s.Name -ErrorAction SilentlyContinue}
}
function State { $rk=Get-Item "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$Clsid\InprocServer32" -ErrorAction SilentlyContinue; [pscustomobject]@{Project=$Root;LocalDll=$Dll;DllHash=if(Test-Path $Dll){(Get-FileHash $Dll -Algorithm SHA256).Hash}else{$null};Ensp=$EnspDir;VBox=$VBoxDir;VBoxVersion=if($VBoxDir){(& (Join-Path $VBoxDir 'VBoxManage.exe') --version 2>$null | select -First 1)};Clsid32=if($rk){$rk.GetValue('')}else{$null}} }

if(-not (Is-Admin)){
  if($Elevated){ throw 'UAC elevation failed or was cancelled.' }
  $self=(Resolve-Path $MyInvocation.MyCommand.Path).Path
  $arg=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$self,'-Elevated')
  if($Uninstall){$arg += '-Uninstall'}
  if($EnspDir){$arg += @('-EnspDir',('"{0}"' -f $EnspDir))}
  if($VBoxDir){$arg += @('-VBoxDir',('"{0}"' -f $VBoxDir))}
  if($GrantSid){$arg += @('-GrantSid',('"{0}"' -f $GrantSid))}
  $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru
  exit $p.ExitCode
}
if(-not $EnspDir -or -not (Test-Path (Join-Path $EnspDir 'tools'))){ throw 'Classic eNSP was not found.' }
if(-not $Uninstall -and -not (Test-Path $Dll)){ throw "Local DLL missing: $Dll" }
$client=Join-Path $EnspDir 'eNSP_Client.exe'; $server=Join-Path $EnspDir 'vboxserver\eNSP_VBoxServer.exe'
if(-not $Uninstall){
  $actual=(Get-FileHash $Dll -Algorithm SHA256).Hash.ToUpperInvariant(); if($actual -ne $ExpectedHash){ throw "Local DLL hash mismatch: $actual" }
  Assert-X86 $Dll 'Local VBox52.dll'; Assert-X86 $client 'eNSP_Client.exe'; Assert-X86 $server 'eNSP_VBoxServer.exe'
  if(-not $VBoxDir){ throw 'VirtualBox was not found.' }; $vbm=Join-Path $VBoxDir 'VBoxManage.exe'; $ver=((& $vbm --version 2>$null | Select-Object -First 1).Trim()); if($ver -notmatch '^7\.2\.') { throw "VirtualBox 7.2.x is required; current version is $ver" }; Log "VirtualBox $ver OK"
  $locked=@('eNSP_Client','eNSP_VBoxServer','VBoxHeadless') | % { Get-Process -Name $_ -ErrorAction SilentlyContinue }; if($locked){ throw ('Close running processes first: '+(($locked|Select-Object -Expand ProcessName -Unique)-join ', ')) }
  $hv=$null; try { $hv=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch {}; Log ("OSArchitecture=$([Environment]::OSVersion.Platform) Is64BitOS=$([Environment]::Is64BitOperatingSystem); HypervisorPresent=$($hv.HypervisorPresent); FirmwareVirtualization=$($hv.VirtualizationFirmwareEnabled)")
}
$targets=@('tools','vboxserver','.','plugin\ngfw\tools\ngfw') | % { Join-Path $EnspDir $_ } | % { Join-Path $_ 'VBox52.dll' }
if($Uninstall){
 try {
  Log "Uninstall started. eNSP=$EnspDir"
  $st=if(Test-Path $Stamp){Get-Content $Stamp -Raw|ConvertFrom-Json}else{$null}; $installedHash=if($st.Hash){$st.Hash}else{$null}
  if(-not $st){Log "No install-state.json found ($Stamp). File backup only; registry snapshot unavailable."}
   $restored=0; $removed=0; $skipped=0
  foreach($t in $targets){
    $b="$t.orig.bak"
    $currentHash=if(Test-Path $t){(Get-FileHash $t -Algorithm SHA256).Hash}else{$null}
     # An upgrade can leave install-state.json from the previous shim build.
     # Accept both the recorded hash and this source's current expected hash;
     # preserve files with any other hash as genuine external modifications.
     $knownHashes=@($installedHash,$ExpectedHash) | Where-Object { $_ } | Select-Object -Unique
      if($currentHash -and $currentHash -notin $knownHashes){Log "Skipping modified target: $t"; $skipped++; continue}
    if(Test-Path $b){
      Copy-Item -LiteralPath $b -Destination $t -Force
      $restoredHash=(Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash
      if($restoredHash -ne (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash){throw "Restore hash mismatch: $t"}
      Log "Restored backup: $b -> $t; SHA256=$restoredHash"
      $restored++
     } elseif($currentHash -and $currentHash -in $knownHashes){
      Remove-Item -LiteralPath $t -Force
       Log "Removed installed shim (no original file backup): $t"
      $removed++
     } else {Log "No file action required: $t"}
  }
   if($skipped -gt 0){throw "Uninstall incomplete: $skipped modified target(s) preserved. State and registry snapshot kept at $Stamp."}
  if($st){foreach($r in @($st.Registry)){Restore-Reg $r; Log "Restored CLSID registry snapshot: $($r.Path)"}}
  if($st){foreach($r in @($st.VersionRegistry)){Restore-RegValue $r; Log "Restored VirtualBox registry value: $($r.Path) [$($r.Name)]"}}
  Remove-Item $Stamp -Force -ErrorAction SilentlyContinue
  Log "Uninstall completed. Restored=$restored; Removed=$removed; Skipped=$skipped. eNSP, VirtualBox and VMs not removed."
 } catch {
    Log ("Uninstall failed: " + $_.Exception.Message)
    Log ("At: " + $_.InvocationInfo.PositionMessage)
   throw
 }
  exit 0
}
$hash=(Get-FileHash $Dll -Algorithm SHA256).Hash
$done=@(); $created=@()
try {
  $regPaths=@(
    ('HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\' + $Clsid + '\InprocServer32')
  )
  $regBackup=@($regPaths|%{Reg-Snapshot $_})
  $versionBackup=@($VersionKeys | % { $p=$_; $VersionValueNames | % { Reg-ValueSnapshot $p $_ } })
  foreach($t in $targets){
    $d=Split-Path $t
    New-Item $d -ItemType Directory -Force | Out-Null
    if(Test-Path $t){ $b="$t.orig.bak"; if(-not(Test-Path $b)){Copy-Item $t $b} } else { $created += $t }
    Copy-Item -LiteralPath $Dll -Destination $t -Force
    $done += $t
    $targetHash = (Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash.ToUpperInvariant()
    if($targetHash -ne $ExpectedHash){ throw "Target hash verification failed: $t" }
    Log "Copied and verified $t"
  }
  foreach($base in $regPaths){New-Item $base -Force|Out-Null; Set-Item $base -Value (Join-Path $EnspDir 'tools\VBox52.dll') -Force; New-ItemProperty $base -Name ThreadingModel -Value Both -PropertyType String -Force|Out-Null}
  # The 64-bit COM view must stay on LocalServer32 -> VBoxSVC.exe. Pointing it
  # at the x86 VBox52.dll breaks 64-bit clients such as HCL with 0x800700C1.
  $inproc64=('HKLM:\SOFTWARE\Classes\CLSID\' + $Clsid + '\InprocServer32')
  if(Test-Path $inproc64){ Remove-Item $inproc64 -Recurse -Force; Log "Removed 64-bit InprocServer32: $inproc64" }
  New-Item (Split-Path $Stamp) -ItemType Directory -Force|Out-Null; foreach($p in $VersionKeys){New-Item $p -Force|Out-Null; New-ItemProperty $p -Name Version -Value $SpoofVersion -PropertyType String -Force|Out-Null; New-ItemProperty $p -Name VersionExt -Value $SpoofVersionExt -PropertyType String -Force|Out-Null; New-ItemProperty $p -Name InstallDir -Value ($VBoxDir.TrimEnd('\')+'\') -PropertyType String -Force|Out-Null}
  [pscustomobject]@{Hash=$hash;Targets=$done;Ensp=$EnspDir;VBox=$VBoxDir;Registry=$regBackup;VersionRegistry=$versionBackup;Utc=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content $Stamp -Encoding UTF8
  Log "Installed local x86 shim: $hash"
} catch { Log ("Install failed: "+$_.Exception.Message); Log ("At: "+$_.InvocationInfo.PositionMessage); foreach($t in $done){$b="$t.orig.bak"; if(Test-Path $b){Copy-Item $b $t -Force}elseif($created -contains $t){Remove-Item $t -Force -ErrorAction SilentlyContinue}}; if($regBackup){foreach($r in $regBackup){Restore-Reg $r}}; if($versionBackup){foreach($r in $versionBackup){Restore-RegValue $r}}; throw }
