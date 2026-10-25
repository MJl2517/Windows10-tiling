using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

sealed class WinGesture {
    readonly Dictionary<uint,bool> held=new Dictionary<uint,bool>();
    public sealed class Result { public bool Consume,Toggle;public readonly List<uint> Replay=new List<uint>(); }
    public Result Key(uint key,bool down,bool modified){
        var result=new Result();
        if(key==0x5b || key==0x5c){
            bool forwarded;
            if(down){
                if(held.TryGetValue(key,out forwarded)){result.Consume=!forwarded;return result;}
                bool pass=modified || held.Values.Any(value=>value);
                held[key]=pass;result.Consume=!pass;
            }else if(held.TryGetValue(key,out forwarded)){
                held.Remove(key);result.Consume=!forwarded;result.Toggle=!forwarded && held.Count==0;
            }
        }else if(down && held.Values.Any(value=>!value)){
            foreach(var win in held.Keys.ToArray())if(!held[win]){result.Replay.Add(win);held[win]=true;}
            result.Replay.Add(key);result.Consume=true;
        }
        return result;
    }
}

static class TaskbarToggle {
    const string Title="Rose Pine Taskbar Toggle v1";
    const int Message=0x8000+173;
    static readonly string StateFile=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"taskbar-original-state.txt");
    delegate bool EnumProc(IntPtr window,IntPtr data);
    delegate IntPtr KeyboardProc(int code,IntPtr message,IntPtr data);
    delegate void EventProc(IntPtr hook,uint evt,IntPtr window,int objectId,int child,uint thread,uint time);
    [StructLayout(LayoutKind.Sequential)] struct Rect {public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)] struct AppBarData {public uint Size;public IntPtr Window;public uint Callback,Edge;public Rect Rect;public IntPtr State;}
    [StructLayout(LayoutKind.Sequential)] struct KeyboardData {public uint Key,Scan,Flags,Time;public UIntPtr Extra;}
    [StructLayout(LayoutKind.Sequential)] struct KeyInput {public ushort Key,Scan;public uint Flags,Time;public UIntPtr Extra;}
    [StructLayout(LayoutKind.Explicit,Size=32)] struct InputUnion {[FieldOffset(0)]public KeyInput Keyboard;}
    [StructLayout(LayoutKind.Sequential)] struct Input {public uint Type;public InputUnion Data;}
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr data);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder value,int size);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls,string title);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window,int command);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out Rect rect);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookEx(int type,KeyboardProc callback,IntPtr module,uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,Input[] input,int size);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window,int message,IntPtr wParam,IntPtr lParam);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr window,int message,IntPtr wParam,IntPtr lParam,uint flags,uint timeout,out IntPtr result);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint first,uint last,IntPtr module,EventProc callback,uint process,uint thread,uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint message,ref AppBarData data);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string module);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder text,ref int size);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    static string ImagePath(IntPtr window){
        uint pid;GetWindowThreadProcessId(window,out pid);var process=OpenProcess(0x1000,false,pid);if(process==IntPtr.Zero)return "";
        try{var text=new StringBuilder(32768);int size=text.Capacity;return QueryFullProcessImageName(process,0,text,ref size)?text.ToString():"";}finally{CloseHandle(process);}
    }
    static bool ExplorerBar(IntPtr window){
        var name=new StringBuilder(128);GetClassName(window,name,name.Capacity);
        if(name.ToString()!="Shell_TrayWnd" && name.ToString()!="Shell_SecondaryTrayWnd")return false;
        // Zebar's systray also uses Shell_TrayWnd. Only the Windows Explorer owns bars we hide.
        return String.Equals(ImagePath(window),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"explorer.exe"),StringComparison.OrdinalIgnoreCase);
    }
    static List<IntPtr> Bars(){var bars=new List<IntPtr>();EnumWindows((window,data)=>{if(ExplorerBar(window))bars.Add(window);return true;},IntPtr.Zero);return bars;}
    static uint State(){var data=new AppBarData{Size=(uint)Marshal.SizeOf(typeof(AppBarData))};return (uint)SHAppBarMessage(4,ref data).ToUInt64();}
    static void State(uint state){var data=new AppBarData{Size=(uint)Marshal.SizeOf(typeof(AppBarData)),State=new IntPtr(state)};SHAppBarMessage(10,ref data);}
    static uint Original(){uint value;return File.Exists(StateFile) && UInt32.TryParse(File.ReadAllText(StateFile),out value) && value<=3?value:State();}
    static void Restore(uint state){foreach(var bar in Bars())ShowWindowAsync(bar,8);State(state);if(File.Exists(StateFile))File.Delete(StateFile);}
    static IntPtr Controller(){var window=FindWindow(null,Title);return String.Equals(ImagePath(window),Process.GetCurrentProcess().MainModule.FileName,StringComparison.OrdinalIgnoreCase)?window:IntPtr.Zero;}
    static int Request(int action){var window=Controller();IntPtr result;if(window==IntPtr.Zero)return 3;return SendMessageTimeout(window,Message,new IntPtr(action),IntPtr.Zero,2,3000,out result)==IntPtr.Zero?4:result.ToInt32();}
    static void Write(string text){using(var output=new StreamWriter(Console.OpenStandardOutput(),new UTF8Encoding(false))){output.WriteLine(text);}}
    sealed class Host:NativeWindow,IDisposable {
        public bool Shown;
        readonly uint original;
        readonly WinGesture gesture=new WinGesture();
        readonly KeyboardProc keyboard;
        readonly EventProc changed;
        readonly System.Windows.Forms.Timer timer;
        IntPtr keyHook,showHook,moveHook;
        List<IntPtr> bars=new List<IntPtr>();
        bool disposed;
        public Host(){
            original=Original();File.WriteAllText(StateFile,original.ToString());
            CreateHandle(new CreateParams{Caption=Title,Style=unchecked((int)0x80000000),ExStyle=0x80});
            keyboard=OnKey;changed=OnEvent;
            keyHook=SetWindowsHookEx(13,keyboard,GetModuleHandle(null),0);
            showHook=SetWinEventHook(0x8002,0x8002,IntPtr.Zero,changed,0,0,0);
            moveHook=SetWinEventHook(0x800b,0x800b,IntPtr.Zero,changed,0,0,0);
            if(keyHook==IntPtr.Zero || showHook==IntPtr.Zero || moveHook==IntPtr.Zero){Dispose();throw new Win32Exception();}
            timer=new System.Windows.Forms.Timer{Interval=500};timer.Tick+=(s,e)=>Enforce();timer.Start();Apply();
        }
        void Apply(){State(Shown?original & ~1u:original | 1u);Enforce();}
        void Enforce(){
            var found=Bars();bool replaced=found.Any(bar=>!bars.Contains(bar));bars=found;
            if(replaced)State(Shown?original & ~1u:original | 1u);
            foreach(var bar in bars){
                if(!Shown){if(IsWindowVisible(bar))ShowWindowAsync(bar,0);}
                else if(!IsWindowVisible(bar) || replaced){ShowWindowAsync(bar,8);SetWindowPos(bar,new IntPtr(-1),0,0,0,0,0x53);}
            }
        }
        void OnEvent(IntPtr hook,uint evt,IntPtr window,int objectId,int child,uint thread,uint time){
            if(!Shown && objectId==0 && ExplorerBar(window))ShowWindowAsync(window,0);
        }
        IntPtr OnKey(int code,IntPtr message,IntPtr data){
            if(code<0)return CallNextHookEx(keyHook,code,message,data);
            var key=(KeyboardData)Marshal.PtrToStructure(data,typeof(KeyboardData));
            if((key.Flags & 0x10)!=0)return CallNextHookEx(keyHook,code,message,data);
            bool down=message.ToInt32()==0x100 || message.ToInt32()==0x104;
            bool modified=(GetAsyncKeyState(0x10)&0x8000)!=0 || (GetAsyncKeyState(0x11)&0x8000)!=0 || (GetAsyncKeyState(0x12)&0x8000)!=0;
            var decision=gesture.Key(key.Key,down,modified);
            if(decision.Replay.Count>0){
                var inputs=decision.Replay.Select(vk=>new Input{Type=1,Data=new InputUnion{Keyboard=new KeyInput{Key=(ushort)vk,Scan=vk==key.Key?(ushort)key.Scan:(ushort)0,Flags=vk==key.Key?key.Flags&1u:1u}}}).ToArray();
                if(SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(Input)))!=inputs.Length){PostMessage(Handle,0x10,IntPtr.Zero,IntPtr.Zero);return CallNextHookEx(keyHook,code,message,data);}
            }
            if(decision.Toggle)PostMessage(Handle,Message,new IntPtr(1),IntPtr.Zero);
            return decision.Consume?new IntPtr(1):CallNextHookEx(keyHook,code,message,data);
        }
        protected override void WndProc(ref Message message){
            if(message.Msg==Message){
                int action=message.WParam.ToInt32();
                if(action==4){Application.ExitThread();message.Result=IntPtr.Zero;return;}
                if(action==1)Shown=!Shown;else if(action==2)Shown=true;else if(action==3)Shown=false;
                if(action!=5)Apply();message.Result=new IntPtr(Shown?1:2);return;
            }
            if(message.Msg==0x10){Application.ExitThread();return;}base.WndProc(ref message);
        }
        public void Dispose(){
            if(disposed)return;disposed=true;if(timer!=null)timer.Dispose();
            if(keyHook!=IntPtr.Zero)UnhookWindowsHookEx(keyHook);if(showHook!=IntPtr.Zero)UnhookWinEvent(showHook);if(moveHook!=IntPtr.Zero)UnhookWinEvent(moveHook);
            Restore(original);DestroyHandle();
        }
    }
    static void SelfTest(){
        var state=new WinGesture();if(!state.Key(0x5b,true,false).Consume || !state.Key(0x5b,true,false).Consume || !state.Key(0x5b,false,false).Toggle)throw new Exception("Bare Win failed");
        state=new WinGesture();state.Key(0x5b,true,false);var combo=state.Key(0x45,true,false);
        if(!combo.Consume || !combo.Replay.SequenceEqual(new uint[]{0x5b,0x45}) || state.Key(0x45,false,false).Consume || state.Key(0x5b,false,false).Toggle)throw new Exception("Win+E forwarding failed");
        state=new WinGesture();state.Key(0x5b,true,false);var alt=state.Key(0x12,true,false);
        if(!alt.Replay.SequenceEqual(new uint[]{0x5b,0x12})||state.Key(0x20,true,true).Consume||state.Key(0x5b,false,true).Toggle)throw new Exception("Win+Alt+Space forwarding failed");
        state=new WinGesture();if(state.Key(0x5c,true,true).Consume || state.Key(0x5c,false,true).Toggle)throw new Exception("Modified Win failed");
        state=new WinGesture();state.Key(0x5c,true,false);if(!state.Key(0x5c,false,false).Toggle || state.Key(0x41,true,false).Consume)throw new Exception("Right Win failed");
        state=new WinGesture();state.Key(0x5b,true,false);state.Key(0x10,true,false);if(state.Key(0x53,true,true).Consume || state.Key(0x5b,false,true).Toggle)throw new Exception("Win+Shift+S forwarding failed");
        if(Marshal.SizeOf(typeof(Input))!=40 || Marshal.SizeOf(typeof(AppBarData))!=48)throw new Exception("Native x64 layouts failed");
        if(Bars().Count==0)throw new Exception("Explorer taskbars not found");
        Write("PASS: bare left/right Win, repeats, Win+E, modifiers, Win+Shift+S, native structures and Explorer-only taskbars");
    }
    [STAThread]static int Main(string[] args){
        try{
            if(args.Length==1 && args[0]=="--self-test"){SelfTest();return 0;}
            if(args.Length==1 && args[0]=="--status"){
                var bars=Bars().Select(bar=>{Rect rect;GetWindowRect(bar,out rect);return new{handle=bar.ToInt64(),visible=IsWindowVisible(bar),bounds=rect};}).ToArray();
                Write(new JavaScriptSerializer().Serialize(new{controller=Controller()!=IntPtr.Zero,shown=Request(5)==1,state=State(),bars=bars}));return 0;
            }
            if(args.Length==1 && args[0]=="--restore"){
                if(Controller()!=IntPtr.Zero){Request(4);return 0;}Restore(Original());return 0;
            }
            if(args.Length==1){int action=args[0]=="--toggle"?1:args[0]=="--show"?2:args[0]=="--hide"?3:args[0]=="--stop"?4:0;if(action==0)return 2;var reply=Request(action);return reply<=2?0:reply;}
            if(args.Length!=0)return 2;
            bool created;using(var mutex=new Mutex(true,"Local\\RosePineTaskbarToggle-"+Environment.UserName,out created)){
                if(!created)return 0;
                try{using(var host=new Host())Application.Run();}finally{mutex.ReleaseMutex();}
            }
            return 0;
        }catch(Exception error){try{File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"taskbar-toggle-error.log"),DateTime.Now.ToString("o")+" "+error);}catch{}return 1;}
    }
}
