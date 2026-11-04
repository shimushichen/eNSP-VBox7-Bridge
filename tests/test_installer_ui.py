import hashlib
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "src" / "ui"
PREVIEW = Path("/workspace/vesperash-ui-preview")
EXE = ROOT / "dist" / "eNSP-VBox7-Bridge-Installer.exe"

class InstallerUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = (UI / "index.html").read_text(encoding="utf-8")
        cls.js = (UI / "app.js").read_text(encoding="utf-8")
        cls.source = (ROOT / "src" / "Program.cs").read_text(encoding="utf-8-sig")
        cls.project = (ROOT / "src" / "Installer.csproj").read_text(encoding="utf-8")

    def test_javascript_syntax(self):
        if not shutil.which("node"):
            self.skipTest("node 不可用")
        result = subprocess.run(["node", "--check", str(UI / "app.js")], capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_log_translations_cover_script_output(self):
        verify = ROOT / "tests" / "verify_translations.js"
        if not shutil.which("node"):
            self.skipTest("node 不可用")
        result = subprocess.run(["node", str(verify)], capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_all_javascript_id_references_exist(self):
        ids = set(re.findall(r'\bid="([^"]+)"', self.html))
        references = set(re.findall(r'getElementById\("([^"]+)"\)', self.js))
        references.update(re.findall(r'setText\("([^"]+)"', self.js))
        self.assertEqual(sorted(references - ids), [])

    def test_all_actions_are_registered(self):
        html_actions = set(re.findall(r'data-action="([^"]+)"', self.html))
        js_actions = set(re.findall(r"^  (\w+): \{$", self.js, re.MULTILINE))
        self.assertEqual(html_actions, {"install", "check", "uninstall", "hcl", "mumu", "oracle", "hclstatus"})
        self.assertTrue(html_actions.issubset(js_actions))

    def test_all_navigation_targets_exist(self):
        pages = set(re.findall(r'id="page-([^"]+)"', self.html))
        targets = set(re.findall(r'data-(?:page|go)="([^"]+)"', self.html))
        self.assertEqual(targets, {"dashboard", "ensp", "hcl", "settings"})
        self.assertEqual(targets, pages)

    def test_desktop_ui_uses_real_host(self):
        self.assertIn("window.chrome && window.chrome.webview", self.js)
        for message in ("action", "save-settings", "detect", "browse", "refresh"):
            self.assertIn(f'type: "{message}"', self.js)
        self.assertNotIn("模拟任务", self.html + self.js)
        self.assertNotIn("原型模拟", self.html + self.js)

    def test_ui_resources_are_local(self):
        # Resource tags (link/script/img) must be local; anchor (<a>) tags may
        # point to external references (opened in the system browser by Program.cs).
        resource_urls = re.findall(r'<(?:link|script|img)[^>]*\s(?:src|href)=["\']https?://', self.html)
        self.assertEqual(resource_urls, [])
        for resource in ("styles.css", "app.js"):
            self.assertTrue((UI / resource).is_file())
            self.assertIn(f'LogicalName="payload.{resource}"', self.project)
        self.assertIn('LogicalName="payload.index.html"', self.project)

    def test_webview2_and_single_file_configuration(self):
        self.assertIn('<TargetFramework>net8.0-windows</TargetFramework>', self.project)
        self.assertIn('<PackageReference Include="Microsoft.Web.WebView2" Version="1.0.4314.35" />', self.project)
        self.assertIn("<PublishSingleFile>true</PublishSingleFile>", self.project)
        self.assertIn("<SelfContained>true</SelfContained>", self.project)
        self.assertIn("<UseWindowsForms>true</UseWindowsForms>", self.project)

    def test_cli_and_script_mappings_preserved(self):
        for argument in ("/check", "/uninstall", "/register", "/hcl", "/mumu", "/oracle", "/hclstatus"):
            self.assertIn(f'"{argument}"', self.source)
        for script in ("Check.ps1", "Install.ps1", "RegisterVM.ps1", "HCLStatus.ps1", "Set-VBoxComMode.ps1", "Use-HCL.ps1"):
            self.assertIn(f'RunPowerShell("{script}"', self.source)
        for option in ("-EnspDir", "-VBoxDir", "-HclDir"):
            self.assertIn(f'GetOption(args, "{option}")', self.source)

    def test_embedded_shim_hash_unchanged(self):
        expected = "AEA65CA5A8863A308DA482379D0C02965C5336F7B80A61087549874387B51204"
        actual = hashlib.sha256((ROOT / "vendor" / "VBox52.dll").read_bytes()).hexdigest().upper()
        self.assertEqual(actual, expected)
        self.assertIn(expected, self.source)

    def test_exe_is_windows_x64_and_matches_manifest(self):
        if not EXE.is_file():
            self.skipTest(f"安装器 EXE 未构建（需 dotnet publish）：{EXE}")
        data = EXE.read_bytes()
        self.assertEqual(data[:2], b"MZ")
        offset = int.from_bytes(data[0x3C:0x40], "little")
        self.assertEqual(data[offset:offset + 4], b"PE\0\0")
        self.assertEqual(int.from_bytes(data[offset + 4:offset + 6], "little"), 0x8664)
        manifest = json.loads((EXE.parent / "manifest.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(manifest["Length"], len(data))
        self.assertEqual(manifest["SHA256"], hashlib.sha256(data).hexdigest().upper())
        self.assertIn(".NET 8", manifest["Runtime"])

    def test_original_web_prototype_untouched(self):
        if not PREVIEW.is_dir():
            self.skipTest(f"原始 web 原型目录不存在：{PREVIEW}")
        expected = {
            "index.html": "f77b0c822bfbb6c07b0be38818b3dea44fe12c00233fe0a79e2c92b7ef968207",
            "styles.css": "122c64d62cc2bda7b676bac2d20018cd8b8c3d056cc60cfa97b291300469f278",
            "app.js": "fe2f0c34cbc38674951d072175224d7afe87998581392628f48b1beadd009ca8"
        }
        for name, digest in expected.items():
            self.assertEqual(hashlib.sha256((PREVIEW / name).read_bytes()).hexdigest(), digest)

if __name__ == "__main__":
    unittest.main()
