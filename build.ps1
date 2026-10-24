param([string]$Version=(Get-Content "$PSScriptRoot\VERSION" -Raw).Trim(),[string]$Iscc,[switch]$SkipBar)
$ErrorActionPreference='Stop'
$repo=$PSScriptRoot
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
$payload=Join-Path $repo "build\payload-$Version"
if(Test-Path $payload){$full=[IO.Path]::GetFullPath($payload);if(!$full.StartsWith([IO.Path]::GetFullPath((Join-Path $repo 'build'))+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe build path'};Remove-Item -LiteralPath $full -Recurse -Force}
New-Item -ItemType Directory -Path $payload -Force|Out-Null
foreach($dir in 'templates','helpers','licenses'){New-Item -ItemType Directory -Path (Join-Path $payload $dir) -Force|Out-Null}
Copy-Item "$repo\templates\*" "$payload\templates" -Recurse -Force
Copy-Item "$repo\dependencies.json" $payload -Force
Copy-Item "$repo\prerequisites.json" $payload -Force
Copy-Item "$repo\shortcuts.json" $payload -Force
Copy-Item "$repo\THIRD-PARTY.md" $payload -Force
& node.exe "$repo\scripts\npm-notices.cjs"
if($LASTEXITCODE){throw 'License collection failed'}
Copy-Item "$repo\LICENSE" "$payload\licenses\RosePineDesktop-MIT.txt" -Force
Get-ChildItem "$repo\licenses" -File|Copy-Item -Destination "$payload\licenses" -Force
[IO.File]::WriteAllText("$payload\Desktop.ps1",[IO.File]::ReadAllText("$repo\runtime\Desktop.ps1"),[Text.UTF8Encoding]::new($true))
$bar=Join-Path $repo 'src\bar'
if(!$SkipBar){
    Push-Location $bar
    try{if(!(Test-Path 'node_modules')){& npm.cmd ci --no-audit --no-fund;if($LASTEXITCODE){throw 'npm ci failed'}};& npm.cmd run build;if($LASTEXITCODE){throw 'Bar build failed'}}finally{Pop-Location}
}
New-Item -ItemType Directory "$payload\templates\zebar\bar-rose-pine\dist" -Force|Out-Null
Copy-Item "$bar\dist\*" "$payload\templates\zebar\bar-rose-pine\dist" -Recurse -Force
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$refs=@('/r:System.Web.Extensions.dll','/r:System.Windows.Forms.dll','/r:System.Drawing.dll','/r:System.Xaml.dll')
$framework=Split-Path $csc
foreach($name in 'PresentationCore','PresentationFramework','WindowsBase','UIAutomationClient','UIAutomationTypes'){$refs+='/r:'+(Join-Path $framework "WPF\$name.dll")}
$helpers=@{CloseWindow='close-window';ResizeWindow='resize-window';PowerMenu='power-menu';TaskbarToggle='taskbar-toggle';TaskWindows='task-windows';TrayIdentity='tray-identity';OpenWithLauncher='open-with';YaziDrag='yazi-drag'}
foreach($name in $helpers.Keys){$target=if($name -in 'TaskWindows','TrayIdentity'){'/target:exe'}else{'/target:winexe'};& $csc /nologo $target /platform:x64 /optimize+ @refs "/out:$payload\helpers\$($helpers[$name]).exe" "$repo\src\helpers\$name.cs";if($LASTEXITCODE){throw "Compile failed: $name"}}
& $csc /nologo /target:library /optimize+ /r:System.Web.Extensions.dll "/out:$payload\Shortcuts.dll" "$repo\src\Shortcuts.cs"
if($LASTEXITCODE){throw 'Shortcut library compile failed'}
& $csc /nologo /target:winexe /platform:x64 /optimize+ @refs "/r:$payload\Shortcuts.dll" "/resource:$repo\src\Center.xaml,Center.xaml" "/out:$payload\Center.exe" "$repo\src\Center.cs"
if($LASTEXITCODE){throw 'Center compile failed'}
& $csc /nologo /target:winexe /platform:x64 /optimize+ @refs "/out:$repo\build\RosePineCenter.exe" "$repo\src\Launcher.cs"
if($LASTEXITCODE){throw 'Launcher compile failed'}
Copy-Item "$repo\build\RosePineCenter.exe" "$payload\Bootstrap.exe" -Force
$notes=[regex]::Match([IO.File]::ReadAllText("$repo\CHANGELOG.md"),'(?ms)^## '+[regex]::Escape($Version)+'\r?\n(.*?)(?=^## |\z)').Groups[1].Value.Trim()
if(!$notes){$notes='Rose Pine Desktop '+$Version}
$manifest=@{schema=1;version=$Version;os=@('Windows 10 1809+ x64','Windows 11 x64');notes=$notes;components=@('desktop','files','borders','cursor')}
[IO.File]::WriteAllText("$payload\release.json",($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
New-Item -ItemType Directory "$repo\dist" -Force|Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip="$repo\dist\RosePineDesktop-$Version.zip"
if(Test-Path $zip){Remove-Item -LiteralPath $zip}
[IO.Compression.ZipFile]::CreateFromDirectory($payload,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
$feed=@{schema=1;version=$Version;url="RosePineDesktop-$Version.zip";sha256=(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant();notes=$manifest.notes}
[IO.File]::WriteAllText("$repo\dist\release-$Version.json",($feed|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
if(!$Iscc){$candidates=@((Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'));$Iscc=$candidates|Where-Object{Test-Path $_}|Select-Object -First 1}
if(!$Iscc){throw 'Inno Setup 6.5+ required. Pass -Iscc full-path-to-ISCC.exe'}
& $Iscc "/DReleaseVersion=$Version" "/DPayload=$payload" "$repo\installer\Desktop.iss"
if($LASTEXITCODE){throw 'Installer build failed'}
Write-Output "Built: $repo\dist"
