param([string]$Root=(Join-Path $env:LOCALAPPDATA 'RosePineDesktop'),[string]$Repo=(Split-Path $PSScriptRoot))
$ErrorActionPreference='Stop'
$state=Get-Content (Join-Path $Root 'installed.json') -Raw -Encoding UTF8|ConvertFrom-Json
$folder=Join-Path $Root ('native-tools\'+[char]0x41A+[char]0x430+[char]0x442+' & 100% (test)')
New-Item -ItemType Directory $folder -Force|Out-Null
$report=@()
foreach($action in 'console','files'){
    $before=@(Get-CimInstance Win32_Process -Filter "Name='alacritty.exe'"|Select-Object -ExpandProperty ProcessId)
    try{
        $launcher=Start-Process -FilePath (Join-Path $Root 'RosePineCenter.exe') -ArgumentList ('--'+$action) -WorkingDirectory $folder -WindowStyle Hidden -PassThru
        # Do not use Start-Process -Wait: it waits for the whole interactive process tree.
        [void]$launcher.WaitForExit(2000);Start-Sleep -Seconds 2
        $new=@(Get-CimInstance Win32_Process -Filter "Name='alacritty.exe'"|Where-Object{$_.ProcessId -notin $before -and $_.ExecutablePath -eq $state.paths.alacritty -and $_.CommandLine.Contains($folder)})
        if($new.Count -ne 1){throw "Expected one terminal: $action"}
        $process=Get-Process -Id $new[0].ProcessId
        $expected=if($action -eq 'console'){'PowerShell'}else{'Yazi'}
        if($process.MainWindowTitle -ne $expected){throw "Wrong terminal title: $($process.MainWindowTitle)"}
        $report+=@{action=$action;title=$process.MainWindowTitle;cwdArgumentVerified=$true;ok=$true}
    }finally{
        foreach($p in Get-CimInstance Win32_Process -Filter "Name='alacritty.exe'"|Where-Object{$_.ProcessId -notin $before -and $_.ExecutablePath -eq $state.paths.alacritty -and $_.CommandLine.Contains($folder)}){
            $live=Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
            if($live){$window=(& $state.paths.glazewm query windows|ConvertFrom-Json).data.windows|Where-Object handle -eq ([long]$live.MainWindowHandle)|Select-Object -First 1;if($window){& $state.paths.glazewm command --id $window.id close|Out-Null}else{Stop-Process -Id $p.ProcessId}}
        }
        Start-Sleep -Milliseconds 300
    }
}
ConvertTo-Json -InputObject $report -Depth 5|Set-Content "$Repo\test-results\launch-check.json" -Encoding UTF8
Get-Content "$Repo\test-results\launch-check.json"
