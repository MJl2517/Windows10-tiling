using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;

static class TaskWindows {
    delegate bool EnumProc(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int size);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder text, int size);
    [DllImport("user32.dll",EntryPoint="GetWindowLongW")] static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll",EntryPoint="GetClassLongPtrW")] static extern IntPtr GetClassLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window,uint message,IntPtr wParam,IntPtr lParam,uint flags,uint timeout,out IntPtr result);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access,bool inherit,uint process);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder path,ref int length);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window,uint attribute,out int value,int size);
    static string Text(IntPtr window,bool className){var text=new StringBuilder(1024);if(className)GetClassName(window,text,text.Capacity);else GetWindowText(window,text,text.Capacity);return text.ToString();}
    static string ImagePath(IntPtr window){
        uint pid;GetWindowThreadProcessId(window,out pid);var process=OpenProcess(0x1000,false,pid);if(process==IntPtr.Zero)return null;
        try{var text=new StringBuilder(32768);int length=text.Capacity;return QueryFullProcessImageName(process,0,text,ref length)?text.ToString():null;}finally{CloseHandle(process);}
    }
    static bool Eligible(IntPtr window,bool managed){
        if(!IsWindow(window) || String.IsNullOrWhiteSpace(Text(window,false)))return false;
        var cls=Text(window,true);
        if(cls=="Progman" || cls=="WorkerW" || cls=="Shell_TrayWnd" || cls=="Shell_SecondaryTrayWnd")return false;
        if(managed)return true; // GlazeWM deliberately hides windows from other workspaces.
        int style=GetWindowLong(window,-20),cloaked;
        return IsWindowVisible(window) && (style & 0x08000080)==0 &&
            ((style & 0x40000)!=0 || GetWindow(window,4)==IntPtr.Zero) &&
            (DwmGetWindowAttribute(window,14,out cloaked,4)!=0 || cloaked==0);
    }
    static string IconData(IntPtr window,string path){
        try{
            IntPtr icon;SendMessageTimeout(window,0x7f,new IntPtr(1),IntPtr.Zero,2,60,out icon);
            if(icon==IntPtr.Zero)icon=GetClassLongPtr(window,-14);
            if(icon!=IntPtr.Zero){using(var copy=(Icon)Icon.FromHandle(icon).Clone())return Png(copy);}
            if(path!=null){using(var extracted=Icon.ExtractAssociatedIcon(path))if(extracted!=null)return Png(extracted);}
        }catch{}
        return Png(SystemIcons.Application);
    }
    static string Png(Icon icon){using(var bitmap=icon.ToBitmap())using(var stream=new MemoryStream()){bitmap.Save(stream,ImageFormat.Png);return "data:image/png;base64,"+Convert.ToBase64String(stream.ToArray());}}
    static long Handle(string value){long number;if(!Int64.TryParse(value,NumberStyles.None,CultureInfo.InvariantCulture,out number) || number<=0)throw new ArgumentException("Invalid window handle");return number;}
    static List<object> List(HashSet<long> managed){
        var handles=new HashSet<long>(managed);EnumWindows((window,data)=>{if(Eligible(window,false))handles.Add(window.ToInt64());return true;},IntPtr.Zero);
        var rows=new List<object>();var foreground=GetForegroundWindow();
        foreach(var handle in handles){
            var window=new IntPtr(handle);if(!Eligible(window,managed.Contains(handle)))continue;
            var path=ImagePath(window);var process=path==null?"":Path.GetFileNameWithoutExtension(path);
            if(process.Equals("zebar",StringComparison.OrdinalIgnoreCase) || process.Equals("tacky-borders",StringComparison.OrdinalIgnoreCase) || process.Equals("wallpaper32",StringComparison.OrdinalIgnoreCase) || process.Equals("wallpaper64",StringComparison.OrdinalIgnoreCase))continue;
            rows.Add(new {handle=handle,title=Text(window,false),processName=process,icon=IconData(window,path),active=window==foreground,minimized=IsIconic(window)});
        }
        return rows;
    }
    static int Main(string[] args){
        try{
            Console.OutputEncoding=new UTF8Encoding(false);
            if(args.Length==1 && args[0]=="--self-test"){
                bool rejected=false;try{Handle("12 x");}catch(ArgumentException){rejected=true;}
                if(!rejected || Handle("123")!=123 || Eligible(IntPtr.Zero,false) || !Png(SystemIcons.Application).StartsWith("data:image/png;base64,"))return 1;
                var json=new JavaScriptSerializer().Serialize(List(new HashSet<long>()));
                if(new JavaScriptSerializer().DeserializeObject(json)==null)return 1;
                Console.WriteLine("PASS: handle validation, window enumeration, PNG icons and JSON output");return 0;
            }
            if(args.Length>=1 && args[0]=="--list"){
                var managed=new HashSet<long>();for(int i=1;i<args.Length;i++)managed.Add(Handle(args[i]));
                Console.WriteLine(new JavaScriptSerializer{MaxJsonLength=16*1024*1024}.Serialize(List(managed)));return 0;
            }
            if(args.Length==2 && (args[0]=="--activate" || args[0]=="--minimize")){
                var window=new IntPtr(Handle(args[1]));if(!Eligible(window,false))return 3;
                if(args[0]=="--minimize")ShowWindowAsync(window,6);
                else{if(IsIconic(window))ShowWindowAsync(window,9);if(!SetForegroundWindow(window))return 4;}
                return 0;
            }
            return 2;
        }catch(Exception error){Console.Error.WriteLine(error.Message);return 1;}
    }
}
