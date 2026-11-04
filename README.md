# eNSP-VBox7-Bridge

让经典 eNSP 继续使用 VirtualBox 7.2，并在 eNSP、HCL 5.10.3 与 MuMu Player 之间安全切换 VirtualBox COM 归属的 Windows 桌面工具。

> 本项目是个人研究项目，与华为、H3C、Oracle、MuMu 官方无隶属关系。涉及注册表和系统文件修改，请先阅读[安全边界](#安全边界)并自行备份。

## 功能

- **eNSP 32 位兼容层**：部署经校验的 `VBox52.dll`，让 32 位 eNSP 在 VirtualBox 7.2 上继续运行。
- **HCL 5.10.3 适配**：通过 `hcl-vbox72-shim.py` 修补 HCL 的 `gen_py` 缓存，适配 VirtualBox 6.0 → 7.2 的 API 差异。
- **模式切换**：在同一组 `VirtualBox.VirtualBox` / `VirtualBoxClient` / `Session` ProgID 之间切换 Oracle 与 eNSP/MuMu 归属。
- **图形化安装器**：单文件 EXE，内置 WebView2 UI 和全部 PowerShell / Python / DLL 资源。
- **可回滚**：安装、卸载和模式切换都会生成备份与日志；eNSP 32 位注册表视图始终只读保护。

## 界面

安装器包含四个页面：

| 页面 | 功能 |
| --- | --- |
| 状态总览 | 查看 COM 归属、eNSP 兼容层、MuMu 服务、HCL 目录和 VirtualBox 版本 |
| eNSP 兼容层 | 部署、只读检查、卸载兼容层 |
| HCL / eNSP 模式 | 手动切换 Oracle / eNSP 模式，或启动 HCL 工作流 |
| 环境设置 | 配置 HCL、eNSP、VirtualBox 目录 |

## 系统要求

运行安装器：

- Windows 10 / 11 x64
- WebView2 Runtime（Windows 10/11 通常已预装）
- VirtualBox 7.2.x（Oracle 官方版）
- eNSP 5.2.x（32 位经典版）
- 可选：HCL 5.10.3 便携版（含 `SimwareClient.exe`）
- 可选：MuMu Player（使用 eNSP/MuMu 模式时）

从源码构建：

- .NET 8 SDK
- Node.js（仅 UI 语法测试需要）
- Visual Studio Build Tools 2022 + MSVC x86 + MASM（仅重新构建 `VBox52.dll` 时需要）

## 快速开始

1. 从 Releases 下载 `eNSP-VBox7-Bridge-Installer.exe`。
2. 右键以管理员身份运行（安装和模式切换需要 UAC）。
3. 打开「环境设置」，确认 HCL / eNSP / VirtualBox 目录。
4. 在「eNSP 兼容层」页点击「开始部署」。
5. 在「HCL / eNSP 模式」页选择需要的模式。

> HCL 与 MuMu/eNSP 不能同时运行。启动 HCL 会切换到 Oracle 模式；HCL 正常退出后会自动恢复 eNSP 模式。

## 手动切换模式

不需要启动 HCL 也可以切换 COM 归属：

- **切换到 Oracle**：只把 64 位 VirtualBox ProgID 指向 Oracle 7.2。
- **切换到 eNSP**：把 ProgID 指回 eNSP/MuMu VMM。

对应命令行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-VBoxComMode.ps1 -Mode Oracle
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-VBoxComMode.ps1 -Mode MuMu
```

脚本会先创建 `logs\vbox-com-mode-backup-*` 快照，再执行切换并回读校验。

## 从源码构建

```powershell
# 还原并发布单文件 EXE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Installer.ps1
```

输出：

```text
dist\eNSP-VBox7-Bridge-Installer.exe
dist\SHA256SUMS.txt
```

如果机器只有 .NET Runtime 而没有 SDK，`Build-Installer.ps1` 会自动使用仓库上级目录的 `.dotnet\dotnet.exe`（如果存在）。也可以在 GitHub Actions 的 `build` workflow 中构建。

### 重新构建 VBox52.dll

需要 Visual Studio Build Tools 2022（MSVC x86 + MASM）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Local.ps1
```

脚本从 `third_party\ensp-vbox-shim\src` 构建，并同步到 `vendor\VBox52.dll`。

## 仓库结构

```text
.
├─ src/                       # .NET 8 WinForms + WebView2 安装器
│  ├─ Program.cs
│  ├─ Installer.csproj
│  ├─ app.manifest
│  └─ ui/                     # HTML / CSS / JS 界面
├─ scripts/                   # PowerShell 安装、检查、模式切换脚本
├─ tests/                     # UI / 翻译回归测试
├─ third_party/
│  └─ ensp-vbox-shim/         # VBox52.dll 上游源码（MPL 2.0）
├─ vendor/
│  └─ VBox52.dll              # 预构建兼容层，SHA-256 固定
├─ dist/                      # 构建产物（不提交）
└─ *.bat                      # 命令行快捷入口
```

## 测试

```powershell
# 需要 Node.js
node .\tests\verify_translations.js

# 需要 Python 3
python -m unittest discover -s tests
```

## 安全边界

- 安装/卸载会修改 eNSP 目录下的 `VBox52.dll` 以及 `HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7...}`。
- 模式切换会修改 `HKLM\SOFTWARE\Classes` 下六个 VirtualBox ProgID，但不会写 eNSP 32 位 `WOW6432Node` 视图。
- 每次写操作前都会备份；日志位于 `%LOCALAPPDATA%\eNSP-VBox7-Bridge\logs`。
- 卸载不会删除 eNSP、VirtualBox、虚拟磁盘或已注册的 VM。
- 不要运行 HCL 官方安装器：它自带 VirtualBox 6.0.14，可能覆盖主机 7.2 驱动和 eNSP shim。

## 已知限制

- 仅验证了 S6850 等部分 HCL 设备；WLAN、NGFW、PC、路由器等设备可能触发更多 API 差异。
- HCL 与 MuMu/eNSP 共用同一组 VirtualBox COM ProgID，不能同时运行。
- 需要管理员权限；UAC 被取消时操作不会执行。
- 仅支持 Windows x64。

## 许可证

本项目以 **Mozilla Public License 2.0** 发布，见 [LICENSE](LICENSE)。

`third_party/ensp-vbox-shim` 和 `vendor/VBox52.dll` 来自 [LBXaaa/ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim)，同样使用 MPL 2.0。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 致谢

- [LBXaaa/ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim)：VBox52 兼容层源码与思路
- Microsoft WebView2：桌面 UI 宿主
- 所有参与测试和反馈的人
