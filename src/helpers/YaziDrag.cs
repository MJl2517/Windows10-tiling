using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

static class YaziDrag {
    const string Title = "Yazi — Перетаскивание файлов";
    static Brush Color(string hex) { return (Brush)new BrushConverter().ConvertFromString(hex); }
    static TextBlock Text(string text, double size, string color) {
        return new TextBlock { Text=text, FontSize=size, Foreground=Color(color), TextWrapping=TextWrapping.Wrap };
    }
    static string[] Validate(string[] paths) {
        if(paths==null || paths.Length==0) throw new ArgumentException("В Yazi не выбран ни один файл.");
        var files=new List<string>(); var unique=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var value in paths) {
            if(String.IsNullOrWhiteSpace(value)) throw new ArgumentException("Пустой путь к файлу.");
            var path=Path.GetFullPath(value);
            if(!File.Exists(path) && !Directory.Exists(path)) throw new FileNotFoundException("Файл больше не существует: "+path);
            if(unique.Add(path)) files.Add(path);
        }
        return files.ToArray();
    }
    static DataObject FilesData(string[] files) {
        var data=new DataObject();
        data.SetData(DataFormats.FileDrop, files);
        data.SetData("Preferred DropEffect",new MemoryStream(BitConverter.GetBytes((int)DragDropEffects.Copy)));
        return data;
    }
    static string[] ReadSelection(Stream input) {
        using(var reader=new StreamReader(input,new UTF8Encoding(false,true)))
            return new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue}.Deserialize<string[]>(reader.ReadLine() ?? "[]");
    }
    static Window CreateWindow(string[] files) {
        var window=new Window {Title=Title, Width=490, Height=350, MinWidth=380, MinHeight=280,
            WindowStyle=WindowStyle.None, ResizeMode=ResizeMode.NoResize, AllowsTransparency=true,
            Background=Brushes.Transparent, WindowStartupLocation=WindowStartupLocation.CenterScreen,
            FontFamily=new FontFamily("Segoe UI"), ShowInTaskbar=true};
        var frame=new Border {Background=Color("#191724"),BorderBrush=Color("#6e6a86"),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(14),Padding=new Thickness(20)};
        var layout=new Grid();
        layout.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
        layout.RowDefinitions.Add(new RowDefinition {Height=new GridLength(1,GridUnitType.Star)});
        layout.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
        frame.Child=layout; window.Content=frame;
        var header=new DockPanel {Margin=new Thickness(0,0,0,16)};
        var close=new Button {Content="×",Width=30,Height=28,FontSize=21,Foreground=Color("#e0def4"),Background=Brushes.Transparent,BorderThickness=new Thickness(0),ToolTip="Закрыть (Esc)"};
        System.Windows.Automation.AutomationProperties.SetName(close,"Закрыть");
        close.Click+=(s,e)=>window.Close(); DockPanel.SetDock(close,Dock.Right); header.Children.Add(close);
        var heading=Text("Перетащить в браузер",19,"#e0def4"); heading.FontWeight=FontWeights.SemiBold;
        heading.MouseLeftButtonDown+=(s,e)=>{if(e.ButtonState==MouseButtonState.Pressed)window.DragMove();};
        header.Children.Add(heading); layout.Children.Add(header);
        var area=new Border {Background=Color("#26233a"),BorderBrush=Color("#c4a7e7"),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(10),Padding=new Thickness(18),Cursor=Cursors.Hand};
        Grid.SetRow(area,1); layout.Children.Add(area);
        var content=new Grid(); content.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto}); content.RowDefinitions.Add(new RowDefinition {Height=new GridLength(1,GridUnitType.Star)}); area.Child=content;
        var count=Text("Файлов: "+files.Length+"   ·   Зажми здесь левую кнопку мыши",14,"#c4a7e7"); count.Margin=new Thickness(0,0,0,12); content.Children.Add(count);
        var list=new StackPanel();
        foreach(var file in files) {
            var item=Text(Path.GetFileName(file.TrimEnd(Path.DirectorySeparatorChar)) ,14,"#e0def4");
            item.Margin=new Thickness(0,3,0,3); item.TextWrapping=TextWrapping.NoWrap; item.TextTrimming=TextTrimming.CharacterEllipsis; item.ToolTip=file; list.Children.Add(item);
        }
        var scroll=new ScrollViewer {Content=list,VerticalScrollBarVisibility=ScrollBarVisibility.Auto}; Grid.SetRow(scroll,1); content.Children.Add(scroll);
        var status=Text("Перетащи блок с файлами в область загрузки сайта.\nEsc — отменить",12,"#908caa"); status.Margin=new Thickness(0,14,0,0); Grid.SetRow(status,2); layout.Children.Add(status);
        Point? start=null; bool dragging=false,escaped=false;
        area.PreviewMouseLeftButtonDown+=(s,e)=>{start=e.GetPosition(area);};
        area.PreviewMouseLeftButtonUp+=(s,e)=>{start=null;};
        area.PreviewMouseMove+=(s,e)=>{
            if(dragging || start==null || e.LeftButton!=MouseButtonState.Pressed)return;
            var point=e.GetPosition(area); var delta=point-start.Value;
            if(Math.Abs(delta.X)<SystemParameters.MinimumHorizontalDragDistance && Math.Abs(delta.Y)<SystemParameters.MinimumVerticalDragDistance)return;
            start=null; dragging=true; escaped=false;
            try {
                var effect=DragDrop.DoDragDrop(area,FilesData(files),DragDropEffects.Copy);
                if(effect!=DragDropEffects.None || escaped)window.Close();
                else status.Text="Сайт не принял файлы. Перетащи их в область загрузки ещё раз.\nEsc — закрыть";
            } catch(Exception error) {status.Text="Не удалось начать перетаскивание: "+error.Message;}
            finally {dragging=false;}
        };
        area.QueryContinueDrag+=(s,e)=>{if(e.EscapePressed){escaped=true;e.Action=DragAction.Cancel;}};
        window.PreviewKeyDown+=(s,e)=>{if(e.Key==Key.Escape && !dragging){e.Handled=true;window.Close();}};
        return window;
    }
    static void SelfTest() {
        var folder=Path.Combine(Path.GetTempPath(),"yazi-drag-check-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
        try {
            var first=Path.Combine(folder,"Файл & пробел % test.txt"); var second=Path.Combine(folder,"second.txt");
            File.WriteAllText(first,"first"); File.WriteAllText(second,"second");
            var files=Validate(new[]{first,second,first});
            var data=FilesData(files); var actual=(string[])data.GetData(DataFormats.FileDrop);
            if(actual.Length!=2 || actual[0]!=first || actual[1]!=second)throw new Exception("FileDrop roundtrip failed");
            var stream=(MemoryStream)data.GetData("Preferred DropEffect");
            if(BitConverter.ToInt32(stream.ToArray(),0)!=(int)DragDropEffects.Copy)throw new Exception("Copy effect check failed");
            bool rejected=false; try {Validate(new[]{Path.Combine(folder,"missing.txt")});}catch(FileNotFoundException){rejected=true;}
            if(!rejected)throw new Exception("Missing file check failed");
            var serializer=new JavaScriptSerializer();
            if(Validate(ReadSelection(new MemoryStream(Encoding.UTF8.GetBytes(serializer.Serialize(files))))).Length!=2)throw new Exception("Selection UTF8 stream roundtrip failed");
        } finally {foreach(var file in Directory.GetFiles(folder))File.Delete(file);Directory.Delete(folder);}
    }
    [STAThread] static int Main(string[] args) {
        try {
            if(args.Length==1 && args[0]=="--self-test"){SelfTest();return 0;}
            if(args.Length==1 && args[0]=="--stdin") {
                args=ReadSelection(Console.OpenStandardInput());
            }
            var files=Validate(args);
            new Application().Run(CreateWindow(files)); return 0;
        } catch(Exception error) {
            try {File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"yazi-drag-error.log"),DateTime.Now.ToString("o")+" "+error); }catch{}
            if(args!=null && args.Length==1 && args[0]=="--self-test")return 1;
            MessageBox.Show(error.Message,Title,MessageBoxButton.OK,MessageBoxImage.Information); return 1;
        }
    }
}
