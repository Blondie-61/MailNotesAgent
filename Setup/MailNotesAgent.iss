; MailNotes Agent - Windows Setup 0.2
; Erstellt mit Inno Setup 6

#define MyAppName "MailNotes Agent"
#define MyAppVersion "1.0.0.4"
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
Name: "addinsetup"; Description: "Outlook-Add-in jetzt einrichten (manifest.xml)"; GroupDescription: "Zusätzliche Aufgaben:"; Flags: checkedonce

[Files]
Source: "..\Main\Win64\Release\MailNotesAgent.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Data\MailNotes.sqlite"; DestDir: "{app}\Data"; Flags: ignoreversion
Source: "Addin\*"; DestDir: "{autopf}\MailNotes\Addin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "OpenSSL\*"; DestDir: "{app}"; Flags: ignoreversion
Source: "CreateLocalCertificate.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "RemoveLocalCertificate.ps1"; DestDir: "{app}\Tools"; Flags: ignoreversion
Source: "..\Resources\Windows\MN-OK-ALL.ico"; DestDir: "{app}"; DestName: "MailNotes.ico"; Flags: ignoreversion

[Icons]
Name: "{group}\MailNotes Agent"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\MailNotes.ico"
Name: "{autodesktop}\MailNotes Agent"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\MailNotes.ico"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "MailNotesAgent"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart
Root: HKLM; Subkey: "Software\MailNotes"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"; Flags: uninsdeletekeyifempty
Root: HKLM; Subkey: "Software\MailNotes"; ValueType: string; ValueName: "AgentVersion"; ValueData: "{#MyAppVersion}"; Flags: uninsdeletekeyifempty
Root: HKLM; Subkey: "Software\MailNotes"; ValueType: string; ValueName: "SetupVersion"; ValueData: "{#MySetupVersion}"; Flags: uninsdeletekeyifempty

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "MailNotes Agent starten"; Flags: nowait postinstall skipifsilent

[Code]
var
  AddinHelpLabel: TNewStaticText;
  AddinSetupOpened: Boolean;


procedure InitializeWizard;
begin
  AddinSetupOpened := False;

  AddinHelpLabel := TNewStaticText.Create(WizardForm);
  AddinHelpLabel.Parent := WizardForm.FinishedPage;
  AddinHelpLabel.Left := ScaleX(0);
  AddinHelpLabel.Top := ScaleY(64);
  AddinHelpLabel.Width := ScaleX(430);
  AddinHelpLabel.Height := ScaleY(230);
  AddinHelpLabel.AutoSize := False;
  AddinHelpLabel.WordWrap := True;
  AddinHelpLabel.Font.Size := 9;
  AddinHelpLabel.Visible := False;
end;

const
  HWND_TOPMOST = -1;
  SWP_NOSIZE = $0001;
  SWP_NOMOVE = $0002;
  SWP_SHOWWINDOW = $0040;

function SetWindowPos(
  hWnd: HWND;
  hWndInsertAfter: HWND;
  X, Y, cx, cy: Integer;
  uFlags: UINT
): Boolean;
external 'SetWindowPos@user32.dll stdcall';

function SetForegroundWindow(hWnd: HWND): Boolean;
external 'SetForegroundWindow@user32.dll stdcall';

procedure OpenAddinSetup;
var
  ErrorCode: Integer;
begin
  if not WizardIsTaskSelected('addinsetup') then
    Exit;

  if not ShellExecAsOriginalUser(
    '',
    'https://aka.ms/olksideload',
    '',
    '',
    SW_SHOWNORMAL,
    ewNoWait,
    ErrorCode
  ) then
    MsgBox(
      'Die Outlook-Seite konnte nicht im Standard-Browser geöffnet werden.' + #13#10 +
      'Bitte öffnen Sie aka.ms/olksideload manuell.',
      mbError,
      MB_OK
    );

  { Browser/Explorer kurz Zeit zum Öffnen geben und danach
    das bereits sichtbare Setup-Fenster nach vorn holen. }
  Sleep(1200);

  SetWindowPos(
    WizardForm.Handle,
    HWND_TOPMOST,
    0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_SHOWWINDOW
  );
  SetForegroundWindow(WizardForm.Handle);
