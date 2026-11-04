const pageNames = {
  dashboard: "状态总览",
  ensp: "eNSP 兼容层",
  hcl: "HCL / eNSP 模式",
  settings: "环境设置"
};

const actions = {
  install: {
    title: "部署 eNSP 兼容层",
    description: "将执行环境校验、兼容层部署和基础 VM 注册检查。",
    items: ["检查 eNSP 与 VirtualBox 版本及架构", "备份并部署四个 VBox52.dll 位置", "写入 32 位 COM 配置并检查基础 VM"],
    confirm: "确认部署",
    danger: false
  },
  check: {
    title: "只读环境检查",
    description: "检查当前环境，不修改文件、注册表或虚拟机。",
    items: ["读取核心文件版本与 SHA-256", "检查 32 位及 64 位 COM 归属", "读取 Hyper-V 与 eNSP 服务状态"],
    confirm: "运行检查",
    danger: false
  },
  uninstall: {
    title: "卸载并恢复原始环境",
    description: "此操作会移除已部署的兼容层，并尽可能恢复到安装前状态。",
    items: ["恢复 VBox52.dll 的原始备份", "还原 CLSID 与 VirtualBox 版本快照", "保留 eNSP、VirtualBox、虚拟磁盘和 VM"],
    confirm: "确认卸载",
    danger: true
  },
  hcl: {
    title: "启动 HCL 工作空间",
    description: "将切换到 Oracle 模式并应用 API Shim，HCL 退出后恢复 eNSP。",
    items: ["备份 gen_py 缓存与当前 COM 配置", "切换 Oracle ProgID 并应用 HCL Shim", "启动 HCL，退出后自动恢复 eNSP"],
    confirm: "切换并启动",
    danger: false
  },
  mumu: {
    title: "恢复 eNSP 模式",
    description: "将 64 位 VirtualBox ProgID 切回 eNSP VMM，32 位视图保持不变。",
    items: ["还原 eNSP VirtualBox COM 归属", "恢复 HCL gen_py 原始缓存", "保留 eNSP 32 位 VBox52.dll 配置"],
    confirm: "确认恢复",
    danger: false
  },
  oracle: {
    title: "切换到 Oracle 模式",
    description: "只切换 64 位 VirtualBox COM ProgID 到 Oracle 7.2，不启动 HCL。",
    items: ["备份当前 COM 归属与 eNSP 32 位视图", "切换六个 VirtualBox ProgID 到 Oracle", "保留 eNSP 32 位 VBox52.dll 配置"],
    confirm: "确认切换",
    danger: false
  },
  hclstatus: {
    title: "查看 HCL / eNSP 状态",
    description: "只读检查 COM 归属、HCL 目录和 eNSP 服务状态。",
    items: ["读取 64 位 VirtualBox COM 版本", "检查 HCL Shim 与运行目录", "检查 MuMuRemoteService 状态"],
    confirm: "查看状态",
    danger: false
  }
};

let pendingAction = null;
let activeAction = null;
let hostBusy = false;
let settingsDirty = false;
let taskTimer = null;
let toastTimer = null;
let taskCounter = 0;
let taskStartedAt = 0;
const host = window.chrome && window.chrome.webview;
const modal = document.getElementById("confirm-modal");
const modalConfirm = document.getElementById("modal-confirm");
const dock = document.getElementById("task-dock");
const log = document.getElementById("task-log");

function navigate(page) {
  if (!pageNames[page]) return;
  document.querySelectorAll(".page").forEach(element => element.classList.toggle("active", element.id === `page-${page}`));
  document.querySelectorAll(".nav-item").forEach(button => {
    const selected = button.dataset.page === page;
    button.classList.toggle("active", selected);
    if (selected) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });
  document.getElementById("breadcrumb").textContent = pageNames[page];
  document.querySelector(".main-content").scrollTop = 0;
  document.title = `${pageNames[page]} · eNSP Bridge`;
}

function showToast(message) {
  const toast = document.getElementById("toast");
  toast.querySelector("span").textContent = message;
  toast.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("show"), 3200);
}

function post(message) {
  if (!host) {
    showToast("桌面桥未连接，请在 eNSP Bridge EXE 中打开此界面");
    return false;
  }
  host.postMessage(message);
  return true;
}

function setText(id, value) {
  const element = document.getElementById(id);
  if (element) element.textContent = value;
}

function openAction(name) {
  const action = actions[name];
  if (!action) return;
  if (hostBusy) {
    showToast("另一个操作仍在执行，请等待完成");
    return;
  }
  if (name === "check" || name === "hclstatus") {
    runTask(name);
    return;
  }
  pendingAction = name;
  setText("modal-title", action.title);
  setText("modal-description", action.description);
  document.getElementById("modal-list").replaceChildren(...action.items.map(text => {
    const item = document.createElement("li");
    item.textContent = text;
    return item;
  }));
  document.getElementById("modal-icon").classList.toggle("danger", action.danger);
  modalConfirm.textContent = action.confirm;
  modalConfirm.classList.toggle("button-danger-ghost", action.danger);
  modalConfirm.classList.toggle("button-primary", !action.danger);
  modal.hidden = false;
  modalConfirm.focus();
}

