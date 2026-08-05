unit uUpdater;

interface

type
  TUpdateCheckResult = record
    Success: Boolean;
    UpdateAvailable: Boolean;
    CurrentVersion: string;
    LatestVersion: string;
    ReleaseName: string;
    ReleasePageUrl: string;
    DownloadUrl: string;
    AssetName: string;
    ErrorMessage: string;
  end;

  TMailNotesUpdater = class sealed
  public
    class function CheckLatest: TUpdateCheckResult; static;
    class function DownloadInstaller(const ADownloadUrl,
      AAssetName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  uAppInfo,
  uVersion,
  uGithubRelease;

class function TMailNotesUpdater.CheckLatest: TUpdateCheckResult;
var
  CurrentVersion: TMailNotesVersion;
  LatestVersion: TMailNotesVersion;
  ReleaseInfo: TGitHubReleaseInfo;
begin
  Result := Default(TUpdateCheckResult);
  Result.CurrentVersion := TAppInfo.Version;

  try
    CurrentVersion := TMailNotesVersion.Parse(Result.CurrentVersion);
    ReleaseInfo := TGitHubReleaseClient.GetLatest;
    LatestVersion := TMailNotesVersion.Parse(ReleaseInfo.TagName);

    Result.LatestVersion := LatestVersion.ToString;
    Result.ReleaseName := ReleaseInfo.ReleaseName;
    Result.ReleasePageUrl := ReleaseInfo.ReleasePageUrl;
    Result.AssetName := ReleaseInfo.AssetName;
    Result.DownloadUrl := ReleaseInfo.AssetDownloadUrl;
    Result.UpdateAvailable := LatestVersion.CompareTo(CurrentVersion) > 0;
    Result.Success := True;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

class function TMailNotesUpdater.DownloadInstaller(const ADownloadUrl,
  AAssetName: string): string;
var
  DownloadsDirectory: string;
  FileName: string;
begin
  DownloadsDirectory := TPath.Combine(
    GetEnvironmentVariable('USERPROFILE'), 'Downloads');
  if (GetEnvironmentVariable('USERPROFILE') = '') or
     not TDirectory.Exists(DownloadsDirectory) then
    DownloadsDirectory := TPath.GetTempPath;

  FileName := Trim(AAssetName);
  if FileName = '' then
    FileName := 'MailNotesAgent-Setup.exe';

  Result := TPath.Combine(DownloadsDirectory, FileName);
  TGitHubReleaseClient.DownloadAsset(ADownloadUrl, Result);
end;

end.
