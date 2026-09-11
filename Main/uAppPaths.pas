unit uAppPaths;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.IniFiles;

type
  TAppPaths = class sealed
  public
    class function ExecutableDirectory: string; static;
    class function AgentFile: string; static;
    class function AddinDirectory: string; static;
    class function DataDirectory: string; static;
    class function DefaultDatabaseFile: string; static;
    class function DatabaseFile: string; static;
    class function ConfigFile: string; static;
    class procedure SetDatabaseFile(const AFileName: string); static;
    class function BackupDirectory: string; static;
    class procedure SetBackupDirectory(const ADirectory: string); static;
    class function LastSuccessfulBackup: string; static;
    class procedure SetLastSuccessfulBackup(const AFileName: string); static;
    class function BackupRetentionCount: Integer; static;
    class function LogFile: string; static;
    class function TlsDirectory: string; static;
    class function TlsCertificateFile: string; static;
    class function TlsPrivateKeyFile: string; static;
    class function BundledDatabaseFile: string; static;
    class procedure EnsureDataDirectory; static;
  end;

implementation

class function TAppPaths.ExecutableDirectory: string;
begin
  Result := TPath.GetFullPath(ExtractFilePath(ParamStr(0)));
end;

class function TAppPaths.AgentFile: string;
begin
  Result := TPath.GetFullPath(ParamStr(0));
end;

class function TAppPaths.AddinDirectory: string;
var
  ProgramFilesDirectory: string;
begin
{$IF Defined(MSWINDOWS)}
  ProgramFilesDirectory := GetEnvironmentVariable('ProgramFiles');
  if ProgramFilesDirectory = '' then
    ProgramFilesDirectory := 'C:\Program Files';
  Result := TPath.Combine(TPath.Combine(ProgramFilesDirectory, 'MailNotes'), 'Addin');
{$ELSEIF Defined(MACOS)}
  Result := TPath.Combine(TPath.GetHomePath, 'Library/Application Support/MailNotes/Addin');
{$ELSE}
  Result := TPath.Combine(TPath.GetHomePath, 'MailNotes/Addin');
{$ENDIF}
end;

class function TAppPaths.DataDirectory: string;
var
  BaseDirectory: string;
begin
{$IF Defined(MSWINDOWS)}
  BaseDirectory := GetEnvironmentVariable('LOCALAPPDATA');

  if BaseDirectory = '' then
    BaseDirectory := TPath.Combine(
      GetEnvironmentVariable('USERPROFILE'),
      'AppData\Local'
    );
{$ELSEIF Defined(MACOS)}
  BaseDirectory := TPath.Combine(
    GetEnvironmentVariable('HOME'),
    'Library/Application Support'
  );
{$ELSE}
  BaseDirectory := TPath.GetHomePath;
{$ENDIF}

  if BaseDirectory = '' then
    raise Exception.Create('Benutzerdatenverzeichnis konnte nicht ermittelt werden.');

  Result := TPath.Combine(BaseDirectory, 'MailNotes');
end;

class function TAppPaths.DefaultDatabaseFile: string;
begin
  Result := TPath.Combine(DataDirectory, 'MailNotes.sqlite');
end;

class function TAppPaths.ConfigFile: string;
begin
  Result := TPath.Combine(DataDirectory, 'mailnotes.ini');
end;

class function TAppPaths.DatabaseFile: string;
var
  Ini: TIniFile;
  ConfiguredPath: string;
begin
  Result := DefaultDatabaseFile;

  if not TFile.Exists(ConfigFile) then
    Exit;

  Ini := TIniFile.Create(ConfigFile);
  try
    ConfiguredPath := Trim(Ini.ReadString('Database', 'Path', ''));
  finally
    Ini.Free;
  end;

  if ConfiguredPath <> '' then
    Result := TPath.GetFullPath(ConfiguredPath);
end;

class procedure TAppPaths.SetDatabaseFile(const AFileName: string);
var
  Ini: TIniFile;
  NormalizedPath: string;
begin
  EnsureDataDirectory;
  NormalizedPath := Trim(AFileName);

  Ini := TIniFile.Create(ConfigFile);
  try
    if (NormalizedPath = '') or SameText(TPath.GetFullPath(NormalizedPath), DefaultDatabaseFile) then
      Ini.DeleteKey('Database', 'Path')
    else
      Ini.WriteString('Database', 'Path', TPath.GetFullPath(NormalizedPath));
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