function closeModal() {
  modal.hidden = true;
  pendingAction = null;
}

function appendLog(text, className = "") {
  const row = document.createElement("div");
  const type = className === "log-accent" ? "header" : className === "log-success" ? "success" : "default";
  row.className = "log-row log-" + type;
  row.innerHTML = '<i class="log-ico"></i><span class="log-txt">' + escapeHtml(text) + '</span>';
  log.appendChild(row);
  log.scrollTop = log.scrollHeight;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

const LOG_TRANSLATIONS = [
  [/^VirtualBox (\S+) OK$/, "VirtualBox $1 版本检测通过", "success"],
  [/^Copied and verified (.+)$/, "已部署并校验：$1", "success"],
  [/^Installed local x86 shim: ([A-F0-9]+)$/, "本地 x86 兼容层已安装（SHA256 $1）", "success"],
  [/^Removed 64-bit InprocServer32: (.+)$/, "已移除 64 位 InprocServer32：$1", "step"],
  [/^Uninstall started\. eNSP=(.+)$/, "开始卸载｜eNSP 目录：$1", "section"],
  [/^Restored backup: .+ -> (.+); SHA256=[A-F0-9]+$/, "已恢复备份：$1", "success"],
  [/^Removed installed shim \(no original file backup\): (.+)$/, "已移除兼容层（无原始备份）：$1", "step"],
  [/^No file action required: (.+)$/, "无需文件操作：$1", "default"],
  [/^Skipping modified target: (.+)$/, "跳过被外部修改的目标：$1", "warning"],
  [/^Uninstall completed\. Restored=(\d+); Removed=(\d+); Skipped=(\d+)\. (.+)$/, "卸载完成｜恢复 $1 · 移除 $2 · 跳过 $3｜$4", "success"],
  [/^Install failed: (.+)$/, "安装失败：$1", "error"],
  [/^Uninstall failed: (.+)$/, "卸载失败：$1", "error"],
  [/^At: (.+)$/, "位置：$1", "error"],
  [/^No install-state\.json found.*$/, "未找到安装状态快照，仅能恢复文件备份，注册表快照不可用。", "warning"],
  [/^(\w[\w-]*): registered and path is valid$/, "$1：已注册且路径有效", "success"],
  [/^(\w[\w-]*): re-registered$/, "$1：已重新注册", "success"],
  [/^(\w[\w-]*): registered$/, "$1：已注册", "success"],
  [/^(\w[\w-]*): template missing; skipped$/, "$1：模板缺失，已跳过", "warning"],
  [/^(\w[\w-]*): not registered; would register (.+)$/, "$1：未注册，将注册 $2", "step"],
  [/^(\w[\w-]*): stale path; would re-register (.+)$/, "$1：路径过期，将重新注册 $2", "step"],
  [/^(\w[\w-]*): stale path but VM is (.+); skipped$/, "$1：路径过期但 VM 状态为 $2，已跳过", "warning"],
  [/^(\w[\w-]*): created (\w+_Link)$/, "$1：已创建链接快照 $2", "success"],
  [/^(\w[\w-]*): missing (\w+_Link); would create in normal mode$/, "$1：缺少 $2，将在正常模式创建", "step"],
  [/^(\w[\w-]*): VM registration not found$/, "$1：未找到 VM 注册", "warning"],
  [/^(\w[\w-]*): failed to create (\w+_Link)$/, "$1：创建 $2 失败", "warning"],
  [/^(\w[\w-]*): register failed$/, "$1：注册失败", "warning"],
  [/^(\w[\w-]*): unregister failed$/, "$1：取消注册失败", "warning"],
  [/^Registered VMs:$/, "已注册的虚拟机", "section"],
  [/^(check|reconcile) complete: registered=(\d+) reregistered=(\d+) snapshots=(\d+) warnings=(\d+)$/, "$1 完成｜注册 $2 · 重注册 $3 · 快照 $4 · 警告 $5", "success"],
  [/^This script never deletes.*$/, "此脚本不会删除磁盘、VM 或现有快照；-Check 为只读。", "info"],
  [/^This command is read-only\..*$/, "此命令为只读，不会写入文件、注册表、ACL、服务或 VM 注册。", "info"],
  [/^64-bit VirtualBox COM: ERROR: (.+)$/, "64 位 VirtualBox COM 错误：$1", "error"],
  [/^64-bit VirtualBox COM: (.+)$/, "64 位 VirtualBox COM：$1", "default"],
  [/^eNSP 32-bit InprocServer32: (.+)$/, "eNSP 32 位 InprocServer32：$1", "default"],
  [/^Oracle registry Version: (.+)$/, "Oracle 注册表版本：$1", "default"],
  [/^MuMuRemoteService: not found$/, "MuMuRemoteService：未安装", "warning"],
  [/^MuMuRemoteService: (.+)$/, "MuMuRemoteService：$1", "default"],
  [/^=== Set-VBoxComMode ===$/, "Set-VBoxComMode · COM 模式切换", "header"],
  [/^=== RESULT ===$/, "执行结果", "header"],
  [/^Time\s*:\s*(.+)$/, "时间：$1", "default"],
  [/^User\s*:\s*(.+)$/, "用户：$1", "default"],
  [/^Host\s*:\s*(.+)$/, "主机：$1", "default"],
  [/^Action\s*:\s*(.+)$/, "操作：$1", "default"],
  [/^Current mode\s*:\s*(.+)$/, "当前模式：$1", "default"],
  [/^Target mode\s*:\s*(.+)$/, "目标模式：$1", "default"],
  [/^Backup\s*:\s*(.+)$/, "备份目录：$1", "default"],
  [/^Safety backup\s*:\s*(.+)$/, "安全备份：$1", "default"],
  [/^Mode before\s*:\s*(.+)$/, "切换前模式：$1", "default"],
  [/^Mode after\s*:\s*(.+)$/, "切换后模式：$1", "success"],
  [/^Changed\s*:\s*(\d+) value\(s\)$/, "变更：$1 项", "default"],
  [/^Summary\s*:\s*(.+)$/, "摘要文件：$1", "default"],
  [/^MuMu\s*:\s*service=(.+), processes=(.*)$/, "eNSP：服务 $1 · 进程 $2", "default"],
  [/^Restore source: (.+)$/, "恢复来源：$1", "default"],
  [/^Restored mode: (.+)$/, "恢复后模式：$1", "success"],
  [/^Restored \(legacy\)\. Current mode: (.+)$/, "已恢复（旧版兼容）｜当前模式：$1", "success"],
  [/^Restore completed successfully\.$/, "恢复成功完成。", "success"],
  [/^Read-back:$/, "回读校验", "section"],
  [/^COM activation test \(64-bit\):$/, "COM 激活测试（64 位）", "section"],
  [/^COM activation test after restore:$/, "恢复后 COM 激活测试", "section"],
  [/^COM activation test skipped.*$/, "已跳过 COM 激活测试（-SkipComTest）。", "info"],
  [/^\s*\[set\]\s+(.+)$/, "已设置：$1", "step"],
  [/^\s*\[unchanged\]\s+(.+)$/, "未变更：$1", "default"],
  [/^\s*\[removed\]\s+(.+)$/, "已移除：$1", "step"],
  [/^\s*COM check OK: (.+)$/, "COM 校验通过：$1", "success"],
  [/^\s*eNSP 32-bit view unchanged: (.+)$/, "eNSP 32 位视图未变：$1", "success"],
  [/^\s*restored (.+)$/, "已恢复：$1", "success"],
  [/^\s*removed\s+(.+)$/, "已移除：$1", "step"],
  [/^\s*verified\s+(.+)$/, "已校验：$1", "success"],
  [/^Requesting administrator elevation\.\.\.$/, "正在请求管理员权限（UAC）…", "info"],
  [/^Re-launching in native 64-bit PowerShell\.\.\.$/, "正在以原生 64 位 PowerShell 重新启动…", "info"],
  [/^Rollback backup: (.+)$/, "回滚备份：$1", "warning"],
  [/^Rollback command: (.+)$/, "回滚命令：$1", "warning"],
  [/^ERROR: (.+)$/, "错误：$1", "error"],
  [/^HCL dir\s*:\s*(.+)$/, "HCL 目录：$1", "default"],
  [/^HCL exe\s*:\s*(.+)$/, "HCL 可执行：$1", "default"],
  [/^Log\s*:\s*(.+)$/, "日志文件：$1", "default"],
  [/^gen_py cache not found.*$/, "未找到 gen_py 缓存，先启动一次 HCL 以生成…", "step"],
  [/^gen_py backup: (.+)$/, "gen_py 备份：$1", "default"],
  [/^HCL VBox72 shim appended\.$/, "已追加 HCL VBox72 兼容 Shim。", "success"],
  [/^HCL VBox72 shim already present\.$/, "HCL VBox72 兼容 Shim 已存在。", "default"],
  [/^Switching VirtualBox COM to Oracle 7\.2\.\.\.$/, "正在将 VirtualBox COM 切换到 Oracle 7.2…", "step"],
  [/^Switching VirtualBox COM back to MuMu\.\.\.$/, "正在将 VirtualBox COM 切回 eNSP…", "step"],
  [/^Starting HCL\.\.\.$/, "正在启动 HCL…", "step"],
  [/^HCL PID: (\d+)$/, "HCL 进程 PID：$1", "default"],
  [/^Close HCL normally.*$/, "请在停止设备后正常关闭 HCL，本脚本将随后恢复 eNSP 模式。", "info"],
  [/^HCL exited\.$/, "HCL 已退出。", "default"],
  [/^gen_py cache restored\.$/, "gen_py 缓存已恢复。", "success"],
  [/^Final mode: MuMu\.$/, "最终模式：eNSP。", "success"],
  [/^failed to restore MuMu mode: (.+)$/, "恢复 eNSP 模式失败：$1", "warning"],
  [/^Operation: install$/, "操作：安装", "section"],
  [/^Operation: uninstall$/, "操作：卸载", "section"],
  [/^(.+?) x86 OK$/, "$1 架构校验通过（x86）", "success"],
  [/^OSArchitecture=(\S+) Is64BitOS=(\S+); HypervisorPresent=(\S+); FirmwareVirtualization=(\S+)$/, "系统架构：$1 · 64位系统：$2 · Hypervisor：$3 · 固件虚拟化：$4", "default"],
  [/^\s+(VirtualBox\.[.\w]+) -> \{([0-9a-f-]+)\}$/, "  $1 → $2", "step"],
  [/^\s+Stopping MuMuVMMSVC\.exe \(PID (\d+)\) before switching to Oracle mode\.\.\.$/, "  正在停止 MuMuVMMSVC.exe（PID $1），准备切换到 Oracle 模式…", "step"],
  [/^\s+Restarting MuMuRemoteService\.\.\.$/, "  正在重启 MuMuRemoteService…", "step"],
  [/^\s+MuMuRemoteService: (Running|Stopped)$/, "  MuMuRemoteService：$1", "default"],
  [/^Restored mode: MuMu \(snapshot was taken in (.+)\)$/, "恢复后模式：eNSP（快照拍摄于 $1）", "success"],
  [/^Restored mode: Oracle \(snapshot was taken in (.+)\)$/, "恢复后模式：Oracle（快照拍摄于 $1）", "success"],
  [/^No manifest\.json found; performing legacy restore of the known seven keys only\.$/, "未找到 manifest.json，执行旧版恢复（仅恢复已知七个键）。", "warning"],
  [/^Legacy backup has no data for (.+); key left unchanged\.$/, "旧版备份无 $1 的数据，该键保持不变。", "warning"],
  [/^No usable backup directory found under logs\\\.$/, "logs 目录下未找到可用的备份目录。", "error"],
  [/^Classic eNSP was not found\..*$/, "未找到经典 eNSP，请先安装并验证 eNSP。", "error"],
  [/^VirtualBox was not found\.$/, "未找到 VirtualBox。", "error"],
  [/^VirtualBox 7\.2\.x is required; current version is (.+)$/, "需要 VirtualBox 7.2.x，当前版本：$1", "error"],
  [/^Close running processes first: (.+)$/, "请先关闭正在运行的进程：$1", "error"],
  [/^UAC elevation failed or was cancelled\.$/, "UAC 提权失败或被取消。", "error"],
  [/^Local DLL missing: (.+)$/, "本地 DLL 缺失：$1", "error"],
  [/^Oracle VirtualBox was not found.*$/, "未找到 Oracle VirtualBox（VBoxSVC.exe 缺失）。", "error"],
  [/^MuMu Player is running.*$/, "eNSP 模拟器正在运行，请先退出后再切换。", "error"],
  [/^MuMu COM server file is missing: (.+)\..*$/, "eNSP COM 服务文件缺失：$1", "error"],
  [/^HCL did not generate gen_py cache\.$/, "HCL 未生成 gen_py 缓存。", "error"],
  [/^HCL SimwareClient\.exe not found\..*$/, "未找到 HCL SimwareClient.exe，请通过 -HclDir 指定。", "error"],
  [/^Set-VBoxComMode -Mode Oracle failed \(exit (\d+)\)\..*$/, "切换 Oracle 模式失败（退出码 $1），请查看 logs\\set-vbox-mode-oracle-*.log", "error"],
  [/^Set-VBoxComMode -Mode MuMu failed \(exit (\d+)\)\..*$/, "恢复 eNSP 模式失败（退出码 $1），请查看 logs\\set-vbox-mode-mumu-*.log", "warning"],
  [/^Restored CLSID registry snapshot: (.+)$/, "已恢复 CLSID 注册表快照：$1", "success"],
  [/^Restored VirtualBox registry value: (.+)$/, "已恢复 VirtualBox 注册表值：$1", "success"],
  [/^MuMuRemoteService is not installed; skipped\.$/, "MuMuRemoteService 未安装，已跳过。", "warning"],
  [/^(\w[\w-]*): missing snapshot; VM state is (.+)$/, "$1：缺少快照，VM 状态为 $2", "warning"],
  [/^(\w[\w-]*): no valid \.vbox template$/, "$1：无有效的 .vbox 模板", "warning"],
  [/^at (.+), (.+): line (\d+)$/, "于 $1，$2：第 $3 行", "error"],
  [/^Local DLL hash mismatch: (.+)$/, "本地 DLL 哈希不匹配：$1", "error"],
  [/^This script must run in 64-bit PowerShell.*$/, "此脚本必须在 64 位 PowerShell 中运行；未找到 Sysnative PowerShell。", "error"],
  [/^Restore hash mismatch: (.+)$/, "恢复文件哈希不匹配：$1", "error"],
  [/^Target hash verification failed: (.+)$/, "目标哈希校验失败：$1", "error"],
  [/^Uninstall incomplete: (\d+) modified target\(s\) preserved\..*$/, "卸载不完整：$1 个已修改目标已保留。", "error"],
  [/^Unsupported registry path: (.+)$/, "不支持的注册表路径：$1", "error"],
  [/^reg export failed: (.+)$/, "reg 导出失败：$1", "error"],
  [/^reg import failed: (.+)$/, "reg 导入失败：$1", "error"],
  [/^reg delete failed: (.+)$/, "reg 删除失败：$1", "error"],
  [/^MuMu COM server is not registered: (.+)$/, "eNSP VirtualBox COM 服务未注册：$1", "error"],
  [/^MuMu CLSID (.+) missing 64-bit InprocServer32.*$/, "eNSP CLSID $1 缺少 64 位 InprocServer32。", "error"],
  [/^MuMu CLSID (.+) points to missing DLL: (.+)$/, "eNSP CLSID $1 指向缺失的 DLL：$2", "error"],
  [/^Oracle VirtualBox incomplete: (.+)$/, "Oracle VirtualBox 不完整：$1", "error"],
  [/^Oracle CLSID (.+) missing 64-bit InprocServer32.*$/, "Oracle CLSID $1 缺少 64 位 InprocServer32。", "error"],
  [/^Oracle CLSID (.+) points to missing DLL: (.+)$/, "Oracle CLSID $1 指向缺失的 DLL：$2", "error"],
  [/^Read-back verification failed: (.+)$/, "回读验证失败：$1", "error"],
  [/^eNSP 32-bit WOW6432Node CLSID view changed during switch.*$/, "eNSP 32 位 WOW6432Node CLSID 视图在切换过程中发生变化。请立即恢复备份。", "error"],
  [/^eNSP 32-bit InprocServer32 no longer points to VBox52\.dll: (.+)$/, "eNSP 32 位 InprocServer32 不再指向 VBox52.dll：$1", "error"],
  [/^eNSP 32-bit view changed during legacy restore\.$/, "eNSP 32 位视图在旧版恢复过程中发生变化。", "error"],
  [/^eNSP 32-bit WOW6432Node view does not match snapshot.*$/, "eNSP 32 位 WOW6432Node 视图与快照不匹配，恢复失败。", "error"],
  [/^Restored mode '(.+)' does not match snapshot mode '(.+)'\.$/, "恢复后模式 '$1' 与快照模式 '$2' 不匹配。", "error"],
  [/^Backup incomplete: (.+) missing\..*$/, "备份不完整：缺少 $1。", "error"],
  [/^Restore did not rebuild (.+)\.$/, "恢复未重建 $1。", "error"],
  [/^Restore verification failed: (.+)$/, "恢复验证失败：$1", "error"],
  [/^Key should not exist after restore: (.+)$/, "恢复后该键应不存在：$1", "error"],
  [/^Backup directory not found: (.+)$/, "未找到备份目录：$1", "error"],
  [/^(.+) has no manifest\.json and no \.reg files; cannot restore\.$/, "$1 中没有 manifest.json 和 .reg 文件，无法恢复。", "error"],
  [/^Mode switch script missing: (.+)$/, "缺少模式切换脚本：$1", "error"],
  [/^Shim file missing: (.+)$/, "缺少兼容层文件：$1", "error"],
  [/^HCL executable not found: (.+)$/, "未找到 HCL 可执行文件：$1", "error"],
  [/^MuMu server file not found: (.+)$/, "未找到 eNSP 服务文件：$1", "error"],
  [/^Cannot read product version of (.+)\.$/, "无法读取 $1 的产品版本。", "error"],
  [/^(VirtualBox\.[.\w]+) activation failed: (.+)$/, "$1 激活失败：$2", "error"],
  [/^VirtualBox\.VirtualBox returned empty version string\.$/, "VirtualBox.VirtualBox 返回空版本字符串。", "error"],
  [/^VirtualBox\.VirtualBox returned '(.+)', expected '(.+)'\..*$/, "VirtualBox.VirtualBox 返回 '$1'，期望 '$2'。", "error"],
  [/^VirtualBoxClient\.VirtualBox returned '(.+)', expected '(.+)'\.$/, "VirtualBoxClient.VirtualBox 返回 '$1'，期望 '$2'。", "error"],
  [/^64-bit COM probe process failed.*$/, "64 位 COM 探测进程失败。", "error"],
  [/^Cannot parse 64-bit COM probe output.*$/, "无法解析 64 位 COM 探测输出。", "error"],
  [/^ProgID not registered$/, "ProgID 未注册", "error"]
];

const LOG_KEY_TRANSLATIONS = {
  "Project": "项目根目录", "Local DLL": "本地 DLL", "Local DLL SHA256": "本地 DLL SHA256",
  "Local DLL hash match": "哈希是否匹配", "Local DLL PE machine": "PE 架构", "Local DLL size": "文件大小（字节）",
  "eNSP directory": "eNSP 目录", "VirtualBox directory": "VirtualBox 目录",
  "eNSP_Client PE machine": "eNSP_Client 架构", "eNSP_VBoxServer PE machine": "eNSP_VBoxServer 架构",
  "VirtualBox version": "VirtualBox 版本", "Hypervisor present": "Hypervisor 是否存在",
  "Firmware virtualization": "固件虚拟化",
  "eNSP 32-bit CLSID target": "eNSP 32 位 CLSID 目标",
  "VirtualBox registry 32-bit Version": "注册表 32 位版本",
  "VirtualBox registry 32-bit InstallDir": "注册表 32 位安装目录",
  "VirtualBox registry 64-bit Version": "注册表 64 位版本",
  "VirtualBox registry 64-bit InstallDir": "注册表 64 位安装目录"
};

function translateKey(key) {
  if (LOG_KEY_TRANSLATIONS[key]) return LOG_KEY_TRANSLATIONS[key];
  return key.replace("VirtualBox registry 32-bit", "注册表 32 位").replace("VirtualBox registry 64-bit", "注册表 64 位");
}

function translateValue(v) {
  if (v === "0x014C") return "x86（0x014C）";
  if (v === "0x8664") return "x64（0x8664）";
  if (v === "True") return "是";
  if (v === "False") return "否";
  if (v === "<not found>") return "未找到";
  if (v === "<not PE>") return "非 PE 文件";
  if (v === "<key not found>") return "键不存在";
  if (v === "<VBoxManage failed>") return "VBoxManage 执行失败";
  return v;
}

function translateLine(line) {
  for (const [re, repl, type] of LOG_TRANSLATIONS) {
    if (re.test(line)) {
      let text = line.replace(re, repl)
        .replace(/\bTrue\b/g, '是').replace(/\bFalse\b/g, '否')
        .replace(/\s->\s/g, ' → ');
      return { text, type: type || null };
    }
  }
  return { text: line, type: null };
}

function classifyLine(text) {
  if (/^=== .* ===$/.test(text)) return "header";
  if (/^\s*".*"\s+\{[0-9a-fA-F-]+\}/.test(text)) return "vm";
  if (/CategoryInfo|FullyQualifiedErrorId|char:\s*\d|\.ps1:\d+|^\s*\+/.test(text)) return "error";
  if (/\b(ERROR|Exception|throw|failed|失败)\b/i.test(text)) return "error";
  if (/^Read-back:|Registered VMs|RESULT|COM activation/.test(text)) return "section";
  if (/(read-only|never deletes|不会删除|此命令为只读)/i.test(text)) return "info";
  if (/\b(complete|completed|verified|registered|Restored|成功|已恢复|已完成)\b/i.test(text)) return "success";
  if (/^\s*\[/.test(text)) return "step";
  return "default";
}

function renderLine(raw) {
  if (raw.trim() === "") { const g = document.createElement("div"); g.className = "log-gap"; log.appendChild(g); return; }
  let body = raw;
  let forced = null;
  const m = body.match(/^WARNING:\s*(.*)$/);
  if (m) { body = m[1]; forced = "warning"; }
  const { text, type } = translateLine(body);
  const row = document.createElement("div");
  row.className = "log-row log-" + (forced || type || classifyLine(text));
  row.innerHTML = '<i class="log-ico"></i><span class="log-txt">' + escapeHtml(text) + '</span>';
  log.appendChild(row);
}

function isTableSeparator(s) {
  const t = s.trim();
  return t.length >= 3 && /^[-\s]+$/.test(t) && t.includes("---");
}

function renderTableBlock(lines, i) {
  let j = i + 2;
  const grid = document.createElement("div");
  grid.className = "log-table";
  while (j < lines.length && lines[j].trim() !== "" && !isTableSeparator(lines[j])) {
    const parts = lines[j].trimEnd().split(/\s{2,}/);
    const key = parts[0] || "";
    const value = parts.slice(1).join("  ");
    const kv = document.createElement("div");
    kv.className = "log-kv";
    kv.innerHTML = '<span class="log-k">' + escapeHtml(translateKey(key)) + '</span><span class="log-v">' + escapeHtml(translateValue(value)) + '</span>';
    grid.appendChild(kv);
    j++;
  }
  log.appendChild(grid);
  return j;
}

function renderOutput(text) {
  if (!text) return;
  const lines = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  for (const raw of lines) {
    const m = raw.match(/^([A-Za-z][^:]{2,60}):\s(.*)$/);
    if (m && LOG_KEY_TRANSLATIONS[m[1].trim()]) {
      const kv = document.createElement("div");
      kv.className = "log-kv";
      kv.innerHTML = '<span class="log-k">' + escapeHtml(LOG_KEY_TRANSLATIONS[m[1].trim()]) + '</span><span class="log-v">' + escapeHtml(translateValue(m[2].trim())) + '</span>';
      log.appendChild(kv);
      continue;
    }
    renderLine(raw);
  }
  log.scrollTop = log.scrollHeight;
}

function setActionsDisabled(disabled) {
  document.querySelectorAll("[data-action]").forEach(button => { button.disabled = disabled; });
}

function startTimer() {
  clearInterval(taskTimer);
  taskStartedAt = Date.now();
  taskTimer = setInterval(() => {
    const seconds = Math.floor((Date.now() - taskStartedAt) / 1000);
    const minutes = Math.floor(seconds / 60);
    setText("task-time", `${String(minutes).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`);
  }, 500);
}

function runTask(name) {
  const action = actions[name];
  if (!action || hostBusy) return;
  if (!host) {
    post({});
    return;
  }
  activeAction = name;
  hostBusy = true;
  setActionsDisabled(true);
  taskCounter += 1;
  dock.classList.remove("collapsed", "running", "success", "error");
  dock.classList.add("running");
  setText("task-title", action.title);
  setText("task-subtitle", "正在执行真实 PowerShell 操作，请等待 UAC（如有）");
  setText("task-time", "00:00");
  log.innerHTML = "";
  appendLog(`VESPERASH TASK ${String(taskCounter).padStart(4, "0")} · DESKTOP HOST`, "log-accent");
  appendLog(`正在启动 ${action.title}...`);
  startTimer();
  post({ type: "action", action: name });
}

function completeTask(message, failed = false) {
  clearInterval(taskTimer);
  const action = actions[activeAction] || { title: "桌面操作" };
  const exitCode = failed ? 1 : message.exitCode;
  const hasWarning = !failed && exitCode === 2;
  const isError = failed || (exitCode !== 0 && exitCode !== 2);
  dock.classList.remove("running", "success", "error");
  dock.classList.add(isError ? "error" : hasWarning ? "warning" : "success");
  setText("task-subtitle", isError ? "操作失败 · 请查看详细输出和 logs 目录" : hasWarning ? "操作完成（有警告）· 详见输出" : "操作完成 · 可以继续选择其他操作");
  if (failed) appendLog(message.message || "桌面桥发生未知错误", "log-success");
  else {
    appendLog(`退出码：${exitCode}`, isError ? "" : "log-success");
    if (message.output) renderOutput(message.output);
  }
  hostBusy = false;
  activeAction = null;
  setActionsDisabled(false);
  showToast(isError ? `${action.title}：执行失败` : hasWarning ? `${action.title}：完成（有警告）` : `${action.title}：执行完成`);
  if (host) {
    const pill = document.getElementById("ensp-page-status");
    if (pill) {
      pill.textContent = "●  正在刷新状态…";
      pill.classList.add("status-neutral");
      pill.classList.remove("status-success", "status-warning");
    }
    post({ type: "refresh" });
  }
}

function applySettings(settings, force = false) {
  if (!settings || (settingsDirty && !force)) return;
  setText("hcl-current-path", settings.hclDir || "未配置");
  const values = { "hcl-path": settings.hclDir, "ensp-path": settings.enspDir, "vbox-path": settings.vboxDir };
  Object.entries(values).forEach(([id, value]) => {
    const input = document.getElementById(id);
    if (input) input.value = value || "";
  });
  settingsDirty = false;
}

function updateDashboard(data) {
  const version = data.comVersion || "未知";
  const oracle = version.startsWith("7.2");
  const mumu = version === "6.1.36_OSE";
  setText("metric-com-value", oracle ? "Oracle" : mumu ? "eNSP" : "异常");
  setText("metric-com-detail", oracle ? "VirtualBox 7.2 服务" : mumu ? "eNSP VMM 6.1 服务" : version);
  setText("metric-ensp-value", data.enspInstalled ? "已部署" : "未部署");
  setText("metric-ensp-detail", data.enspPath || "32 位 COM 未配置");
  setText("metric-mumu-value", data.mumuStatus === "Running" ? "运行中" : data.mumuStatus === "未找到" ? "未安装" : "已停止");
  setText("metric-mumu-detail", `MuMuRemoteService · ${data.mumuStatus || "未知"}`);
  setText("metric-hcl-value", data.hclExists ? "已就绪" : "未找到");
  setText("metric-hcl-detail", data.settings ? data.settings.hclDir : "未配置");
  setText("engine-title", oracle ? `Oracle VirtualBox ${version}` : mumu ? "eNSP VirtualBox 6.1.36_OSE" : "VirtualBox COM 未就绪");
  setText("engine-description", `eNSP 32 位兼容层独立运行 · 注册表版本 ${data.vboxVersion || "未知"}`);
  setText("engine-status", oracle || mumu ? "●  运行就绪" : "●  需要检查");
  const enspPill = document.getElementById("ensp-page-status");
  if (enspPill) {
    enspPill.textContent = data.enspInstalled ? "●  兼容层已部署" : "●  兼容层未部署";
    enspPill.classList.remove("status-neutral");
    enspPill.classList.toggle("status-success", !!data.enspInstalled);
    enspPill.classList.toggle("status-warning", !data.enspInstalled);
    enspPill.classList.remove("flash");
    void enspPill.offsetWidth;
    enspPill.classList.add("flash");
  }
  setText("ensp-refresh-time", "最后刷新 " + new Date().toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" }));
  const compatStatus = document.getElementById("compatibility-ensp-status");
  if (compatStatus) {
    compatStatus.textContent = data.enspInstalled ? "● 正常" : "● 未部署";
    compatStatus.classList.toggle("success", !!data.enspInstalled);
    compatStatus.classList.toggle("warning", !data.enspInstalled);
  }
  setText("compatibility-vbox-version", oracle ? version : data.vboxVersion || "未知");
  setText("compatibility-vbox-status", oracle || mumu ? "● 已连接" : "● 需检查");
  setText("oracle-mode-status", oracle ? "● 当前模式" : "● 可用模式");
  setText("mumu-mode-status", mumu ? "● 当前模式" : data.mumuStatus === "Running" ? "● 服务运行中" : "● 已暂停");
  setText("oracle-com-version", oracle ? version : "7.2.x");
  setText("mumu-service-status", data.mumuStatus || "未知");
  setText("hcl-path-status", data.hclExists ? "● 目录可用" : "● 目录不存在");
  setText("hcl-path-validation", data.hclExists ? "✓ 目录已验证" : "目录当前不存在");
  setText("ensp-path-validation", data.enspExists ? "✓ 目录已验证" : "目录当前不存在");
  setText("vbox-path-validation", data.vboxExists ? `✓ ${data.vboxVersion || "目录已验证"}` : "目录当前不存在");
  const oracleCard = document.getElementById("oracle-mode-card");
  const mumuCard = document.getElementById("mumu-mode-card");
  if (oracleCard) oracleCard.classList.toggle("selected", oracle);
  if (mumuCard) mumuCard.classList.toggle("selected", mumu);
  setText("last-check", new Date().toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" }));
  applySettings(data.settings);
}

if (host) {
  host.addEventListener("message", event => {
    const message = typeof event.data === "string" ? JSON.parse(event.data) : (event.data || {});
    if (message.type === "status") updateDashboard(message);
    else if (message.type === "log-line") renderLine(message.text);
    else if (message.type === "operation-complete") completeTask(message);
    else if (message.type === "settings-saved") {
      settingsDirty = false;
      showToast(message.message);
    } else if (message.type === "browse-result") {
      const input = document.getElementById(message.target);
      if (input) {
        input.value = message.path;
        input.dispatchEvent(new Event("input"));
      }
    } else if (message.type === "detect-result") {
      applySettings(message.settings, true);
      const button = document.getElementById("detect-paths");
      button.disabled = false;
      button.classList.remove("spinning");
      showToast("自动检测完成，请检查路径后保存");
    } else if (message.type === "host-error") completeTask(message, true);
  });
}

document.querySelectorAll(".nav-item").forEach(button => button.addEventListener("click", () => navigate(button.dataset.page)));
document.querySelectorAll("[data-go]").forEach(button => button.addEventListener("click", () => navigate(button.dataset.go)));
document.querySelectorAll("[data-action]").forEach(button => button.addEventListener("click", () => openAction(button.dataset.action)));
document.querySelector(".modal-close").addEventListener("click", closeModal);
document.getElementById("modal-cancel").addEventListener("click", closeModal);
modal.addEventListener("click", event => { if (event.target === modal) closeModal(); });
modalConfirm.addEventListener("click", () => {
  if (!pendingAction) return;
  const action = pendingAction;
  closeModal();
  runTask(action);
});
document.addEventListener("keydown", event => { if (event.key === "Escape" && !modal.hidden) closeModal(); });

document.getElementById("refresh-dashboard").addEventListener("click", event => {
  const button = event.currentTarget;
  button.disabled = true;
  button.classList.add("spinning");
  button.querySelector("span").textContent = "正在刷新";
  if (post({ type: "refresh" })) {
    setTimeout(() => {
      button.disabled = false;
      button.classList.remove("spinning");
      button.querySelector("span").textContent = "刷新状态";
      showToast("状态已从本机刷新");
    }, 600);
  } else {
    button.disabled = false;
    button.classList.remove("spinning");
    button.querySelector("span").textContent = "刷新状态";
  }
});

document.getElementById("task-toggle").addEventListener("click", () => dock.classList.toggle("collapsed"));
document.getElementById("collapse-log").addEventListener("click", () => dock.classList.toggle("collapsed"));
document.getElementById("copy-log").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(log.textContent);
    showToast("任务日志已复制");
  } catch {
    showToast("当前环境未授权剪贴板，可手动选择日志复制");
  }
});

document.getElementById("detect-paths").addEventListener("click", event => {
  const button = event.currentTarget;
  button.disabled = true;
  button.classList.add("spinning");
  if (!post({ type: "detect" })) {
    button.disabled = false;
    button.classList.remove("spinning");
  }
});

document.querySelectorAll(".browse-button").forEach(button => button.addEventListener("click", () => {
  const input = document.getElementById(button.dataset.target);
  post({ type: "browse", target: button.dataset.target, current: input.value.trim() });
}));

document.querySelectorAll("#settings-form input").forEach(input => input.addEventListener("input", () => { settingsDirty = true; }));
document.getElementById("settings-form").addEventListener("submit", event => {
  event.preventDefault();
  const hclDir = document.getElementById("hcl-path").value.trim();
  const enspDir = document.getElementById("ensp-path").value.trim();
  const vboxDir = document.getElementById("vbox-path").value.trim();
  const invalid = [hclDir, enspDir, vboxDir].find(value => !/^[A-Za-z]:\\/.test(value));
  if (invalid !== undefined) {
    showToast("请输入以盘符开头的有效 Windows 绝对路径");
    return;
  }
  post({ type: "save-settings", values: { hclDir, enspDir, vboxDir } });
});

navigate("dashboard");
if (host) post({ type: "ready" });
else showToast("这是 EXE 前端副本，请通过 eNSP Bridge 桌面程序打开");
