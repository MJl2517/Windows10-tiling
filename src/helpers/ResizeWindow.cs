using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Web.Script.Serialization;

static class ResizeWindow {
    static string Cli {get {return File.ReadAllText(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".glzr", "tools", "glazewm-cli.txt")).Trim();}}
    static Dictionary<string, object> Obj(object value) { return value as Dictionary<string, object>; }
    static object Get(Dictionary<string, object> node, string key) { object value; return node != null && node.TryGetValue(key, out value) ? value : null; }
    static string Str(Dictionary<string, object> node, string key) { return Get(node, key) as string; }
    static object[] Children(Dictionary<string, object> node) { return Get(node, "children") as object[] ?? new object[0]; }
    static bool Tiled(Dictionary<string, object> node) {
        return Str(node, "type") == "split" || (Str(node, "type") == "window" && Str(Obj(Get(node, "state")), "type") == "tiling");
    }
    static bool Find(Dictionary<string, object> node, List<Dictionary<string, object>> path) {
        path.Add(node);
        if (Str(node, "type") == "window" && Equals(Get(node, "hasFocus"), true)) return true;
        foreach (object child in Children(node)) if (Find(Obj(child), path)) return true;
        path.RemoveAt(path.Count - 1);
        return false;
    }
    static bool AtFarEdge(List<Dictionary<string, object>> path, bool horizontal) {
        if (!Tiled(path[path.Count - 1])) return false;
        for (int i = path.Count - 2; i >= 0; i--) {
            if (Str(path[i], "tilingDirection") != (horizontal ? "horizontal" : "vertical")) continue;
            var siblings = new List<Dictionary<string, object>>();
            foreach (object child in Children(path[i])) if (Tiled(Obj(child))) siblings.Add(Obj(child));
            if (siblings.Count < 2) continue;
            return Str(siblings[siblings.Count - 1], "id") == Str(path[i + 1], "id");
        }
        return false;
    }
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
    static void Check(bool condition) { if (!condition) throw new Exception("Resize self-check failed"); }
    static void SelfTest() {
        var root = Parse(@"{'type':'workspace','tilingDirection':'horizontal','children':[{'id':'left','type':'window','state':{'type':'tiling'}},{'id':'stack','type':'split','tilingDirection':'vertical','children':[{'id':'top','type':'window','state':{'type':'tiling'}},{'id':'bottom','type':'window','state':{'type':'tiling'}}]}]}".Replace('\'', '"'));
        var left = Obj(Children(root)[0]); var stack = Obj(Children(root)[1]);
        var topPath = new List<Dictionary<string, object>> {root, stack, Obj(Children(stack)[0])};
        var bottomPath = new List<Dictionary<string, object>> {root, stack, Obj(Children(stack)[1])};
        Check(!AtFarEdge(new List<Dictionary<string, object>> {root, left}, true));
        Check(AtFarEdge(topPath, true));
        Check(AtFarEdge(bottomPath, true));
        Check(!AtFarEdge(topPath, false));
        Check(AtFarEdge(bottomPath, false));
        var floating = Parse(@"{'type':'window','state':{'type':'floating'}}".Replace('\'', '"'));
        Check(!AtFarEdge(new List<Dictionary<string, object>> {root, floating}, true));
        Check(!AtFarEdge(new List<Dictionary<string, object>> {root, floating}, false));
    }
    [STAThread] static int Main(string[] args) {
        try {
            if (args.Length == 1 && args[0] == "--self-test") { SelfTest(); return 0; }
            if (args.Length != 1 || (args[0] != "left" && args[0] != "right" && args[0] != "up" && args[0] != "down")) return 2;
            var data = Obj(Get(Run("query workspaces"), "data"));
            var path = new List<Dictionary<string, object>>();
            foreach (object workspace in (object[])Get(data, "workspaces")) if (Find(Obj(workspace), path)) break;
            if (path.Count == 0) return 0;
            var window = path[path.Count - 1];
            string state = Str(Obj(Get(window, "state")), "type");
            if (state != "tiling" && state != "floating") return 0;
            Guid id; if (!Guid.TryParse(Str(window, "id"), out id)) throw new Exception("Invalid window identifier");
            bool horizontal = args[0] == "left" || args[0] == "right";
            bool grow = args[0] == "right" || args[0] == "down";
            if (AtFarEdge(path, horizontal)) grow = !grow;
            Run("command --id " + id + " resize " + (horizontal ? "--width " : "--height ") + (grow ? "+5%" : "-5%"));
            return 0;
        } catch (Exception error) {
            try { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "resize-window-error.log"), DateTime.Now.ToString("o") + " " + error.Message); } catch { }
            return 1;
        }
    }
}