class function TAppPaths.BackupDirectory: string;
var
  Ini: TIniFile;
begin
  Result := '';

  if not TFile.Exists(ConfigFile) then
    Exit;

  Ini := TIniFile.Create(ConfigFile);
  try
    Result := Trim(Ini.ReadString('Backup', 'Directory', ''));
  finally
    Ini.Free;
  end;
end;

class procedure TAppPaths.SetBackupDirectory(const ADirectory: string);
var
  Ini: TIniFile;
  NormalizedPath: string;
begin
  EnsureDataDirectory;
  NormalizedPath := Trim(ADirectory);
  if NormalizedPath <> '' then
    NormalizedPath := TPath.GetFullPath(NormalizedPath);

  Ini := TIniFile.Create(ConfigFile);
  try
    if NormalizedPath = '' then
      Ini.DeleteKey('Backup', 'Directory')
    else
      Ini.WriteString('Backup', 'Directory', NormalizedPath);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

class function TAppPaths.LastSuccessfulBackup: string;
var
  Ini: TIniFile;
begin
  Result := '';

  if not TFile.Exists(ConfigFile) then
    Exit;

  Ini := TIniFile.Create(ConfigFile);
  try
    Result := Trim(Ini.ReadString('Backup', 'LastSuccessful', ''));
  finally
    Ini.Free;
  end;
end;

class procedure TAppPaths.SetLastSuccessfulBackup(const AFileName: string);
var
  Ini: TIniFile;
begin
  EnsureDataDirectory;
  Ini := TIniFile.Create(ConfigFile);
  try
    Ini.WriteString('Backup', 'LastSuccessful', Trim(AFileName));
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

class function TAppPaths.BackupRetentionCount: Integer;
const
  DEFAULT_RETENTION_COUNT = 3;
var
  Ini: TIniFile;
begin
  Result := DEFAULT_RETENTION_COUNT;
  if not TFile.Exists(ConfigFile) then
    Exit;

  Ini := TIniFile.Create(ConfigFile);
  try
    Result := Ini.ReadInteger('Backup', 'RetentionCount', DEFAULT_RETENTION_COUNT);
  finally
    Ini.Free;
  end;

  if Result <= 0 then
    Result := DEFAULT_RETENTION_COUNT;
end;


class function TAppPaths.LogFile: string;
begin
  Result := TPath.Combine(DataDirectory, 'MailNotesAgent.log');
end;


class function TAppPaths.TlsDirectory: string;
var
  BaseDirectory: string;
begin
{$IF Defined(MSWINDOWS)}
  BaseDirectory := GetEnvironmentVariable('PROGRAMDATA');
  if BaseDirectory = '' then
    BaseDirectory := 'C:\ProgramData';
  Result := TPath.Combine(TPath.Combine(BaseDirectory, 'MailNotes'), 'TLS');
{$ELSE}
  Result := TPath.Combine(DataDirectory, 'TLS');
{$ENDIF}
end;

class function TAppPaths.TlsCertificateFile: string;
begin
  Result := TPath.Combine(TlsDirectory, 'localhost-cert.pem');
end;

class function TAppPaths.TlsPrivateKeyFile: string;
begin
  Result := TPath.Combine(TlsDirectory, 'localhost-key.pem');
end;

class function TAppPaths.BundledDatabaseFile: string;
var
  BaseDirectory: string;
  Candidate: string;
  I: Integer;
begin
  BaseDirectory := ExecutableDirectory;

  for I := 0 to 6 do
  begin
    Candidate := TPath.Combine(
      TPath.Combine(BaseDirectory, 'Data'),
      'MailNotes.sqlite'
    );

    if TFile.Exists(Candidate) then
      Exit(Candidate);

    BaseDirectory := TPath.GetFullPath(
      TPath.Combine(BaseDirectory, '..')
    );
  end;

  Result := TPath.Combine(
    TPath.Combine(ExecutableDirectory, 'Data'),
    'MailNotes.sqlite'
  );
end;

class procedure TAppPaths.EnsureDataDirectory;
begin
  TDirectory.CreateDirectory(DataDirectory);
end;

end.

