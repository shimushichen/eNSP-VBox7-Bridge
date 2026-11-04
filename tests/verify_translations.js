// Verify that English output from PowerShell scripts matches LOG_TRANSLATIONS in app.js
const fs = require('fs');
const path = require('path');

const appJs = fs.readFileSync(path.join(__dirname, '..', 'src', 'ui', 'app.js'), 'utf-8');

// Extract LOG_TRANSLATIONS array by evaluating it in a sandbox-like context
const start = appJs.indexOf('const LOG_TRANSLATIONS = [');
const end = appJs.indexOf('];', start) + 2;
const arraySrc = appJs.slice(start + 'const LOG_TRANSLATIONS = '.length, end);
const LOG_TRANSLATIONS = eval(arraySrc);

// Sample English output lines that the scripts produce (with example values)
const sampleLines = [
  // Install.ps1
  'Uninstall started. eNSP=D:\\Program Files\\Huawei\\eNSP',
  'No install-state.json found (C:\\proj\\logs\\install-state.json). File backup only; registry snapshot unavailable.',
  'Skipping modified target: D:\\Program Files\\Huawei\\eNSP\\tools\\VBox52.dll',
  'Restored backup: D:\\eNSP\\tools\\VBox52.dll.orig.bak -> D:\\eNSP\\tools\\VBox52.dll; SHA256=ABC123',
  'Removed installed shim (no original file backup): D:\\eNSP\\tools\\VBox52.dll',
  'No file action required: D:\\eNSP\\tools\\VBox52.dll',
  'Restored CLSID registry snapshot: HKLM\\SOFTWARE\\Classes\\WOW6432Node\\CLSID\\{B1A7...}',
  'Restored VirtualBox registry value: HKLM:\\SOFTWARE\\Oracle\\VirtualBox [Version]',
  'Uninstall completed. Restored=4; Removed=0; Skipped=0. eNSP, VirtualBox and VMs not removed.',
  'Uninstall failed: Some error',
  'At: C:\\scripts\\Install.ps1:85 char:5',
  'Copied and verified D:\\eNSP\\tools\\VBox52.dll',
  'Removed 64-bit InprocServer32: HKLM:\\SOFTWARE\\Classes\\CLSID\\{B1A7...}\\InprocServer32',
  'Installed local x86 shim: AEA65CA5A8863A308DA482379D0C02965C5336F7B80A61087549874387B51204',
  'Install failed: Some error',
  'VirtualBox 7.2.16r174877 OK',
  'Local VBox52.dll x86 OK',
  'eNSP_Client.exe x86 OK',
  'Operation: install',
  'Operation: uninstall',
  'OSArchitecture=Win32NT Is64BitOS=True; HypervisorPresent=True; FirmwareVirtualization=True',
  // Check.ps1 table keys
  'This command is read-only. It does not write files, registry values, ACLs, services, or VM registrations.',
  // RegisterVM.ps1
  'AR_Base: registered and path is valid',
  'AR_Base: re-registered',
  'AR_Base: registered',
  'AR_Base: template missing; skipped',
  'AR_Base: not registered; would register D:\\path\\AR_Base.vbox',
  'AR_Base: stale path; would re-register D:\\path\\AR_Base.vbox',
  'AR_Base: stale path but VM is running; skipped',
  'AR_Base: created AR_Base_Link',
  'AR_Base: missing AR_Base_Link; would create in normal mode',
  'AR_Base: VM registration not found',
  'AR_Base: failed to create AR_Base_Link',
  'AR_Base: register failed',
  'AR_Base: unregister failed',
  'Registered VMs:',
  'check complete: registered=0 reregistered=0 snapshots=0 warnings=0',
  'This script never deletes disks, VMs, or existing snapshots; -Check is read-only.',
  // HCLStatus.ps1
  '64-bit VirtualBox COM: 7.2.16',
  '64-bit VirtualBox COM: ERROR: Something went wrong',
  'eNSP 32-bit InprocServer32: D:\\eNSP\\tools\\VBox52.dll',
  'Oracle registry Version: 5.2.44',
  'MuMuRemoteService: Running / Automatic',
  'MuMuRemoteService: not found',
  // Set-VBoxComMode.ps1
  '=== Set-VBoxComMode ===',
  '=== RESULT ===',
  'Time: 2026-11-04T13:00:00.0000000',
  'User: DOMAIN\\User',
  'Host: COMPUTER',
  'Action: Oracle',
  'Current mode: MuMu',
  'Target mode: Oracle',
  'Backup: C:\\proj\\logs\\vbox-com-mode-backup-20261104-130000',
  '  [unchanged] VirtualBox.VirtualBox -> {23cd1535-edaa-4f21-a4ab-45d97fd1d58b}',
  '  [set]   VirtualBox.VirtualBox -> {b1a7a4f2-47b9-4a1e-82b2-07ccd5323c3f} (was: {23cd1535-edaa-4f21-a4ab-45d97fd1d58b})',
  '  [removed]   64-bit InprocServer32 (x86 VBox52.dll shim)',
  '  [unchanged]   64-bit InprocServer32 already absent',
  '  [set]   LocalServer32 -> "D:\\Program Files\\Oracle\\VirtualBox\\VBoxSVC.exe"',
  '  [unchanged]   LocalServer32 -> "D:\\Program Files\\Oracle\\VirtualBox\\VBoxSVC.exe"',
  'Read-back:',
  '  VirtualBox.VirtualBox -> {b1a7a4f2-47b9-4a1e-82b2-07ccd5323c3f}',
  '  eNSP 32-bit view unchanged: D:\\eNSP\\tools\\VBox52.dll (SHA256 ABC123)',
  'COM activation test (64-bit):',
  'COM activation test skipped (-SkipComTest).',
  'Mode before: MuMu',
  'Mode after: Oracle',
  'Changed: 6 value(s)',
  'Summary: C:\\proj\\logs\\set-vbox-mode-oracle-20261104-130000.json',
  'MuMu: service=Running, processes=MuMuVMMSVC(1234)',
  '  Stopping MuMuVMMSVC.exe (PID 1234) before switching to Oracle mode...',
  '  Restarting MuMuRemoteService...',
  '  MuMuRemoteService: Running',
  '  COM check OK: VirtualBox.VirtualBox = 7.2.16; VirtualBoxClient.VirtualBox = 7.2.16',
  'Restore source: C:\\proj\\logs\\vbox-com-mode-backup-20261104-130000',
  'Safety backup: C:\\proj\\logs\\vbox-com-mode-prerestore-20261104-130100',
  'Restored (legacy). Current mode: MuMu',
  '  restored HKLM\\SOFTWARE\\Classes\\VirtualBox.VirtualBox',
  '  verified    HKLM\\SOFTWARE\\Classes\\WOW6432Node\\CLSID\\{B1A7...} (read-only; never written)',
  '  restored    HKLM\\SOFTWARE\\Classes\\VirtualBox.VirtualBox',
  '  removed    HKLM\\SOFTWARE\\Classes\\VirtualBox.Session (absent in snapshot)',
  'Restored mode: MuMu (snapshot was taken in Oracle)',
  'Restored mode: Oracle (snapshot was taken in MuMu)',
  'COM activation test after restore:',
  'Restore completed successfully.',
  'Re-launching in native 64-bit PowerShell...',
  'Requesting administrator elevation...',
  'Rollback backup: C:\\proj\\logs\\vbox-com-mode-backup-20261104-130000',
  'Rollback command: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\\script.ps1" -Restore -BackupDir "C:\\backup"',
  'ERROR: Some error message',
  // Use-HCL.ps1
  'HCL dir: E:\\HCL_5.10.3\\app',
  'HCL exe: E:\\HCL_5.10.3\\app\\SimwareClient.exe',
  'Log: C:\\proj\\logs\\hcl-session-20261104-130000.log',
  'gen_py cache not found; starting HCL once to generate it...',
  'gen_py backup: C:\\proj\\logs\\gen_py_backup\\D7569351-*.py.20261104-130000.bak',
  'HCL VBox72 shim appended.',
  'HCL VBox72 shim already present.',
  'Switching VirtualBox COM to Oracle 7.2...',
  'Starting HCL...',
  'HCL PID: 12345',
  'Close HCL normally (stop devices first); the script will restore eNSP mode automatically.',
  'HCL exited.',
  'gen_py cache restored.',
  'Switching VirtualBox COM back to MuMu...',
  'Final mode: MuMu.',
  // Warnings (WARNING: prefix stripped by renderLine before translateLine)
  'MuMuRemoteService is not installed; skipped.',
  'No manifest.json found; performing legacy restore of the known seven keys only.',
  'Legacy backup has no data for HKLM\\SOFTWARE\\Classes\\VirtualBox.Session; key left unchanged.',
  'Set-VBoxComMode -Mode MuMu failed (exit 1). See logs\\set-vbox-mode-mumu-*.log',
  'failed to restore MuMu mode: Some error',
  // Errors that propagate directly
  'Classic eNSP was not found.',
  'VirtualBox was not found.',
  'VirtualBox 7.2.x is required; current version is 6.1.36',
  'Close running processes first: eNSP_Client, VBoxHeadless',
  'UAC elevation failed or was cancelled.',
  'Local DLL missing: C:\\proj\\build\\local-x86\\VBox52.dll',
  'Oracle VirtualBox was not found (VBoxSVC.exe missing).',
  'MuMu Player is running (MuMuNxMain). Exit MuMu before switching to Oracle mode; HCL and MuMu cannot run simultaneously.',
  'MuMu COM server file is missing: C:\\MuMu\\MuMuVMMSVC.exe. Repair MuMu (keep user data) and retry.',
  'HCL did not generate gen_py cache.',
  'HCL SimwareClient.exe not found. Specify -HclDir.',
  'No usable backup directory found under logs\\.',
  'This script must run in 64-bit PowerShell; Sysnative PowerShell not found.',
  'Local DLL hash mismatch: ABC123',
];

function translateLine(line) {
  for (const [re, repl, type] of LOG_TRANSLATIONS) {
    if (re.test(line)) {
      let text = line.replace(re, repl)
        .replace(/\bTrue\b/g, '是').replace(/\bFalse\b/g, '否')
        .replace(/\s->\s/g, ' → ');
      return { text, type: type || null, matched: true };
    }
  }
  return { text: line, type: null, matched: false };
}

let unmatched = [];
for (const line of sampleLines) {
  const result = translateLine(line);
  if (!result.matched) {
    unmatched.push(line);
  }
}

if (unmatched.length === 0) {
  console.log(`✓ All ${sampleLines.length} sample lines matched a translation.`);
} else {
  console.log(`✗ ${unmatched.length} of ${sampleLines.length} sample lines did NOT match any translation:`);
  for (const line of unmatched) {
    console.log(`  "${line.slice(0, 100)}"`);
  }
  process.exit(1);
}
