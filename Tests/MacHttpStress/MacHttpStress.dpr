program MacHttpStress;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils,
  FireDAC.UI.Intf, FireDAC.ConsoleUI.Wait, FireDAC.Phys.SQLiteWrapper.Stat,
  uAppPaths in '..\Tests\MacHttpStress\uAppPaths.pas', uRuntimeConfig in '..\Tests\MacHttpStress\uRuntimeConfig.pas',
  uDatabase, uHttpServer, uReminderScheduler;
function ImageHeader(Index: UInt32): Pointer; cdecl; external '/usr/lib/libSystem.B.dylib' name '_dyld_get_image_header';
var DB: TDatabase; Server: THttpServer; Reminder: TReminderScheduler;
    Started: UInt64;
begin
  Writeln('IMAGE_BASE=', IntToHex(NativeUInt(ImageHeader(0)),16)); Flush(Output);
  DB := TDatabase.Create;
  try
    DB.Open;
    Server := THttpServer.Create(DB);
    try
      Server.Start;
      Reminder := TReminderScheduler.Create(Server,
        procedure(Count: Integer) begin end);
      try
        Reminder.Start;
        Writeln('READY isolated HTTPS 48579'); Flush(Output);
        Started := TThread.GetTickCount64;
        while (TThread.GetTickCount64 - Started < 180000) and
          not TFile.Exists(TPath.Combine(TAppPaths.DataDirectory,'stop')) do
          TThread.Sleep(100);
      finally Writeln('STOP Reminder'); Flush(Output); Reminder.Free; Writeln('STOPPED Reminder'); Flush(Output); end;
    finally Writeln('STOP Server'); Flush(Output); Server.Free; Writeln('STOPPED Server'); Flush(Output); end;
  finally Writeln('STOP DB'); Flush(Output); DB.Free; Writeln('STOPPED DB'); Flush(Output); end;
  Writeln('PASS clean server and scheduler shutdown');
end.
