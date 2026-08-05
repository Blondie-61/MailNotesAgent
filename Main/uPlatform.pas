unit uPlatform;

interface

uses
  System.SysUtils,
  System.IOUtils;

type
  TMailNotesPlatform = class sealed
  public
    class function Name: string; static;
    class function UserDataBaseDirectory: string; static;
    class function ApplicationResourcesDirectory: string; static;
  end;

implementation

class function TMailNotesPlatform.Name: string;
begin
{$IF Defined(MSWINDOWS)}
  Result := 'Windows';
{$ELSEIF Defined(MACOS)}
  Result := 'macOS';
{$ELSE}
  Result := 'Unbekannt';
{$ENDIF}
end;

class function TMailNotesPlatform.UserDataBaseDirectory: string;
var
  HomeDirectory: string;
begin
{$IF Defined(MSWINDOWS)}
  Result := GetEnvironmentVariable('LOCALAPPDATA');

  if Result = '' then
  begin
    HomeDirectory := GetEnvironmentVariable('USERPROFILE');

    if HomeDirectory <> '' then
      Result := TPath.Combine(HomeDirectory, 'AppData\Local');
  end;
{$ELSEIF Defined(MACOS)}
  HomeDirectory := GetEnvironmentVariable('HOME');

  if HomeDirectory <> '' then
    Result := TPath.Combine(
      HomeDirectory,
      'Library/Application Support'
    )
  else
    Result := '';
{$ELSE}
  Result := TPath.GetHomePath;
{$ENDIF}

  if Result = '' then
    raise Exception.CreateFmt(
      'Benutzerdatenverzeichnis unter %s konnte nicht ermittelt werden.',
      [Name]
    );
end;

class function TMailNotesPlatform.ApplicationResourcesDirectory: string;
var
  ExecutableDirectory: string;
begin
  ExecutableDirectory := TPath.GetFullPath(ExtractFilePath(ParamStr(0)));

{$IF Defined(MACOS)}
  // In einem macOS-App-Bundle liegt das Programm unter Contents/MacOS
  // und seine mitgelieferten Ressourcen unter Contents/Resources.
  Result := TPath.GetFullPath(
    TPath.Combine(ExecutableDirectory, '../Resources')
  );
{$ELSE}
  // Unter Windows liegen mitgelieferte Dateien neben der EXE.
  Result := ExecutableDirectory;
{$ENDIF}
end;

end.
