unit uBackupScheduler;

interface

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  uHttpServer;

const
  MAX_BACKUP_INTERVALS = 3;

type
  TBackupIntervals = array[0..MAX_BACKUP_INTERVALS - 1] of Integer;

  TBackupSettings = class sealed
  public
    class procedure EnsureDefaults; static;
    class function LoadIntervals(out AIntervals: TBackupIntervals): Integer; static;
    class function SelectedIntervalHours: Integer; static;
    class procedure SetSelectedIntervalHours(const AHours: Integer); static;
    class function IntervalCaption(const AHours: Integer): string; static;
  end;

  TBackupScheduler = class(TThread)
  private
    FHttpServer: THttpServer;
    FStopEvent: TEvent;
    procedure Log(const AText: string);
    function BackupTargetValid(out ADirectory: string): Boolean;
    function IsBackupDue(const AIntervalHours: Integer; const ADirectory: string): Boolean;
    function DatabaseChangedSinceLastBackup: Boolean;
    procedure TryAutomaticBackup;
  protected
    procedure Execute; override;
  public
    constructor Create(AHttpServer: THttpServer);
    destructor Destroy; override;
    procedure Stop;
    procedure BackupOnExit;
  end;

implementation

uses
  System.IniFiles,
  System.IOUtils,
  System.DateUtils,
  uAppPaths;

const
  DEFAULT_INTERVALS = '2,4';
  DEFAULT_SELECTED_INTERVAL = 2;
  DEFAULT_RETENTION_COUNT = 3;
  CHECK_INTERVAL_MS = 60 * 1000;

class procedure TBackupSettings.EnsureDefaults;
var
  Ini: TIniFile;
begin
  TAppPaths.EnsureDataDirectory;
  Ini := TIniFile.Create(TAppPaths.ConfigFile);
  try
    if not Ini.ValueExists('Backup', 'AutoIntervals') then
      Ini.WriteString('Backup', 'AutoIntervals', DEFAULT_INTERVALS);
    if not Ini.ValueExists('Backup', 'AutoIntervalHours') then
      Ini.WriteInteger('Backup', 'AutoIntervalHours', DEFAULT_SELECTED_INTERVAL);
    if not Ini.ValueExists('Backup', 'RetentionCount') then
      Ini.WriteInteger('Backup', 'RetentionCount', DEFAULT_RETENTION_COUNT);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

class function TBackupSettings.LoadIntervals(out AIntervals: TBackupIntervals): Integer;
var
  Ini: TIniFile;
  Raw: string;
  Parts: TStringList;
  I, Value: Integer;
  Duplicate: Boolean;

  procedure AddValue(const AValue: Integer);
  var
  J: Integer;

  begin
    if (AValue <= 0) or (Result >= MAX_BACKUP_INTERVALS) then
      Exit;

    Duplicate := False;
    for J := 0 to Result - 1 do
      if AIntervals[J] = AValue then
      begin
        Duplicate := True;
        Break;
      end;

    if Duplicate then
      Exit;

    AIntervals[Result] := AValue;
    Inc(Result);
  end;

begin
  for I := Low(AIntervals) to High(AIntervals) do
    AIntervals[I] := 0;

  Raw := DEFAULT_INTERVALS;
  if TFile.Exists(TAppPaths.ConfigFile) then
  begin
    Ini := TIniFile.Create(TAppPaths.ConfigFile);
    try
      Raw := Trim(Ini.ReadString('Backup', 'AutoIntervals', DEFAULT_INTERVALS));
    finally
      Ini.Free;
    end;
  end;

  Result := 0;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ',';
    Parts.DelimitedText := Raw;

    for I := 0 to Parts.Count - 1 do
      if TryStrToInt(Trim(Parts[I]), Value) then
        AddValue(Value);
  finally
    Parts.Free;
  end;

  if Result = 0 then
  begin
    AddValue(2);
    AddValue(4);
  end;
end;

class function TBackupSettings.SelectedIntervalHours: Integer;
var
  Ini: TIniFile;
  Intervals: TBackupIntervals;
  Count, I, Configured: Integer;
begin
  Count := LoadIntervals(Intervals);
  Configured := DEFAULT_SELECTED_INTERVAL;

  if TFile.Exists(TAppPaths.ConfigFile) then
  begin
    Ini := TIniFile.Create(TAppPaths.ConfigFile);
    try
      Configured := Ini.ReadInteger('Backup', 'AutoIntervalHours', DEFAULT_SELECTED_INTERVAL);
    finally
      Ini.Free;
    end;
  end;

  if Configured = 0 then
    Exit(0);

  for I := 0 to Count - 1 do
    if Intervals[I] = Configured then
      Exit(Configured);

  Result := Intervals[0];
end;

class procedure TBackupSettings.SetSelectedIntervalHours(const AHours: Integer);
var
  Ini: TIniFile;
  Intervals: TBackupIntervals;
  Count, I: Integer;
  Valid: Boolean;
