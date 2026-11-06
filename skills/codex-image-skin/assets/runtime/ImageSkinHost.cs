using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

internal static class ImageSkinSkinHost {
    private static readonly object LogLock = new object();
    private static string Root;
    private static void Log(string value) {
        if (value == null) return;
        lock (LogLock) File.AppendAllText(Path.Combine(Root, "original-profile-host.log"), DateTime.Now.ToString("o") + " " + value + Environment.NewLine);
    }
    [STAThread]
    private static int Main(string[] args) {
        Root = AppDomain.CurrentDomain.BaseDirectory;
        bool inspect = args.Length == 1 && args[0] == "--inspect";
        if (args.Length > 0 && !inspect) return 2;
        bool created;
        using (var mutex = new Mutex(true, "Local\\CodexImageSkinProfileNativeHost", out created)) {
            if (!created) return 0;
            try {
                string script = Path.Combine(Root, "ImageSkin-Controller.ps1");
                if (!File.Exists(script)) throw new FileNotFoundException("Controller missing.");
                var start = new ProcessStartInfo {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe"),
                    Arguments = "-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File \"" + script + "\" " + (inspect ? "-InspectOnly" : "-Watch"),
                    WorkingDirectory = Root,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (var child = new Process { StartInfo = start }) {
                    child.OutputDataReceived += (s, e) => Log(e.Data);
                    child.ErrorDataReceived += (s, e) => Log("stderr: " + e.Data);
                    if (!child.Start()) throw new InvalidOperationException("Controller did not start.");
                    Log("host=" + Process.GetCurrentProcess().Id + " child=" + child.Id + " inspect=" + inspect + " noConsole=true");
                    child.BeginOutputReadLine();
                    child.BeginErrorReadLine();
                    // The GUI browser inherits output handles. Waiting for EOF
                    // after the controller exits would strand this host until
                    // Codex itself quits. Observe process exit without draining
                    // descendant-owned output pipes.
                    while (!child.WaitForExit(1000)) { }
                    Log("controllerExit=" + child.ExitCode);
                    if (inspect) File.WriteAllText(Path.Combine(Root, "original-profile-host-preflight.txt"), "exit=" + child.ExitCode + Environment.NewLine);
                    return child.ExitCode;
                }
            } catch (Exception ex) {
                Log(ex.ToString());
                return 1;
            } finally { mutex.ReleaseMutex(); }
        }
    }
}