end;


const
  AgentExeName = 'MailNotesAgent.exe';

function AgentIsRunning: Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  if Exec(
       ExpandConstant('{cmd}'),
       '/C tasklist /FI "IMAGENAME eq ' + AgentExeName + '" | find /I "' +
       AgentExeName + '" >nul',
       '',
       SW_HIDE,
       ewWaitUntilTerminated,
       ResultCode
     ) then
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


procedure CreateLocalCertificate;
var
  ResultCode: Integer;
  PowerShellParams: string;
begin
  PowerShellParams :=
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{tmp}\CreateLocalCertificate.ps1') +
    '" -OutputDir "' +
    ExpandConstant('{commonappdata}\MailNotes\TLS') + '"';

  if not Exec(
       ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
       PowerShellParams,
       '',
       SW_HIDE,
       ewWaitUntilTerminated,
       ResultCode
     ) then
    RaiseException('Die TLS-Zertifikatserzeugung konnte nicht gestartet werden.');

  if ResultCode <> 0 then
    RaiseException(
      'Das lokale HTTPS-Zertifikat für MailNotes konnte nicht erzeugt werden.' + #13#10 +
      'Die Installation wird abgebrochen, damit kein unvollständiger TLS-Zustand entsteht.'
    );
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    CreateLocalCertificate;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID <> wpFinished then
    Exit;

  if WizardIsTaskSelected('addinsetup') then
  begin
    WizardForm.FinishedHeadingLabel.Caption :=
      'MailNotes Outlook-Add-In einrichten';

    WizardForm.FinishedLabel.Caption :=
      'MailNotes Agent wurde erfolgreich installiert.';

    AddinHelpLabel.Caption :=
      'Die Outlook-Seite wird automatisch im Standard-Browser geöffnet.' + #13#10 + #13#10 +
      '1. Outlook vollständig beenden.' + #13#10 +
      '2. Gehen Sie im Browser zu "Meine Add-Ins".' + #13#10 +
      '3. Wählen Sie "Benutzerdefiniertes Add-In hinzufügen".' + #13#10 +
      '4. Wählen Sie die Datei "manifest.xml" unter' + #13#10 +
      '   "' + ExpandConstant('{autopf}\MailNotes\Addin') + '"' + #13#10 +
      '   aus und klicken Sie auf "Installieren".' + #13#10 + #13#10 +
      '5. Starten Sie Outlook und markieren Sie eine beliebige E-Mail.' + #13#10 +
      '6. Öffnen Sie im Menüband "Add-Ins" > "Weitere Apps" und wählen Sie "MailNotes".' + #13#10 +
      '7. Heften Sie MailNotes mit dem Pin an, wenn das Fenster geöffnet bleiben soll (optional).';

    AddinHelpLabel.Visible := True;

    if not AddinSetupOpened then
    begin
      AddinSetupOpened := True;
      OpenAddinSetup;
    end;
  end
  else
  begin
    AddinHelpLabel.Visible := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDirectory: string;
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    StopAgent;

    DataDirectory := ExpandConstant('{localappdata}\MailNotes');

    if MsgBox(
         'Sollen auch die persönlichen MailNotes-Daten gelöscht werden?' + #13#10 + #13#10 +
         'Dazu gehören insbesondere alle Notizen und die lokale Datenbank.' + #13#10 +
         'Die sichere Standardauswahl ist „Nein“.',
         mbConfirmation,
         MB_YESNO or MB_DEFBUTTON2
       ) = IDYES then
    begin
      if DirExists(DataDirectory) then
        DelTree(DataDirectory, True, True, True);
    end;
  end;

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
  end;
end;
