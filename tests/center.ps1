param([string]$Repo=(Split-Path $PSScriptRoot),[string]$TestRoot)
$ErrorActionPreference='Stop'
$version=(Get-Content (Join-Path $Repo 'VERSION') -Raw).Trim()
$payload=Join-Path $Repo "build\payload-$version"
if(!$TestRoot){$TestRoot=Join-Path $Repo ('test-results\center-'+(Get-Date -Format yyyyMMdd-HHmmss))}
$TestRoot=[IO.Path]::GetFullPath($TestRoot)
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$profile=Join-Path $TestRoot ([string][char]0x41F+[char]0x440+[char]0x43E+[char]0x444+[char]0x438+[char]0x43B+[char]0x44C+' test')
if(Test-Path (Join-Path $TestRoot 'installed.json')){
    $installed=Get-Content (Join-Path $TestRoot 'installed.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if(!$installed.sandbox){throw 'Requires a sandbox installation'}
}else{
    $previous=Join-Path $TestRoot 'previous-release'
    Copy-Item $payload $previous -Recurse
    $manifest=Get-Content (Join-Path $previous 'release.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $manifest.version='0.0.1';$manifest|ConvertTo-Json|Set-Content (Join-Path $previous 'release.json') -Encoding UTF8
    & $ps -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $payload 'Desktop.ps1') -Action Install -Root $TestRoot -ProfileRoot $profile -Sandbox -Release $previous -Cache (Join-Path $Repo 'cache')|Out-Null
    if($LASTEXITCODE){throw 'Previous sandbox installation failed'}
    & $ps -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $payload 'Desktop.ps1') -Action Install -Root $TestRoot -ProfileRoot $profile -Sandbox -Release $payload -Cache (Join-Path $Repo 'cache')|Out-Null
    if($LASTEXITCODE){throw 'Sandbox installation failed'}
}
$receipt=Join-Path $TestRoot 'center-ui.json'
if(Test-Path $receipt){Remove-Item -LiteralPath $receipt}
$app=Start-Process (Join-Path $payload 'Center.exe') -ArgumentList @('--root',('"'+$TestRoot+'"'),'--smoke-test',('"'+$receipt+'"')) -PassThru
if(!$app.WaitForExit(55000)){throw 'Center UI test timed out; test window left open for inspection'}
if(!(Test-Path $receipt)){throw 'Center did not produce a test result'}
$result=Get-Content $receipt -Raw -Encoding UTF8|ConvertFrom-Json
if(!$result.ok){throw $result.error}
$result|ConvertTo-Json
