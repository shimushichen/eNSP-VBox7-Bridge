# Vendor binaries

## VBox52.dll

- 用途：eNSP 32 位 `VBox52.dll` 兼容层，安装器会将此文件嵌入 EXE 并部署到 eNSP。
- 来源：由 [`third_party/ensp-vbox-shim/src`](../third_party/ensp-vbox-shim/src) 构建。
- 许可证：Mozilla Public License 2.0，见 [`third_party/ensp-vbox-shim/LICENSE`](../third_party/ensp-vbox-shim/LICENSE)。
- SHA-256：

```text
AEA65CA5A8863A308DA482379D0C02965C5336F7B80A61087549874387B51204
```

重新构建：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Local.ps1
```

脚本会把产物写入 `build\local-x86\VBox52.dll`，并同步复制到本目录。若哈希与安装器内记录的 `ExpectedHash` 不一致，安装器会拒绝部署。
