using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;

namespace eNSPBridgeInstaller
{
    internal static class Program
    {
        private const string Product = "eNSP-VBox7-Bridge";
        private const string ExpectedHash = "AEA65CA5A8863A308DA482379D0C02965C5336F7B80A61087549874387B51204";
        private static readonly string CacheRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Product);
        private static readonly string SettingsPath = Path.Combine(CacheRoot, "settings.conf");

        [STAThread]
        private static int Main(string[] args)
        {
            using (Mutex mutex = new Mutex(false, "Local\\eNSP-VBox7-Bridge-Installer"))
            {
                bool acquired = false;
                try { acquired = mutex.WaitOne(TimeSpan.FromSeconds(30)); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) { MessageBox.Show("另一个安装器实例正在运行，请稍后重试。", Product, MessageBoxButtons.OK, MessageBoxIcon.Warning); return 1; }
                try
                {
                    if (args.Length == 0)
                    {
                        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
                        Application.EnableVisualStyles();
                        Application.SetCompatibleTextRenderingDefault(false);
                        Application.Run(new HostForm());
                        return 0;
                    }
                    Settings settings = Settings.Load();
                    string ensp = GetOption(args, "-EnspDir");
                    string vbox = GetOption(args, "-VBoxDir");
                    string hcl = GetOption(args, "-HclDir");
                    if (!String.IsNullOrEmpty(ensp)) settings.EnspDir = ensp;
                    if (!String.IsNullOrEmpty(vbox)) settings.VBoxDir = vbox;
                    if (!String.IsNullOrEmpty(hcl)) settings.HclDir = hcl;
                    OperationResult commandResult = Execute(ParseMode(args), settings);
                    if (!String.IsNullOrEmpty(commandResult.Output)) Console.Error.WriteLine(commandResult.Output);
                    return commandResult.ExitCode;
                }
                finally { mutex.ReleaseMutex(); }
            }
        }

        private sealed class OperationResult { public int ExitCode; public string Output = ""; }

        private sealed class Settings
        {
            public string HclDir = "E:\\HCL_5.10.3\\app";
            public string EnspDir = "";
            public string VBoxDir = "";

            public static Settings Load()
            {
                Settings settings = new Settings();
                try
                {
                    if (File.Exists(SettingsPath))
                    {
                        foreach (string line in File.ReadAllLines(SettingsPath))
                        {
                            int index = line.IndexOf('=');
                            if (index <= 0) continue;
                            string key = line.Substring(0, index).Trim();
                            string value = line.Substring(index + 1).Trim();
                            if (key == "HclDir") settings.HclDir = value;
                            else if (key == "EnspDir") settings.EnspDir = value;
                            else if (key == "VBoxDir") settings.VBoxDir = value;
                        }
                    }
                }
                catch { }
                if (String.IsNullOrEmpty(settings.EnspDir) && Directory.Exists("D:\\Program Files\\Huawei\\eNSP")) settings.EnspDir = "D:\\Program Files\\Huawei\\eNSP";
                if (String.IsNullOrEmpty(settings.VBoxDir) && Directory.Exists("D:\\Program Files\\Oracle\\VirtualBox")) settings.VBoxDir = "D:\\Program Files\\Oracle\\VirtualBox";
                return settings;
            }

