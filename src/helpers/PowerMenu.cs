using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;

enum PowerAction { Sleep, Hibernate, Shutdown, Restart, Lock, SignOut }
static class PowerMenu {
    const string Title="Питание — Rosé Pine";
    static readonly string[] Labels={"Сон","Гибернация","Выключение","Перезагрузка","Блокировка","Выход из учётной записи"};
    static readonly string[] Descriptions={"Продолжить работу после пробуждения","Сохранить сеанс на диск","Завершить работу компьютера","Перезапустить Windows","Заблокировать экран","Завершить текущий сеанс"};
    [StructLayout(LayoutKind.Sequential,Pack=1)] struct TokenPrivileges {public uint Count;public long Luid;public uint Attributes;}
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool LookupPrivilegeValue(string system,string name,out long luid);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr token,bool disable,ref TokenPrivileges state,uint length,IntPtr previous,IntPtr returned);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("powrprof.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.U1)] static extern bool SetSuspendState([MarshalAs(UnmanagedType.U1)] bool hibernate,[MarshalAs(UnmanagedType.U1)] bool force,[MarshalAs(UnmanagedType.U1)] bool disableWakeEvents);
    [DllImport("user32.dll",SetLastError=true)] static extern bool LockWorkStation();
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window,uint message,IntPtr wParam,IntPtr lParam);
    static Brush Color(string hex){return (Brush)new BrushConverter().ConvertFromString(hex);}
    static TextBlock Text(string value,double size,string color){return new TextBlock{Text=value,FontSize=size,Foreground=Color(color),TextWrapping=TextWrapping.Wrap};}
    static string Arguments(PowerAction action){
        switch(action){case PowerAction.Shutdown:return "/s /t 0";case PowerAction.Restart:return "/r /t 0";case PowerAction.SignOut:return "/l";default:return null;}
    }
    static bool NeedsConfirmation(PowerAction action){return action==PowerAction.Shutdown || action==PowerAction.Restart || action==PowerAction.SignOut;}
    static void EnableShutdownPrivilege(){
        IntPtr token;
        if(!OpenProcessToken(Process.GetCurrentProcess().Handle,0x28,out token))throw new Win32Exception();
        try{
            long luid; if(!LookupPrivilegeValue(null,"SeShutdownPrivilege",out luid))throw new Win32Exception();
            var privileges=new TokenPrivileges{Count=1,Luid=luid,Attributes=2};
            if(!AdjustTokenPrivileges(token,false,ref privileges,0,IntPtr.Zero,IntPtr.Zero))throw new Win32Exception();
            var error=Marshal.GetLastWin32Error();if(error!=0)throw new Win32Exception(error);
        }finally{CloseHandle(token);}
    }
    static string Execute(PowerAction action,bool preview){
        if(!Enum.IsDefined(typeof(PowerAction),action))throw new ArgumentOutOfRangeException("action");
        if(preview)return "preview:"+action;
        if(action==PowerAction.Sleep || action==PowerAction.Hibernate){
            EnableShutdownPrivilege();
            if(!SetSuspendState(action==PowerAction.Hibernate,false,false))throw new Win32Exception();
        }else if(action==PowerAction.Lock){if(!LockWorkStation())throw new Win32Exception();}
        else{
            var command=Path.Combine(Environment.SystemDirectory,"shutdown.exe");
            using(var process=Process.Start(new ProcessStartInfo(command,Arguments(action)){UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true,RedirectStandardOutput=true})){
                var error=process.StandardError.ReadToEnd();var output=process.StandardOutput.ReadToEnd();process.WaitForExit();
                if(process.ExitCode!=0)throw new Exception(String.IsNullOrWhiteSpace(error)?output:error);
            }
        }
        return action.ToString();
    }
    const string ButtonXml=@"<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'>
      <Setter Property='Foreground' Value='#e0def4'/><Setter Property='Background' Value='#26233a'/>
      <Setter Property='BorderBrush' Value='#403d52'/><Setter Property='BorderThickness' Value='1'/>
      <Setter Property='Padding' Value='13,10'/><Setter Property='Margin' Value='0,0,0,7'/>
      <Setter Property='HorizontalContentAlignment' Value='Stretch'/>
      <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'>
        <Border Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='{TemplateBinding BorderThickness}' CornerRadius='8' Padding='{TemplateBinding Padding}'>
          <ContentPresenter HorizontalAlignment='{TemplateBinding HorizontalContentAlignment}'/>
        </Border></ControlTemplate></Setter.Value></Setter>
      <Style.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter Property='Background' Value='#403d52'/><Setter Property='BorderBrush' Value='#c4a7e7'/></Trigger>
        <Trigger Property='IsKeyboardFocused' Value='True'><Setter Property='Background' Value='#403d52'/><Setter Property='BorderBrush' Value='#c4a7e7'/></Trigger>
        <Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='.5'/></Trigger>
      </Style.Triggers></Style>";
    static Window Menu(bool preview){
        var style=(Style)XamlReader.Parse(ButtonXml);
        var window=new Window{Title=Title+(preview?" [Проверка]":""),Width=460,SizeToContent=SizeToContent.Height,
            WindowStyle=WindowStyle.None,ResizeMode=ResizeMode.NoResize,AllowsTransparency=true,Background=Brushes.Transparent,
            WindowStartupLocation=WindowStartupLocation.CenterScreen,Topmost=true,ShowInTaskbar=true,FontFamily=new FontFamily("Segoe UI")};
        var frame=new Border{Background=Color("#191724"),BorderBrush=Color("#6e6a86"),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(14),Padding=new Thickness(20)};
        var root=new StackPanel();frame.Child=root;window.Content=frame;
        var header=new DockPanel{Margin=new Thickness(0,0,0,12)};
        var close=new Button{Content="×",Style=style,Width=38,FontSize=17,HorizontalContentAlignment=HorizontalAlignment.Center};
        System.Windows.Automation.AutomationProperties.SetName(close,"Закрыть меню");close.Click+=(s,e)=>window.Close();DockPanel.SetDock(close,Dock.Right);header.Children.Add(close);
        var heading=Text("Питание",23,"#e0def4");heading.MouseLeftButtonDown+=(s,e)=>{if(e.ButtonState==MouseButtonState.Pressed)window.DragMove();};header.Children.Add(heading);root.Children.Add(header);
        var panel=new StackPanel();root.Children.Add(panel);
        var footer=Text(preview?"Тестовый режим: команды питания не выполняются":"↑ / ↓ — выбор · Enter — открыть · Esc — закрыть",12,"#908caa");footer.Margin=new Thickness(0,8,0,0);root.Children.Add(footer);
        var buttons=new Button[Labels.Length];int selected=0;bool confirming=false;Action render=null;Action<PowerAction> choose=null;
        Action<PowerAction> perform=action=>{
            try{
                if(!preview)window.Hide();
                var result=Execute(action,preview);
                if(preview){File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"power-menu-preview.log"),result+Environment.NewLine);render();footer.Text="Проверено: "+Labels[(int)action]+". Команда не выполнялась.";}
                else window.Close();
            }catch(Exception error){window.Show();render();footer.Text="Не удалось выполнить действие: "+error.Message;}
        };
        choose=action=>{
            selected=(int)action;
            if(!NeedsConfirmation(action)){perform(action);return;}
            confirming=true;panel.Children.Clear();
            var question=Text(Labels[selected]+"?",20,"#c4a7e7");question.Margin=new Thickness(0,0,0,12);panel.Children.Add(question);
            var message=Text("Открытые приложения будут закрыты.",14,"#e0def4");message.Margin=new Thickness(0,0,0,20);panel.Children.Add(message);
            var cancel=new Button{Content="Отмена",Style=style,FontSize=14};cancel.Click+=(s,e)=>render();panel.Children.Add(cancel);
            var confirm=new Button{Content="Подтвердить: "+Labels[selected],Style=style,FontSize=14};confirm.Click+=(s,e)=>perform(action);panel.Children.Add(confirm);
            footer.Text="Tab — переключить кнопку · Enter — выбрать · Esc — назад";cancel.Focus();
        };
        render=()=>{
            confirming=false;panel.Children.Clear();
            for(int i=0;i<Labels.Length;i++){
                int index=i;var row=new DockPanel();var number=Text((i+1).ToString("00"),18,"#c4a7e7");number.Width=42;number.VerticalAlignment=VerticalAlignment.Center;DockPanel.SetDock(number,Dock.Left);row.Children.Add(number);
                var words=new StackPanel();words.Children.Add(Text(Labels[i],15,"#e0def4"));words.Children.Add(Text(Descriptions[i],11,"#908caa"));row.Children.Add(words);
                var button=new Button{Content=row,Style=style};System.Windows.Automation.AutomationProperties.SetName(button,Labels[i]);
                button.GotKeyboardFocus+=(s,e)=>selected=index;button.Click+=(s,e)=>choose((PowerAction)index);buttons[i]=button;panel.Children.Add(button);
            }
            footer.Text=preview?"Тестовый режим: команды питания не выполняются":"↑ / ↓ — выбор · Enter — открыть · Esc — закрыть";
            buttons[selected].Focus();
        };
        window.PreviewKeyDown+=(s,e)=>{
            if(e.Key==Key.Escape){e.Handled=true;if(confirming)render();else window.Close();}
            else if(!confirming && (e.Key==Key.Down || e.Key==Key.Up)){e.Handled=true;selected=(selected+(e.Key==Key.Down?1:Labels.Length-1))%Labels.Length;buttons[selected].Focus();}
        };
        window.Loaded+=(s,e)=>{render();window.Activate();};return window;
    }
    static void SelfTest(){
        if(Arguments(PowerAction.Shutdown)!="/s /t 0" || Arguments(PowerAction.Restart)!="/r /t 0" || Arguments(PowerAction.SignOut)!="/l")throw new Exception("Command mapping failed");
        foreach(PowerAction action in Enum.GetValues(typeof(PowerAction))){
            if(Execute(action,true)!="preview:"+action)throw new Exception("Preview dispatch failed");
            if(NeedsConfirmation(action)!=(action==PowerAction.Shutdown || action==PowerAction.Restart || action==PowerAction.SignOut))throw new Exception("Confirmation routing failed");
            var command=Arguments(action);if(command!=null && command.Contains("/f"))throw new Exception("Forced close is prohibited");
        }
        if(Marshal.SizeOf(typeof(TokenPrivileges))!=16)throw new Exception("Native privilege layout failed");
        XamlReader.Parse(ButtonXml);EnableShutdownPrivilege();
    }
    [STAThread] static int Main(string[] args){
        try{
            if(args.Length==1 && args[0]=="--self-test"){SelfTest();return 0;}
            bool preview=args.Length==1 && args[0]=="--preview";
            if(args.Length!=0 && !preview)return 2;
            bool created;
            using(var mutex=new Mutex(true,"Local\\RosePinePowerMenu-"+Environment.UserName+(preview?"-preview":""),out created)){
                if(!created){foreach(var process in Process.GetProcessesByName("power-menu"))if(process.Id!=Process.GetCurrentProcess().Id && process.MainWindowTitle==Title+(preview?" [Проверка]":""))PostMessage(process.MainWindowHandle,0x0010,IntPtr.Zero,IntPtr.Zero);return 0;}
                try{new Application().Run(Menu(preview));}finally{mutex.ReleaseMutex();}
            }
            return 0;
        }catch(Exception error){try{File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"power-menu-error.log"),DateTime.Now.ToString("o")+" "+error);}catch{}return 1;}
    }
}
