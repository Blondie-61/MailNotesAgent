unit uDiagnostics;

interface

uses
  System.SysUtils;

type
  TMNDiagnostics = class sealed
  public
    class procedure Write(const ALevel: Integer; const ASource, AText: string); static;
    class procedure Error(const ASource, AText: string); static;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.IniFiles, System.SyncObjs,
  uAppPaths;

var
  GLogLock: TObject;

class procedure TMNDiagnostics.Write(const ALevel: Integer; const ASource, AText: string);
var
  Ini: TIniFile;
  Enabled, Level: Integer;
  LogDir, LogName, Line: string;
begin
  try
    Enabled := 0;
    Level := 1;
    if TFile.Exists(TAppPaths.ConfigFile) then
    begin
      Ini := TIniFile.Create(TAppPaths.ConfigFile);
      try
        Enabled := Ini.ReadInteger('Debug', 'Enabled', 0);
        Level := Ini.ReadInteger('Debug', 'LogLevel', 1);
      finally
        Ini.Free;
      end;
    end;
    if (ALevel > 0) and ((Enabled <> 1) or (ALevel > Level)) then
      Exit;
    LogDir := TPath.Combine(TAppPaths.DataDirectory, 'Logs');
    LogName := TPath.Combine(LogDir, 'MailNotesAgent-Diagnostic.log');
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
      ' [' + ASource + '] ' + StringReplace(StringReplace(AText,
      #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
    TMonitor.Enter(GLogLock);
    try
      TDirectory.CreateDirectory(LogDir);
      // Einfacher Größen-Cap: vorherige Datei erhalten.
      if TFile.Exists(LogName) and (TFile.GetSize(LogName) > 5 * 1024 * 1024) then
      begin
        if TFile.Exists(LogName + '.1') then
          TFile.Delete(LogName + '.1');
        TFile.Move(LogName, LogName + '.1');
      end;
      TFile.AppendAllText(LogName, Line + sLineBreak, TEncoding.UTF8);
    finally
      TMonitor.Exit(GLogLock);
    end;
  except
    // Diagnose darf den Agent niemals beenden.
  end;
end;

class procedure TMNDiagnostics.Error(const ASource, AText: string);
begin
  Write(0, ASource, AText);
end;

initialization
  GLogLock := TObject.Create;
finalization
  GLogLock.Free;
end.
