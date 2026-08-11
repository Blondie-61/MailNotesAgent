; MailNotes Agent - Windows Setup 0.2
; Erstellt mit Inno Setup 6

#define MyAppName "MailNotes Agent"
#define MyAppVersion "1.0.0.1"
#define MySetupVersion "0.2"
#define MyAppPublisher "MailNotes"
#define MyAppExeName "MailNotesAgent.exe"

[Setup]
AppId={{9E6E0D31-9F17-4E65-93DD-43811ED904F8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MailNotes\Agent
DefaultGroupName=MailNotes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=MailNotesAgent-Setup-{#MyAppVersion}
SetupIconFile=..\Resources\Windows\MN-OK-ALL.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
UsePreviousAppDir=yes
UsePreviousTasks=yes
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Setup für MailNotes Agent
VersionInfoProductName=MailNotes Agent Setup
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "autostart"; Description: "MailNotes Agent automatisch mit Windows starten"; GroupDescription: "Zusätzliche Aufgaben:"; Flags: checkedonce
Name: "desktopicon"; Description: "Desktop-Symbol erstellen"; GroupDescription: "Zusätzliche Aufgaben:"; Flags: unchecked

[Files]
Source: "..\Main\Win64\Release\MailNotesAgent.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Data\MailNotes.sqlite"; DestDir: "{app}\Data"; Flags: ignoreversion
Source: "Addin\*"; DestDir: "{autopf}\MailNotes\Addin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "OpenSSL\*"; DestDir: "{app}"; Flags: ignoreversion
Source: "CreateLocalCertificate.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "RemoveLocalCertificate.ps1"; DestDir: "{app}\Tools"; Flags: ignoreversion

[Icons]
Name: "{group}\MailNotes Agent"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\MailNotes Agent"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "MailNotesAgent"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart
Root: HKLM; Subkey: "Software\MailNotes"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"; Flags: uninsdeletekeyifempty
Root: HKLM; Subkey: "Software\MailNotes"; ValueType: string; ValueName: "AgentVersion"; ValueData: "{#MyAppVersion}"; Flags: uninsdeletekeyifempty
Root: HKLM; Subkey: "Software\MailNotes"; ValueType: string; ValueName: "SetupVersion"; ValueData: "{#MySetupVersion}"; Flags: uninsdeletekeyifempty

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{tmp}\CreateLocalCertificate.ps1"" -OutputDir ""{commonappdata}\MailNotes\TLS"""; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "MailNotes Agent starten"; Flags: nowait postinstall skipifsilent

[Code]
const
  AgentExeName = 'MailNotesAgent.exe';

function AgentIsRunning: Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  if Exec(ExpandConstant('{cmd}'),
    '/C tasklist /FI "IMAGENAME eq ' + AgentExeName + '" | find /I "' + AgentExeName + '" >nul',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := ResultCode = 0;
end;

procedure StopAgent;
var
  AgentPath: string;
  ResultCode: Integer;
  I: Integer;
begin
  if not AgentIsRunning then
    Exit;

  AgentPath := ExpandConstant('{app}\' + AgentExeName);
  if FileExists(AgentPath) then
    Exec(AgentPath, '/shutdown', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  for I := 1 to 20 do
  begin
    if not AgentIsRunning then
      Exit;
    Sleep(100);
  end;

  { Rückfall für ältere Agent-Versionen ohne /shutdown. }
  Exec(ExpandConstant('{sys}\taskkill.exe'),
    '/IM "' + AgentExeName + '" /T /F', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';

  if not AgentIsRunning then
    Exit;

  if MsgBox(
       'Zur Installation muss der MailNotes Agent beendet werden.' + #13#10 + #13#10 +
       'Möchten Sie den Agent jetzt beenden und mit der Installation fortfahren?',
       mbConfirmation,
       MB_OKCANCEL or MB_DEFBUTTON1
     ) <> IDOK then
  begin
    Result :=
      'Die Installation wurde abgebrochen, weil der MailNotes Agent noch ausgeführt wird.';
    Exit;
  end;

  StopAgent;

  if AgentIsRunning then
    Result :=
      'Der MailNotes Agent konnte nicht beendet werden.' + #13#10 +
      'Bitte beenden Sie ihn manuell und starten Sie das Setup anschließend erneut.';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDirectory: string;
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
    StopAgent;

  if CurUninstallStep = usPostUninstall then
  begin
    Exec(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""' +
      ExpandConstant('{app}\Tools\RemoveLocalCertificate.ps1') +
      '"" -OutputDir ""' +
      ExpandConstant('{commonappdata}\MailNotes\TLS') + '""',
      '',
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    );

    DataDirectory := ExpandConstant('{localappdata}\MailNotes');
    if DirExists(DataDirectory) and
       (MsgBox(
         'Sollen auch die persönlichen MailNotes-Daten gelöscht werden?' + #13#10 + #13#10 +
         'Dazu gehören insbesondere alle Notizen und die lokale Datenbank.' + #13#10 +
         'Die sichere Standardauswahl ist „Nein“.',
         mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES) then
    begin
      DelTree(DataDirectory, True, True, True);
    end;
  end;
end;
