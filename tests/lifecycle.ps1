param([string]$Repo=(Split-Path $PSScriptRoot),[string]$TestRoot)
$ErrorActionPreference='Stop'
if(!$TestRoot){$TestRoot=Join-Path $Repo ('test-results\lifecycle-'+(Get-Date -Format yyyyMMdd-HHmmss))}
$TestRoot=[IO.Path]::GetFullPath($TestRoot)
$BaseVersion=(Get-Content (Join-Path $Repo 'VERSION') -Raw).Trim()
$baseNumber=[version]$BaseVersion;$NextVersion="{0}.{1}.{2}" -f $baseNumber.Major,$baseNumber.Minor,($baseNumber.Build+1);$BadVersion="{0}.{1}.{2}" -f $baseNumber.Major,$baseNumber.Minor,($baseNumber.Build+2)
$profile=Join-Path $TestRoot ([string][char]0x41F+[char]0x440+[char]0x43E+[char]0x444+[char]0x438+[char]0x43B+[char]0x44C+' test')
$engine=Join-Path $Repo ("build\payload-$BaseVersion\Desktop.ps1")
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$results=New-Object Collections.Generic.List[object]
function Assert($Condition,$Message){if(!$Condition){throw $Message}}
function Invoke-Engine($Action,$Extra=@(),[switch]$Fails,[int]$Monitors=1){
    $raw=& $ps -NoProfile -STA -ExecutionPolicy Bypass -File $engine -Action $Action -Root $TestRoot -ProfileRoot $profile -Sandbox -Cache "$Repo\cache" -MonitorCount $Monitors @Extra
    $code=$LASTEXITCODE
    $r=$raw|ConvertFrom-Json
    if($Fails){Assert ($code -ne 0) "Expected failure: $Action"}else{Assert ($code -eq 0) ($raw -join "`n")}
    $r
}
New-Item -ItemType Directory $profile -Force|Out-Null
$old=Join-Path $profile '.glzr\glazewm\config.yaml';New-Item -ItemType Directory (Split-Path $old) -Force|Out-Null;[IO.File]::WriteAllText($old,'original config')
$r=Invoke-Engine Install @('-Release',"$Repo\build\payload-$BaseVersion");$results.Add(@{test='clean install';passed=$r.ok})
Assert ((Get-Content $old -Raw) -notmatch 'bind_to_monitor: 1') 'Single monitor fallback failed'
Assert ((Get-Content $old -Raw) -notmatch '@[A-Z_]+@') 'Unresolved template'
Assert (!(Get-Content $old -Raw).Contains(([Environment]::GetFolderPath('UserProfile').Replace('\','/')+'/.glzr'))) 'Original user profile leaked'
$r=Invoke-Engine Install @('-Release',"$Repo\build\payload-$BaseVersion");Assert ($r.changed -eq 0) 'Reinstall is not idempotent';$results.Add(@{test='repeat install';passed=$true})
$settings=Get-Content "$TestRoot\settings.json" -Raw|ConvertFrom-Json
$history=Join-Path $profile 'AppData\Roaming\yazi\config\open-with-history.json';[IO.File]::WriteAllText($history,'{"keep":true}')
$feed=Join-Path $TestRoot 'feed.json'
$updatePayload=Join-Path $TestRoot ("fixture-$NextVersion");Copy-Item "$Repo\build\payload-$BaseVersion" $updatePayload -Recurse
$m=Get-Content "$updatePayload\release.json" -Raw|ConvertFrom-Json;$m.version=$NextVersion;$m|ConvertTo-Json|Set-Content "$updatePayload\release.json" -Encoding UTF8
Add-Content "$updatePayload\templates\glazewm\config.yaml" "`n# test update" -Encoding UTF8
$zip=Join-Path $TestRoot ("fixture-$NextVersion.zip");Add-Type -AssemblyName System.IO.Compression.FileSystem;[IO.Compression.ZipFile]::CreateFromDirectory($updatePayload,$zip)
@{schema=1;version=$NextVersion;url=$zip;sha256=(Get-FileHash $zip).Hash;notes='Local update test'}|ConvertTo-Json|Set-Content $feed -Encoding UTF8
$settings.feed=$feed;$settings|ConvertTo-Json -Depth 10|Set-Content "$TestRoot\test-settings.json" -Encoding UTF8
Invoke-Engine Apply @('-SettingsFile',"$TestRoot\test-settings.json")|Out-Null
$r=Invoke-Engine Check;Assert $r.available 'Update was not found'
# Simulate a prior crash during extraction, including an apparently valid manifest.
$partial=Join-Path $TestRoot ("versions\$NextVersion")
New-Item -ItemType Directory $partial -Force|Out-Null
Copy-Item "$updatePayload\release.json" $partial
$r=Invoke-Engine Update;Assert ($r.version -eq $NextVersion) 'Update failed';Assert ((Get-Content $old -Raw) -match '# test update') 'Updated config missing';Assert ((Get-Content $history -Raw) -eq '{"keep":true}') 'History was overwritten';$results.Add(@{test='local update + preserve data';passed=$true})
$results.Add(@{test='retry after interrupted extraction';passed=$true})
$settings.autostart=$false;$settings|ConvertTo-Json -Depth 10|Set-Content "$TestRoot\test-settings.json" -Encoding UTF8
Invoke-Engine Apply @('-SettingsFile',"$TestRoot\test-settings.json")|Out-Null
$r=Invoke-Engine Rollback;Assert ($r.version -eq $BaseVersion) 'Rollback failed';Assert ((Get-Content $old -Raw) -notmatch '# test update') 'Rollback did not restore config';Assert (!(Get-Content "$TestRoot\settings.json" -Raw|ConvertFrom-Json).autostart) 'Rollback lost newer user settings';$results.Add(@{test='version rollback after settings change';passed=$true})
$before=(Get-FileHash $old).Hash
$locked=[IO.File]::Open($old,'Open','ReadWrite','None')
try{Invoke-Engine Update @() -Fails|Out-Null}finally{$locked.Dispose()}
Assert ((Get-FileHash $old).Hash -eq $before) 'Locked file update changed configuration';$results.Add(@{test='busy file deferred';passed=$true})
Invoke-Engine Update @('-FailAfter','1') -Fails|Out-Null
Assert ((Get-FileHash $old).Hash -eq $before) 'Failed write was not restored';Assert ((Get-Content "$TestRoot\installed.json" -Raw|ConvertFrom-Json).version -eq $BaseVersion) 'Failed write changed version';$results.Add(@{test='transaction failure recovery';passed=$true})
$settings.workspaces[4].monitor=1;$settings.workspaces[5].monitor=1;$settings|ConvertTo-Json -Depth 10|Set-Content "$TestRoot\test-settings.json" -Encoding UTF8
Invoke-Engine Apply @('-SettingsFile',"$TestRoot\test-settings.json") -Monitors 2|Out-Null
Assert ((Get-Content $old -Raw) -match 'bind_to_monitor: 1') 'Two monitors not configured';$results.Add(@{test='one and two monitors';passed=$true})
Invoke-Engine Apply|Out-Null
$settings.components=@('files');$settings|ConvertTo-Json -Depth 10|Set-Content "$TestRoot\test-settings.json" -Encoding UTF8
Invoke-Engine Apply @('-SettingsFile',"$TestRoot\test-settings.json")|Out-Null
Assert ((Get-Content $old -Raw) -eq 'original config') 'Removed component did not restore its config'
$settings.components=@('desktop','files','borders');$settings|ConvertTo-Json -Depth 10|Set-Content "$TestRoot\test-settings.json" -Encoding UTF8
Invoke-Engine Apply @('-SettingsFile',"$TestRoot\test-settings.json")|Out-Null;$results.Add(@{test='component selection';passed=$true})
Add-Content $old '# manual edit' -Encoding UTF8
$before=(Get-FileHash $old).Hash
$r=Invoke-Engine Update @() -Fails;Assert ((Get-FileHash $old).Hash -eq $before) 'Manual changes lost';Assert (Test-Path "$TestRoot\conflicts.json") 'Conflict not recorded';$results.Add(@{test='manual conflict';passed=$true})
$settings.feed=Join-Path $TestRoot 'missing-feed.json';$settings|ConvertTo-Json -Depth 10|Set-Content "$TestRoot\settings.json" -Encoding UTF8
Invoke-Engine Check @() -Fails|Out-Null;$results.Add(@{test='unavailable feed';passed=$true})
$settings.feed=$feed;$settings|ConvertTo-Json -Depth 10|Set-Content "$TestRoot\settings.json" -Encoding UTF8
$f=Get-Content $feed -Raw|ConvertFrom-Json;$f.version=$BadVersion;$f.sha256=('0'*64);$f|ConvertTo-Json|Set-Content $feed -Encoding UTF8
Invoke-Engine Update @() -Fails|Out-Null;Assert ((Get-FileHash $old).Hash -eq $before) 'Corrupt update changed configuration';$results.Add(@{test='bad checksum';passed=$true})
$f.sha256=(Get-FileHash $zip).Hash;$f|ConvertTo-Json|Set-Content $feed -Encoding UTF8
Invoke-Engine Update @() -Fails|Out-Null
Assert (@(Get-ChildItem "$TestRoot\versions" -Directory -Filter "$BadVersion*").Count -eq 0) 'Rejected release left an incomplete directory'
Assert ((Get-FileHash $old).Hash -eq $before) 'Version mismatch changed configuration'
$results.Add(@{test='version mismatch cleanup';passed=$true})
Invoke-Engine Uninstall|Out-Null;Assert ((Get-FileHash $old).Hash -eq $before) 'Uninstall overwrote manual edit';Assert (Test-Path $history) 'Uninstall deleted history';$results.Add(@{test='uninstall preserves user changes';passed=$true})
Invoke-Engine Import @('-Release',"$Repo\build\payload-$BaseVersion")|Out-Null
Invoke-Engine Uninstall|Out-Null;Assert ((Get-Content $old -Raw) -eq 'original config') 'Original config not restored';$results.Add(@{test='uninstall restores original config';passed=$true})
Invoke-Engine Install @('-Release',"$Repo\build\payload-$BaseVersion")|Out-Null
$results|ConvertTo-Json -Depth 6|Set-Content "$TestRoot\results.json" -Encoding UTF8
$results|ConvertTo-Json -Depth 6
Write-Output "Evidence: $TestRoot"
