using System;
using System.IO;
using System.Diagnostics;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using System.Windows.Forms;
static class Launcher {
    [STAThread] static int Main(string[] args) {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            var state=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,"installed.json")));
            string payload=(string)state["payload"];
            if(!Path.GetFullPath(payload).StartsWith(Path.Combine(root,"versions")+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Недопустимый путь выпуска");
            string command="--root \""+root+"\"";
            foreach(string a in args)command+=" \""+a.Replace("\"","")+"\"";
            Process.Start(new ProcessStartInfo(Path.Combine(payload,"Center.exe"),command){UseShellExecute=false,WorkingDirectory=Environment.CurrentDirectory});
            return 0;
        } catch(Exception e) {MessageBox.Show(e.Message,"Rose Pine Desktop");return 1;}
    }
}
