param([string]$Repo=(Split-Path $PSScriptRoot),[string]$TestRoot)
$ErrorActionPreference='Stop'
$version=(Get-Content (Join-Path $Repo 'VERSION') -Raw).Trim()
$payload=Join-Path $Repo "build\payload-$version"
Add-Type -AssemblyName System.Web.Extensions
Add-Type -Path (Join-Path $payload 'Shortcuts.dll')
$catalog=Join-Path $payload 'shortcuts.json'
function Assert($test,$message){if(!$test){throw $message}}
function Reject($text,$message){try{[DesktopShortcuts]::Render($catalog,$text)|Out-Null}catch{return};throw $message}
$defs=[DesktopShortcuts]::Load($catalog)
Assert ($defs.Count -eq 51) 'Catalog incomplete'
Assert (($defs|Where-Object id -eq 'workspace-0').bindings[0] -eq 'alt+0') 'Workspace zero missing'
Assert (($defs|Where-Object id -eq 'send-workspace-0').bindings[0] -eq 'alt+shift+0') 'Move to workspace zero missing'
$latin='qwertyuiopasdfghjklzxcvbnm'
$russian=-join @(0x439,0x446,0x443,0x43A,0x435,0x43D,0x433,0x448,0x449,0x437,0x444,0x44B,0x432,0x430,0x43F,0x440,0x43E,0x43B,0x434,0x44F,0x447,0x441,0x43C,0x438,0x442,0x44C|ForEach-Object{[char]$_})
for($i=0;$i -lt $latin.Length;$i++){
    foreach($mods in 'alt+','control+shift+','shift+alt+control+'){
        Assert ([DesktopShortcuts]::Normalize($mods+$latin[$i]) -eq [DesktopShortcuts]::Normalize($mods+$russian[$i])) 'EN/RU mismatch'
    }
}
foreach($item in $defs){foreach($binding in $item.bindings){Assert ([DesktopShortcuts]::Normalize([DesktopShortcuts]::Format($binding)) -eq [DesktopShortcuts]::Normalize($binding)) 'Format round-trip failed'}}
Reject '{"browser":["shift+alt+q"]}' 'Duplicate accepted'
Reject '{"browser":["lalt+q"]}' 'Left modifier overlap accepted'
Reject '{"browser":["alt+e'']}\n- commands: [wm-exit]"]}' 'Injected syntax accepted'
Reject '{"browser":["b"]}' 'Unmodified global letter accepted'
if(!$TestRoot){$TestRoot=Join-Path $Repo ('test-results\shortcuts-'+(Get-Date -Format yyyyMMdd-HHmmss))}
$TestRoot=[IO.Path]::GetFullPath($TestRoot)
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$profile=Join-Path $TestRoot 'profile'
function Engine($action,$extra=@(),[switch]$Fails){
    $raw=& $ps -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $payload 'Desktop.ps1') -Action $action -Root $TestRoot -Sandbox -ProfileRoot $profile -Cache (Join-Path $Repo 'cache') @extra
    if($Fails){Assert ($LASTEXITCODE -ne 0) 'Expected rejection'}else{Assert ($LASTEXITCODE -eq 0) ($raw -join "`n")}
    $raw|ConvertFrom-Json
}
Engine Install @('-Release',$payload)|Out-Null
$config=Join-Path $profile '.glzr\glazewm\config.yaml'
$help=Join-Path $profile '.glzr\zebar\hypr-dark\help.html'
$settings=Get-Content (Join-Path $TestRoot 'settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
$settings|Add-Member NoteProperty hotkeys @{browser=@('alt+f6')}
$request=Join-Path $TestRoot 'test-settings.json'
$settings|ConvertTo-Json -Depth 15|Set-Content $request -Encoding UTF8
Engine Apply @('-SettingsFile',$request)|Out-Null
Assert ((Get-Content $config -Raw).Contains("bindings: ['alt+f6']")) 'Custom shortcut missing'
Assert ((Get-Content $help -Raw -Encoding UTF8).Contains('Alt+F6')) 'Help stale'
$before=(Get-FileHash $config).Hash
$settings.hotkeys.browser=@('alt+e');$settings|ConvertTo-Json -Depth 15|Set-Content $request -Encoding UTF8
Engine Apply @('-SettingsFile',$request) -Fails|Out-Null
Assert ((Get-FileHash $config).Hash -eq $before) 'Failed validation changed config'
Assert ((Get-Content (Join-Path $TestRoot 'settings.json') -Raw|ConvertFrom-Json).hotkeys.browser[0] -eq 'alt+f6') 'Failed validation changed settings'
$next=[version]$version;$nextVersion="{0}.{1}.{2}" -f $next.Major,$next.Minor,($next.Build+1)
$fixture=Join-Path $TestRoot "fixture-$nextVersion"
Copy-Item $payload $fixture -Recurse
$manifest=Get-Content (Join-Path $fixture 'release.json') -Raw -Encoding UTF8|ConvertFrom-Json;$manifest.version=$nextVersion;$manifest|ConvertTo-Json|Set-Content (Join-Path $fixture 'release.json') -Encoding UTF8
Engine Install @('-Release',$fixture)|Out-Null
Assert ((Get-Content $config -Raw).Contains("bindings: ['alt+f6']")) 'Upgrade lost shortcut'
Engine Rollback|Out-Null
Assert ((Get-Content $config -Raw).Contains("bindings: ['alt+f6']")) 'Rollback lost shortcut'
$settings.hotkeys=@{};$settings|ConvertTo-Json -Depth 15|Set-Content $request -Encoding UTF8
Engine Apply @('-SettingsFile',$request)|Out-Null
Assert ((Get-Content $config -Raw).Contains("bindings: ['alt+b']")) 'Default reset failed'
Assert ((Get-Content $help -Raw -Encoding UTF8).Contains('Alt+B')) 'Help reset failed'
@{ok=$true;actions=$defs.Count;physicalLayoutChecks=78;cases=@('validation','EN/RU','format','apply','help','conflict atomicity','upgrade','rollback','reset')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $TestRoot 'shortcuts-test.json')
