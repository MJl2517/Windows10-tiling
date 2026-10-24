using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;

static class CloseWindow {
    static string Cli {get {return File.ReadAllText(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".glzr", "tools", "glazewm-cli.txt")).Trim();}}
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int count);
    [DllImport("user32.dll", SetLastError = true)] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    static bool IsNativeDialog(string name) { return name == "#32770" || name == "OperationStatusWindow" || name == "MsiDialogCloseClass"; }
    static Dictionary<string, object> Obj(object value) { return value as Dictionary<string, object>; }
    static object Get(Dictionary<string, object> node, string key) { object value; return node != null && node.TryGetValue(key, out value) ? value : null; }
    static bool IsWallpaperUi(string process) { return String.Equals(process, "wallpaperui", StringComparison.OrdinalIgnoreCase); }
    static Dictionary<string, object> Parse(string json) { return Obj(new JavaScriptSerializer().DeserializeObject(json)); }
    static Dictionary<string, object> Run(string arguments) {
        using (var process = Process.Start(new ProcessStartInfo(Cli, arguments) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true })) {
            var output = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(3000)) { process.Kill(); throw new Exception("GlazeWM command timed out"); }
            if (process.ExitCode != 0) throw new Exception(error.Result);
            var response = Parse(output.Result);
            if (!Equals(Get(response, "success"), true)) throw new Exception("GlazeWM: " + Get(response, "error"));
            return response;
        }
    }
    static void CloseWallpaperUi(long handle) {
        // WM_CLOSE cancels the wallpaper preview. Invoke the application's own X button.
        var root = AutomationElement.FromHandle(new IntPtr(handle));
        var condition = new AndCondition(
            new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
            new PropertyCondition(AutomationElement.NameProperty, "\uf00d"),
            new PropertyCondition(AutomationElement.IsEnabledProperty, true),
            new PropertyCondition(AutomationElement.IsOffscreenProperty, false));
        var buttons = root.FindAll(TreeScope.Descendants, condition);
        AutomationElement close = null;
        foreach (AutomationElement candidate in buttons) {
            var bounds = candidate.Current.BoundingRectangle;
            if (bounds.IsEmpty) continue;
            if (close == null || bounds.Top < close.Current.BoundingRectangle.Top ||
                (bounds.Top == close.Current.BoundingRectangle.Top && bounds.Right > close.Current.BoundingRectangle.Right)) close = candidate;
        }
        object pattern;
        if (close == null || !close.TryGetCurrentPattern(InvokePattern.Pattern, out pattern))
            throw new Exception("Wallpaper Engine close button unavailable; window left open to preserve the selected wallpaper.");
        ((InvokePattern)pattern).Invoke();
    }
    [STAThread] static int Main(string[] args) {
        try {
            if (args.Length == 1 && args[0] == "--self-test") {
                if (!IsNativeDialog("#32770") || !IsNativeDialog("OperationStatusWindow") || !IsNativeDialog("MsiDialogCloseClass") || IsNativeDialog("Chrome_WidgetWin_1")) throw new Exception("Native dialog routing self-check failed");
                if (!IsWallpaperUi("wallpaperui") || !IsWallpaperUi("WallpaperUI") || IsWallpaperUi("wallpaper64") || IsWallpaperUi("notepad")) throw new Exception("Process routing self-check failed");
                var sample = Parse("{\"data\":{\"focused\":{\"processName\":\"wallpaperui\",\"handle\":123}}}");
                var focused = Obj(Get(Obj(Get(sample, "data")), "focused"));
                if (!IsWallpaperUi(Get(focused, "processName") as string) || Convert.ToInt64(Get(focused, "handle")) != 123) throw new Exception("Focus response self-check failed");
                return 0;
            }
            long explicitHandle = 0;
            if (args.Length != 0 && (args.Length != 2 || args[0] != "--handle" || !Int64.TryParse(args[1], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out explicitHandle) || explicitHandle <= 0)) return 2;
            using (var mutex = new Mutex(false, "Local\\GlazeWMCloseWindow-" + Environment.UserName)) {
                if (!mutex.WaitOne(0)) return 0;
                try {
                    if (explicitHandle > 0) {
                        if (!IsWindow(new IntPtr(explicitHandle))) throw new Exception("Window no longer exists");
                        var windows = Get(Obj(Get(Run("query windows"), "data")), "windows") as System.Collections.IEnumerable;
                        foreach (var entry in windows) {
                            var target = Obj(entry);
                            if (Convert.ToInt64(Get(target, "handle")) != explicitHandle) continue;
                            if (IsWallpaperUi(Get(target, "processName") as string)) CloseWallpaperUi(explicitHandle);
                            else { Guid id; if (!Guid.TryParse(Get(target, "id") as string, out id)) throw new Exception("Invalid window identifier"); Run("command --id " + id + " close"); }
                            return 0;
                        }
                        if (!PostMessage(new IntPtr(explicitHandle), 0x0010, IntPtr.Zero, IntPtr.Zero)) throw new Exception("Cannot close selected window");
                        return 0;
                    }
                    // Ignored native dialogs are absent from the WM tree. Close the foreground
                    // dialog itself rather than the managed window underneath it.
                    var foreground = GetForegroundWindow();
                    var className = new StringBuilder(256);
                    GetClassName(foreground, className, className.Capacity);
                    if (IsNativeDialog(className.ToString())) {
                        if (!PostMessage(foreground, 0x0010, IntPtr.Zero, IntPtr.Zero)) throw new Exception("Cannot close native dialog: " + Marshal.GetLastWin32Error());
                        return 0;
                    }
                    var focused = Obj(Get(Obj(Get(Run("query focused"), "data")), "focused"));
                    if (!Equals(Get(focused, "type"), "window")) return 0;
                    if (IsWallpaperUi(Get(focused, "processName") as string)) CloseWallpaperUi(Convert.ToInt64(Get(focused, "handle")));
                    else {
                        Guid id; if (!Guid.TryParse(Get(focused, "id") as string, out id)) throw new Exception("Invalid window identifier");
                        Run("command --id " + id + " close");
                    }
                } finally { mutex.ReleaseMutex(); }
            }
            return 0;
        } catch (Exception error) {
            try { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "close-window-error.log"), DateTime.Now.ToString("o") + " " + error.Message); } catch { }
            return 1;
        }
    }
}
