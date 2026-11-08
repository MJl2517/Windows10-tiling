param([string]$Repo=(Split-Path $PSScriptRoot),[string]$Iscc)
$ErrorActionPreference='Stop'
$version=(Get-Content "$Repo\VERSION" -Raw).Trim()
if(!$Iscc){$Iscc=Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'}
$testRoot=Join-Path $Repo 'test-results\installer'
$realKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{37BAA880-C637-4F2F-8D8C-414B5B0E4058}_is1'
$realBefore=if(Test-Path $realKey){(Get-ItemProperty $realKey).InstallLocation}else{''}
& $Iscc '/DIsTest=1' "/DReleaseVersion=$version" "/DPayload=$Repo\build\payload-$version" "$Repo\installer\Desktop.iss"|Out-Null
if($LASTEXITCODE){throw 'Test installer compile failed'}
$arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$testRoot+'"'),'/SANDBOX=1',('/CACHE="'+$Repo+'\cache"'),('/LOG="'+$Repo+'\build\installer-test.log"'))
foreach($i in 1,2){$p=Start-Process "$Repo\dist\RosePineDesktop-TestSetup-$version.exe" -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru;if($p.ExitCode){throw "Installer failed: $($p.ExitCode)"};$result=Get-Content "$testRoot\setup-result.json" -Raw|ConvertFrom-Json;if(!$result.ok){throw 'Setup receipt failed'}}
$p=Start-Process "$testRoot\unins000.exe" -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+$Repo+'\build\uninstall-test.log"')) -WindowStyle Hidden -Wait -PassThru
if($p.ExitCode -or (Test-Path "$testRoot\installed.json")){throw 'Uninstaller failed'}
$receipt=Get-Content "$testRoot\uninstall-result.json" -Raw|ConvertFrom-Json
if(!$receipt.ok -or !(Test-Path -LiteralPath $receipt.log)){throw 'Uninstaller did not save its operation log'}
if(!(Test-Path "$Repo\build\installer-test.log") -or !(Test-Path "$Repo\build\uninstall-test.log")){throw 'Missing Inno Setup log'}
$realAfter=if(Test-Path $realKey){(Get-ItemProperty $realKey).InstallLocation}else{''}
if($realBefore -ne $realAfter){throw 'Test modified the real installation registration'}
@{ok=$true;install=$true;reinstall=$true;uninstall=$true;realRegistrationPreserved=$true}|ConvertTo-Json|Set-Content "$Repo\test-results\installer-check.json" -Encoding UTF8
Get-Content "$Repo\test-results\installer-check.json"
