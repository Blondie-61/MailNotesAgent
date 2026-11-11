unit uAddinDeploy;

interface

type
  TAddinDeploy = class sealed
  public
    class procedure ValidatePackage(const DirectoryName: string); static;
    class procedure EnsureInstalled; static;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Hash,
  System.Generics.Collections, uAppPaths;

class procedure TAddinDeploy.ValidatePackage(const DirectoryName: string);
var
  Manifest: TJSONValue;
  Entries: TJSONArray;
  Names: TDictionary<string, Boolean>;
  Entry: TJSONValue;
  Name, Hash, FullName: string;
begin
  Manifest := TJSONObject.ParseJSONValue(
    TFile.ReadAllText(TPath.Combine(DirectoryName, 'addin-build.json'), TEncoding.UTF8));
  Names := TDictionary<string, Boolean>.Create;
  try
    if not (Manifest is TJSONObject) then
      raise Exception.Create('Add-in-Buildmanifest ist ungueltig.');
    if Manifest.GetValue<Integer>('version', 0) <> 1 then
      raise Exception.Create('Add-in-Buildmanifest-Version ist unbekannt.');
    Entries := Manifest.GetValue<TJSONArray>('files');
    if (Entries = nil) or (Entries.Count = 0) then
      raise Exception.Create('Add-in-Dateiliste fehlt.');
    for Entry in Entries do
    begin
      Name := Entry.GetValue<string>('path');
      Hash := Entry.GetValue<string>('sha256');
      if (Name = '') or Name.Contains('\') or Name.StartsWith('/') or
         Name.Contains(':') or Name.Contains('..') or Names.ContainsKey(Name) then
        raise Exception.Create('Ungueltiger Add-in-Dateipfad: ' + Name);
      FullName := TPath.Combine(DirectoryName, Name.Replace('/', PathDelim));
      if not TFile.Exists(FullName) or
         not SameText(THashSHA2.GetHashStringFromFile(FullName), Hash) then
        raise Exception.Create('Add-in-Datei fehlt oder ist veraendert: ' + Name);
      Names.Add(Name, True);
    end;
    for Name in TArray<string>.Create('taskpane.html', 'taskpane.js', 'commands.html', 'commands.js',
      'polyfill.js', 'manifest.xml') do
      if not Names.ContainsKey(Name) then
        raise Exception.Create('Add-in-Build ist unvollstaendig: ' + Name);
    if Length(TDirectory.GetFiles(DirectoryName, '*', TSearchOption.soAllDirectories)) <> Names.Count + 1 then
      raise Exception.Create('Unerwartete Dateien im Add-in-Build.');
  finally
    Names.Free;
    Manifest.Free;
  end;
end;

function SameFileBytes(const A, B: string): Boolean;
var
  X, Y: TBytes;
  J: Integer;
begin
  X := TFile.ReadAllBytes(A);
  Y := TFile.ReadAllBytes(B);
  if Length(X) <> Length(Y) then Exit(False);
  for J := 0 to High(X) do
    if X[J] <> Y[J] then Exit(False);
  Result := True;
end;

class procedure TAddinDeploy.EnsureInstalled;
{$IF Defined(MACOS)}
var
  SourceDir, TargetDir, StagingDir, BackupDir, BundleDir: string;
  SourceFiles: TArray<string>;
  FileName, RelativeName, DestinationName: string;
  I: Integer;
  Changed: Boolean;
{$ENDIF}
begin
{$IF Defined(MACOS)}
  // Contents/MacOS -> Contents/Resources/Addin
  BundleDir := TPath.GetFullPath(TPath.Combine(TAppPaths.ExecutableDirectory, '..'));
  SourceDir := TPath.Combine(TPath.Combine(BundleDir, 'Resources'), 'Addin');
  TargetDir := TAppPaths.AddinDirectory;
  if not TFile.Exists(TPath.Combine(SourceDir, 'taskpane.html')) then
  begin
    Writeln('MailNotes Warnung: Mitgelieferte Add-in-Dateien fehlen: ' + SourceDir);
    Writeln('Vorhandene Add-in-Dateien bleiben unveraendert.');
    Exit;
  end;
  ValidatePackage(SourceDir);

  SourceFiles := TDirectory.GetFiles(SourceDir, '*', TSearchOption.soAllDirectories);
  Changed := not TDirectory.Exists(TargetDir);
  if not Changed then
    Changed := Length(TDirectory.GetFiles(TargetDir, '*', TSearchOption.soAllDirectories)) <> Length(SourceFiles);
  if not Changed then
    for I := 0 to High(SourceFiles) do
    begin
      RelativeName := Copy(SourceFiles[I], Length(IncludeTrailingPathDelimiter(SourceDir)) + 1, MaxInt);
      FileName := TPath.Combine(TargetDir, RelativeName);
      if (not TFile.Exists(FileName)) or
         (TFile.GetSize(SourceFiles[I]) <> TFile.GetSize(FileName)) then
      begin
        Changed := True;
        Break;
      end;
      // Compare bytes even when lengths match (same-size changes).
      if not SameFileBytes(SourceFiles[I], FileName) then
      begin
        Changed := True;
        Break;
      end;
    end;
  if not Changed then Exit;

  StagingDir := TargetDir + '.staging';
  BackupDir := TargetDir + '.rollback';
  if TDirectory.Exists(StagingDir) then TDirectory.Delete(StagingDir, True);
  TDirectory.CreateDirectory(StagingDir);
  try
    for I := 0 to High(SourceFiles) do
    begin
      RelativeName := Copy(SourceFiles[I], Length(IncludeTrailingPathDelimiter(SourceDir)) + 1, MaxInt);
      DestinationName := TPath.Combine(StagingDir, RelativeName);
      TDirectory.CreateDirectory(ExtractFileDir(DestinationName));
      TFile.Copy(SourceFiles[I], DestinationName, True);
    end;
    ValidatePackage(StagingDir);
    if TDirectory.Exists(BackupDir) then TDirectory.Delete(BackupDir, True);
    if TDirectory.Exists(TargetDir) then TDirectory.Move(TargetDir, BackupDir);
    try
      TDirectory.Move(StagingDir, TargetDir);
    except
      if TDirectory.Exists(BackupDir) and not TDirectory.Exists(TargetDir) then
        TDirectory.Move(BackupDir, TargetDir);
      raise;
    end;
    // Keep rollback until next successful deployment.
  except
    if TDirectory.Exists(StagingDir) then TDirectory.Delete(StagingDir, True);
    raise;
  end;
{$ENDIF}
end;

end.
