#requires -Version 5.1
<#
  eNSP-VBox7-Bridge: eNSP / HCL / MuMu control panel.

  Double-click eNSPBridgeTool.bat. The script self-elevates, then shows:
    - current 64-bit VirtualBox COM owner (MuMu or Oracle)
    - eNSP 32-bit shim state
    - MuMu service state
    - buttons to launch HCL (Oracle mode + gen_py shim) or restore MuMu
#>
param([switch]$NoElevate)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $NoElevate -and -not (Test-Admin)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'eNSP Bridge - eNSP / HCL / MuMu 控制台'
$form.Size = New-Object System.Drawing.Size(720, 450)
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(30, 30)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'VirtualBox 模式控制'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(24, 18)
$title.Size = New-Object System.Drawing.Size(500, 32)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'HCL 使用 Oracle 7.2；MuMu 使用 MuMuVMM 6.1.36。两者不能同时运行。'
$subtitle.Location = New-Object System.Drawing.Point(26, 52)
$subtitle.Size = New-Object System.Drawing.Size(700, 24)
$form.Controls.Add($subtitle)

$statusBox = New-Object System.Windows.Forms.GroupBox
$statusBox.Text = '当前状态'
$statusBox.Location = New-Object System.Drawing.Point(24, 84)
$statusBox.Size = New-Object System.Drawing.Size(660, 190)
$form.Controls.Add($statusBox)

$lblCom = New-Object System.Windows.Forms.Label
$lblCom.Location = New-Object System.Drawing.Point(18, 28)
$lblCom.Size = New-Object System.Drawing.Size(660, 24)
$statusBox.Controls.Add($lblCom)

$lblEnsp = New-Object System.Windows.Forms.Label
$lblEnsp.Location = New-Object System.Drawing.Point(18, 62)
$lblEnsp.Size = New-Object System.Drawing.Size(660, 24)
$statusBox.Controls.Add($lblEnsp)

$lblMumu = New-Object System.Windows.Forms.Label
$lblMumu.Location = New-Object System.Drawing.Point(18, 96)
$lblMumu.Size = New-Object System.Drawing.Size(660, 24)
$statusBox.Controls.Add($lblMumu)

$lblHcl = New-Object System.Windows.Forms.Label
$lblHcl.Location = New-Object System.Drawing.Point(18, 130)
$lblHcl.Size = New-Object System.Drawing.Size(660, 24)
$statusBox.Controls.Add($lblHcl)

$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Location = New-Object System.Drawing.Point(18, 158)
$lblNote.Size = New-Object System.Drawing.Size(660, 22)
$lblNote.ForeColor = [System.Drawing.Color]::DimGray
$statusBox.Controls.Add($lblNote)

function Get-VBoxComVersion {
    try {
        $v = New-Object -ComObject 'VirtualBox.VirtualBox'
        $ver = $v.Version
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($v)
        return $ver
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

function Get-HclDir {
    foreach ($p in @('E:\HCL_5.10.3\app', 'C:\Program Files (x86)\HCL', 'C:\Program Files\HCL', 'C:\Program Files (x86)\HCL\HCL')) {
        if (Test-Path (Join-Path $p 'SimwareClient.exe')) { return $p }
    }
    return $null
}

function Update-Status {
    $ver = Get-VBoxComVersion
    if ($ver -eq '6.1.36_OSE') {
        $lblCom.Text = "64 位 COM：$ver  →  MuMu 模式"
        $lblCom.ForeColor = [System.Drawing.Color]::DarkGreen
    } elseif ($ver -like '7.2*') {
        $lblCom.Text = "64 位 COM：$ver  →  Oracle 模式（HCL 可用）"
        $lblCom.ForeColor = [System.Drawing.Color]::DarkOrange
    } else {
        $lblCom.Text = "64 位 COM：$ver"
        $lblCom.ForeColor = [System.Drawing.Color]::Firebrick
    }

    $cls = 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}\InprocServer32'
    $dll = (Get-ItemProperty $cls -ErrorAction SilentlyContinue).'(default)'
    $ver32 = (Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue).Version
    $lblEnsp.Text = "eNSP 32 位：$dll  /  Version=$ver32"

    $svc = Get-Service MuMuRemoteService -ErrorAction SilentlyContinue
    if ($svc) { $lblMumu.Text = "MuMuRemoteService：$($svc.Status) / $($svc.StartType)" }
    else { $lblMumu.Text = 'MuMuRemoteService：未找到' }

    $hcl = Get-HclDir
    if ($hcl) { $lblHcl.Text = "HCL 目录：$hcl" }
    else { $lblHcl.Text = 'HCL 目录：未找到（请把 HCL 放到 E:\HCL_5.10.3\app 或修改 Use-HCL.ps1）' }

    $lblNote.Text = '提示：HCL 退出后必须回到 MuMu 模式；异常中断请点“恢复 MuMu”。'
}

$btnHcl = New-Object System.Windows.Forms.Button
$btnHcl.Text = '启动 HCL（自动切 Oracle）'
$btnHcl.Location = New-Object System.Drawing.Point(24, 292)
$btnHcl.Size = New-Object System.Drawing.Size(210, 42)
$btnHcl.Add_Click({
    $form.Hide()
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Use-HCL.ps1')
    ) | Out-Null
    $form.Close()
})
$form.Controls.Add($btnHcl)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = '恢复 MuMu'
$btnRestore.Location = New-Object System.Drawing.Point(250, 292)
$btnRestore.Size = New-Object System.Drawing.Size(150, 42)
$btnRestore.Add_Click({
    $btnRestore.Enabled = $false
    try {
        & (Join-Path $PSScriptRoot 'Set-VBoxComMode.ps1') -Mode MuMu | Out-Null
        [System.Windows.Forms.MessageBox]::Show('已切回 MuMu 模式。', '完成') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("切换失败：$($_.Exception.Message)", '错误') | Out-Null
    } finally {
        Update-Status
        $btnRestore.Enabled = $true
    }
})
$form.Controls.Add($btnRestore)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = '刷新状态'
$btnRefresh.Location = New-Object System.Drawing.Point(416, 292)
$btnRefresh.Size = New-Object System.Drawing.Size(110, 42)
$btnRefresh.Add_Click({ Update-Status })
$form.Controls.Add($btnRefresh)

$btnShortcut = New-Object System.Windows.Forms.Button
$btnShortcut.Text = '创建 HCL 快捷方式'
$btnShortcut.Location = New-Object System.Drawing.Point(530, 292)
$btnShortcut.Size = New-Object System.Drawing.Size(160, 42)
$btnShortcut.Add_Click({
    $script = Join-Path $PSScriptRoot 'Install-HCLShortcuts.ps1'
    if (Test-Path $script) {
        & $script
        [System.Windows.Forms.MessageBox]::Show('已创建桌面/开始菜单快捷方式。', '完成') | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show('缺少 Install-HCLShortcuts.ps1。', '错误') | Out-Null
    }
})
$form.Controls.Add($btnShortcut)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = '退出'
$btnClose.Location = New-Object System.Drawing.Point(590, 356)
$btnClose.Size = New-Object System.Drawing.Size(100, 34)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

Update-Status
[void]$form.ShowDialog()