            public void Save()
            {
                Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath));
                using (StreamWriter writer = new StreamWriter(SettingsPath, false, new UTF8Encoding(true)))
                {
                    writer.WriteLine("HclDir=" + HclDir);
                    writer.WriteLine("EnspDir=" + EnspDir);
                    writer.WriteLine("VBoxDir=" + VBoxDir);
                }
            }
        }

        private sealed class HostForm : Form
        {
            private readonly WebView2 browser = new WebView2();
            private Settings settings = Settings.Load();
            private bool busy;

            [DllImport("dwmapi.dll", PreserveSig = true)]
            private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int cbAttribute);

            private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
            private const int DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 = 19;
            private const int DWMWA_BORDER_COLOR = 34;
            private const int DWMWA_CAPTION_COLOR = 35;

            public HostForm()
            {
                Text = "";
                MinimumSize = new Size(960, 640);
                StartPosition = FormStartPosition.CenterScreen;
                BackColor = Color.FromArgb(8, 14, 24);
                ShowIcon = false;
                FitToScreen(1280, 840);
                browser.Dock = DockStyle.Fill;
                Controls.Add(browser);
                Shown += async delegate { await InitializeAsync(); };
                FormClosing += delegate(object sender, FormClosingEventArgs e)
                {
                    if (busy)
                    {
                        e.Cancel = true;
                        MessageBox.Show("操作仍在执行，请等待完成后再退出。", Product, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }
                };
            }

            private void FitToScreen(int preferredWidth, int preferredHeight)
            {
                try
                {
                    Rectangle area = Screen.PrimaryScreen != null ? Screen.PrimaryScreen.WorkingArea : SystemInformation.WorkingArea;
                    Width = Math.Max(Math.Min(preferredWidth, area.Width - 24), MinimumSize.Width);
                    Height = Math.Max(Math.Min(preferredHeight, area.Height - 24), MinimumSize.Height);
                }
                catch
                {
                    Width = preferredWidth;
                    Height = preferredHeight;
                }
            }

            protected override void OnHandleCreated(EventArgs e)
            {
                base.OnHandleCreated(e);
                ApplyDarkTitleBar();
            }

            private void ApplyDarkTitleBar()
            {
                if (Environment.OSVersion.Version.Major < 10) return;
                int dark = 1;
                if (DwmSetWindowAttribute(Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, sizeof(int)) != 0)
                    DwmSetWindowAttribute(Handle, DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1, ref dark, sizeof(int));
                // Windows 11: custom caption color matching interface background (#080e18)
                int captionColor = 0x00180E08; // COLORREF = 0x00BBGGRR
                DwmSetWindowAttribute(Handle, DWMWA_CAPTION_COLOR, ref captionColor, sizeof(int));
                // Windows 11: window border color matching interface border (#1d2b3e)
                int borderColor = 0x003E2B1D;
                DwmSetWindowAttribute(Handle, DWMWA_BORDER_COLOR, ref borderColor, sizeof(int));
            }

            private async Task InitializeAsync()
            {
                try
                {
                    EnsurePayload();
                    CoreWebView2Environment environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(CacheRoot, "webview"));
                    await browser.EnsureCoreWebView2Async(environment);
                    browser.CoreWebView2.SetVirtualHostNameToFolderMapping("app.vesperash", Path.Combine(CacheRoot, "ui"), CoreWebView2HostResourceAccessKind.DenyCors);
                    browser.CoreWebView2.WebMessageReceived += OnWebMessage;
                    browser.CoreWebView2.NavigationStarting += delegate(object sender, CoreWebView2NavigationStartingEventArgs e)
                    {
                        if (Uri.TryCreate(e.Uri, UriKind.Absolute, out Uri uri) && (uri.Scheme == "http" || uri.Scheme == "https") && !uri.Host.Equals("app.vesperash", StringComparison.OrdinalIgnoreCase))
                        {
                            e.Cancel = true;
                            Process.Start(new ProcessStartInfo(e.Uri) { UseShellExecute = true });
                        }
                    };
                    browser.Source = new Uri("https://app.vesperash/index.html");
                }
                catch (Exception ex)
                {
                    MessageBox.Show("界面初始化失败。请确认 Windows 已安装 WebView2 Runtime。\r\n\r\n" + ex.Message, Product, MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }

            private void OnWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
            {
                try
                {
                    using (JsonDocument document = JsonDocument.Parse(e.WebMessageAsJson))
                    {
                        JsonElement root = document.RootElement;
                        string type = root.GetProperty("type").GetString();
                        if (type == "ready" || type == "refresh") SendStatus();
                        else if (type == "action") StartOperation(root.GetProperty("action").GetString());
                        else if (type == "save-settings") SaveSettings(root.GetProperty("values"));
                        else if (type == "detect") DetectPaths();
                        else if (type == "browse") Browse(root.GetProperty("target").GetString(), root.GetProperty("current").GetString());
                    }
                }
                catch (Exception ex) { Post(new { type = "host-error", message = ex.Message }); }
            }

            private void StartOperation(string mode)
            {
                if (busy)
                {
                    Post(new { type = "host-error", message = "另一个操作仍在执行，请等待完成。" });
                    return;
                }
                busy = true;
                Action<string> onLine = line => Post(new { type = "log-line", text = line });
                Task.Run(() => Execute(mode, Settings.Load(), onLine)).ContinueWith(task =>
                {
                    OperationResult result = task.Result;
                    BeginInvoke((Action)delegate
                    {
                        string output = result.Output ?? "";
                        if (output.Length > 30000) output = output.Substring(0, 30000) + "\r\n...（输出已截断）";
                        Post(new { type = "operation-complete", exitCode = result.ExitCode, output });
                        busy = false;
                        SendStatus();
                    });
                });
            }

            private void SaveSettings(JsonElement values)
            {
                Settings updated = new Settings
                {
                    HclDir = values.GetProperty("hclDir").GetString().Trim(),
                    EnspDir = values.GetProperty("enspDir").GetString().Trim(),
                    VBoxDir = values.GetProperty("vboxDir").GetString().Trim()
                };
                updated.Save();
                settings = updated;
                bool missing = !Directory.Exists(settings.HclDir) || !Directory.Exists(settings.EnspDir) || !Directory.Exists(settings.VBoxDir);
                Post(new { type = "settings-saved", message = missing ? "设置已保存；部分目录当前不存在" : "设置已保存，三个目录均已验证" });
                SendStatus();
            }

            private void DetectPaths()
            {
                settings.HclDir = FirstExisting(new[] { settings.HclDir, "E:\\HCL_5.10.3\\app", "C:\\Program Files (x86)\\HCL" }) ?? settings.HclDir;
                settings.EnspDir = FirstExisting(new[] { settings.EnspDir, "D:\\Program Files\\Huawei\\eNSP", "C:\\Program Files\\Huawei\\eNSP", "C:\\Program Files (x86)\\Huawei\\eNSP" }) ?? settings.EnspDir;
                settings.VBoxDir = FirstExisting(new[] { settings.VBoxDir, "D:\\Program Files\\Oracle\\VirtualBox", "C:\\Program Files\\Oracle\\VirtualBox" }) ?? settings.VBoxDir;
                Post(new { type = "detect-result", settings = SettingsPayload() });
            }

            private void Browse(string target, string current)
            {
                using (FolderBrowserDialog dialog = new FolderBrowserDialog { ShowNewFolderButton = false, Description = "选择程序目录" })
                {
                    if (Directory.Exists(current)) dialog.SelectedPath = current;
                    if (dialog.ShowDialog(this) == DialogResult.OK) Post(new { type = "browse-result", target, path = dialog.SelectedPath });
                }
            }

            private object SettingsPayload()
            {
                return new { hclDir = settings.HclDir, enspDir = settings.EnspDir, vboxDir = settings.VBoxDir };
            }

            private void SendStatus()
            {
                settings = Settings.Load();
                string enspPath = RegValue("HKLM\\SOFTWARE\\Classes\\WOW6432Node\\CLSID\\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}\\InprocServer32", null);
                Post(new
                {
                    type = "status",
                    comVersion = GetComVersion(),
                    enspPath,
                    enspInstalled = IsShimDeployed(enspPath, settings.EnspDir),
                    mumuStatus = GetServiceStatus("MuMuRemoteService"),
                    hclExists = Directory.Exists(settings.HclDir),
                    enspExists = Directory.Exists(settings.EnspDir),
                    vboxExists = Directory.Exists(settings.VBoxDir),
                    vboxVersion = RegValue("HKLM\\SOFTWARE\\Oracle\\VirtualBox", "Version"),
                    settings = SettingsPayload()
                });
            }

            private void Post(object message)
            {
                if (browser.IsDisposed || browser.Disposing) return;
                if (browser.InvokeRequired) { browser.BeginInvoke((Action<object>)Post, new object[] { message }); return; }
                if (browser.CoreWebView2 == null) return;
                browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(message));
            }
        }

        private static string FirstExisting(string[] paths)
        {
            foreach (string path in paths) if (!String.IsNullOrWhiteSpace(path) && Directory.Exists(path)) return path;
            return null;
        }

        private static string GetComVersion()
        {
            object instance = null;
            try
            {
                Type type = Type.GetTypeFromProgID("VirtualBox.VirtualBox");
                if (type == null) return "未注册";
                instance = Activator.CreateInstance(type);
                object version = type.InvokeMember("Version", BindingFlags.GetProperty, null, instance, null);
                return version == null ? "N/A" : version.ToString();
            }
            catch (Exception ex) { return "ERR: " + ex.Message; }
            finally { if (instance != null) Marshal.ReleaseComObject(instance); }
        }

        private static string RegValue(string key, string value)
        {
            try
            {
                if (key.StartsWith("HKLM\\", StringComparison.OrdinalIgnoreCase)) key = "HKEY_LOCAL_MACHINE\\" + key.Substring(5);
                object result = Registry.GetValue(key, value, null);
                return result == null ? "" : result.ToString();
            }
            catch { return ""; }
        }

        private static bool IsShimDeployed(string enspPath, string enspDir)
        {
            if (!String.IsNullOrEmpty(enspPath) && HashMatches(enspPath)) return true;
            if (!String.IsNullOrEmpty(enspDir))
            {
                foreach (string sub in new[] { "tools", "vboxserver", "", Path.Combine("plugin", "ngfw", "tools", "ngfw") })
                {
                    if (HashMatches(Path.Combine(enspDir, sub, "VBox52.dll"))) return true;
                }
            }
            return false;
        }

        private static bool HashMatches(string file)
        {
            try
            {
                if (!File.Exists(file)) return false;
                using (SHA256 sha = SHA256.Create())
                {
                    string hash = BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(file))).Replace("-", "");
                    return hash.Equals(ExpectedHash, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch { return false; }
        }

        private static string GetServiceStatus(string name)
        {
            try
            {
                ProcessStartInfo start = new ProcessStartInfo("sc.exe")
                {
                    Arguments = "query \"" + name + "\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (Process process = Process.Start(start))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();
                    if (process.ExitCode != 0) return "未找到";
                    if (output.IndexOf("RUNNING", StringComparison.OrdinalIgnoreCase) >= 0) return "Running";
                    if (output.IndexOf("STOPPED", StringComparison.OrdinalIgnoreCase) >= 0) return "Stopped";
                    return "未知";
                }
            }
            catch { return "未找到"; }
        }

        private static OperationResult Execute(string mode, Settings settings, Action<string> onLine = null)
        {
            try
            {
                EnsurePayload();
                if (mode == "check") return RunPowerShell("Check.ps1", settings.EnspDir, settings.VBoxDir, false, onLine: onLine);
                if (mode == "uninstall") return RunPowerShell("Install.ps1", settings.EnspDir, settings.VBoxDir, true, true, onLine: onLine);
                if (mode == "register") return RunPowerShell("RegisterVM.ps1", settings.EnspDir, settings.VBoxDir, false, onLine: onLine);
                if (mode == "hclstatus") return RunPowerShell("HCLStatus.ps1", null, null, false, onLine: onLine);
                if (mode == "mumu") return RunPowerShell("Set-VBoxComMode.ps1", null, null, true, false, "-Mode MuMu", null, "set-vbox-mode-mumu-*.log", onLine);
                if (mode == "oracle") return RunPowerShell("Set-VBoxComMode.ps1", null, null, true, false, "-Mode Oracle", null, "set-vbox-mode-oracle-*.log", onLine);
                if (mode == "hcl") return RunPowerShell("Use-HCL.ps1", null, null, true, false, null, settings.HclDir, "hcl-session-*.log", onLine);
                OperationResult install = RunPowerShell("Install.ps1", settings.EnspDir, settings.VBoxDir, true, onLine: onLine);
                if (install.ExitCode != 0) return install;
                OperationResult register = RunPowerShell("RegisterVM.ps1", settings.EnspDir, settings.VBoxDir, false, onLine: onLine);
                install.Output += "\r\n" + register.Output;
                install.ExitCode = register.ExitCode;
                return install;
            }
            catch (Exception ex) { return new OperationResult { ExitCode = 1, Output = ex.ToString() }; }
        }

        private static OperationResult RunPowerShell(string name, string ensp, string vbox, bool elevate, bool uninstall = false, string extraArgs = null, string hclDir = null, string transcriptPattern = null, Action<string> onLine = null)
        {
            if (onLine != null)
            {
                Action<string> original = onLine;
                object gate = new object();
                bool inClixml = false;
                onLine = line =>
                {
                    lock (gate)
                    {
                        if (inClixml) { if (line.Contains("</Objs>")) inClixml = false; return; }
                        if (line.StartsWith("#< CLIXML", StringComparison.Ordinal)) { inClixml = true; return; }
                    }
                    original(line);
                };
            }
            string log = Path.Combine(CacheRoot, "logs", uninstall ? "uninstall.log" : "install.log");
            if (elevate && File.Exists(log)) File.Delete(log);
            ProcessStartInfo start = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = elevate,
                Verb = elevate ? "runas" : "",
                WorkingDirectory = CacheRoot,
                CreateNoWindow = !elevate,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = !elevate,
                RedirectStandardError = !elevate
            };
            string command = "$ProgressPreference='SilentlyContinue'; & " + PsLiteral(Path.Combine(CacheRoot, "scripts", name));
            if (uninstall) command += " -Uninstall";
            if (!String.IsNullOrEmpty(ensp)) command += " -EnspDir " + PsLiteral(ensp);
            if (!String.IsNullOrEmpty(vbox)) command += " -VBoxDir " + PsLiteral(vbox);
            if (!String.IsNullOrEmpty(hclDir)) command += " -HclDir " + PsLiteral(hclDir);
            if (!String.IsNullOrEmpty(extraArgs)) command += " " + extraArgs;
            start.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
            DateTime startTime = DateTime.Now;
            try
            {
                using (Process process = Process.Start(start))
                {
                    if (process == null) throw new InvalidOperationException("无法启动 PowerShell");
                    if (!elevate)
                    {
                        if (onLine != null)
                        {
                            var stdoutTask = Task.Run(() => { string l; while ((l = process.StandardOutput.ReadLine()) != null) onLine(l); });
                            var stderrTask = Task.Run(() => { string l; while ((l = process.StandardError.ReadLine()) != null) onLine(l); });
                            process.WaitForExit();
                            stdoutTask.Wait();
                            stderrTask.Wait();
                            return new OperationResult { ExitCode = process.ExitCode, Output = "" };
                        }
                        var stdout = process.StandardOutput.ReadToEndAsync();
                        var stderr = process.StandardError.ReadToEndAsync();
                        process.WaitForExit();
                        return new OperationResult { ExitCode = process.ExitCode, Output = stdout.Result + stderr.Result };
                    }
                    if (onLine != null)
                    {
                        int linesSent = 0;
                        Action<string> countingOnLine = line => { Interlocked.Increment(ref linesSent); onLine(line); };
                        CancellationTokenSource cts = new CancellationTokenSource();
                        // Set-VBoxComMode.ps1 / Use-HCL.ps1 write transcripts to
                        // CacheRoot\logs when released to %LOCALAPPDATA%. Ensure
                        // that directory exists before the elevated child starts.
                        string transcriptDir = Path.Combine(CacheRoot, "logs");
                        try { Directory.CreateDirectory(transcriptDir); } catch { }
                        // Give the elevated child time to create its transcript
                        // before we start tailing (Start-Transcript buffers).
                        Thread.Sleep(2000);
                        Task tailTask;
                        if (!String.IsNullOrEmpty(transcriptPattern))
                            tailTask = Task.Run(() => TailTranscript(transcriptDir, transcriptPattern, countingOnLine, cts.Token, startTime));
                        else
                            tailTask = Task.Run(() => TailFile(log, countingOnLine, cts.Token, true));
                        process.WaitForExit();
                        Thread.Sleep(1000);
                        cts.Cancel();
                        try { tailTask.Wait(3000); } catch { }
                        if (linesSent == 0)
                        {
                            string tpath;
                            string tcontent = String.IsNullOrEmpty(transcriptPattern) ? null : ReadLatestTranscript(transcriptPattern, out tpath, startTime);
                            if (tcontent == null && File.Exists(log)) tcontent = File.ReadAllText(log);
                            if (tcontent != null)
                            {
                                countingOnLine(CleanTranscript(tcontent));
                                return new OperationResult { ExitCode = process.ExitCode, Output = "" };
                            }
                            string fallback = process.ExitCode == 0
                                ? "操作已执行，但未生成可显示的日志（PowerShell 退出码 0）。"
                                : "提权操作失败（退出码 " + process.ExitCode + "）。请检查是否取消了 UAC 提权窗口，或查看 logs 目录中的日志文件。";
                            countingOnLine(fallback);
                        }
                        return new OperationResult { ExitCode = process.ExitCode, Output = "" };
                    }
                    process.WaitForExit();
                    string output;
                    string usedLog = log;
                    if (File.Exists(log)) output = File.ReadAllText(log);
                    else if (!String.IsNullOrEmpty(transcriptPattern))
                    {
                        string tpath;
                        string tcontent = ReadLatestTranscript(transcriptPattern, out tpath, startTime);
                        if (tcontent != null) { output = CleanTranscript(tcontent); usedLog = tpath; }
                        else output = "本次操作未生成日志。PowerShell 退出码：" + process.ExitCode;
                    }
                    else output = "本次操作未生成日志。PowerShell 退出码：" + process.ExitCode;
                    return new OperationResult { ExitCode = process.ExitCode, Output = output + "\r\n日志：" + usedLog };
                }
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                if (ex.NativeErrorCode == 1223) return new OperationResult { ExitCode = 1, Output = "UAC 提权已被取消，操作未执行。" };
                return new OperationResult { ExitCode = 1, Output = "PowerShell 启动失败（Win32 错误 " + ex.NativeErrorCode + "）：" + ex.Message };
            }
            catch (Exception ex) { return new OperationResult { ExitCode = 1, Output = "PowerShell 启动失败：" + ex }; }
        }

        private static string ReadLatestTranscript(string pattern, out string path, DateTime minTime = default(DateTime))
        {
            path = null;
            try
            {
                string dir = Path.Combine(CacheRoot, "logs");
                if (!Directory.Exists(dir)) return null;
                string[] files = Directory.GetFiles(dir, pattern);
                if (files.Length == 0) return null;
                Array.Sort(files, (a, b) => File.GetLastWriteTime(b).CompareTo(File.GetLastWriteTime(a)));
                if (minTime != default(DateTime))
                {
                    for (int i = 0; i < files.Length; i++)
                    {
                        if (File.GetLastWriteTime(files[i]) >= minTime.AddSeconds(-5))
                        {
                            path = files[i];
                            return File.ReadAllText(path);
                        }
                    }
                    return null;
                }
                path = files[0];
                return File.ReadAllText(path);
            }
            catch { return null; }
        }

        private static string CleanTranscript(string text)
        {
            StringBuilder sb = new StringBuilder();
            foreach (string raw in text.Replace("\r\n", "\n").Split('\n'))
            {
                string line = raw.TrimEnd();
                string trimmed = line.TrimStart();
                if (trimmed.StartsWith("******")) continue;
                if (trimmed.StartsWith("Windows PowerShell transcript")) continue;
                if (trimmed.StartsWith("Start time") || trimmed.StartsWith("Start machine") || trimmed.StartsWith("Start user") || trimmed.StartsWith("PSVersion") || trimmed.StartsWith("Transcript started") || trimmed.StartsWith("End time")) continue;
                if (trimmed.StartsWith("PS ") && trimmed.Contains(">")) continue;
                if (trimmed == "") continue;
                sb.AppendLine(line);
            }
            return sb.ToString().TrimEnd();
        }

        private static string StripLogTimestamp(string line)
        {
            if (line.Length > 20 && line[4] == '-' && line[7] == '-' && line[10] == 'T' && line[13] == ':' && line[16] == ':' && line[19] == ' ')
                return line.Substring(20);
            return line;
        }

        private static bool IsTranscriptNoise(string line)
        {
            string t = line.TrimStart();
            if (t.Length == 0) return true;
            if (t.StartsWith("******")) return true;
            if (t.StartsWith("Windows PowerShell transcript")) return true;
            if (t.StartsWith("Start time") || t.StartsWith("Start machine") || t.StartsWith("Start user")) return true;
            if (t.StartsWith("PSVersion") || t.StartsWith("Transcript started") || t.StartsWith("End time")) return true;
            if (t.StartsWith("PS ") && t.Contains(">")) return true;
            return false;
        }

        private static void TailFile(string path, Action<string> onLine, CancellationToken token, bool fromStart = false)
        {
            long lastPos = 0;
            if (!fromStart && File.Exists(path)) lastPos = new FileInfo(path).Length;
            while (!token.IsCancellationRequested)
            {
                try
                {
                    if (File.Exists(path))
                    {
                        using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                        {
                            fs.Position = lastPos;
                            using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                            {
                                string line;
                                while ((line = sr.ReadLine()) != null)
                                {
                                    string cleaned = StripLogTimestamp(line);
                                    if (!string.IsNullOrWhiteSpace(cleaned)) onLine(cleaned);
                                }
                                lastPos = fs.Position;
                            }
                        }
                    }
                }
                catch { }
                if (token.WaitHandle.WaitOne(200)) break;
            }
        }

        private static void TailTranscript(string dir, string pattern, Action<string> onLine, CancellationToken token, DateTime minTime = default(DateTime))
        {
            long lastPos = 0;
            string currentFile = null;
            while (!token.IsCancellationRequested)
            {
                try
                {
                    if (Directory.Exists(dir))
                    {
                        string[] files = Directory.GetFiles(dir, pattern);
                        string newestFile = null;
                        DateTime newestTime = DateTime.MinValue;
                        foreach (string f in files)
                        {
                            DateTime t = File.GetLastWriteTime(f);
                            if (t >= minTime && t > newestTime) { newestTime = t; newestFile = f; }
                        }
                        if (newestFile != null && newestFile != currentFile)
                        {
                            currentFile = newestFile;
                            lastPos = 0;
                        }
                    }
                    if (currentFile != null && File.Exists(currentFile))
                    {
                        using (FileStream fs = new FileStream(currentFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                        {
                            fs.Position = lastPos;
                            using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                            {
                                string line;
                                while ((line = sr.ReadLine()) != null)
                                {
                                    if (IsTranscriptNoise(line)) continue;
                                    if (!string.IsNullOrWhiteSpace(line)) onLine(line);
                                }
                                lastPos = fs.Position;
                            }
                        }
                    }
                }
                catch { }
                if (token.WaitHandle.WaitOne(200)) break;
            }
        }

        private static void EnsurePayload()
        {
            Directory.CreateDirectory(Path.Combine(CacheRoot, "scripts"));
            Directory.CreateDirectory(Path.Combine(CacheRoot, "build", "local-x86"));
            Directory.CreateDirectory(Path.Combine(CacheRoot, "logs"));
            WriteResource("payload.Install.ps1", Path.Combine("scripts", "Install.ps1"));
            WriteResource("payload.Uninstall.ps1", Path.Combine("scripts", "Uninstall.ps1"));
            WriteResource("payload.Check.ps1", Path.Combine("scripts", "Check.ps1"));
            WriteResource("payload.RegisterVM.ps1", Path.Combine("scripts", "RegisterVM.ps1"));
            WriteResource("payload.Use-HCL.ps1", Path.Combine("scripts", "Use-HCL.ps1"));
            WriteResource("payload.Set-VBoxComMode.ps1", Path.Combine("scripts", "Set-VBoxComMode.ps1"));
            WriteResource("payload.HCLStatus.ps1", Path.Combine("scripts", "HCLStatus.ps1"));
            WriteResource("payload.hcl-vbox72-shim.py", Path.Combine("scripts", "hcl-vbox72-shim.py"));
            WriteResource("payload.index.html", Path.Combine("ui", "index.html"));
            WriteResource("payload.styles.css", Path.Combine("ui", "styles.css"));
            WriteResource("payload.app.js", Path.Combine("ui", "app.js"));
            string dll = WriteResource("payload.VBox52.dll", Path.Combine("build", "local-x86", "VBox52.dll"));
            using (SHA256 sha = SHA256.Create())
            {
                string actual = BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(dll))).Replace("-", "");
                if (!actual.Equals(ExpectedHash, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("内置 VBox52.dll 哈希不匹配：" + actual);
            }
        }

        private static string WriteResource(string resource, string relative)
        {
            string target = Path.Combine(CacheRoot, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target));
            using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource))
            {
                if (input == null) throw new InvalidOperationException("缺少内置资源：" + resource);
                using (FileStream output = File.Create(target)) input.CopyTo(output);
            }
            return target;
        }

        private static string ParseMode(string[] args)
        {
            foreach (string argument in args)
            {
                if (argument.Equals("/uninstall", StringComparison.OrdinalIgnoreCase) || argument.Equals("-Uninstall", StringComparison.OrdinalIgnoreCase)) return "uninstall";
                if (argument.Equals("/check", StringComparison.OrdinalIgnoreCase) || argument.Equals("-Check", StringComparison.OrdinalIgnoreCase)) return "check";
                if (argument.Equals("/register", StringComparison.OrdinalIgnoreCase) || argument.Equals("-Register", StringComparison.OrdinalIgnoreCase)) return "register";
                if (argument.Equals("/hcl", StringComparison.OrdinalIgnoreCase) || argument.Equals("-Hcl", StringComparison.OrdinalIgnoreCase)) return "hcl";
                if (argument.Equals("/mumu", StringComparison.OrdinalIgnoreCase) || argument.Equals("-MuMu", StringComparison.OrdinalIgnoreCase)) return "mumu";
                if (argument.Equals("/oracle", StringComparison.OrdinalIgnoreCase) || argument.Equals("-Oracle", StringComparison.OrdinalIgnoreCase)) return "oracle";
                if (argument.Equals("/hclstatus", StringComparison.OrdinalIgnoreCase) || argument.Equals("-HclStatus", StringComparison.OrdinalIgnoreCase)) return "hclstatus";
            }
            return "install";
        }

        private static string GetOption(string[] args, string name)
        {
            for (int i = 0; i + 1 < args.Length; i++)
            {
                if (!args[i].Equals(name, StringComparison.OrdinalIgnoreCase)) continue;
                StringBuilder value = new StringBuilder(args[++i]);
                while (i + 1 < args.Length && !args[i + 1].StartsWith("-", StringComparison.Ordinal)) value.Append(" ").Append(args[++i]);
                return value.ToString().Trim('"', '\'');
            }
            return null;
        }

        private static string PsLiteral(string value) { return "'" + value.Replace("'", "''") + "'"; }
    }
}
