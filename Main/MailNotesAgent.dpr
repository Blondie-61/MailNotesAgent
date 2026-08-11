program MailNotesAgent;

{$IF Defined(MSWINDOWS)}
  {$APPTYPE GUI}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}

{$R *.res}
{$R *.dres}

uses
  System.SysUtils,
  {$IF Defined(MSWINDOWS)}
  Winapi.Windows,
  {$ENDIF }
  uAppPaths in 'uAppPaths.pas',
  uAppInfo in 'uAppInfo.pas',
  uRuntimeConfig in 'uRuntimeConfig.pas',
  uVersion in 'uVersion.pas',
  uGithubRelease in 'uGithubRelease.pas',
  uUpdater in 'uUpdater.pas',
  uDatabase in 'uDatabase.pas',
  uNote in 'uNote.pas',
  uLinkBuffer in 'uLinkBuffer.pas',
  uRepairQueue in 'uRepairQueue.pas',
  uHttpServer in 'uHttpServer.pas',
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

procedure ShowAlreadyRunning;
begin
{$IF Defined(MSWINDOWS)}
  MessageBox(
    0,
    'MailNotes Agent läuft bereits.',
    'MailNotes Agent',
    MB_OK or MB_ICONINFORMATION
  );
{$ELSE}
  Writeln('MailNotes Agent läuft bereits.');
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

begin
  Database := nil;
  HttpServer := nil;
  TrayIcon := nil;
  SingleInstance := nil;

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

      Database := TDatabase.Create;
      Database.Open;

      HttpServer := THttpServer.Create(Database);
      HttpServer.Start;

      TrayIcon := TTrayIcon.Create;
      TrayIcon.SetState(tsOK);
      TrayIcon.Run;
    except
      on E: Exception do
      begin
        ShowStartupError(
          'MailNotes Agent konnte nicht gestartet werden.' +
          sLineBreak + sLineBreak + E.Message
        );
      end;
    end;
  finally
    TrayIcon.Free;
    HttpServer.Free;
    Database.Free;
    SingleInstance.Free;
  end;
end.
