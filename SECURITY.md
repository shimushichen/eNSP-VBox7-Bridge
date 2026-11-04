# Security policy

## 报告问题

如果你发现安全问题，请不要公开提交 issue。请通过 GitHub 的私密安全报告功能联系维护者，或直接发送邮件给仓库所有者。

## 安全边界

本项目会修改：

- eNSP 安装目录下的 `VBox52.dll`
- `HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}`
- 模式切换时的 `HKLM\SOFTWARE\Classes\VirtualBox.*` ProgID

所有写操作都会先创建备份。不要在没有备份和恢复计划的生产环境中直接运行。
