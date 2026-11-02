program MailNotesAgent;

{$IF Defined(MSWINDOWS)}
  {$APPTYPE GUI}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}

{$IF Defined(MSWINDOWS)}
  {$R *.res}
{$ENDIF}

{$R *.dres}

uses
  System.SysUtils,
  System.IOUtils,
  {$IF Defined(MSWINDOWS)}
  Winapi.Windows,
  Winapi.ShellAPI,
  {$ELSEIF Defined(MACOS)}
  Posix.Stdlib,
  FireDAC.UI.Intf,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Phys.SQLiteWrapper.Stat,
  {$ENDIF}
  uAppPaths in 'uAppPaths.pas',
  uAddinDeploy in 'uAddinDeploy.pas',
  uAppInfo in 'uAppInfo.pas',
  uRuntimeConfig in 'uRuntimeConfig.pas',
  uDiagnostics in 'uDiagnostics.pas',
  uVersion in 'uVersion.pas',
  uGithubRelease in 'uGithubRelease.pas',
  uUpdater in 'uUpdater.pas',
  uDatabase in 'uDatabase.pas',
  uGraphAccounts in 'uGraphAccounts.pas',
  uGraphAuth in 'uGraphAuth.pas',
  uGraphClient in 'uGraphClient.pas',
  uGML in 'uGML.pas',
  uGraphTokenStore in 'uGraphTokenStore.pas',
  uNote in 'uNote.pas',
  uLinkBuffer in 'uLinkBuffer.pas',
  uRepairQueue in 'uRepairQueue.pas',
  uHttpServer in 'uHttpServer.pas',
  uBackupScheduler in 'uBackupScheduler.pas',
  uSingleInstance in 'uSingleInstance.pas',
  uTrayIconResources in 'uTrayIconResources.pas',
  uStatusLogo in 'uStatusLogo.pas',
  uStatusDialog in 'uStatusDialog.pas',
  uTrayIcon in 'uTrayIcon.pas';

var
  Database: TDatabase;
  HttpServer: THttpServer;
  TrayIcon: TTrayIcon;
  SingleInstance: TSingleInstanceGuard;
  RestartRequested: Boolean;

procedure ShowAlreadyRunning;
begin
{$IF Defined(MSWINDOWS)}
  MessageBox(
    0,
    PChar('MailNotes Agent v' + TAppInfo.Version + ' läuft bereits.'),
    'MailNotes Agent',
    MB_OK or MB_ICONINFORMATION
  );
{$ELSE}
  Writeln('MailNotes Agent v' + TAppInfo.Version + ' läuft bereits.');
{$ENDIF}
end;

procedure ShowStartupError(const ErrorText: string);
begin
{$IF Defined(MSWINDOWS)}
  MessageBox(
    0,
    PChar(ErrorText),
    'MailNotes Agent',
    MB_OK or MB_ICONERROR
  );
{$ELSE}
  Writeln(ErrorText);
{$ENDIF}
end;

{$IF Defined(MACOS)}
function MacSystem(Command: PAnsiChar): Integer; cdecl;
  external '/usr/lib/libSystem.B.dylib' name 'system';
{$ENDIF}

procedure LaunchRestart;
{$IF Defined(MSWINDOWS)}
var
  Executable: string;
{$ELSEIF Defined(MACOS)}
var
  Executable, Command: string;
  CommandUtf8: UTF8String;
{$ENDIF}
begin
{$IF Defined(MSWINDOWS)}
  Executable := ParamStr(0);
  if ShellExecute(0, 'open', PChar(Executable), nil,
    PChar(ExtractFilePath(Executable)), SW_SHOWNORMAL) <= 32 then
    ShowStartupError('MailNotesAgent konnte nicht neu gestartet werden.');
{$ELSEIF Defined(MACOS)}
  // Dem beendeten Prozess Zeit geben, bevor die neue Instanz die
  // Single-Instance-Sperre anfordert. Auch Pfade mit Leerzeichen beachten.
  Executable := ParamStr(0);
  Command := '(sleep 2; exec ' + #39 +
    StringReplace(Executable, #39, #39 + '"' + #39 + '"' + #39, [rfReplaceAll]) +
    #39 + ') >/dev/null 2>&1 &';
  CommandUtf8 := UTF8String(Command);
  if MacSystem(PAnsiChar(CommandUtf8)) <> 0 then
    ShowStartupError('MailNotesAgent konnte nicht neu gestartet werden.');
{$ENDIF}
end;

begin
  Database := nil;
  HttpServer := nil;
  TrayIcon := nil;
  SingleInstance := nil;
  RestartRequested := False;
  TMNDiagnostics.Write(1, 'Agent', 'Start');

  try
    try
{$IF Defined(MSWINDOWS)}
      if FindCmdLineSwitch('shutdown', True) then
      begin
        TTrayIcon.RequestRunningInstanceShutdown;
        Exit;
      end;
{$ENDIF}

      SingleInstance := TSingleInstanceGuard.Create('MailNotesAgent');

      if not SingleInstance.Acquired then
      begin
        ShowAlreadyRunning;
        Exit;
      end;

{$IF Defined(MACOS)}
      try
        TAddinDeploy.EnsureInstalled;
      except
        on E: Exception do
          Writeln('MailNotes Warnung: Add-in-Bereitstellung fehlgeschlagen: ' + E.Message);
      end;
{$ENDIF}

      Database := TDatabase.Create;
      Database.Open;

      HttpServer := THttpServer.Create(Database);
      HttpServer.Start;

{$IF Defined(MSWINDOWS) or Defined(MACOS)}
      TrayIcon := TTrayIcon.Create(HttpServer);
{$ELSE}
      TrayIcon := TTrayIcon.Create;
{$ENDIF}
      TrayIcon.SetState(tsOK);
      TrayIcon.Run;
      RestartRequested := TrayIcon.RestartRequested;
    except
      on E: Exception do
      begin
        TMNDiagnostics.Error('Agent', E.ClassName + ': ' + E.Message);
        ShowStartupError(
          'MailNotes Agent konnte nicht gestartet werden.' +
          sLineBreak + sLineBreak + E.Message
        );
      end;
    end;
  finally
    TMNDiagnostics.Write(1, 'Agent', 'Shutdown begin');
    TrayIcon.Free;
    HttpServer.Free;
    Database.Free;
    SingleInstance.Free;
  end;

  if RestartRequested then
    LaunchRestart;
end.
