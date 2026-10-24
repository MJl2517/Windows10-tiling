param(
    [switch]$Choose,
    [switch]$ListApps,
    [switch]$SelfTest,
    [switch]$Server,
    [string]$PreviewPath,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Files
)
$ErrorActionPreference = 'Stop'
if ($Server) {
    $serverMutex = New-Object Threading.Mutex($false, ('Local\YaziOpenWith-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    if (-not $serverMutex.WaitOne(0)) { $serverMutex.Dispose(); return }
    $Files = @()
}

$statePath = Join-Path $PSScriptRoot 'open-with-history.json'

function Get-UsageState {
    if (Test-Path -LiteralPath $statePath) {
        try { return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { }
    }
    [pscustomobject]@{ usage=[pscustomobject]@{}; customApps=@() }
}
function Get-AppId([string]$Path) { $Path.ToLowerInvariant() }
function Get-AppCatalog($State) {
    $apps = @{}
    $apps['default'] = [pscustomobject]@{Id='default'; Name='Приложение по умолчанию Windows'; Path=''}
    function Add-App([string]$Name, [string]$Path) {
        $Path = [Environment]::ExpandEnvironmentVariables($Path).Trim('"')
        if ($Path -and $Path.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $id = Get-AppId $Path
            if (-not $apps.ContainsKey($id)) { $apps[$id]=[pscustomobject]@{Id=$id; Name=$Name; Path=$Path} }
        }
    }
    foreach ($app in $State.customApps) { Add-App $app.Name $app.Path }
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($root in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))) {
        Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $shortcut = $wsh.CreateShortcut($_.FullName)
            if ($_.BaseName -notmatch '(?i)uninstall|удалени|help|справка') { Add-App $_.BaseName $shortcut.TargetPath }
        }
    }
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')) {
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $path = $_.GetValue('')
            if ($path -is [string]) { Add-App ([IO.Path]::GetFileNameWithoutExtension($_.PSChildName)) $path }
        }
    }
    Add-App 'Блокнот' (Join-Path $env:WINDIR 'System32\notepad.exe')
    Add-App 'Paint' (Join-Path $env:WINDIR 'System32\mspaint.exe')
    return @($apps.Values)
}
function Get-RankedApps($Apps, $State, [string]$Query='') {
    $Apps | Where-Object { -not $Query -or $_.Name.IndexOf($Query,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Path.IndexOf($Query,[StringComparison]::OrdinalIgnoreCase) -ge 0 } |
        Sort-Object @{Expression={ $u=$State.usage.PSObject.Properties[$_.Id]; if($u){[int]$u.Value.count}else{0} };Descending=$true},
                    @{Expression={ $u=$State.usage.PSObject.Properties[$_.Id]; if($u){[string]$u.Value.lastUsed}else{''} };Descending=$true}, Name
}
function Save-AppUse($App, $State, [switch]$Custom) {
    $old = $State.usage.PSObject.Properties[$App.Id]
    $count = if($old){[int]$old.Value.count}else{0}
    $State.usage | Add-Member -NotePropertyName $App.Id -NotePropertyValue ([pscustomobject]@{count=$count+1;lastUsed=[DateTime]::UtcNow.ToString('o')}) -Force
    if ($Custom -and $App.Id -notin @($State.customApps | ForEach-Object Id)) { $State.customApps=@($State.customApps)+@($App) }
    $json=$State | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($statePath+'.tmp',$json,(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath ($statePath+'.tmp') -Destination $statePath -Force
}
function Open-InApp($App, [string[]]$Paths) {
    if($App.Id -eq 'default') {
        foreach($path in $Paths) {
            $info=New-Object Diagnostics.ProcessStartInfo
            $info.FileName=$path
            $info.UseShellExecute=$true
            [Diagnostics.Process]::Start($info) | Out-Null
        }
    } else {
        $arguments=@($Paths | ForEach-Object {
            $trimmed=$_.TrimEnd('\')
            '"'+$trimmed+('\'*(2*($_.Length-$trimmed.Length)))+'"'
        }) -join ' '
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=$App.Path
        $info.Arguments=$arguments
        $info.UseShellExecute=$true
        [Diagnostics.Process]::Start($info) | Out-Null
    }
}
if($SelfTest) {
    $testState=[pscustomobject]@{usage=[pscustomobject]@{b=[pscustomobject]@{count=4;lastUsed='2026-01-01'}};customApps=@()}
    $testApps=@([pscustomobject]@{Id='a';Name='Alpha';Path='C:\alpha.exe'},[pscustomobject]@{Id='b';Name='Zen Browser';Path='C:\zen.exe'})
    if(@(Get-RankedApps $testApps $testState)[0].Id -ne 'b') { throw 'Frequency ordering failed' }
    if(@(Get-RankedApps $testApps $testState 'ZEN').Count -ne 1) { throw 'Case-insensitive search failed' }
    if(@(Get-RankedApps $testApps $testState 'missing').Count -ne 0) { throw 'Search filtering failed' }
    $originalStatePath=$statePath
    $statePath=Join-Path ([IO.Path]::GetTempPath()) ('yazi-open-with-test-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        Save-AppUse $testApps[0] $testState
        Save-AppUse $testApps[0] $testState
        $saved=Get-UsageState
        if($saved.usage.a.count -ne 2) { throw 'Usage history did not survive reloading' }
    } finally {
        if(Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath }
        $statePath=$originalStatePath
    }
    Write-Output 'PASS: frequency ranking, application search and persistent usage history'
    return
}
$state = Get-UsageState
if($ListApps) { Get-RankedApps (Get-AppCatalog $state) $state | Select-Object Name,Path; return }
if(-not $Files -and -not $Server) { return }
foreach($file in $Files) { if(-not (Test-Path -LiteralPath $file)) { throw "Файл не найден: $file" } }
if(-not $Choose -and -not $Server) {
    try { Open-InApp ([pscustomobject]@{Id='default'}) $Files; return } catch { $Choose=$true }
}
if ($Choose -and -not $Server -and -not $PreviewPath) {
    $launcher = Join-Path $PSScriptRoot 'bin\open-with.exe'
    if (Test-Path -LiteralPath $launcher) { & $launcher @Files; return }
}
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$iconCache=@{}
function Get-AppIcon([string]$Path) {
    if($iconCache.ContainsKey($Path)) { return $iconCache[$Path] }
    $icon=$null
    try {
        if($Path) { $icon=[Drawing.Icon]::ExtractAssociatedIcon($Path) }
        if(-not $icon) { $icon=[Drawing.SystemIcons]::Application.Clone() }
        $bitmap=[Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($icon.Handle,[Windows.Int32Rect]::Empty,[Windows.Media.Imaging.BitmapSizeOptions]::FromWidthAndHeight(32,32))
        $bitmap.Freeze()
    } catch {
        $fallback=[Drawing.SystemIcons]::Application
        $bitmap=[Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($fallback.Handle,[Windows.Int32Rect]::Empty,[Windows.Media.Imaging.BitmapSizeOptions]::FromWidthAndHeight(32,32))
        $bitmap.Freeze()
    } finally { if($icon) { $icon.Dispose() } }
    $iconCache[$Path]=$bitmap
    return $bitmap
}
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Yazi — Открыть с помощью" Width="820" Height="610" WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" Foreground="#e0def4" FontFamily="Segoe UI" FontSize="14">
 <Window.Resources>
  <Style TargetType="Button">
   <Setter Property="Foreground" Value="#e0def4"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="12,8"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Name="ButtonSurface" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonSurface" Property="Background" Value="#403d52"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ButtonSurface" Property="Background" Value="#524f67"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ListBoxItem">
   <Setter Property="Foreground" Value="#e0def4"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Padding" Value="12,10"/><Setter Property="Margin" Value="0,2"/><Setter Property="FocusVisualStyle" Value="{x:Null}" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border Name="Row" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="10" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Row" Property="Background" Value="#2a273f"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="Row" Property="Background" Value="#393552"/><Setter TargetName="Row" Property="BorderBrush" Value="#6e6a86"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ScrollBar">
   <Setter Property="Width" Value="7"/><Setter Property="Background" Value="Transparent"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Track Name="PART_Track" IsDirectionReversed="True">
    <Track.DecreaseRepeatButton><RepeatButton Command="{x:Static ScrollBar.PageUpCommand}" Opacity="0" Focusable="False" IsTabStop="False"/></Track.DecreaseRepeatButton>
    <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Name="Grip" Background="#524f67" CornerRadius="3" Margin="1,2"/><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Grip" Property="Background" Value="#908caa"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
    <Track.IncreaseRepeatButton><RepeatButton Command="{x:Static ScrollBar.PageDownCommand}" Opacity="0" Focusable="False" IsTabStop="False"/></Track.IncreaseRepeatButton>
   </Track></ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>
 <Grid Margin="14">
  <Border Background="#232136" CornerRadius="16" BorderBrush="#524f67" BorderThickness="1">
   <Border.Effect><DropShadowEffect BlurRadius="20" ShadowDepth="4" Opacity="0.35" Color="#000000"/></Border.Effect>
   <Grid>
    <Grid.RowDefinitions><RowDefinition Height="84"/><RowDefinition Height="66"/><RowDefinition Height="*"/><RowDefinition Height="64"/></Grid.RowDefinitions>
    <Border BorderBrush="#393552" BorderThickness="0,0,0,1" Padding="24,0,18,0">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="48"/><ColumnDefinition Width="*"/><ColumnDefinition Width="38"/></Grid.ColumnDefinitions>
      <Border Name="DragHandle" Width="34" Height="34" Background="#393552" CornerRadius="10" HorizontalAlignment="Left" Cursor="SizeAll"><TextBlock Text="↗" Foreground="#c4a7e7" FontSize="25" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-3,0,0"/></Border>
      <Grid Grid.Column="1" Margin="0,0,12,0" VerticalAlignment="Center">
       <TextBox Name="Search" FontSize="21" Background="Transparent" Foreground="#e0def4" CaretBrush="#c4a7e7" BorderThickness="0" Padding="0,8" VerticalContentAlignment="Center" ToolTip="Поиск приложения по названию или пути">
        <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer Name="PART_ContentHost"/></ControlTemplate></TextBox.Template>
       </TextBox>
       <TextBlock Text="Через какое приложение открыть?" FontSize="21" Foreground="#908caa" VerticalAlignment="Center" IsHitTestVisible="False">
        <TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/><Style.Triggers><DataTrigger Binding="{Binding Text.Length, ElementName=Search}" Value="0"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers></Style></TextBlock.Style>
       </TextBlock>
      </Grid>
      <Button Name="Close" Grid.Column="2" Content="×" FontSize="23" Foreground="#908caa" Padding="8,2" VerticalAlignment="Center" ToolTip="Закрыть · Esc"/>
     </Grid>
    </Border>
    <Grid Name="TitleArea" Grid.Row="1" Margin="28,12,28,8">
     <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
     <TextBlock Text="ОТКРЫТЬ С ПОМОЩЬЮ" FontSize="10" FontWeight="SemiBold" Foreground="#c4a7e7" Margin="0,0,0,5"/>
     <TextBlock Name="FileLabel" Grid.Row="1" FontSize="13" Foreground="#908caa" TextTrimming="CharacterEllipsis"/>
    </Grid>
    <Grid Grid.Row="2" Margin="14,0,14,12">
     <ListBox Name="Apps" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.CanContentScroll="True">
      <ListBox.ItemTemplate><DataTemplate><Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="50"/><ColumnDefinition Width="*"/><ColumnDefinition Width="50"/></Grid.ColumnDefinitions>
       <Border Width="36" Height="36" Background="#2a273f" CornerRadius="8" HorizontalAlignment="Left"><Image Source="{Binding Icon}" Width="28" Height="28" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/></Border>
       <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,14,0"><TextBlock Text="{Binding Name}" FontSize="15" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/><TextBlock Text="{Binding Subtitle}" FontSize="11" Foreground="#908caa" TextTrimming="CharacterEllipsis" Margin="0,3,0,0"/></StackPanel>
       <TextBlock Grid.Column="2" Text="{Binding UsageLabel}" Foreground="#c4a7e7" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" ToolTip="Количество открытий через это приложение"/>
      </Grid></DataTemplate></ListBox.ItemTemplate>
     </ListBox>
     <StackPanel Name="EmptyState" Visibility="Collapsed" VerticalAlignment="Center" HorizontalAlignment="Center"><TextBlock Text="Ничего не найдено" FontSize="19" Foreground="#e0def4" HorizontalAlignment="Center"/><TextBlock Text="Попробуйте другое название или выберите .exe" FontSize="13" Foreground="#908caa" Margin="0,8,0,0"/></StackPanel>
    </Grid>
    <Border Grid.Row="3" Background="#1f1d2e" BorderBrush="#393552" BorderThickness="0,1,0,0" CornerRadius="0,0,16,16" Padding="16,12">
     <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Button Name="Browse" Content="Другой .exe…" Foreground="#908caa" FontSize="12" Padding="10,7"/>
      <Button Name="SystemChooser" Grid.Column="1" Content="Windows…" Foreground="#908caa" FontSize="12" Padding="10,7" ToolTip="Системный диалог, в том числе приложения Microsoft Store"/>
      <StackPanel Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="6,0,15,0"><TextBlock Name="Status" Foreground="#908caa" FontSize="10" HorizontalAlignment="Right"/><TextBlock Text="↑ ↓  выбор    Esc  закрыть" Foreground="#908caa" FontSize="10" Margin="0,3,0,0"/></StackPanel>
      <Button Name="Open" Grid.Column="3" Content="Открыть  ↵" Background="#393552" Padding="15,8" IsDefault="True"/>
     </Grid>
    </Border>
   </Grid>
  </Border>
 </Grid>
</Window>

'@
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$search=$window.FindName('Search'); $list=$window.FindName('Apps'); $status=$window.FindName('Status')
$window.FindName('FileLabel').Text=($Files | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', '
$catalog=Get-AppCatalog $state
foreach($app in $catalog) {
    $iconPath=if($app.Path){$app.Path}else{$Files[0]}
    $countProperty=$state.usage.PSObject.Properties[$app.Id]
    $count=if($countProperty){[int]$countProperty.Value.count}else{0}
    $subtitle=if($app.Id -eq 'default'){'Windows выберет приложение для этого типа файла'}else{$app.Path}
    $label=if($count -gt 0){"$count"+[char]0x00D7}else{''}
    $app | Add-Member -NotePropertyName Icon -NotePropertyValue (Get-AppIcon $iconPath) -Force
    $app | Add-Member -NotePropertyName Subtitle -NotePropertyValue $subtitle -Force
    $app | Add-Member -NotePropertyName UsageLabel -NotePropertyValue $label -Force
}
$refresh={
    $list.ItemsSource=@(Get-RankedApps $catalog $state $search.Text)
    if($list.Items.Count -gt 0) { $list.SelectedIndex=0 }
    $status.Text="Найдено: $($list.Items.Count) · частые вверху"
    $window.FindName('EmptyState').Visibility=if($list.Items.Count -eq 0){'Visible'}else{'Collapsed'}
    $window.FindName('Open').IsEnabled=$list.Items.Count -gt 0
}
$openSelected={
    if($list.SelectedItem) {
        try { Open-InApp $list.SelectedItem $Files; Save-AppUse $list.SelectedItem $state; $window.Close() }
        catch { [Windows.MessageBox]::Show($_.Exception.Message,'Не удалось открыть файл') | Out-Null }
    }
}
$search.Add_TextChanged($refresh)
$window.FindName('Open').Add_Click($openSelected)
$window.FindName('Close').Add_Click({ $window.Close() })
$window.FindName('DragHandle').Add_MouseLeftButtonDown({ $window.DragMove() })
$window.FindName('TitleArea').Add_MouseLeftButtonDown({ $window.DragMove() })
$list.Add_MouseDoubleClick($openSelected)
$window.Add_PreviewKeyDown({
    if($_.Key -eq 'Escape') { $window.Close(); $_.Handled=$true }
    elseif($search.IsKeyboardFocusWithin -and $list.Items.Count -gt 0 -and $_.Key -in @('Down','Up')) {
        $delta=if($_.Key -eq 'Down'){1}else{-1}
        $list.SelectedIndex=[Math]::Max(0,[Math]::Min($list.Items.Count-1,$list.SelectedIndex+$delta))
        $list.ScrollIntoView($list.SelectedItem); $_.Handled=$true
    }
})
$window.FindName('Browse').Add_Click({
    $dialog=New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter='Приложения (*.exe)|*.exe'; $dialog.Title='Выберите приложение'
    if($dialog.ShowDialog() -eq 'OK') {
        $app=[pscustomobject]@{Id=(Get-AppId $dialog.FileName);Name=[IO.Path]::GetFileNameWithoutExtension($dialog.FileName);Path=$dialog.FileName}
        try { Open-InApp $app $Files; Save-AppUse $app $state -Custom; $window.Close() }
        catch { [Windows.MessageBox]::Show($_.Exception.Message,'Не удалось открыть файл') | Out-Null }
    }
})
$window.FindName('SystemChooser').Add_Click({
    foreach($file in $Files) { Start-Process -FilePath rundll32.exe -ArgumentList ('shell32.dll,OpenAs_RunDLL "'+$file+'"') }
    $window.Close()
})
& $refresh
$window.Add_ContentRendered({ $search.Focus() | Out-Null })
if($PreviewPath) {
    $root=$window.Content
    $root.Measure((New-Object Windows.Size(820,610)))
    $root.Arrange((New-Object Windows.Rect(0,0,820,610)))
    $root.UpdateLayout()
    $render=New-Object Windows.Media.Imaging.RenderTargetBitmap(820,610,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $render.Render($root)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
    $stream=[IO.File]::Create($PreviewPath)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    # Exercise filtering against the same controls and data used in the live palette.
    $search.Text='zen'
    if($list.Items.Count -eq 0 -or @($list.Items | Where-Object Name -notmatch 'zen').Count) { throw 'Palette search binding failed' }
    $search.Text='__no_such_app__'
    if($window.FindName('EmptyState').Visibility -ne 'Visible' -or $window.FindName('Open').IsEnabled) { throw 'Empty search state failed' }
    if(@($catalog | Where-Object { -not $_.Icon }).Count) { throw 'An application is missing its icon' }
    $window.Close()
    Write-Output 'PASS: WPF palette render, icons, search and empty state'
    return
}
if (-not $Server) { $window.ShowDialog() | Out-Null; return }

$queuePath = Join-Path $PSScriptRoot 'open-with-requests'
[IO.Directory]::CreateDirectory($queuePath) | Out-Null
$window.Add_Closing({ $_.Cancel = $true; $window.Hide() })
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(40)
$timer.Add_Tick({
    $request = Get-ChildItem -LiteralPath $queuePath -Filter '*.request' | Sort-Object Name | Select-Object -First 1
    if (-not $request) { return }
    $receipt = Join-Path $queuePath ($request.BaseName + '.done')
    try {
        $script:Files = @([IO.File]::ReadAllLines($request.FullName) | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
        [IO.File]::Delete($request.FullName)
        if ($Files.Count -eq 0) { throw 'Empty request' }
        foreach ($file in $Files) { if (-not (Test-Path -LiteralPath $file)) { throw "File not found: $file" } }
        $script:state = Get-UsageState
        foreach ($app in $state.customApps) {
            if ($app.Id -notin @($catalog | ForEach-Object Id)) {
                $script:catalog += [pscustomobject]@{Id=$app.Id;Name=$app.Name;Path=$app.Path;Icon=(Get-AppIcon $app.Path);Subtitle=$app.Path;UsageLabel=''}
            }
        }
        foreach ($app in $catalog) {
            $use = $state.usage.PSObject.Properties[$app.Id]
            $app.UsageLabel = if ($use -and $use.Value.count -gt 0) { [string]$use.Value.count + [char]0x00D7 } else { '' }
        }
        ($catalog | Where-Object Id -eq 'default').Icon = Get-AppIcon $Files[0]
        $window.FindName('FileLabel').Text = ($Files | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', '
        $search.Clear()
        & $refresh
        $window.Show()
        $window.Activate() | Out-Null
        $search.Focus() | Out-Null
        [IO.File]::WriteAllText($receipt, 'OK')
    } catch {
        [IO.File]::WriteAllText($receipt, $_.Exception.ToString())
        [IO.File]::Delete($request.FullName)
    }
    # Receipts are diagnostic acknowledgements, never needed after one minute.
    Get-ChildItem -LiteralPath $queuePath -Filter '*.done' | Where-Object LastWriteTime -lt (Get-Date).AddMinutes(-1) | Remove-Item -Force
})
$timer.Start()
try { [Windows.Threading.Dispatcher]::Run() }
finally { $timer.Stop(); $serverMutex.ReleaseMutex(); $serverMutex.Dispose() }
