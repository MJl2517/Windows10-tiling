using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Threading;

internal static class OpenWithLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "yazi", "config");
            string queue = Path.Combine(root, "open-with-requests");
            Directory.CreateDirectory(queue);
            string mutexName = @"Local\YaziOpenWith-" + WindowsIdentity.GetCurrent().User.Value;
            bool running;
            Mutex mutex;
            running = Mutex.TryOpenExisting(mutexName, out mutex);
            if (mutex != null) mutex.Dispose();
            if (!running)
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
                    Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + Path.Combine(root, "open-file.ps1") + "\" -Server",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                });
            }
            if (args.Length == 1 && args[0] == "--warm") return 0;
            if (args.Length == 0) return 2;
            bool wait = args[0] == "--wait";
            int start = wait ? 1 : 0;
            if (args.Length == start) return 2;
            string[] request = new string[args.Length - start];
            for (int i = start; i < args.Length; i++)
            {
                if (!File.Exists(args[i]) && !Directory.Exists(args[i])) return 2;
                request[i - start] = Convert.ToBase64String(Encoding.UTF8.GetBytes(Path.GetFullPath(args[i])));
            }
            string id = Guid.NewGuid().ToString("N");
            string temporary = Path.Combine(queue, id + ".tmp");
            File.WriteAllLines(temporary, request, new UTF8Encoding(false));
            File.Move(temporary, Path.Combine(queue, id + ".request"));
            if (!wait) return 0;
            string receipt = Path.Combine(queue, id + ".done");
            for (int i = 0; i < 200; i++)
            {
                if (File.Exists(receipt))
                {
                    string result = File.ReadAllText(receipt);
                    File.Delete(receipt);
                    return result == "OK" ? 0 : 1;
                }
                Thread.Sleep(25);
            }
            return 3;
        }
        catch (Exception error)
        {
            try { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "open-with-launch-error.txt"), error.ToString()); }
            catch { }
            return 1;
        }
    }
}
