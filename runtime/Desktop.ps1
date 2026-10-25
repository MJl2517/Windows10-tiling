param(
    [ValidateSet('Install','Apply','Check','Update','Rollback','Status','RestoreTaskbar','Uninstall','Start','Browser','Console','Files','Palette','Import')][string]$Action='Status',
    [string]$Root=(Join-Path $env:LOCALAPPDATA 'RosePineDesktop'),
    [string]$Release, [string]$SettingsFile, [string]$Feed, [string]$Result,
    [string]$ProfileRoot, [string]$Cache, [int]$MonitorCount=0, [switch]$Sandbox,
    [string]$Components='desktop,files,borders,palette', [switch]$HideTaskbar, [switch]$Cursor,
    [int]$FailAfter=0, [switch]$PaletteSettings
)
$ErrorActionPreference='Stop'
$env:PSModulePath=(Join-Path $PSHOME 'Modules')+';'+$env:PSModulePath
Set-StrictMode -Version 2
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-Json($Path) { $data=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)); return $data }
function Write-Json($Path,$Value) {
    [IO.Directory]::CreateDirectory((Split-Path $Path))|Out-Null
    $tmp=$Path+'.tmp'; [IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $Value -Depth 40),[Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tmp,$Path,$Path+'.previous');Remove-Item -LiteralPath ($Path+'.previous')}else{[IO.File]::Move($tmp,$Path)}
}
function Hash($Path) { if(Test-Path -LiteralPath $Path -PathType Leaf){$stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}}else{''} }
function Bytes-Hash($Bytes) {if($null -eq $Bytes){return ''};$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Under($Base,$Path) {
    $b=[IO.Path]::GetFullPath($Base).TrimEnd('\')+'\'; $p=[IO.Path]::GetFullPath($Path)
    if(!$p.StartsWith($b,[StringComparison]::OrdinalIgnoreCase)){throw "Путь вне разрешённой папки: $Path"}; $p
}
function Expand-Safe($Archive,$Destination) {
    [IO.Directory]::CreateDirectory($Destination)|Out-Null
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach($e in $zip.Entries){
            $p=Under $Destination (Join-Path $Destination $e.FullName)
            if($e.FullName.EndsWith('/')){[IO.Directory]::CreateDirectory($p)|Out-Null;continue}
            [IO.Directory]::CreateDirectory((Split-Path $p))|Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e,$p,$true)
        }
    }finally{$zip.Dispose()}
}
function Download($Url,$Destination,$Sha) {
    if($Sha -notmatch '^[a-fA-F0-9]{64}$'){throw 'Отсутствует SHA-256 пакета'}
    if((Hash $Destination) -eq $Sha.ToLowerInvariant()){return}
    if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination}
    $part=$Destination+'.part'; [IO.Directory]::CreateDirectory((Split-Path $part))|Out-Null
    try {
        if([IO.Path]::IsPathRooted($Url)){Copy-Item -LiteralPath $Url -Destination $part}
        else {
            $uri=[uri]$Url; if($uri.Scheme -ne 'https'){throw 'Загрузка разрешена только по HTTPS'}
            [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            $request=[Net.WebRequest]::Create($uri);$request.Timeout=60000
            $response=$request.GetResponse()
            try{if($response.ResponseUri.Scheme -ne 'https'){throw 'Небезопасное перенаправление загрузки'};$inputStream=$response.GetResponseStream();$outputStream=[IO.File]::Create($part);try{$inputStream.CopyTo($outputStream)}finally{$outputStream.Dispose();$inputStream.Dispose()}}finally{$response.Dispose()}
        }
        if((Hash $part) -ne $Sha.ToLowerInvariant()){throw "Контрольная сумма не совпадает: $Url"}
        Move-Item -LiteralPath $part -Destination $Destination -Force
    }finally{if(Test-Path -LiteralPath $part){Remove-Item -LiteralPath $part}}
}
function Default-Settings {
    if(!$MonitorCount){Add-Type -AssemblyName System.Windows.Forms; $script:MonitorCount=[Windows.Forms.Screen]::AllScreens.Count}
    $names='WEB','DEV','FILES','CHAT','MEDIA','OTHER','TTRPG','8','9'
    $spaces=@(for($i=0;$i -lt 9;$i++){[pscustomobject]@{name=[string]($i+1);label=$names[$i];monitor=$(if($MonitorCount -gt 1 -and $i -in 4,5){1}else{0})}})
    [pscustomobject]@{components=@($Components.Split(',')|Where-Object{$_});autostart=$true;hideTaskbar=[bool]$HideTaskbar;cursor=[bool]$Cursor;browser='';workspaces=$spaces;feed='';checkAtLogon=$true}
}
function Packages($Payload,$Settings) {
    $deps=Read-Json (Join-Path $Payload 'dependencies.json'); $paths=@{}
    foreach($d in $deps){
        if($d.component -notin $Settings.components -and !($d.component -eq 'cursor' -and $Settings.cursor)){continue}
        if($d.id -notmatch '^[a-z0-9-]+$' -or $d.version -notmatch '^[a-zA-Z0-9.\-]+$'){throw 'Некорректная зависимость'}
        $dest=Join-Path $Root ('packages\'+$d.id+'\'+$d.version)
        $archive=Join-Path $Cache ($d.id+'-'+$d.version+$d.extension)
        if(!(Test-Path -LiteralPath (Join-Path $dest '.complete'))){
            Download $d.url $archive $d.sha256
            [IO.Directory]::CreateDirectory($dest)|Out-Null
            switch($d.kind){
                'zip' {Expand-Safe $archive $dest}
                'exe' {Copy-Item -LiteralPath $archive -Destination (Join-Path $dest $d.entry)}
                'sfx' {$p=Start-Process -FilePath $archive -ArgumentList @('-y',('-o"'+$dest+'"')) -WindowStyle Hidden -Wait -PassThru; if($p.ExitCode){throw "Ошибка распаковки $($d.id)"}}
                'msi' {$p=Start-Process msiexec.exe -ArgumentList @('/a',('"'+$archive+'"'),'/qn',('TARGETDIR="'+$dest+'"')) -WindowStyle Hidden -Wait -PassThru; if($p.ExitCode -notin 0,3010){throw "Ошибка извлечения MSI $($d.id): $($p.ExitCode)"}}
                default {throw 'Неизвестный формат зависимости'}
            }
            $pattern=$d.entry.Replace('/','\')
            $entry=@(if($pattern.StartsWith('**\')){Get-ChildItem -LiteralPath $dest -Recurse -File|Where-Object{$_.FullName.EndsWith($pattern.Substring(2),[StringComparison]::OrdinalIgnoreCase)}}else{Get-Item -LiteralPath (Join-Path $dest $pattern) -ErrorAction SilentlyContinue})
            if($entry.Count -ne 1){throw "Не найден однозначный файл $($d.entry) после распаковки $($d.id)"}
            [IO.File]::WriteAllText((Join-Path $dest '.entry'),$entry[0].FullName)
            [IO.File]::WriteAllText((Join-Path $dest '.complete'),$d.sha256)
        }
        $paths[$d.id]=[IO.File]::ReadAllText((Join-Path $dest '.entry'))
    }
    if($paths['conpty'] -and $paths['alacritty']){
        $al=Split-Path $paths['alacritty'];$co=Split-Path (Split-Path (Split-Path (Split-Path $paths['conpty'])))
        $console=Join-Path $co 'build\native\runtimes\x64\OpenConsole.exe'
        foreach($f in @($paths['conpty'],$console)){if(!(Test-Path $f)){throw "Не найден ConPTY: $f"};$target=Join-Path $al (Split-Path $f -Leaf);if((Hash $f) -ne (Hash $target)){Copy-Item -LiteralPath $f -Destination $target -Force}}
    }
    $paths
}
function Ensure-WebView($Payload,$Settings) {
    if($Sandbox -or 'desktop' -notin $Settings.components){return}
    $patterns=@((Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application\*\msedgewebview2.exe'),(Join-Path $env:LOCALAPPDATA 'Microsoft\EdgeWebView\Application\*\msedgewebview2.exe'))
    if(@($patterns|ForEach-Object{Get-Item $_ -ErrorAction SilentlyContinue}).Count){return}
    $p=Read-Json (Join-Path $Payload 'prerequisites.json');$file=Join-Path $Cache 'webview2-bootstrap.exe';Download $p.webview2.url $file $p.webview2.sha256
    $signature=Get-AuthenticodeSignature -LiteralPath $file
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Microsoft Corporation*'){throw 'Не подтверждена подпись Microsoft WebView2'}
    $process=Start-Process -FilePath $file -ArgumentList '/silent /install' -WindowStyle Hidden -Wait -PassThru
    if($process.ExitCode){throw "Установка WebView2 не завершена: $($process.ExitCode)"}
}
function Find-PowerToys {
    $candidates=New-Object Collections.Generic.List[string]
    foreach($base in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')){
        foreach($key in Get-ChildItem $base -ErrorAction SilentlyContinue){
            $entry=Get-ItemProperty $key.PSPath
            if($entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -like 'PowerToys*' -and $entry.PSObject.Properties['InstallLocation'] -and $entry.InstallLocation){$candidates.Add((Join-Path $entry.InstallLocation 'PowerToys.exe'))}
        }
    }
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe'))
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\PowerToys\PowerToys.exe'))
    $candidates.Add((Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe'))
    foreach($file in $candidates){if(Test-Path -LiteralPath $file){return $file}}
    return ''
}
function Ensure-PowerToys($Payload,$Settings) {
    if($Sandbox -or 'palette' -notin $Settings.components){return ''}
    $requirement=(Read-Json (Join-Path $Payload 'prerequisites.json')).powertoys
    if([Environment]::OSVersion.Version.Build -lt $requirement.minBuild){throw 'Палитра PowerToys требует Windows 10 2004 (19041) или новее. Отключи этот компонент для более ранней Windows.'}
    $runner=Find-PowerToys
    if($runner){
        $number=[regex]::Match([Diagnostics.FileVersionInfo]::GetVersionInfo($runner).ProductVersion,'\d+\.\d+\.\d+(?:\.\d+)?').Value
        if(!$number -or [version]$number -lt [version]'0.90.0'){throw 'Установленная версия PowerToys не содержит Command Palette. Обнови PowerToys или отключи компонент палитры.'}
        return $runner
    }
    $file=Join-Path $Cache ('powertoys-'+$requirement.version+'.exe')
    Download $requirement.url $file $requirement.sha256
    $signature=Get-AuthenticodeSignature -LiteralPath $file
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Microsoft Corporation*'){throw 'Не подтверждена подпись Microsoft PowerToys'}
    $process=Start-Process -FilePath $file -ArgumentList @('/quiet','/norestart') -WindowStyle Hidden -Wait -PassThru
    if($process.ExitCode -notin 0,3010){throw "Не удалось установить PowerToys: $($process.ExitCode)"}
    $runner=Find-PowerToys
    if(!$runner){throw 'PowerToys не найден после установки. Перезапусти Windows, если установщик запросил перезагрузку.'}
    return $runner
}
function Render($Text,$Tokens) {
    foreach($k in $Tokens.Keys){$Text=$Text.Replace('@'+$k+'@',[string]$Tokens[$k])}
    if($Text -match '@[A-Z_]+@'){throw "Неизвестный параметр шаблона: $($Matches[0])"}; $Text
}
function Make-Plan($Payload,$Settings,$Paths) {
    $catalog=Join-Path $Payload 'shortcuts.json'
    $keybindings='';$helpRows=''
    if(Test-Path $catalog){
        Add-Type -AssemblyName System.Web.Extensions
        Add-Type -Path (Join-Path $Payload 'Shortcuts.dll')
        $overrides=if($Settings.PSObject.Properties['hotkeys']){ConvertTo-Json -InputObject $Settings.hotkeys -Depth 10 -Compress}else{'{}'}
        $keybindings=[DesktopShortcuts]::Render($catalog,$overrides)
        $helpRows=[DesktopShortcuts]::HelpRows($catalog,$overrides)
    }
    if($Settings.hideTaskbar){$helpRows='<tr><td>Win</td><td>Показать / скрыть панель Windows</td></tr>'+$helpRows}
    if('palette' -in $Settings.components){$helpRows='<tr><td>Win+Alt+Пробел</td><td>Палитра команд PowerToys (стандартное сочетание; изменяется в PowerToys)</td></tr>'+$helpRows}
    if(!$MonitorCount){Add-Type -AssemblyName System.Windows.Forms; $script:MonitorCount=[Windows.Forms.Screen]::AllScreens.Count}
    $wm=$Paths['glazewm'];$zb=$Paths['zebar'];$ya=$Paths['yazi'];$al=$Paths['alacritty']
    $tokens=@{PROFILE_F=$ProfileRoot.Replace('\','/');PROFILE_B=$ProfileRoot;WINDOWS_F=$env:WINDIR.Replace('\','/');WINDOWS_B=$env:WINDIR;WMCLI_F=$wm.Replace('\','/');ZEBAR_F=$zb.Replace('\','/');ROOT_F=$Root.Replace('\','/');ROOT_B=$Root}
    $tokens.YAZI_F=$ya.Replace('\','/');$tokens.YAZI_B=$ya;$tokens.ALACRITTY_F=$al.Replace('\','/');$tokens.ALACRITTY_B=$al
    $tokens.ALACRITTY_CONFIG_F=(Join-Path $Root 'config\alacritty.toml').Replace('\','/')
    $nativePath=[Environment]::ExpandEnvironmentVariables(([Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')))
    $tokens.FILE_B=$Paths['file'];$tokens.TOOLS_PATH=(@('poppler','chafa','archive','yazi','file'|ForEach-Object{if($Paths[$_]){Split-Path $Paths[$_]}}) -join ';')+';'+$env:WINDIR+'\System32;'+$env:WINDIR+'\System32\WindowsPowerShell\v1.0;'+$nativePath
    $items=New-Object Collections.Generic.List[object]
    $items.Add([pscustomobject]@{target=(Join-Path $Root 'RosePineCenter.exe');bytes=[IO.File]::ReadAllBytes((Join-Path $Payload 'Bootstrap.exe'))})
    $map=@{glazewm='.glzr\glazewm';zebar='.glzr\zebar';borders='.config\tacky-borders';yazi='AppData\Roaming\yazi\config';alacritty=''}
    foreach($dir in $map.Keys){
        if(($dir -in 'glazewm','zebar' -and 'desktop' -notin $Settings.components) -or ($dir -in 'yazi','alacritty' -and 'files' -notin $Settings.components) -or ($dir -eq 'borders' -and 'borders' -notin $Settings.components)){continue}
        $base=Join-Path $Payload ('templates\'+$dir)
        foreach($f in Get-ChildItem -LiteralPath $base -Recurse -File){
            $relative=$f.FullName.Substring($base.Length+1)
            $target=Join-Path $ProfileRoot ($map[$dir]+'\'+$relative)
            if($dir -eq 'alacritty'){$target=Join-Path $Root 'config\alacritty.toml'}
            $bytes=[IO.File]::ReadAllBytes($f.FullName)
            if($f.Extension -in '.yaml','.toml','.json','.lua','.html','.js','.css','.ps1','.cmd','.txt'){
                $raw=[IO.File]::ReadAllText($f.FullName)
                if($dir -eq 'glazewm'){$raw=$raw.Replace('@KEYBINDINGS@',$keybindings)}
                if($dir -eq 'zebar' -and $relative -eq 'hypr-dark\help.html'){$raw=$raw.Replace('@SHORTCUT_ROWS@',$helpRows)}
                $text=Render $raw $tokens
                if($dir -eq 'glazewm'){
                    $spaces=($Settings.workspaces|ForEach-Object{ $monitor=[Math]::Min([Math]::Max(0,[int]$_.monitor),$MonitorCount-1); "  - {name: '$($_.name)', display_name: '$($_.name) $($_.label.Replace("'","''"))', bind_to_monitor: $monitor, keep_alive: true}"}) -join "`n"
                    $text=[regex]::Replace($text,'(?s)workspaces:\s*.*?(?=\r?\nwindow_rules:)','workspaces:'+"`n"+$spaces+"`n")
                    if(!$Settings.hideTaskbar){$text=$text.Replace(", 'shell-exec @TASKBAR@'",'')}
                    if(!$Settings.hideTaskbar){$text=[regex]::Replace($text,", 'shell-exec [^']*taskbar-toggle.exe'",'')}
                    if('borders' -notin $Settings.components){$text=[regex]::Replace($text,", 'shell-exec [^']*tacky-borders.exe'",'')}
                }
                $bytes=[Text.UTF8Encoding]::new($f.Extension -eq '.ps1').GetBytes($text)
                if($f.Extension -eq '.ps1'){$bytes=[byte[]](0xEF,0xBB,0xBF)+$bytes}
            }
            $items.Add([pscustomobject]@{target=$target;bytes=$bytes})
        }
    }
    foreach($f in Get-ChildItem (Join-Path $Payload 'helpers') -File){
        if($f.BaseName -in 'open-with','yazi-drag' -and 'files' -notin $Settings.components){continue}
        if($f.BaseName -in 'tray-identity','task-windows','close-window','resize-window','power-menu' -and 'desktop' -notin $Settings.components){continue}
        $target=Join-Path $ProfileRoot ('.glzr\tools\'+$f.BaseName+'\'+$f.Name)
        if($f.BaseName -in 'open-with','yazi-drag'){$target=Join-Path $ProfileRoot ('AppData\Roaming\yazi\config\bin\'+$f.Name)}
        if($f.BaseName -in 'tray-identity','task-windows'){$target=Join-Path $ProfileRoot ('.glzr\zebar\bar-rose-pine\tools\'+$f.Name)}
        $items.Add([pscustomobject]@{target=$target;bytes=[IO.File]::ReadAllBytes($f.FullName)})
    }
    $items.Add([pscustomobject]@{target=(Join-Path $ProfileRoot '.glzr\tools\glazewm-cli.txt');bytes=[Text.Encoding]::UTF8.GetBytes($wm)})
    if('borders' -in $Settings.components){$items.Add([pscustomobject]@{target=(Join-Path $ProfileRoot '.glzr\tools\tacky-borders\tacky-borders.exe');bytes=[IO.File]::ReadAllBytes($Paths['borders'])})}
    if(!$Sandbox){
        $temp=Join-Path $Root 'requests\planned.lnk'
        $links=@{(Join-Path ([Environment]::GetFolderPath('Programs')) 'Rose Pine Desktop\Центр управления.lnk')='';(Join-Path ([Environment]::GetFolderPath('Programs')) 'Rose Pine Desktop\Восстановить панель Windows.lnk')='--restore-taskbar'}
        if($Settings.autostart -or $Settings.checkAtLogon){$links[(Join-Path ([Environment]::GetFolderPath('Startup')) 'Rose Pine Desktop.lnk')]='--logon'}
        foreach($link in $links.Keys){Shortcut $temp (Join-Path $Root 'RosePineCenter.exe') $links[$link];$items.Add([pscustomobject]@{target=$link;bytes=[IO.File]::ReadAllBytes($temp)})}
        if(Test-Path $temp){Remove-Item -LiteralPath $temp}
        $ws=New-Object -ComObject WScript.Shell
        foreach($old in Get-ChildItem ([Environment]::GetFolderPath('Startup')) -Filter '*.lnk'){
            if($links.ContainsKey($old.FullName)){continue}
            $ln=$ws.CreateShortcut($old.FullName)
            $glaze=$ln.TargetPath -match '[\\/]glzr\.io[\\/]GlazeWM[\\/].*glazewm\.exe$'
            $palette=$ln.TargetPath -match '[\\/]Programs[\\/]Yazi[\\/]open-with\.exe$'
            if(($glaze -and 'desktop' -in $Settings.components) -or ($palette -and 'files' -in $Settings.components)){$items.Add([pscustomobject]@{target=$old.FullName;bytes=$null})}
        }
    }
    ,$items
}
function File-Record($Path,$Backup,$Index) {
    $exists=Test-Path -LiteralPath $Path -PathType Leaf; $copy=Join-Path $Backup ([string]$Index)
    if($exists){Copy-Item -LiteralPath $Path -Destination $copy}
    [pscustomobject]@{target=$Path;exists=$exists;copy=$copy;before=(Hash $Path);after=''}
}
function Restore-Records($Records,[switch]$RespectChanges) {
    foreach($r in $Records){
        if($RespectChanges -and (Hash $r.target) -ne $r.after){continue}
        if($r.exists){if((Hash $r.target) -ne $r.before){[IO.Directory]::CreateDirectory((Split-Path $r.target))|Out-Null; Copy-Item -LiteralPath $r.copy -Destination $r.target -Force}}
        elseif(Test-Path -LiteralPath $r.target){Remove-Item -LiteralPath $r.target -Force}
    }
}
function Assert-Free($Items) {
    foreach($i in $Items){if(Test-Path -LiteralPath $i.target){try{$s=[IO.File]::Open($i.target,'Open','ReadWrite','None');$s.Dispose()}catch{throw "Файл занят. Закрой соответствующий компонент и повтори: $($i.target)"}}}
}
function Resume-Services($Paths) {
    if($Sandbox){return}
    foreach($path in $Paths){if(Test-Path -LiteralPath $path){Start-Process -FilePath $path -WindowStyle Hidden}}
}
function Pause-Services($Items,$Previous) {
    if($Sandbox){return @()}
    $restart=New-Object Collections.Generic.List[string]
    try{
        $barRoot=(Join-Path $ProfileRoot '.glzr\zebar').TrimEnd('\')+'\'
        if($Previous -and @($Items|Where-Object{$_.target.StartsWith($barRoot,[StringComparison]::OrdinalIgnoreCase)}).Count){
            $barPath=$Previous.paths.zebar
            if($barPath.StartsWith((Join-Path $Root 'packages')+'\',[StringComparison]::OrdinalIgnoreCase)){
                foreach($p in Get-CimInstance Win32_Process -Filter "Name='zebar.exe'"|Where-Object{$_.ExecutablePath -eq $barPath}){$restart.Add($barPath);Stop-Process -Id $p.ProcessId;Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue}
            }
        }
        foreach($i in $Items){
            $name=Split-Path $i.target -Leaf
            if($name -notin 'taskbar-toggle.exe','tacky-borders.exe'){continue}
            $running=@(Get-CimInstance Win32_Process -Filter "Name='$name'"|Where-Object{$_.ExecutablePath -eq $i.target})
            if(!$running.Count){continue}
            $restart.Add($i.target)
            if($name -eq 'taskbar-toggle.exe'){$p=Start-Process -FilePath $i.target -ArgumentList '--stop' -WindowStyle Hidden -Wait -PassThru;if($p.ExitCode){throw 'Не удалось остановить контроллер панели'}}
            else{foreach($p in $running){Stop-Process -Id $p.ProcessId}}
            foreach($p in $running){Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue}
        }
        return $restart.ToArray()
    }catch{Resume-Services $restart;throw}
}
function Apply-Payload($Payload,$Settings,[switch]$ImportExisting) {
    $manifest=Read-Json (Join-Path $Payload 'release.json')
    if($manifest.version -notmatch '^\d+\.\d+\.\d+$' -or $manifest.schema -ne 1){throw 'Неподдерживаемый манифест выпуска'}
    if(!$Sandbox -and (![Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Build -lt 17763)){throw 'Требуется Windows 10 1809+ x64 или Windows 11 x64'}
    Ensure-WebView $Payload $Settings
    $paths=Packages $Payload $Settings
    $powerToys=Ensure-PowerToys $Payload $Settings
    if($powerToys){$paths['powertoys']=$powerToys}
    # Paths always exist for rendering; a disabled component has no files deployed.
    foreach($k in 'glazewm','zebar','yazi','alacritty','file'){if(!$paths[$k]){$paths[$k]=Join-Path $Root ('disabled\'+$k+'.exe')}}
    $plan=Make-Plan $Payload $Settings $paths
    $previous=$null; if(Test-Path $stateFile){$previous=Read-Json $stateFile}
    $base=@{}; if($previous){foreach($f in $previous.files){$base[$f.target]=$f}}
    $conflicts=New-Object Collections.Generic.List[object];$changes=New-Object Collections.Generic.List[object]
    foreach($i in $plan){
        $next=Bytes-Hash $i.bytes
        $current=Hash $i.target
        if($base.ContainsKey($i.target) -and $current -ne $base[$i.target].after -and $current -ne $next -and !$ImportExisting){
            $incoming=Join-Path $Root ('conflicts\'+[guid]::NewGuid().ToString()+'.incoming');[IO.Directory]::CreateDirectory((Split-Path $incoming))|Out-Null;[IO.File]::WriteAllBytes($incoming,$i.bytes)
            $conflicts.Add([pscustomobject]@{target=$i.target;incoming=$incoming});continue
        }
        if($current -ne $next){$changes.Add($i)}
    }
    # Restore removed components only when their files still match our last deployment.
    $targets=@{};foreach($i in $plan){$targets[$i.target]=$true}
    if($previous -and (Test-Path (Join-Path $Root 'baseline.json'))){
        $initial=@{};foreach($b in (Read-Json (Join-Path $Root 'baseline.json'))){$initial[$b.target]=$b}
        foreach($f in $previous.files){if(!$targets.ContainsKey($f.target) -and (Hash $f.target) -eq $f.after -and $initial.ContainsKey($f.target)){$b=$initial[$f.target];$bytes=if($b.exists){[IO.File]::ReadAllBytes($b.copy)}else{$null};$changes.Add([pscustomobject]@{target=$f.target;bytes=$bytes})}}
    }
    if($conflicts.Count){Write-Json (Join-Path $Root 'conflicts.json') $conflicts.ToArray();throw 'Обнаружены ручные изменения. Сравни файлы в разделе восстановления; обновление не применено.'}
    $backup=Join-Path $Root ('backups\'+(Get-Date -Format yyyyMMdd-HHmmss-fff)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($backup)|Out-Null
    $records=New-Object Collections.Generic.List[object]
    foreach($i in $changes){$record=File-Record $i.target $backup $records.Count;$record.after=Bytes-Hash $i.bytes;$records.Add($record)}
    $oldState=File-Record $stateFile $backup 'state';$oldSettings=File-Record $settingsPath $backup 'settings';$oldBaseline=File-Record (Join-Path $Root 'baseline.json') $backup 'baseline'
    $system=Backup-System $backup
    $services=@()
    Write-Json (Join-Path $backup 'transaction.json') @{status='prepared';files=$records.ToArray();state=$oldState;settings=$oldSettings;baseline=$oldBaseline;system=$system;services=$services}
    try{
        $services=@(Pause-Services $changes $previous)
        Write-Json (Join-Path $backup 'transaction.json') @{status='prepared';files=$records.ToArray();state=$oldState;settings=$oldSettings;baseline=$oldBaseline;system=$system;services=$services}
        Assert-Free $changes
        $written=0;foreach($i in $changes){[IO.Directory]::CreateDirectory((Split-Path $i.target))|Out-Null;if($null -eq $i.bytes){if(Test-Path -LiteralPath $i.target){Remove-Item -LiteralPath $i.target}}else{[IO.File]::WriteAllBytes($i.target,$i.bytes)};$written++;if($Sandbox -and $FailAfter -gt 0 -and $written -ge $FailAfter){throw 'Simulated disk failure'}}
        foreach($r in $records){$r.after=Hash $r.target}
        $files=@(foreach($i in $plan){[pscustomobject]@{target=$i.target;after=(Hash $i.target)}})
        $baseline=Join-Path $Root 'baseline.json'
        $original=@();if(Test-Path $baseline){$original=@(Read-Json $baseline)}
        $known=@{};foreach($b in $original){$known[$b.target]=$true};foreach($r in $records){if(!$known.ContainsKey($r.target)){$original+= $r}}
        Write-Json $baseline $original
        Write-Json $settingsPath $Settings
        Write-Json $stateFile @{version=$manifest.version;payload=$Payload;files=$files;paths=$paths;previousBackup=$backup;installedAt=(Get-Date -Format o);imported=[bool]$ImportExisting;sandbox=[bool]$Sandbox;profile=$ProfileRoot}
        Configure-System $Settings $paths
        if(!$Sandbox -and 'desktop' -in $Settings.components -and (Get-Process glazewm -ErrorAction SilentlyContinue)){$reload=& $paths.glazewm command wm-reload-config|ConvertFrom-Json;if(!$reload.success){throw 'GlazeWM отклонил конфиг. Восстанавливаю предыдущую версию.'}}
        Resume-Services @($services|Where-Object{((Split-Path $_ -Leaf) -ne 'taskbar-toggle.exe' -or $Settings.hideTaskbar) -and ((Split-Path $_ -Leaf) -ne 'tacky-borders.exe' -or 'borders' -in $Settings.components) -and ((Split-Path $_ -Leaf) -ne 'zebar.exe' -or 'desktop' -in $Settings.components)}|ForEach-Object{if((Split-Path $_ -Leaf) -eq 'zebar.exe'){$paths['zebar']}else{$_}})
        Write-Json (Join-Path $backup 'transaction.json') @{status='complete';files=$records.ToArray();state=$oldState;settings=$oldSettings;baseline=$oldBaseline;system=$system}
        if(Test-Path (Join-Path $Root 'conflicts.json')){Remove-Item (Join-Path $Root 'conflicts.json')}
        @{ok=$true;version=$manifest.version;backup=$backup;changed=$changes.Count}
    }catch{Restore-Records $records;Restore-Records @($oldState,$oldSettings,$oldBaseline);Restore-System $system;Resume-Services $services;Write-Json (Join-Path $backup 'transaction.json') @{status='reverted';files=$records.ToArray()};throw}
}
function Shortcut($Path,$Target,$Arguments) {
    [IO.Directory]::CreateDirectory((Split-Path $Path))|Out-Null
    $ws=New-Object -ComObject WScript.Shell;$ln=$ws.CreateShortcut($Path);$ln.TargetPath=$Target;$ln.Arguments=$Arguments;$ln.WorkingDirectory=$Root;$ln.Save()
}
function Configure-System($Settings,$Paths) {
    if($Sandbox){return}
    if('files' -in $Settings.components){Register-Fonts $Paths}
    Set-Cursor $Settings $Paths
    if(!$Settings.hideTaskbar){Restore-Taskbar}
}
function Backup-System($Backup) {
    if($Sandbox){return $null}
    $file=Join-Path $Backup 'cursors.reg'; & reg.exe export 'HKCU\Control Panel\Cursors' $file /y|Out-Null;if($LASTEXITCODE){throw 'Не удалось сохранить параметры курсора'}
    $fonts=@{};$key=Get-Item 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
    if($key){foreach($n in $key.GetValueNames()){if($n.StartsWith('Rose Pine Desktop ')){$fonts[$n]=$key.GetValue($n)}}}
    @{cursorFile=$file;fonts=$fonts}
}
function Restore-System($Snapshot) {
    if($Sandbox -or !$Snapshot){return}
    & reg.exe import $Snapshot.cursorFile|Out-Null
    $reg='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts';$key=Get-Item $reg -ErrorAction SilentlyContinue
    if($key){foreach($n in $key.GetValueNames()){if($n.StartsWith('Rose Pine Desktop ')){Remove-ItemProperty $reg $n}}}
    if($Snapshot.fonts -is [Collections.IDictionary]){foreach($n in $Snapshot.fonts.Keys){New-ItemProperty $reg -Name $n -Value $Snapshot.fonts[$n] -Force|Out-Null}}
    else{foreach($p in $Snapshot.fonts.PSObject.Properties){New-ItemProperty $reg -Name $p.Name -Value $p.Value -Force|Out-Null}}
    if('RpdNative' -as [type]){[void][RpdNative]::SystemParametersInfo(0x57,0,[IntPtr]::Zero,0)}
}
function Register-Fonts($Paths) {
    if(!$Paths['fonts']){return}
    $font=Split-Path $Paths['fonts'];$reg='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    New-Item $reg -Force|Out-Null
    foreach($f in Get-ChildItem $font -Filter 'JetBrainsMonoNerdFontMono-*.ttf'){
        $name='Rose Pine Desktop '+$f.BaseName+' (TrueType)';New-ItemProperty $reg -Name $name -Value $f.FullName -Force|Out-Null
    }
    if(!('RpdNative' -as [type])){Add-Type 'using System; using System.Runtime.InteropServices; public static class RpdNative { [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string p,uint f,IntPtr r); [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern bool SystemParametersInfo(uint a,uint b,IntPtr c,uint d); }'}
    foreach($f in Get-ChildItem $font -Filter 'JetBrainsMonoNerdFontMono-*.ttf'){[void][RpdNative]::AddFontResourceEx($f.FullName,0,[IntPtr]::Zero)}
}
function Set-Cursor($Settings,$Paths) {
    $saved=Join-Path $Root 'original-cursors.reg'
    if($Settings.cursor){
        if(!(Test-Path $saved)){& reg.exe export 'HKCU\Control Panel\Cursors' $saved /y|Out-Null;if($LASTEXITCODE){throw 'Не удалось сохранить курсор'}}
        $roles=@{Arrow='Pointer.cur';Help='Help.cur';AppStarting='Work.ani';Wait='Busy.ani';Crosshair='Cross.cur';IBeam='Text.cur';NWPen='Handwriting.cur';No='Unavailable.cur';SizeNS='Vert.cur';SizeWE='Horz.cur';SizeNWSE='Dgn1.cur';SizeNESW='Dgn2.cur';SizeAll='Move.cur';UpArrow='Alternate.cur';Hand='Link.cur';Pin='Pin.cur';Person='Person.cur'}
        $folder=Split-Path $Paths['cursor'];foreach($role in $roles.Keys){Set-ItemProperty 'HKCU:\Control Panel\Cursors' $role (Join-Path $folder $roles[$role])}
    }elseif(Test-Path $saved){& reg.exe import $saved|Out-Null;if($LASTEXITCODE){throw 'Не удалось восстановить курсор'}}
    if('RpdNative' -as [type]){[void][RpdNative]::SystemParametersInfo(0x57,0,[IntPtr]::Zero,0)}
}
function Restore-Taskbar {
    if($Sandbox){return}
    $helper=Join-Path $ProfileRoot '.glzr\tools\taskbar-toggle\taskbar-toggle.exe'
    if(Test-Path $helper){$p=Start-Process $helper '--restore' -WindowStyle Hidden -Wait -PassThru;if($p.ExitCode){throw 'Не удалось восстановить панель Windows'}}
}
function Get-Update($Settings) {
    if(!$Settings.feed){return @{available=$false;message='Источник обновлений не подключён';current=$(if(Test-Path $stateFile){(Read-Json $stateFile).version}else{'не установлено'})}}
    if([IO.Path]::IsPathRooted($Settings.feed)){$m=Read-Json $Settings.feed}
    else{$u=[uri]$Settings.feed;if($u.Scheme -ne 'https'){throw 'Источник обновлений должен использовать HTTPS'};$m=Invoke-RestMethod -Uri $u -TimeoutSec 20}
    if($m.schema -ne 1 -or $m.version -notmatch '^\d+\.\d+\.\d+$' -or $m.sha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Некорректный манифест обновления'}
    if([IO.Path]::IsPathRooted($Settings.feed)){
        if(![IO.Path]::IsPathRooted($m.url) -and !([uri]$m.url).IsAbsoluteUri){$m.url=Join-Path (Split-Path $Settings.feed) $m.url}
    }else{
        $resolved=New-Object Uri([uri]$Settings.feed,[string]$m.url);if($resolved.Scheme -ne 'https'){throw 'Пакет удалённого источника должен использовать HTTPS'};$m.url=$resolved.AbsoluteUri
    }
    $current=if(Test-Path $stateFile){(Read-Json $stateFile).version}else{'0.0.0'}
    @{available=([version]$m.version -gt [version]$current);current=$current;version=$m.version;notes=$m.notes;url=$m.url;sha256=$m.sha256;message=$(if([version]$m.version -gt [version]$current){'Доступно обновление'}else{'Установлена актуальная версия'})}
}
function Stage-Release($Zip,$Sha,$Version) {
    Download $Zip (Join-Path $Cache ('release-'+$Version+'.zip')) $Sha
    # Never trust or overwrite an existing release directory after an interrupted update.
    $dest=Under (Join-Path $Root 'versions') (Join-Path $Root ('versions\'+$Version+'-'+[guid]::NewGuid().ToString('N')))
    try {
        Expand-Safe (Join-Path $Cache ('release-'+$Version+'.zip')) $dest
        $m=Read-Json (Join-Path $dest 'release.json');if($m.schema -ne 1 -or $m.version -ne $Version){throw 'Версия пакета не совпадает с манифестом'}
    }catch{if(Test-Path -LiteralPath $dest){Remove-Item -LiteralPath $dest -Recurse -Force};throw}
    $dest
}
function Previous-Payload($Version) {
    $candidates=@(foreach($file in Get-ChildItem (Join-Path $Root 'backups') -Filter 'transaction.json' -Recurse -ErrorAction SilentlyContinue){
        $tx=Read-Json $file.FullName
        if($tx.status -eq 'complete' -and $tx.state.exists -and (Test-Path -LiteralPath $tx.state.copy)){
            $old=Read-Json $tx.state.copy
            if([version]$old.version -lt [version]$Version -and (Test-Path (Join-Path $old.payload 'release.json'))){[pscustomobject]@{version=[version]$old.version;payload=$old.payload}}
        }
    })
    $chosen=$candidates|Sort-Object version -Descending|Select-Object -First 1
    if(!$chosen){throw 'Предыдущая версия отсутствует'};$chosen.payload
}
function Run-Start($Settings,$Paths) {
    if($Sandbox){return}
    if('palette' -in $Settings.components){$runner=Find-PowerToys;if(!$runner){throw 'PowerToys не найден. Сохрани настройки, чтобы установить компонент палитры.'};if(!(Get-Process PowerToys -ErrorAction SilentlyContinue)){Start-Process -FilePath $runner -WindowStyle Hidden}}
    if('desktop' -in $Settings.components){
        if(!(Get-Process glazewm -ErrorAction SilentlyContinue)){Start-Process ($Paths.glazewm.Replace('\cli\','\')) -WindowStyle Hidden}
        else{& $Paths.glazewm command wm-reload-config|Out-Null}
        if(!(Get-Process zebar -ErrorAction SilentlyContinue)){Start-Process $Paths.zebar -WindowStyle Hidden}
    }
    if('borders' -in $Settings.components -and !(Get-Process tacky-borders -ErrorAction SilentlyContinue)){Start-Process (Join-Path $ProfileRoot '.glzr\tools\tacky-borders\tacky-borders.exe') -WindowStyle Hidden}
    if($Settings.hideTaskbar -and !(Get-Process taskbar-toggle -ErrorAction SilentlyContinue)){Start-Process (Join-Path $ProfileRoot '.glzr\tools\taskbar-toggle\taskbar-toggle.exe') -WindowStyle Hidden}
    if('files' -in $Settings.components){Start-Process (Join-Path $ProfileRoot 'AppData\Roaming\yazi\config\bin\open-with.exe') '--warm' -WindowStyle Hidden}
}
try{
    $Root=[IO.Path]::GetFullPath($Root)
    if(Test-Path (Join-Path $Root 'installed.json')){$existing=Read-Json (Join-Path $Root 'installed.json');if($existing.PSObject.Properties['sandbox'] -and $existing.sandbox){$Sandbox=$true;$ProfileRoot=$existing.profile}}
    if(!$ProfileRoot){$ProfileRoot=[Environment]::GetFolderPath('UserProfile')};if(!$Cache){$Cache=Join-Path $Root 'cache'}
    if($Sandbox -and ![IO.Path]::GetFullPath($ProfileRoot).StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Тестовый профиль должен находиться внутри тестового корня'}
    [IO.Directory]::CreateDirectory($Root)|Out-Null
    $stateFile=Join-Path $Root 'installed.json';$settingsPath=Join-Path $Root 'settings.json'
    $settings=if(Test-Path $settingsPath){Read-Json $settingsPath}else{Default-Settings}
    $mutating=$Action -in 'Install','Apply','Update','Rollback','Uninstall','Import'
    $lock=$null;if($mutating){try{$lock=[IO.File]::Open((Join-Path $Root '.operation.lock'),'OpenOrCreate','ReadWrite','None')}catch{throw 'Другая операция уже выполняется'}}
    try{
        if($mutating){foreach($txFile in Get-ChildItem (Join-Path $Root 'backups') -Filter 'transaction.json' -Recurse -ErrorAction SilentlyContinue){$tx=Read-Json $txFile.FullName;if($tx.status -eq 'prepared'){Restore-Records $tx.files -RespectChanges;Restore-Records @($tx.state,$tx.settings,$tx.baseline);Restore-System $tx.system;if($tx.PSObject.Properties['services']){Resume-Services $tx.services};Write-Json $txFile.FullName @{status='recovered';files=$tx.files}}}}
        $answer=switch($Action){
            {$_ -in 'Install','Import'} {
                if(!$Release){throw 'Не указан каталог выпуска'}
                $manifest=Read-Json (Join-Path $Release 'release.json');if($manifest.schema -ne 1 -or $manifest.version -notmatch '^\d+\.\d+\.\d+$'){throw 'Неподдерживаемый манифест выпуска'};$dest=Join-Path $Root ('versions\'+$manifest.version)
                if([IO.Path]::GetFullPath($Release) -ne [IO.Path]::GetFullPath($dest)){[IO.Directory]::CreateDirectory($dest)|Out-Null;Copy-Item (Join-Path $Release '*') $dest -Recurse -Force}
                if($SettingsFile){$settings=Read-Json $SettingsFile}
                Apply-Payload $dest $settings -ImportExisting:($Action -eq 'Import')
            }
            'Apply' {$s=Read-Json $stateFile;if($SettingsFile){$settings=Read-Json $SettingsFile};if($Feed){$settings.feed=$Feed};Apply-Payload $s.payload $settings}
            'Check' {Get-Update $settings}
            'Update' {$u=Get-Update $settings;if(!$u.available){$u}else{$payload=Stage-Release $u.url $u.sha256 $u.version;Apply-Payload $payload $settings}}
            'Rollback' {
                $s=Read-Json $stateFile;$oldPayload=Previous-Payload $s.version
                Apply-Payload $oldPayload $settings
            }
            'Status' {
                $s=if(Test-Path $stateFile){Read-Json $stateFile}else{$null}
                $conflictRows=@(if(Test-Path (Join-Path $Root 'conflicts.json')){Read-Json (Join-Path $Root 'conflicts.json')})
                $modifiedRows=@(if($s){$s.files|Where-Object{(Hash $_.target) -ne $_.after}|ForEach-Object{$_.target}})
                $checks=@(if($s){foreach($property in $s.paths.PSObject.Properties){if($property.Value -notlike '*\disabled\*'){[pscustomobject]@{name=$property.Name;exists=(Test-Path -LiteralPath $property.Value)}}}})
                @{ok=$true;version=$(if($s){$s.version}else{'не установлено'});settings=$settings;root=$Root;monitors=$(Add-Type -AssemblyName System.Windows.Forms; @([Windows.Forms.Screen]::AllScreens).Count);backups=@(Get-ChildItem (Join-Path $Root 'backups') -Directory -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name);conflicts=$conflictRows;components=$(if($s){$s.paths}else{@{}});modified=$modifiedRows;checks=$checks}
            }
            'RestoreTaskbar' {Restore-Taskbar;@{ok=$true;message='Панель Windows восстановлена'}}
            'Palette' {if('palette' -notin $settings.components){throw 'Включи компонент палитры PowerToys в центре управления'};if(!$Sandbox){if(!(Find-PowerToys)){throw 'PowerToys не найден. Повтори сохранение настроек'};if(!(Get-AppxPackage -Name Microsoft.CommandPalette)){throw 'Command Palette не зарегистрирована. Включи её в настройках PowerToys, затем повтори запуск.'};Start-Process $(if($PaletteSettings){'x-cmdpal://settings/'}else{'x-cmdpal://'})};@{ok=$true}}
            'Uninstall' {
                $s=Read-Json $stateFile;$base=@(Read-Json (Join-Path $Root 'baseline.json'))
                $hadWm=@($base|Where-Object{$_.target -eq (Join-Path $ProfileRoot '.glzr\glazewm\config.yaml') -and $_.exists}).Count -gt 0
                $hadBar=@($base|Where-Object{$_.target -eq (Join-Path $ProfileRoot '.glzr\zebar\settings.json') -and $_.exists}).Count -gt 0
                if(!$Sandbox){
                    if(!$hadWm -and 'desktop' -in $settings.components){& $s.paths.glazewm command wm-exit|Out-Null}
                    foreach($p in Get-CimInstance Win32_Process -Filter "Name='zebar.exe' OR Name='tacky-borders.exe'"){
                        $ownedBar=$p.ExecutablePath -eq $s.paths.zebar
                        $ownedBorder=@($base|Where-Object{$_.target -eq $p.ExecutablePath -and !$_.exists}).Count -gt 0
                        if($ownedBar -or $ownedBorder){Stop-Process -Id $p.ProcessId}
                    }
                }
                Restore-Taskbar
                if(!$Sandbox){$settings.cursor=$false;Set-Cursor $settings @{}; $auto=Join-Path ([Environment]::GetFolderPath('Startup')) 'Rose Pine Desktop.lnk';if(Test-Path $auto){Remove-Item -LiteralPath $auto};$reg='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts';$key=Get-Item $reg -ErrorAction SilentlyContinue;if($key){foreach($n in $key.GetValueNames()){if($n.StartsWith('Rose Pine Desktop ')){Remove-ItemProperty $reg $n}}}}
                $last=@{};foreach($f in $s.files){$last[$f.target]=$f.after};foreach($f in $base){if($last.ContainsKey($f.target)){$f.after=$last[$f.target]}}
                Restore-Records $base -RespectChanges
                if(!$Sandbox){if($hadWm -and (Test-Path $s.paths.glazewm)){& $s.paths.glazewm command wm-reload-config|Out-Null};if($hadBar){$original=Join-Path $env:ProgramFiles 'glzr.io\Zebar\zebar.exe';if(Test-Path $original){Start-Process $original -WindowStyle Hidden}}}
                Move-Item -LiteralPath $stateFile -Destination (Join-Path $Root 'uninstalled.json') -Force
                @{ok=$true;message='Исходные конфиги восстановлены. Личные правки и резервные копии сохранены.'}
            }
            'Start' {$s=Read-Json $stateFile;Run-Start $settings $s.paths;@{ok=$true}}
            'Browser' {if($settings.browser -and (Test-Path -LiteralPath $settings.browser)){Start-Process -FilePath $settings.browser}else{Start-Process 'https://www.google.com/'};@{ok=$true}}
            {$_ -in 'Files','Console'} {if('files' -notin $settings.components){throw 'Включи компонент Yazi и терминала в центре управления'};$s=Read-Json $stateFile;$args=@('--config-file',('"'+(Join-Path $Root 'config\alacritty.toml')+'"'),'--working-directory',('"'+(Get-Location).Path+'"'));if($Action -eq 'Console'){$args+=@('--title','PowerShell','-e',('"'+$env:WINDIR+'\System32\WindowsPowerShell\v1.0\powershell.exe"'),'-NoLogo')};Start-Process $s.paths.alacritty -ArgumentList $args;@{ok=$true}}
        }
    }finally{if($lock){$lock.Dispose()}}
    if($Result){Write-Json $Result $answer}else{$answer|ConvertTo-Json -Depth 40}
}catch{
    $failure=@{ok=$false;error=$_.Exception.Message;detail=$_.ScriptStackTrace}
    if($Result){Write-Json $Result $failure}else{$failure|ConvertTo-Json -Depth 10};exit 1
}
