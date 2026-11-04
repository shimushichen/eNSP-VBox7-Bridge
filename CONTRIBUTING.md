# Contributing

1. Fork 仓库并创建分支。
2. 修改后至少运行：
   ```powershell
   node --check .\src\ui\app.js
   node .\tests\verify_translations.js
   python -m unittest discover -s tests
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Installer.ps1
   ```
3. 提交 PR，说明修改范围、测试环境和是否涉及注册表/系统文件操作。

请勿在 issue 或 PR 中粘贴完整注册表导出、个人路径、Token 或未脱敏日志。