begin
  Valid := AHours = 0;
  if not Valid then
  begin
    Count := LoadIntervals(Intervals);
    for I := 0 to Count - 1 do
      if Intervals[I] = AHours then
      begin
        Valid := True;
        Break;
      end;
  end;

  if not Valid then
    raise Exception.CreateFmt('Ungültiges Backup-Intervall: %d Stunden.', [AHours]);

  TAppPaths.EnsureDataDirectory;
  Ini := TIniFile.Create(TAppPaths.ConfigFile);
  try
    Ini.WriteInteger('Backup', 'AutoIntervalHours', AHours);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

class function TBackupSettings.IntervalCaption(const AHours: Integer): string;
begin
  if AHours = 1 then
    Result := 'Jede Stunde'
  else
    Result := Format('Alle %d Stunden', [AHours]);
end;

constructor TBackupScheduler.Create(AHttpServer: THttpServer);
begin
  inherited Create(True);
  TBackupSettings.EnsureDefaults;
  FreeOnTerminate := False;
  FHttpServer := AHttpServer;
  FStopEvent := TEvent.Create(nil, True, False, '');
//  Start;
end;

destructor TBackupScheduler.Destroy;
begin
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TBackupScheduler.Stop;
begin
  Terminate;
  FStopEvent.SetEvent;
  WaitFor;
end;

procedure TBackupScheduler.Log(const AText: string);
var
  Line: string;
begin
  try
    TAppPaths.EnsureDataDirectory;
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' [Backup] ' + AText;
    TFile.AppendAllText(TAppPaths.LogFile, Line + sLineBreak, TEncoding.UTF8);
  except
    // Logging darf den Agent niemals beeinträchtigen.
  end;
end;

function TBackupScheduler.BackupTargetValid(out ADirectory: string): Boolean;
begin
  ADirectory := TAppPaths.BackupDirectory;
  Result := (ADirectory <> '') and TDirectory.Exists(ADirectory);
end;

function TBackupScheduler.IsBackupDue(
  const AIntervalHours: Integer;
  const ADirectory: string
): Boolean;
var
  LastBackup: string;
  LastTime: TDateTime;
begin
  if AIntervalHours <= 0 then
    Exit(False);

  LastBackup := TAppPaths.LastSuccessfulBackup;
  if (LastBackup = '') or not TFile.Exists(LastBackup) then
    Exit(True);

  if not SameText(
    ExcludeTrailingPathDelimiter(ExtractFileDir(LastBackup)),
    ExcludeTrailingPathDelimiter(ADirectory)
  ) then
    Exit(True);

  LastTime := TFile.GetLastWriteTime(LastBackup);
  Result := MinutesBetween(Now, LastTime) >= (AIntervalHours * 60);
end;

function TBackupScheduler.DatabaseChangedSinceLastBackup: Boolean;
var
  LastBackup: string;
  LastBackupTime: TDateTime;
  DatabaseFile: string;
  WalFile: string;

  function ChangedAfterBackup(const AFileName: string): Boolean;
  begin
    Result := TFile.Exists(AFileName) and
      (TFile.GetLastWriteTime(AFileName) > LastBackupTime);
  end;

begin
  LastBackup := TAppPaths.LastSuccessfulBackup;
  if (LastBackup = '') or not TFile.Exists(LastBackup) then
    Exit(True);

  LastBackupTime := TFile.GetLastWriteTime(LastBackup);
  DatabaseFile := TAppPaths.DatabaseFile;
  WalFile := DatabaseFile + '-wal';

  // SQLite kann Änderungen in der Hauptdatei oder im WAL halten.
  // Die SHM-Datei wird nicht berücksichtigt, weil sie sich auch
  // bei reinen Lesezugriffen ändern kann.
  Result := ChangedAfterBackup(DatabaseFile) or ChangedAfterBackup(WalFile);
end;

procedure TBackupScheduler.TryAutomaticBackup;
var
  Directory: string;
  IntervalHours: Integer;
begin
  IntervalHours := TBackupSettings.SelectedIntervalHours;
  if IntervalHours = 0 then
    Exit;

  if not BackupTargetValid(Directory) then
    Exit;

  if not IsBackupDue(IntervalHours, Directory) then
    Exit;

  if not DatabaseChangedSinceLastBackup then
    Exit;

  try
    FHttpServer.CreateDatabaseBackup(Directory);
    Log(Format('Automatisches Backup erfolgreich (%d h).', [IntervalHours]));
  except
    on E: Exception do
      Log('Automatisches Backup fehlgeschlagen: ' + E.Message);
  end;
end;

procedure TBackupScheduler.Execute;
begin
  while not Terminated do
  begin
    TryAutomaticBackup;
    if FStopEvent.WaitFor(CHECK_INTERVAL_MS) = wrSignaled then
      Break;
  end;
end;

procedure TBackupScheduler.BackupOnExit;
var
  Directory: string;
begin
  if not BackupTargetValid(Directory) then
    Exit;

  try
    FHttpServer.CreateDatabaseBackup(Directory);
    Log('Backup beim Beenden erfolgreich.');
  except
    on E: Exception do
      Log('Backup beim Beenden fehlgeschlagen: ' + E.Message);
  end;
end;

end.
