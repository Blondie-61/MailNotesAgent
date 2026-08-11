unit uAppPaths;

interface

uses
  System.SysUtils,
  System.IOUtils;

type
  TAppPaths = class sealed
  public
    class function ExecutableDirectory: string; static;
    class function AgentFile: string; static;
    class function AddinDirectory: string; static;
    class function DataDirectory: string; static;
    class function DatabaseFile: string; static;
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

class function TAppPaths.DatabaseFile: string;
begin
  Result := TPath.Combine(DataDirectory, 'MailNotes.sqlite');
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
