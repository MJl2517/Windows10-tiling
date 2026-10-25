param([string]$Repo=(Split-Path $PSScriptRoot))
$ErrorActionPreference='Stop'
function Assert($test,$message){if(!$test){throw $message}}
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'runtime\Desktop.ps1'),[ref]$tokens,[ref]$errors)
Assert (!$errors.Count) 'Runtime syntax error'
foreach($name in 'Read-Json','Find-PowerToys','Ensure-PowerToys'){
    $definition=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
    . ([scriptblock]::Create($definition.Extent.Text))
}
$detected=Find-PowerToys
$fixture=Join-Path $Repo ('test-results\palette-'+(Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory $fixture -Force|Out-Null
$Cache=$fixture;$Sandbox=$false;$script:downloadCount=0;$script:installCount=0
$script:runner='';$script:afterInstall=Join-Path $env:WINDIR 'System32\notepad.exe'
function Find-PowerToys {return $script:runner}
function Download($url,$destination,$sha){$script:downloadCount++;Assert ($sha -match '^[0-9a-f]{64}$') 'Missing checksum';[IO.File]::WriteAllText($destination,'test installer')}
function Get-AuthenticodeSignature {param($LiteralPath) return @{Status=$script:signature;SignerCertificate=@{Subject='CN=Microsoft Corporation'}}}
function Start-Process {param($FilePath,$ArgumentList,[string]$WindowStyle,[switch]$Wait,[switch]$PassThru) $script:installCount++;$script:runner=$script:afterInstall;return @{ExitCode=$script:exitCode}}
# This test never runs an installer or writes PowerToys settings.
$script:signature='Valid';$script:exitCode=0
$settings=[pscustomobject]@{components=@('desktop')}
Assert (!(Ensure-PowerToys $Repo $settings)) 'Disabled component installed'
$settings.components=@('palette');$Sandbox=$true
Assert (!(Ensure-PowerToys $Repo $settings)) 'Sandbox installed PowerToys'
$Sandbox=$false;$script:runner=$script:afterInstall
Assert ((Ensure-PowerToys $Repo $settings) -eq $script:runner) 'Existing installation not reused'
Assert ($script:downloadCount -eq 0 -and $script:installCount -eq 0) 'Existing installation was replaced'
$script:runner='';$script:signature='NotSigned'
try{Ensure-PowerToys $Repo $settings|Out-Null;throw 'Unsigned installer accepted'}catch{Assert ($_.Exception.Message -ne 'Unsigned installer accepted') 'Unsigned installer accepted'}
Assert ($script:installCount -eq 0) 'Unsigned installer executed'
$script:signature='Valid'
Assert ((Ensure-PowerToys $Repo $settings) -eq $script:runner) 'New installation not detected'
Assert ($script:installCount -eq 1) 'Installer not invoked'
$script:runner='';$script:exitCode=1603
try{Ensure-PowerToys $Repo $settings|Out-Null;throw 'Failed installer accepted'}catch{Assert ($_.Exception.Message -ne 'Failed installer accepted') 'Failed installer accepted'}
$script:runner='';$script:exitCode=3010
Assert ((Ensure-PowerToys $Repo $settings) -eq $script:runner) 'Reboot exit code rejected'
$requirements=Get-Content (Join-Path $Repo 'prerequisites.json') -Raw|ConvertFrom-Json
$requirements.powertoys.minBuild=2147483647;$requirements|ConvertTo-Json -Depth 8|Set-Content (Join-Path $fixture 'prerequisites.json') -Encoding UTF8
$downloadsBefore=$script:downloadCount
try{Ensure-PowerToys $fixture $settings|Out-Null;throw 'Unsupported OS accepted'}catch{Assert ($_.Exception.Message -ne 'Unsupported OS accepted') 'Unsupported OS accepted'}
Assert ($script:downloadCount -eq $downloadsBefore) 'Unsupported OS downloaded installer'
@{ok=$true;cases=@('disabled','sandbox','reuse','signature rejection','install','failure','reboot required','unsupported OS');detected=$detected;realInstallerExecuted=$false}|ConvertTo-Json|Tee-Object (Join-Path $fixture 'result.json')
