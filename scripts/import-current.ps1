param([string]$Root=(Join-Path $env:LOCALAPPDATA 'RosePineDesktop'))
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$version=(Get-Content "$repo\VERSION" -Raw).Trim()
$userRoot=[Environment]::GetFolderPath('UserProfile')
$snapshot=Join-Path $Root ('backups\migration-'+(Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory $snapshot -Force|Out-Null
$items=@{glazewm=(Join-Path $userRoot '.glzr\glazewm');bar=(Join-Path $userRoot '.glzr\zebar\bar-rose-pine');help=(Join-Path $userRoot '.glzr\zebar\hypr-dark');zebarSettings=(Join-Path $userRoot '.glzr\zebar\settings.json');tools=(Join-Path $userRoot '.glzr\tools');yazi=(Join-Path $env:APPDATA 'yazi\config');terminal=(Join-Path $env:LOCALAPPDATA 'Programs\Alacritty\yazi.toml');borders=(Join-Path $userRoot '.config\tacky-borders');startup=[Environment]::GetFolderPath('Startup')}
foreach($name in $items.Keys){if(Test-Path -LiteralPath $items[$name]){Copy-Item -LiteralPath $items[$name] -Destination (Join-Path $snapshot $name) -Recurse -Force}}
$wm=Join-Path $userRoot '.glzr\glazewm\config.yaml'
$text=[IO.File]::ReadAllText($wm)
$spaces=@(foreach($m in [regex]::Matches($text,"name: '([1-9])', display_name: '([^']+)', bind_to_monitor: (\d+)")){[pscustomobject]@{name=$m.Groups[1].Value;label=($m.Groups[2].Value -replace '^\d+\s+','');monitor=[int]$m.Groups[3].Value}})
foreach($n in '8','9'){if($n -notin $spaces.name){$spaces+=[pscustomobject]@{name=$n;label=$n;monitor=0}}}
if($spaces.Count -ne 9){throw 'Could not import all nine workspaces'}
$browser='';$match=[regex]::Match($text,"commands: \['shell-exec ([^\r\n']+)'\]\r?\n    bindings: \['alt\+b'\]")
if($match.Success){$candidate=$match.Groups[1].Value.Replace('/','\');if(Test-Path -LiteralPath $candidate){$browser=$candidate}}
$controller=Join-Path $userRoot '.glzr\tools\taskbar-toggle\taskbar-toggle.exe'
$hidden=@(Get-Process taskbar-toggle -ErrorAction SilentlyContinue).Count -gt 0
$cursor=(Get-ItemProperty 'HKCU:\Control Panel\Cursors').Arrow -like '*Bibata*'
$settings=@{components=@('desktop','files','borders');autostart=$true;hideTaskbar=$hidden;cursor=$cursor;browser=$browser;workspaces=$spaces;feed='';checkAtLogon=$true}
$settingsFile=Join-Path $snapshot 'settings.json'
[IO.File]::WriteAllText($settingsFile,(ConvertTo-Json -InputObject $settings -Depth 10),[Text.UTF8Encoding]::new($false))
$stopped=$false
try{
    if($hidden -and (Test-Path $controller)){$p=Start-Process -FilePath $controller -ArgumentList '--stop' -WindowStyle Hidden -Wait -PassThru;if($p.ExitCode){throw 'Taskbar controller did not stop'};$stopped=$true}
    $p=Start-Process -FilePath "$repo\dist\RosePineDesktop-Setup-$version.exe" -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$Root+'"'),'/IMPORT=1',('/SETTINGS="'+$settingsFile+'"'),('/CACHE="'+$repo+'\cache"'),('/LOG="'+$snapshot+'\setup.log"')) -WindowStyle Hidden -Wait -PassThru
    if($p.ExitCode){throw "Setup failed ($($p.ExitCode)); see $snapshot"}
    $state=Get-Content (Join-Path $Root 'installed.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $cli=$state.paths.glazewm
    $response=& $cli command wm-reload-config | ConvertFrom-Json
    if(!$response.success){throw 'GlazeWM rejected the managed config'}
    # Restart only the desktop bar; never close user terminals or applications.
    foreach($p in Get-CimInstance Win32_Process -Filter "Name='zebar.exe'"){
        if($p.ExecutablePath -eq $state.paths.zebar -or $p.ExecutablePath -eq (Join-Path $env:ProgramFiles 'glzr.io\Zebar\zebar.exe')){Stop-Process -Id $p.ProcessId}
    }
    $command='command shell-exec '+$state.paths.zebar.Replace('\','/')+' startup --config-dir "'+(Join-Path $userRoot '.glzr\zebar').Replace('\','/')+'" --log-level error'
    $response=& $cli @($command -split ' ') | ConvertFrom-Json
    if(!$response.success){throw 'Could not restart bar'}
    if($hidden){& $cli command shell-exec $controller.Replace('\','/')|Out-Null}
    & $cli command shell-exec (Join-Path $Root 'RosePineCenter.exe').Replace('\','/')|Out-Null
    [pscustomobject]@{ok=$true;root=$Root;snapshot=$snapshot;version=$version;browser=$browser;taskbarHidden=$hidden;cursor=$cursor}|ConvertTo-Json
}catch{if($stopped -and $hidden -and (Test-Path $controller)){Start-Process $controller -WindowStyle Hidden};throw}
