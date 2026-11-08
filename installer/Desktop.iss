#ifndef ReleaseVersion
  #define ReleaseVersion "0.1.0"
#endif
[Setup]
#ifdef IsTest
AppId={{FF2DC10D-353B-4D9F-B87E-AF6721707EB1}
#else
AppId={{37BAA880-C637-4F2F-8D8C-414B5B0E4058}
#endif
AppName=Rose Pine Desktop
AppVersion={#ReleaseVersion}
DefaultDirName={localappdata}\RosePineDesktop
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\dist
#ifdef IsTest
OutputBaseFilename=RosePineDesktop-TestSetup-{#ReleaseVersion}
#else
OutputBaseFilename=RosePineDesktop-Setup-{#ReleaseVersion}
#endif
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\RosePineCenter.exe
CloseApplications=no
RestartApplications=no
SetupLogging=yes
UninstallLogging=yes
[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
[Types]
Name: "full"; Description: "Всё окружение"
Name: "custom"; Description: "Выбрать компоненты"; Flags: iscustom
[Components]
Name: "desktop"; Description: "GlazeWM и панель Rosé Pine"; Types: full
Name: "files"; Description: "Yazi, терминал и предпросмотр файлов"; Types: full
Name: "borders"; Description: "Обводка активного окна"; Types: full
Name: "palette"; Description: "Палитра команд Microsoft PowerToys (Win+Alt+Пробел)"; Types: full; MinVersion: 10.0.19041
[Tasks]
Name: "hide"; Description: "Скрывать панель Windows; переключать клавишей Win"; Flags: unchecked
Name: "cursor"; Description: "Установить курсор Bibata Modern Ice"; Flags: unchecked
[Files]
Source: "..\build\RosePineCenter.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Payload}\*"; DestDir: "{app}\versions\{#ReleaseVersion}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Run]
Filename: "{app}\RosePineCenter.exe"; Description: "Открыть центр управления"; Flags: postinstall nowait skipifsilent
[Code]
function InstallRuntime(): Boolean;
var
  Args, Receipt: String;
  Code: Integer;
begin
  Receipt := ExpandConstant('{app}\setup-result.json');
  Args := '-NoProfile -STA -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\versions\{#ReleaseVersion}\Desktop.ps1') + '" -Action Install -Root "' + ExpandConstant('{app}') + '" -Release "' + ExpandConstant('{app}\versions\{#ReleaseVersion}') + '" -Components "' + WizardSelectedComponents(False) + '" -Result "' + Receipt + '"';
  if ExpandConstant('{param:IMPORT|0}') = '1' then StringChangeEx(Args, '-Action Install', '-Action Import', True);
  if ExpandConstant('{param:SETTINGS|}') <> '' then Args := Args + ' -SettingsFile "' + ExpandConstant('{param:SETTINGS|}') + '"';
  if WizardIsTaskSelected('hide') then Args := Args + ' -HideTaskbar';
  if WizardIsTaskSelected('cursor') then Args := Args + ' -Cursor';
  if ExpandConstant('{param:SANDBOX|0}') = '1' then Args := Args + ' -Sandbox -ProfileRoot "' + ExpandConstant('{app}\Test Profile') + '"';
  if ExpandConstant('{param:CACHE|}') <> '' then Args := Args + ' -Cache "' + ExpandConstant('{param:CACHE|}') + '"';
  WizardForm.StatusLabel.Caption := 'Загрузка и проверка компонентов. Это может занять несколько минут…';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
end;
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and not InstallRuntime() then
    RaiseException('Настройка не завершена. Проверьте setup-result.json и папку logs в каталоге RosePineDesktop. Журнал установщика сохраняется в %TEMP%.');
end;
function InitializeUninstall(): Boolean;
var Code: Integer;
begin
  Result := True;
  if FileExists(ExpandConstant('{app}\installed.json')) then
    Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), '-NoProfile -STA -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\versions\{#ReleaseVersion}\Desktop.ps1') + '" -Action Uninstall -Root "' + ExpandConstant('{app}') + '" -Result "' + ExpandConstant('{app}\uninstall-result.json') + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
  if not Result then MsgBox('Удаление не завершено. Проверьте uninstall-result.json и папку logs в каталоге RosePineDesktop.', mbInformation, MB_OK);
end;
