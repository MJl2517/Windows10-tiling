using System;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;
using System.Collections;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows.Data;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Text.RegularExpressions;
using Microsoft.Win32;
class Space {
    public string name{get;set;} public string label{get;set;} public int monitor{get;set;}
    [ScriptIgnore] public string shortcut{get;set;}
    [ScriptIgnore] public int displayMonitor{get{return monitor+1;}set{monitor=value-1;}}
}
class ShortcutRow {public string id{get;set;} public string group{get;set;} public string title{get;set;} public string text{get;set;}}
class Settings {
    public string[] components{get;set;} public bool autostart{get;set;} public bool hideTaskbar{get;set;} public bool cursor{get;set;}
    public string browser{get;set;} public Space[] workspaces{get;set;} public string feed{get;set;} public bool checkAtLogon{get;set;} public Dictionary<string,string[]> hotkeys{get;set;}
}
class Center {
    static string root;
    static JavaScriptSerializer json=new JavaScriptSerializer(){MaxJsonLength=16000000};
    Window window;TextBlock status,version,update,health;TextBox feed,browser;DataGrid spaces;
    CheckBox desktop,files,borders,palette,auto,hide,cursor,check;Grid actions;ListBox backups,conflicts;Dictionary<string,object> latest;
    bool loading,dirty,busy,closingAllowed,hotkeysDirty;int monitors=1;string savedFeed="";
    ShortcutDefinition[] definitions;ObservableCollection<ShortcutRow> shortcutRows;DataGrid hotkeys;Dictionary<string,string[]> savedHotkeys;
    string Catalog {get{return Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"shortcuts.json");}}
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
    void Bind(string name,Func<Task> click){Get<Button>(name).Click+=async(s,e)=>await Busy(click);}
    void Say(string text,bool error=false){status.Text=text;status.Foreground=(Brush)window.Resources[error?"ErrorBrush":"StatusBrush"];}
    async Task Busy(Func<Task> f){
        busy=true;actions.IsEnabled=false;Get<ProgressBar>("Progress").Visibility=Visibility.Visible;Say("Выполняется…");
        try{await f();if(status.Text=="Выполняется…")Say("Готово");}
        catch(Exception e){Say(e.Message,true);}
        finally{busy=false;actions.IsEnabled=true;Get<ProgressBar>("Progress").Visibility=Visibility.Collapsed;}
    }
    void Changed(){if(loading)return;dirty=true;Get<Button>("SaveSettings").IsEnabled=true;Get<TextBlock>("SettingsState").Text="Есть несохранённые изменения";Get<TextBlock>("SettingsState").Foreground=new SolidColorBrush(Color.FromRgb(246,193,119));}
    void Clean(){dirty=false;Get<Button>("SaveSettings").IsEnabled=false;Get<TextBlock>("SettingsState").Text="Все изменения сохранены";Get<TextBlock>("SettingsState").Foreground=new SolidColorBrush(Color.FromRgb(144,140,170));}
    void SourceChanged(){
        Get<Button>("SaveSource").IsEnabled=feed.Text.Trim()!=savedFeed;
        Get<TextBlock>("SourceStatus").Text=feed.Text.Trim()!=savedFeed?"Источник изменён. Сохрани его перед проверкой обновлений.":savedFeed.Length==0?"Источник не подключён. Укажи адрес выпуска или выбери локальный манифест.":"Используется сохранённый источник. Можно проверить наличие обновлений.";
        Get<Button>("CheckUpdates").IsEnabled=feed.Text.Trim()==savedFeed;
        Get<Button>("InstallUpdate").IsEnabled=feed.Text.Trim()==savedFeed&&latest!=null&&latest.ContainsKey("available")&&Equals(latest["available"],true);
    }
    void BrowserLabel(){Get<TextBlock>("BrowserLabel").Text=browser.Text.Length==0?"Системный браузер":Path.GetFileNameWithoutExtension(browser.Text);}
    void LoadSettings(){
        loading=true;var s=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));
        desktop.IsChecked=Array.IndexOf(s.components,"desktop")>=0;files.IsChecked=Array.IndexOf(s.components,"files")>=0;borders.IsChecked=Array.IndexOf(s.components,"borders")>=0;
        palette.IsChecked=Array.IndexOf(s.components,"palette")>=0;palette.IsEnabled=Convert.ToInt32(Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber","0"))>=19041;
        Get<Button>("OpenPalette").IsEnabled=palette.IsChecked==true;Get<Button>("PaletteSettings").IsEnabled=palette.IsChecked==true;
        auto.IsChecked=s.autostart;hide.IsChecked=s.hideTaskbar;cursor.IsChecked=s.cursor;check.IsChecked=s.checkAtLogon;
        browser.Text=s.browser;savedFeed=s.feed??"";feed.Text=savedFeed;spaces.ItemsSource=new ObservableCollection<Space>(s.workspaces);
        savedHotkeys=s.hotkeys??new Dictionary<string,string[]>();
        shortcutRows=new ObservableCollection<ShortcutRow>(definitions.Select(x=>new ShortcutRow{id=x.id,group=x.group,title=x.title,text=String.Join("; ",DesktopShortcuts.Effective(x,savedHotkeys).Select(DesktopShortcuts.Format))}));hotkeys.ItemsSource=shortcutRows;
        loading=false;Clean();CleanHotkeys();UpdateWorkspaceKeys();BrowserLabel();SourceChanged();FilterHotkeys();
    }
    async Task Refresh(){
        var s=await Run("Status","");version.Text="Версия "+s["version"];monitors=Convert.ToInt32(s["monitors"]);
        Get<TextBlock>("MonitorHint").Text=monitors==1?"Доступен один монитор. Все пространства открываются на нём. Названия редактируются двойным щелчком.":"Мониторов: "+monitors+". Укажи номер от 1 до "+monitors+". Названия редактируются двойным щелчком.";
        backups.Items.Clear();var names=new List<string>();foreach(string name in (IEnumerable)s["backups"])names.Add(name);names.Sort(StringComparer.Ordinal);names.Reverse();foreach(string backup in names){
            string label=backup;var match=Regex.Match(backup,@"(\d{8})-(\d{6})");DateTime date;
            if(match.Success&&DateTime.TryParseExact(match.Groups[1].Value+match.Groups[2].Value,"yyyyMMddHHmmss",System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.None,out date))label=date.ToString("dd.MM.yyyy · HH:mm:ss")+(backup.StartsWith("migration")?" · До переноса":" · Перед изменениями");
            backups.Items.Add(new ListBoxItem{Content=label,Tag=backup,ToolTip=backup});
        }
        Get<TextBlock>("BackupsEmpty").Visibility=backups.Items.Count==0?Visibility.Visible:Visibility.Collapsed;
        conflicts.Items.Clear();conflictFiles.Clear();foreach(var c in (IEnumerable)s["conflicts"]){var d=(Dictionary<string,object>)c;conflictFiles.Add(d);conflicts.Items.Add(new ListBoxItem{Content="Конфликт: "+Path.GetFileName((string)d["target"]),ToolTip=(string)d["target"]});}
        foreach(string m in (IEnumerable)s["modified"])conflicts.Items.Add(new ListBoxItem{Content="Ручные правки: "+Path.GetFileName(m),ToolTip=m});
        Get<TextBlock>("ConflictsEmpty").Visibility=conflicts.Items.Count==0?Visibility.Visible:Visibility.Collapsed;
        Get<Button>("Compare").IsEnabled=false;
        if(s.ContainsKey("checks")){int total=0;var missing=new List<string>();foreach(Dictionary<string,object> item in (IEnumerable)s["checks"]){total++;if(!Equals(item["exists"],true))missing.Add((string)item["name"]);}health.Text=missing.Count==0?"Все необходимые файлы на месте · проверено: "+total:"Не найдены файлы: "+String.Join(", ",missing);}
        if(latest==null)Get<TextBlock>("UpdateTitle").Text=savedFeed.Length==0?"Источник не подключён":"Можно проверить обновления";
        SourceChanged();
    }
    Task Compare(){
        int index=conflicts.SelectedIndex;if(index<0||index>=conflictFiles.Count)return Task.FromResult(0);var item=conflictFiles[index];
        var panel=new Grid();panel.ColumnDefinitions.Add(new ColumnDefinition());panel.ColumnDefinitions.Add(new ColumnDefinition());
        for(int i=0;i<2;i++){string path=(string)item[i==0?"target":"incoming"];var box=new TextBox{Text=(i==0?"Текущий файл: ":"Новый файл: ")+path+"\r\n\r\n"+(File.Exists(path)?File.ReadAllText(path):"Файл отсутствует"),IsReadOnly=true,AcceptsReturn=true,HorizontalScrollBarVisibility=ScrollBarVisibility.Auto,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,FontFamily=new FontFamily("Consolas"),Background=new SolidColorBrush(Color.FromRgb(38,35,58)),Foreground=Brushes.White,Margin=new Thickness(6)};Grid.SetColumn(box,i);panel.Children.Add(box);}
        new Window{Owner=window,Title="Сравнение конфигов",Width=1100,Height=650,Content=panel,Resources=window.Resources,Background=new SolidColorBrush(Color.FromRgb(25,23,36))}.Show();return Task.FromResult(0);
    }
    void ChooseBrowser(Button button){
        var menu=new ContextMenu{PlacementTarget=button,Resources=window.Resources};var system=new MenuItem{Header="Системный браузер"};system.Click+=(s,e)=>browser.Text="";menu.Items.Add(system);
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
        if(!spaces.CommitEdit(DataGridEditingUnit.Cell,true)||!spaces.CommitEdit(DataGridEditingUnit.Row,true))throw new Exception("Проверь значения в таблице рабочих пространств.");
        var components=new List<string>();if(desktop.IsChecked==true)components.Add("desktop");if(files.IsChecked==true)components.Add("files");if(borders.IsChecked==true)components.Add("borders");if(palette.IsChecked==true)components.Add("palette");
        if(components.Count==0)throw new Exception("Выбери хотя бы один компонент");
        if(browser.Text.Length>0&&!File.Exists(browser.Text))throw new Exception("Файл браузера не найден");
        var rows=(ObservableCollection<Space>)spaces.ItemsSource;foreach(var row in rows){if(String.IsNullOrWhiteSpace(row.label)||row.label.Contains("\n"))throw new Exception("Укажи название рабочего пространства");if(row.monitor<0||row.monitor>=monitors)throw new Exception("Номер монитора должен быть от 1 до "+monitors);}
        var s=new Settings{components=components.ToArray(),autostart=auto.IsChecked==true,hideTaskbar=hide.IsChecked==true,cursor=cursor.IsChecked==true,checkAtLogon=check.IsChecked==true,browser=browser.Text,feed=savedFeed,hotkeys=savedHotkeys,workspaces=new List<Space>(rows).ToArray()};
        await ApplySettings(s);Get<Button>("OpenPalette").IsEnabled=palette.IsChecked==true;Get<Button>("PaletteSettings").IsEnabled=palette.IsChecked==true;Clean();Say("Настройки сохранены. Новые параметры терминала применятся при следующем запуске.");
    }
    void HotkeysChanged(){if(loading)return;hotkeysDirty=true;Get<Button>("SaveHotkeys").IsEnabled=true;Get<TextBlock>("HotkeysState").Text="Есть несохранённые сочетания";Get<TextBlock>("HotkeysState").Foreground=new SolidColorBrush(Color.FromRgb(246,193,119));}
    void CleanHotkeys(){hotkeysDirty=false;Get<Button>("SaveHotkeys").IsEnabled=false;Get<TextBlock>("HotkeysState").Text="Все сочетания сохранены";Get<TextBlock>("HotkeysState").Foreground=new SolidColorBrush(Color.FromRgb(144,140,170));}
    void UpdateWorkspaceKeys(){
        foreach(Space space in (IEnumerable)spaces.ItemsSource){var item=definitions.FirstOrDefault(x=>x.id=="workspace-"+space.name);space.shortcut=item==null?"—":String.Join("; ",DesktopShortcuts.Effective(item,savedHotkeys).Select(DesktopShortcuts.Format));}spaces.Items.Refresh();
    }
    void FilterHotkeys(){
        if(shortcutRows==null)return;if(!hotkeys.CommitEdit(DataGridEditingUnit.Cell,true)||!hotkeys.CommitEdit(DataGridEditingUnit.Row,true))return;string search=Get<TextBox>("HotkeySearch").Text.Trim();var view=CollectionViewSource.GetDefaultView(shortcutRows);
        view.Filter=item=>{var row=(ShortcutRow)item;return (row.group+" "+row.title+" "+row.text).IndexOf(search,StringComparison.CurrentCultureIgnoreCase)>=0;};
        Get<TextBlock>("HotkeysEmpty").Visibility=view.IsEmpty?Visibility.Visible:Visibility.Collapsed;
    }
    Dictionary<string,string[]> DraftHotkeys(){
        if(!hotkeys.CommitEdit(DataGridEditingUnit.Cell,true)||!hotkeys.CommitEdit(DataGridEditingUnit.Row,true))throw new Exception("Заверши ввод сочетания.");
        var result=new Dictionary<string,string[]>(savedHotkeys);
        foreach(var row in shortcutRows){var item=definitions.First(x=>x.id==row.id);string[] keys=DesktopShortcuts.Parse(row.text);if(keys.SequenceEqual(item.bindings.Select(DesktopShortcuts.Normalize)))result.Remove(row.id);else result[row.id]=keys;}
        DesktopShortcuts.Validate(definitions,result);return result;
    }
    async Task SaveHotkeys(){
        var draft=DraftHotkeys();var s=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));s.hotkeys=draft;await ApplySettings(s);savedHotkeys=draft;
        foreach(var row in shortcutRows){var item=definitions.First(x=>x.id==row.id);row.text=String.Join("; ",DesktopShortcuts.Effective(item,savedHotkeys).Select(DesktopShortcuts.Format));}
        hotkeys.Items.Refresh();CleanHotkeys();UpdateWorkspaceKeys();Say("Сочетания сохранены и применены. Подсказка обновлена; открой её заново, если она уже была открыта.");
    }
    Task ResetHotkey(){var row=hotkeys.SelectedItem as ShortcutRow;if(row!=null){hotkeys.CancelEdit(DataGridEditingUnit.Cell);hotkeys.CancelEdit(DataGridEditingUnit.Row);row.text=String.Join("; ",definitions.First(x=>x.id==row.id).bindings.Select(DesktopShortcuts.Format));hotkeys.Items.Refresh();HotkeysChanged();}return Task.FromResult(0);}
    Task ResetHotkeys(){
        if(!Confirm("Сбросить все сочетания?","Будут выбраны стандартные сочетания окружения. Изменения применятся только после нажатия «Сохранить сочетания».","Сбросить сочетания",false))return Task.FromResult(0);
        hotkeys.CancelEdit(DataGridEditingUnit.Cell);hotkeys.CancelEdit(DataGridEditingUnit.Row);
        foreach(var row in shortcutRows)row.text=String.Join("; ",definitions.First(x=>x.id==row.id).bindings.Select(DesktopShortcuts.Format));hotkeys.Items.Refresh();HotkeysChanged();return Task.FromResult(0);
    }
    async Task ApplySettings(Settings s){
        var request=Path.Combine(root,"requests","settings-"+Guid.NewGuid().ToString("N")+".json");Directory.CreateDirectory(Path.GetDirectoryName(request));File.WriteAllText(request,json.Serialize(s));
        try{await Run("Apply","-SettingsFile "+Quote(request));await Run("Start","");await Refresh();}finally{File.Delete(request);}
    }
    async Task Rollback(){await Run("Rollback","");await Refresh();Say("Предыдущая версия восстановлена. Открой центр заново.");}
    async Task SaveSource(){
        string source=feed.Text.Trim();Uri address;
        if(source.Length>0&&!Path.IsPathRooted(source)&&(!Uri.TryCreate(source,UriKind.Absolute,out address)||address.Scheme!="https"))throw new Exception("Укажи HTTPS-адрес манифеста или полный путь к локальному файлу.");
        if(Path.IsPathRooted(source)&&!File.Exists(source))throw new Exception("Локальный манифест не найден. Проверь путь или выбери файл.");
        var s=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));s.feed=source;await ApplySettings(s);savedFeed=s.feed;latest=null;SourceChanged();
        update.Text=savedFeed.Length==0?"Подключи источник выпусков, чтобы получать обновления.":"Источник сохранён. Проверь наличие обновлений.";
        Get<TextBlock>("UpdateTitle").Text=savedFeed.Length==0?"Источник не подключён":"Источник настроен";Say("Источник обновлений сохранён.");
    }
    async Task Check(){
        latest=null;Get<Button>("InstallUpdate").IsEnabled=false;latest=await Run("Check","");bool available=Equals(latest["available"],true);
        Get<TextBlock>("UpdateTitle").Text=available?"Доступна версия "+latest["version"]:savedFeed.Length==0?"Источник не подключён":"Установлена актуальная версия";
        update.Text=(string)latest["message"];if(latest.ContainsKey("notes"))update.Text+="\n\n"+(string)latest["notes"];SourceChanged();
    }
    bool Confirm(string title,string text,string action,bool danger){
        var panel=new StackPanel{Margin=new Thickness(26)};panel.Children.Add(new TextBlock{Text=title,FontSize=22,FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,0,0,14)});panel.Children.Add(new TextBlock{Text=text,TextWrapping=TextWrapping.Wrap});
        var buttons=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,20,0,0)};panel.Children.Add(buttons);
        var dialog=new Window{Owner=window,Title=title,Width=520,SizeToContent=SizeToContent.Height,ResizeMode=ResizeMode.NoResize,WindowStartupLocation=WindowStartupLocation.CenterOwner,Background=window.Background,Foreground=window.Foreground,FontFamily=window.FontFamily,FontSize=14,Resources=window.Resources,Content=panel};
        var cancel=new Button{Content="Отмена",IsCancel=true};var accept=new Button{Content=action,Style=(Style)window.Resources[danger?"Danger":"Primary"]};cancel.Click+=(s,e)=>dialog.DialogResult=false;accept.Click+=(s,e)=>dialog.DialogResult=true;buttons.Children.Add(cancel);buttons.Children.Add(accept);cancel.Focus();
        dialog.SourceInitialized+=(s,e)=>{int dark=1;DwmSetWindowAttribute(new WindowInteropHelper(dialog).Handle,20,ref dark,4);};return dialog.ShowDialog()==true;
    }
    void Build(bool autoRefresh=true){
        using(var stream=typeof(Center).Assembly.GetManifestResourceStream("Center.xaml"))window=(Window)XamlReader.Load(stream);
        window.Resources["StatusBrush"]=new SolidColorBrush(Color.FromRgb(156,207,216));window.Resources["ErrorBrush"]=new SolidColorBrush(Color.FromRgb(235,111,146));
        version=Get<TextBlock>("Version");status=Get<TextBlock>("Status");update=Get<TextBlock>("Update");feed=Get<TextBox>("Feed");browser=Get<TextBox>("Browser");spaces=Get<DataGrid>("Spaces");actions=Get<Grid>("Actions");backups=Get<ListBox>("Backups");conflicts=Get<ListBox>("Conflicts");health=Get<TextBlock>("Health");
        definitions=DesktopShortcuts.Load(Catalog);hotkeys=Get<DataGrid>("Hotkeys");
        desktop=Get<CheckBox>("Desktop");files=Get<CheckBox>("Files");borders=Get<CheckBox>("Borders");palette=Get<CheckBox>("Palette");auto=Get<CheckBox>("Auto");hide=Get<CheckBox>("Hide");cursor=Get<CheckBox>("Cursor");check=Get<CheckBox>("Check");
        Bind("OpenPalette",async()=>{await Run("Palette","");Say("Палитра открыта. Если она отключена, включи Command Palette в настройках PowerToys.");});
        Bind("PaletteSettings",async()=>{await Run("Palette","-PaletteSettings");Say("Открыты настройки палитры: сочетание клавиш и оформление.");});
        Bind("CheckUpdates",Check);Bind("InstallUpdate",async()=>{await Run("Update","");await Refresh();await Check();Say("Обновление установлено. Новая версия центра откроется при следующем запуске.");});
        Bind("SaveHotkeys",SaveHotkeys);Bind("ResetHotkey",ResetHotkey);Bind("ResetHotkeys",ResetHotkeys);
        Bind("SaveSource",SaveSource);Bind("SaveSettings",Save);Bind("CheckHealth",Refresh);
        Bind("StartDesktop",async()=>{await Run("Start","");Say("Включённые компоненты запущены с сохранёнными настройками.");});
        Bind("Rollback",async()=>{if(!Confirm("Вернуть предыдущую версию?","Окружение вернётся к предыдущему выпуску. Текущие личные настройки сохранятся.","Вернуть версию",false))return;await Rollback();});
        Bind("RestoreTaskbar",async()=>{await Run("RestoreTaskbar","");Say("Панель Windows показана. Чтобы оставить её, отключи скрытие в настройках.");});
        Bind("OpenBackups",()=>{string folder=Path.Combine(root,"backups");Directory.CreateDirectory(folder);Process.Start("explorer.exe",Quote(folder));return Task.FromResult(0);});
        Bind("Compare",Compare);
        Bind("Uninstall",async()=>{if(!Confirm("Удалить Rose Pine Desktop?","Будут восстановлены исходные конфиги и системные настройки. Резервные копии и ранее установленные приложения сохранятся.","Удалить окружение",true))return;await Run("Uninstall","");dirty=false;hotkeysDirty=false;feed.Text=savedFeed;closingAllowed=true;string uninstaller=Path.Combine(root,"unins000.exe");if(File.Exists(uninstaller))Process.Start(uninstaller);window.Close();});
        Get<Button>("Browse").Click+=(s,e)=>ChooseBrowser((Button)s);
        Get<Button>("PickSource").Click+=(s,e)=>{var dialog=new OpenFileDialog{Filter="Манифест выпуска (*.json)|*.json|Все файлы|*.*"};if(dialog.ShowDialog(window)==true)feed.Text=dialog.FileName;};
        foreach(var box in new[]{desktop,files,borders,palette,auto,hide,cursor,check})box.Click+=(s,e)=>Changed();
        browser.TextChanged+=(s,e)=>{BrowserLabel();Changed();};feed.TextChanged+=(s,e)=>SourceChanged();
        Get<TextBox>("HotkeySearch").TextChanged+=(s,e)=>FilterHotkeys();
        hotkeys.CellEditEnding+=(s,e)=>{if(e.EditAction==DataGridEditAction.Commit)HotkeysChanged();};
        hotkeys.SelectionChanged+=(s,e)=>Get<Button>("ResetHotkey").IsEnabled=hotkeys.SelectedItem!=null;
        spaces.CellEditEnding+=(s,e)=>{if(e.EditAction==DataGridEditAction.Commit)Changed();};
        conflicts.SelectionChanged+=(s,e)=>Get<Button>("Compare").IsEnabled=conflicts.SelectedIndex>=0&&conflicts.SelectedIndex<conflictFiles.Count;
        window.PreviewKeyDown+=(s,e)=>{if(e.Key==System.Windows.Input.Key.Escape&&!busy&&!(e.OriginalSource is TextBox))window.Close();};
        window.Closing+=(s,e)=>{if(busy&&!closingAllowed){e.Cancel=true;return;}if((dirty||hotkeysDirty||feed.Text.Trim()!=savedFeed)&&!Confirm("Изменения не сохранены","Закрыть центр и отменить несохранённые изменения?","Закрыть без сохранения",false))e.Cancel=true;};
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
            foreach(var pair in new[]{new[]{"--console","Console"},new[]{"--files","Files"},new[]{"--browser","Browser"},new[]{"--palette","Palette"},new[]{"--restore-taskbar","RestoreTaskbar"}})if(Array.IndexOf(args,pair[0])>=0){Task.Run(()=>Run(pair[1],"")).GetAwaiter().GetResult();return 0;}
            if(Array.IndexOf(args,"--logon")>=0){Task.Run(()=>Logon()).GetAwaiter().GetResult();return 0;}
            var app=new Application();var center=new Center();center.Build(Array.IndexOf(args,"--smoke-test")<0);if(Array.IndexOf(args,"--hotkeys")>=0)center.Get<TabControl>("Tabs").SelectedIndex=2;
            int smoke=Array.IndexOf(args,"--smoke-test");
            if(smoke>=0){
                var installed=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,"installed.json")));if(!Equals(installed["sandbox"],true))throw new Exception("Smoke test requires sandbox installation");
                center.window.Loaded+=async(s,e)=>{
                    try{
                        await center.Refresh();var tabs=center.Get<TabControl>("Tabs");if(tabs.SelectedIndex!=0)throw new Exception("Initial page missing");
                        foreach(int width in new[]{1080,920}){center.window.Width=width;for(int i=0;i<tabs.Items.Count;i++){tabs.SelectedIndex=i;center.window.UpdateLayout();if(((TabItem)tabs.Items[i]).ActualWidth<100)throw new Exception("Navigation clipped");var host=(ContentPresenter)tabs.Template.FindName("PART_SelectedContentHost",tabs);if(host==null||host.Content==null||host.ActualWidth<500)throw new Exception("Page content missing");}}
                        if(((ObservableCollection<Space>)center.spaces.ItemsSource).Count!=9)throw new Exception("Workspaces missing");
                        if(center.Get<Button>("InstallUpdate").IsEnabled||center.Get<Button>("SaveSettings").IsEnabled)throw new Exception("Initial action state");
                        if(center.palette.IsChecked!=true||!center.Get<Button>("OpenPalette").IsEnabled||!center.Get<Button>("PaletteSettings").IsEnabled)throw new Exception("Palette component state");
                        string original=center.feed.Text;center.feed.Text="https://example.test/release.json";
                        if(!center.Get<Button>("SaveSource").IsEnabled||center.Get<Button>("CheckUpdates").IsEnabled)throw new Exception("Unsaved source state");
                        center.feed.Text=original;center.Changed();if(!center.dirty||!center.Get<Button>("SaveSettings").IsEnabled)throw new Exception("Dirty settings");center.Clean();
                        center.latest=json.Deserialize<Dictionary<string,object>>("{\"available\":true}");center.SourceChanged();if(!center.Get<Button>("InstallUpdate").IsEnabled)throw new Exception("Available update state");center.latest=null;center.SourceChanged();
                        await center.Busy(()=>{throw new Exception("test error");});if(center.status.Text!="test error"||!center.actions.IsEnabled)throw new Exception("Error state");
                        await center.Busy(()=>{center.Say("test success");return Task.FromResult(0);});if(center.status.Text!="test success")throw new Exception("Success overwritten");
                        var row=new Space{name="7",monitor=0};if(row.displayMonitor!=1)throw new Exception("Workspace labels");row.displayMonitor=2;if(row.monitor!=1||json.Serialize(row).Contains("displayMonitor"))throw new Exception("Monitor storage");
                        if(center.shortcutRows.Count!=49||center.Get<Button>("SaveHotkeys").IsEnabled)throw new Exception("Hotkeys initial state");
                        center.Get<TextBox>("HotkeySearch").Text="браузер";if(center.hotkeys.Items.Count!=1)throw new Exception("Hotkey search");center.Get<TextBox>("HotkeySearch").Text="no-such-action";if(center.Get<TextBlock>("HotkeysEmpty").Visibility!=Visibility.Visible)throw new Exception("Hotkey empty state");center.Get<TextBox>("HotkeySearch").Text="";
                        var browserKey=center.shortcutRows.First(x=>x.id=="browser");browserKey.text="Alt+E";center.HotkeysChanged();string settingsBefore=File.ReadAllText(Path.Combine(root,"settings.json"));
                        await center.Busy(center.SaveHotkeys);if(!center.status.Text.Contains("повторяется")||File.ReadAllText(Path.Combine(root,"settings.json"))!=settingsBefore||!center.hotkeysDirty)throw new Exception("Shortcut conflict state");browserKey.text="Alt+F6";
                        // This mode only runs against an explicitly sandboxed installation.
                        string fixture=Path.Combine(root,"ui-feed.json");File.WriteAllText(fixture,json.Serialize(new{schema=1,version="99.0.0",url="unused.zip",sha256=new String('0',64),notes="UI test"}));
                        bool oldAuto=center.auto.IsChecked==true;center.auto.IsChecked=!oldAuto;center.Changed();center.feed.Text=fixture;await center.SaveSource();
                        var saved=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));if(saved.feed!=fixture||saved.autostart!=oldAuto||center.auto.IsChecked==oldAuto||!center.dirty)throw new Exception("Source save lost setting drafts");
                        await center.Check();if(!center.Get<Button>("InstallUpdate").IsEnabled||!center.update.Text.Contains("UI test"))throw new Exception("Update check state");
                        await center.Save();saved=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));if(saved.autostart==oldAuto||center.dirty||center.Get<Button>("SaveSettings").IsEnabled)throw new Exception("Settings save failed");
                        if(!saved.components.Contains("palette"))throw new Exception("Palette selection lost");await Run("Palette","");await Run("Palette","-PaletteSettings");
                        if(!center.hotkeysDirty||browserKey.text!="Alt+F6")throw new Exception("Settings save lost shortcut draft");
                        await center.SaveHotkeys();saved=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));if(saved.hotkeys["browser"][0]!="alt+f6"||center.hotkeysDirty)throw new Exception("Hotkey save failed");
                        tabs.SelectedIndex=2;center.hotkeys.SelectedItem=browserKey;center.hotkeys.CurrentCell=new DataGridCellInfo(browserKey,center.hotkeys.Columns[2]);center.hotkeys.ScrollIntoView(browserKey);center.window.UpdateLayout();if(!center.hotkeys.BeginEdit())throw new Exception("Shortcut edit did not start");await center.ResetHotkey();await center.SaveHotkeys();saved=json.Deserialize<Settings>(File.ReadAllText(Path.Combine(root,"settings.json")));if(saved.hotkeys.ContainsKey("browser"))throw new Exception("Hotkey reset failed");
                        center.feed.Text="https://example.test/draft.json";center.auto.IsChecked=oldAuto;center.Changed();browserKey.text="Alt+F7";center.HotkeysChanged();
                        await center.Rollback();if(!center.dirty||!center.hotkeysDirty||browserKey.text!="Alt+F7"||center.auto.IsChecked!=oldAuto||center.feed.Text!="https://example.test/draft.json")throw new Exception("Rollback lost drafts");
                        File.WriteAllText(args[smoke+1],json.Serialize(new{ok=true,tabs=tabs.Items.Count,widths=new[]{1080,920},states=20,shortcuts=center.shortcutRows.Count,backups=center.backups.Items.Count,version=center.version.Text}));
                    }catch(Exception error){File.WriteAllText(args[smoke+1],json.Serialize(new{ok=false,error=error.ToString()}));}
                    finally{center.dirty=false;center.hotkeysDirty=false;center.feed.Text=center.savedFeed;center.window.Close();}
                };
            }
            app.Run(center.window);return 0;
        }catch(Exception e){MessageBox.Show(e.Message,"Rose Pine Desktop");return 1;}
    }
}
