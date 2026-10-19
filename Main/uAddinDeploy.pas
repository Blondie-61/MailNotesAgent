unit uAddinDeploy;

interface

type
  TAddinDeploy = class sealed
  public
    class procedure EnsureInstalled; static;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uAppPaths;

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

  SourceFiles := TDirectory.GetFiles(SourceDir, '*', TSearchOption.soAllDirectories);
  Changed := not TFile.Exists(TPath.Combine(TargetDir, 'taskpane.html'));
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
