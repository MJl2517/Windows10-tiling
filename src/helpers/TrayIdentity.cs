using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

static class TrayIdentity {
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint process);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder path, ref int length);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    static bool Parse(string id, out long window, out uint uid) {
        window=0; uid=0;
        var parts=id.Split(':');
        return parts.Length==2 && Int64.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out window) && window>0 && UInt32.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out uid);
    }
    static string Image(uint pid) {
        var process=OpenProcess(0x1000, false, pid);
        if(process==IntPtr.Zero) return null;
        try {
            var path=new StringBuilder(32768); int length=path.Capacity;
            return QueryFullProcessImageName(process, 0, path, ref length) ? path.ToString().ToLowerInvariant() : null;
        } finally { CloseHandle(process); }
    }
    // null means the callback window is gone. An unreadable process is unknown.
    static bool TryResolve(long window, uint uid, out string identity) {
        identity=null;
        uint pid;
        if(GetWindowThreadProcessId(new IntPtr(window),out pid)==0) return true;
        var path=Image(pid);
        if(path==null) return false;
        identity="exe:"+path+"|"+uid.ToString(CultureInfo.InvariantCulture);
        return true;
    }
    static int Main(string[] args) {
        if(args.Length==1 && args[0]=="--self-test") {
            long window; uint uid;
            if(!Parse("123:0",out window,out uid) || window!=123 || uid!=0 || Parse("0:1",out window,out uid) || Parse("1:4294967296",out window,out uid) || Parse("1:2 x",out window,out uid) || String.IsNullOrEmpty(Image((uint)Process.GetCurrentProcess().Id))) return 1;
            var testWindow=new NativeWindow();
            testWindow.CreateHandle(new CreateParams { Parent=new IntPtr(-3) });
            long handle=testWindow.Handle.ToInt64();
            string identity;
            try {
                if(!TryResolve(handle,0,out identity) || identity==null) return 1;
            } finally { testWindow.DestroyHandle(); }
            if(!TryResolve(handle,0,out identity) || identity!=null) return 1;
            Console.WriteLine("PASS: identifier validation, live callback window and destroyed callback window"); return 0;
        }
        var identities=new Dictionary<string,string>();
        foreach(var id in args) {
            long window; uint uid;
            if(!Parse(id,out window,out uid)) return 2;
            string identity;
            if(TryResolve(window,uid,out identity)) identities[id]=identity;
        }
        Console.OutputEncoding=new UTF8Encoding(false);
        Console.WriteLine(new JavaScriptSerializer().Serialize(identities)); return 0;
    }
}
