using System;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;
using System.Collections;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Xml;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Text.RegularExpressions;
using Microsoft.Win32;
class Space {public string name{get;set;} public string label{get;set;} public int monitor{get;set;}}
class Settings {
    public string[] components{get;set;} public bool autostart{get;set;} public bool hideTaskbar{get;set;} public bool cursor{get;set;}
    public string browser{get;set;} public Space[] workspaces{get;set;} public string feed{get;set;} public bool checkAtLogon{get;set;}
}
class Center {
    static string root;
    static JavaScriptSerializer json=new JavaScriptSerializer(){MaxJsonLength=16000000};
    Window window;TextBlock status,version,update,health;TextBox feed,browser;DataGrid spaces;
    CheckBox desktop,files,borders,auto,hide,cursor,check;StackPanel actions;ListBox backups,conflicts;Dictionary<string,object> latest;
    List<Dictionary<string,object>> conflictFiles=new List<Dictionary<string,object>>();
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd,int attribute,ref int value,int size);
    static string Quote(string s){return "\""+s.Replace("\"","")+"\"";}
    static string Engine {get {var s=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,"installed.json")));return Path.Combine((string)s["payload"],"Desktop.ps1");}}
    static async Task<Dictionary<string,object>> Run(string action,string extra) {
        string receipt=Path.Combine(root,"requests",Guid.NewGuid().ToString("N")+".json");Directory.CreateDirectory(Path.GetDirectoryName(receipt));
        var p=Process.Start(new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"),"-NoProfile -STA -ExecutionPolicy Bypass -File "+Quote(Engine)+" -Action "+action+" -Root "+Quote(root)+" -Result "+Quote(receipt)+" "+extra){UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Environment.CurrentDirectory});
        await Task.Run(()=>p.WaitForExit());
        if(!File.Exists(receipt))throw new Exception("Компонент завершился без ответа. Проверь доступ к папке установки.");
        var result=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(receipt));File.Delete(receipt);
        if(result.ContainsKey("ok")&&Equals(result["ok"],false))throw new Exception((string)result["error"]);
        return result;
    }
    T Get<T>(string name) where T:FrameworkElement{return (T)window.FindName(name);}
    Button Button(string title,Func<Task> click,Panel parent) {var b=new Button{Content=title};b.Click+=async(s,e)=>await Busy(click);parent.Children.Add(b);return b;}
    async Task Busy(Func<Task> f){actions.IsEnabled=false;status.Text="Выполняется…";try{await f();status.Text="Готово";}catch(Exception e){status.Text=e.Message;MessageBox.Show(window,e.Message,"Rose Pine Desktop",MessageBoxButton.OK,MessageBoxImage.Information);}finally{actions.IsEnabled=true;}}
    void LoadSettings(){
        var s=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));
        desktop.IsChecked=Array.IndexOf(s.components,"desktop")>=0;files.IsChecked=Array.IndexOf(s.components,"files")>=0;borders.IsChecked=Array.IndexOf(s.components,"borders")>=0;
        auto.IsChecked=s.autostart;hide.IsChecked=s.hideTaskbar;cursor.IsChecked=s.cursor;check.IsChecked=s.checkAtLogon;
        browser.Text=s.browser;feed.Text=s.feed;spaces.ItemsSource=new ObservableCollection<Space>(s.workspaces);
    }
    async Task Refresh(){var s=await Run("Status","");version.Text="Установлена версия "+s["version"]+" · мониторов: "+s["monitors"];backups.ItemsSource=(IEnumerable)s["backups"];conflicts.Items.Clear();conflictFiles.Clear();foreach(var c in (IEnumerable)s["conflicts"]){var d=(Dictionary<string,object>)c;conflictFiles.Add(d);conflicts.Items.Add((string)d["target"]+"\nНовая версия: "+d["incoming"]);}foreach(var m in (IEnumerable)s["modified"])conflicts.Items.Add("Изменён вручную: "+m);if(s.ContainsKey("checks")){int total=0;var missing=new List<string>();foreach(Dictionary<string,object> item in (IEnumerable)s["checks"]){total++;if(!Equals(item["exists"],true))missing.Add((string)item["name"]);}health.Text=missing.Count==0?"Файлы компонентов найдены: "+total:"Отсутствуют файлы: "+String.Join(", ",missing);}}
    Task Compare(){
        if(conflictFiles.Count==0){Process.Start("explorer.exe",Quote(Path.Combine(root,"conflicts")));return Task.FromResult(0);}
        int index=Math.Max(0,Math.Min(conflicts.SelectedIndex,conflictFiles.Count-1));var item=conflictFiles[index];
        var panel=new Grid();panel.ColumnDefinitions.Add(new ColumnDefinition());panel.ColumnDefinitions.Add(new ColumnDefinition());
        for(int i=0;i<2;i++){string path=(string)item[i==0?"target":"incoming"];var box=new TextBox{Text=(i==0?"Текущий файл: ":"Новый файл: ")+path+"\r\n\r\n"+(File.Exists(path)?File.ReadAllText(path):"Файл отсутствует"),IsReadOnly=true,AcceptsReturn=true,HorizontalScrollBarVisibility=ScrollBarVisibility.Auto,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,FontFamily=new FontFamily("Consolas"),Background=new SolidColorBrush(Color.FromRgb(38,35,58)),Foreground=Brushes.White,Margin=new Thickness(6)};Grid.SetColumn(box,i);panel.Children.Add(box);}
        new Window{Owner=window,Title="Сравнение конфигов",Width=1100,Height=650,Content=panel,Background=new SolidColorBrush(Color.FromRgb(25,23,36))}.Show();return Task.FromResult(0);
    }
    void ChooseBrowser(Button button){
        var menu=new ContextMenu{PlacementTarget=button};var system=new MenuItem{Header="Системный браузер"};system.Click+=(s,e)=>browser.Text="";menu.Items.Add(system);
        var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var hive in new[]{RegistryHive.CurrentUser,RegistryHive.LocalMachine})foreach(var view in new[]{RegistryView.Registry64,RegistryView.Registry32}){
            using(var basis=RegistryKey.OpenBaseKey(hive,view))using(var clients=basis.OpenSubKey(@"Software\Clients\StartMenuInternet")){
                if(clients==null)continue;foreach(string name in clients.GetSubKeyNames())using(var client=clients.OpenSubKey(name))using(var command=client.OpenSubKey(@"shell\open\command")){
                    if(command==null)continue;string raw=command.GetValue(null) as string??"";var match=Regex.Match(raw,"^\\s*(?:\"([^\"]+\\.exe)\"|(.+?\\.exe))",RegexOptions.IgnoreCase);if(!match.Success)continue;
                    string path=Environment.ExpandEnvironmentVariables(match.Groups[1].Success?match.Groups[1].Value:match.Groups[2].Value);if(!File.Exists(path)||!seen.Add(path))continue;
                    var item=new MenuItem{Header=client.GetValue(null) as string??name};item.Click+=(s,e)=>browser.Text=path;menu.Items.Add(item);
                }
            }
        }
        menu.Items.Add(new Separator());var other=new MenuItem{Header="Выбрать файл приложения…"};other.Click+=(s,e)=>{var dialog=new OpenFileDialog{Filter="Приложение|*.exe"};if(dialog.ShowDialog(window)==true)browser.Text=dialog.FileName;};menu.Items.Add(other);menu.IsOpen=true;
    }
    async Task Save(){
        spaces.CommitEdit(DataGridEditingUnit.Cell,true);spaces.CommitEdit(DataGridEditingUnit.Row,true);
        var components=new List<string>();if(desktop.IsChecked==true)components.Add("desktop");if(files.IsChecked==true)components.Add("files");if(borders.IsChecked==true)components.Add("borders");
        if(components.Count==0)throw new Exception("Выбери хотя бы один компонент");
        if(browser.Text.Length>0&&!File.Exists(browser.Text))throw new Exception("Файл браузера не найден");
        var rows=(ObservableCollection<Space>)spaces.ItemsSource;foreach(var row in rows){if(String.IsNullOrWhiteSpace(row.label)||row.label.Contains("\n"))throw new Exception("Укажи название рабочего пространства");}
        var s=new Settings{components=components.ToArray(),autostart=auto.IsChecked==true,hideTaskbar=hide.IsChecked==true,cursor=cursor.IsChecked==true,checkAtLogon=check.IsChecked==true,browser=browser.Text,feed=feed.Text,workspaces=new List<Space>(rows).ToArray()};
        var request=Path.Combine(root,"requests","settings-"+Guid.NewGuid().ToString("N")+".json");Directory.CreateDirectory(Path.GetDirectoryName(request));File.WriteAllText(request,json.Serialize(s));
        try{await Run("Apply","-SettingsFile "+Quote(request));await Run("Start","");await Refresh();}finally{File.Delete(request);}
        status.Text="Настройки сохранены. Уже открытые терминалы используют прежние параметры до следующего запуска.";
    }
    async Task Check(){latest=await Run("Check","");update.Text=(string)latest["message"];if(latest.ContainsKey("notes"))update.Text+="\n\n"+(string)latest["notes"];}
    void Build(bool autoRefresh=true){
        string xaml=@"<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' Title='Rose Pine Desktop' Width='840' Height='690' MinWidth='720' MinHeight='580' Background='#191724' Foreground='#e0def4' WindowStartupLocation='CenterScreen' FontFamily='Segoe UI' FontSize='14'>
<Window.Resources>
<Style TargetType='Button'><Setter Property='Margin' Value='0,6,10,6'/><Setter Property='Padding' Value='15,9'/><Setter Property='Background' Value='#26233a'/><Setter Property='Foreground' Value='#e0def4'/><Setter Property='BorderBrush' Value='#524f67'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'><Border x:Name='b' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1' CornerRadius='8' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center'/></Border><ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Background' Value='#403852'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter TargetName='b' Property='Opacity' Value='.45'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='TextBox'><Setter Property='Background' Value='#26233a'/><Setter Property='Foreground' Value='#e0def4'/><Setter Property='CaretBrush' Value='#e0def4'/><Setter Property='BorderBrush' Value='#524f67'/><Setter Property='Padding' Value='8'/><Setter Property='Margin' Value='0,5,0,10'/></Style>
<Style TargetType='CheckBox'><Setter Property='Foreground' Value='#e0def4'/><Setter Property='Margin' Value='0,7,15,7'/></Style>
<Style TargetType='TabItem'><Setter Property='Foreground' Value='#e0def4'/><Setter Property='Padding' Value='16,10'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='TabItem'><Border x:Name='b' Padding='{TemplateBinding Padding}' Background='#26233a' CornerRadius='7,7,0,0' Margin='0,0,3,0'><ContentPresenter ContentSource='Header'/></Border><ControlTemplate.Triggers><Trigger Property='IsSelected' Value='True'><Setter TargetName='b' Property='Background' Value='#403852'/><Setter Property='Foreground' Value='#c4a7e7'/></Trigger><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Background' Value='#403852'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='ListBox'><Setter Property='Background' Value='#26233a'/><Setter Property='Foreground' Value='#e0def4'/><Setter Property='BorderBrush' Value='#524f67'/></Style>
</Window.Resources>
<Grid Margin='26'><Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='*'/><RowDefinition Height='Auto'/></Grid.RowDefinitions>
<StackPanel Margin='0,0,0,20'><TextBlock Text='Rose Pine Desktop' FontSize='30' FontWeight='SemiBold' Foreground='#c4a7e7'/><TextBlock x:Name='Version' Margin='0,5,0,0'/></StackPanel>
<StackPanel x:Name='Actions' Grid.Row='1'><TabControl x:Name='Tabs' Background='#191724' BorderBrush='#403d52' Height='470'>
<TabItem Header='Обновления'><StackPanel Margin='18'><TextBlock x:Name='Update' Text='Нажми «Проверить обновления».' TextWrapping='Wrap' Height='155'/><WrapPanel x:Name='UpdateButtons'/><TextBlock Text='Источник обновлений: HTTPS-манифест или локальный файл' Margin='0,16,0,0'/><TextBox x:Name='Feed'/><TextBlock Text='Адрес начнёт использоваться после сохранения настроек.' Foreground='#908caa'/></StackPanel></TabItem>
<TabItem Header='Настройки'><ScrollViewer VerticalScrollBarVisibility='Auto'><StackPanel Margin='18'>
<WrapPanel><CheckBox x:Name='Desktop' Content='Окна и панель'/><CheckBox x:Name='Files' Content='Yazi и терминал'/><CheckBox x:Name='Borders' Content='Обводки'/></WrapPanel>
<CheckBox x:Name='Auto' Content='Запускать окружение при входе'/><CheckBox x:Name='Check' Content='Проверять обновления при входе'/><CheckBox x:Name='Hide' Content='Скрывать панель Windows, переключать клавишей Win'/><CheckBox x:Name='Cursor' Content='Курсор Bibata Modern Ice'/>
<TextBlock Text='Браузер: пустое поле — системный'/><DockPanel><Button x:Name='Browse' Content='Выбрать…' DockPanel.Dock='Right'/><TextBox x:Name='Browser'/></DockPanel>
<TextBlock Text='Рабочие пространства · монитор 0 — основной, 1 — второй' Margin='0,8,0,8'/>
<DataGrid x:Name='Spaces' AutoGenerateColumns='False' CanUserAddRows='False' CanUserDeleteRows='False' Height='180' Foreground='#191724' Background='#e0def4'><DataGrid.Columns><DataGridTextColumn Header='Клавиша Alt+' Binding='{Binding name}' IsReadOnly='True'/><DataGridTextColumn Header='Название' Binding='{Binding label}' Width='*'/><DataGridTextColumn Header='Монитор' Binding='{Binding monitor}' Width='90'/></DataGrid.Columns></DataGrid><WrapPanel x:Name='SettingsButtons'/>
</StackPanel></ScrollViewer></TabItem>
<TabItem Header='Восстановление'><ScrollViewer VerticalScrollBarVisibility='Auto'><StackPanel Margin='18'><WrapPanel x:Name='RecoveryButtons'/><TextBlock x:Name='Health' TextWrapping='Wrap' Foreground='#9ccfd8' Margin='0,10'/><TextBlock Text='Резервные копии' Margin='0,10'/><ListBox x:Name='Backups' Height='85'/><TextBlock Text='Ручные изменения и конфликты' Margin='0,10'/><ListBox x:Name='Conflicts' Height='115'/><TextBlock Text='Откат сохраняет личные данные. При конфликте сначала сохрани правки и сравни файлы.' TextWrapping='Wrap' Margin='0,10'/></StackPanel></ScrollViewer></TabItem>
</TabControl></StackPanel><TextBlock x:Name='Status' Grid.Row='2' Text='Готово' Foreground='#9ccfd8' TextWrapping='Wrap' Margin='0,12,0,0'/></Grid></Window>";
        using(var reader=XmlReader.Create(new StringReader(xaml)))window=(Window)XamlReader.Load(reader);
        version=Get<TextBlock>("Version");status=Get<TextBlock>("Status");update=Get<TextBlock>("Update");feed=Get<TextBox>("Feed");browser=Get<TextBox>("Browser");spaces=Get<DataGrid>("Spaces");actions=Get<StackPanel>("Actions");backups=Get<ListBox>("Backups");conflicts=Get<ListBox>("Conflicts");
        health=Get<TextBlock>("Health");
        desktop=Get<CheckBox>("Desktop");files=Get<CheckBox>("Files");borders=Get<CheckBox>("Borders");auto=Get<CheckBox>("Auto");hide=Get<CheckBox>("Hide");cursor=Get<CheckBox>("Cursor");check=Get<CheckBox>("Check");
        Button("Проверить обновления",Check,Get<WrapPanel>("UpdateButtons"));Button("Установить",async()=>{await Run("Update","");await Refresh();await Check();},Get<WrapPanel>("UpdateButtons"));
        Button("Сохранить настройки",Save,Get<WrapPanel>("SettingsButtons"));
        Button("Проверить состояние",async()=>{await Refresh();},Get<WrapPanel>("RecoveryButtons"));
        Button("Откатить версию",async()=>{if(MessageBox.Show(window,"Вернуться к предыдущей версии?","Откат",MessageBoxButton.YesNo)!=MessageBoxResult.Yes)return;await Run("Rollback","");LoadSettings();await Refresh();},Get<WrapPanel>("RecoveryButtons"));
        Button("Панель Windows",async()=>{await Run("RestoreTaskbar","");},Get<WrapPanel>("RecoveryButtons"));
        Button("Открыть копии",()=>{Process.Start("explorer.exe",Quote(Path.Combine(root,"backups")));return Task.FromResult(0);},Get<WrapPanel>("RecoveryButtons"));
        Button("Сравнить конфиги",Compare,Get<WrapPanel>("RecoveryButtons"));
        Button("Удалить окружение",async()=>{if(MessageBox.Show(window,"Восстановить исходные конфиги и отключить сборку? Резервные копии сохранятся.","Удаление",MessageBoxButton.YesNo)!=MessageBoxResult.Yes)return;await Run("Uninstall","");string uninstaller=Path.Combine(root,"unins000.exe");if(File.Exists(uninstaller))Process.Start(uninstaller);window.Close();},Get<WrapPanel>("RecoveryButtons"));
        Get<Button>("Browse").Click+=(s,e)=>ChooseBrowser((Button)s);
        window.PreviewKeyDown+=(s,e)=>{if(e.Key==System.Windows.Input.Key.Escape)window.Close();};
        window.SourceInitialized+=(s,e)=>{int dark=1;DwmSetWindowAttribute(new WindowInteropHelper(window).Handle,20,ref dark,4);};
        LoadSettings();if(autoRefresh)window.Loaded+=async(s,e)=>await Busy(Refresh);
    }
    static async Task Logon(){
        var s=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));
        if(s.autostart)await Run("Start","");if(!s.checkAtLogon)return;
        var u=await Run("Check","");if(!Equals(u["available"],true))return;
        using(var icon=new System.Windows.Forms.NotifyIcon{Icon=System.Drawing.SystemIcons.Information,Visible=true,BalloonTipTitle="Rose Pine Desktop",BalloonTipText="Доступна версия "+u["version"]+". Открой центр управления для установки."}){
            icon.BalloonTipClicked+=(s1,e)=>Process.Start(Path.Combine(root,"RosePineCenter.exe"));icon.ShowBalloonTip(15000);
            var end=DateTime.UtcNow.AddSeconds(20);while(DateTime.UtcNow<end){System.Windows.Forms.Application.DoEvents();await Task.Delay(100);}
        }
    }
    [STAThread] static int Main(string[] args){
        root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"RosePineDesktop");
        for(int i=0;i<args.Length-1;i++)if(args[i]=="--root")root=args[++i];
        try{
            if(Array.IndexOf(args,"--self-test")>=0){var test=json.Deserialize<Settings>("{\"components\":[\"desktop\"],\"workspaces\":[]}");if(test.components[0]!="desktop")throw new Exception("JSON");var data=json.Deserialize<Dictionary<string,object>>("{\"backups\":[\"first\"],\"conflicts\":[],\"modified\":[]}");int count=0;foreach(object item in (IEnumerable)data["backups"])count++;if(count!=1)throw new Exception("Backup lists");return 0;}
            foreach(var pair in new[]{new[]{"--console","Console"},new[]{"--files","Files"},new[]{"--browser","Browser"},new[]{"--restore-taskbar","RestoreTaskbar"}})if(Array.IndexOf(args,pair[0])>=0){Task.Run(()=>Run(pair[1],"")).GetAwaiter().GetResult();return 0;}
            if(Array.IndexOf(args,"--logon")>=0){Task.Run(()=>Logon()).GetAwaiter().GetResult();return 0;}
            var app=new Application();var center=new Center();center.Build(Array.IndexOf(args,"--smoke-test")<0);
            int smoke=Array.IndexOf(args,"--smoke-test");
            if(smoke>=0){
                var installed=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,"installed.json")));if(!Equals(installed["sandbox"],true))throw new Exception("Smoke test requires sandbox installation");
                center.window.Loaded+=async(s,e)=>{try{await center.Refresh();var tabs=center.Get<TabControl>("Tabs");for(int i=0;i<tabs.Items.Count;i++){tabs.SelectedIndex=i;center.window.UpdateLayout();}if(((ObservableCollection<Space>)center.spaces.ItemsSource).Count!=9)throw new Exception("Workspaces missing");File.WriteAllText(args[smoke+1],json.Serialize(new{ok=true,tabs=tabs.Items.Count,backups=center.backups.Items.Count,version=center.version.Text}));}catch(Exception error){File.WriteAllText(args[smoke+1],json.Serialize(new{ok=false,error=error.ToString()}));}finally{center.window.Close();}};
            }
            app.Run(center.window);return 0;
        }catch(Exception e){MessageBox.Show(e.Message,"Rose Pine Desktop");return 1;}
    }
}
