unit uGithubRelease;

interface

type
  TGitHubReleaseInfo = record
    TagName: string;
    ReleaseName: string;
    ReleasePageUrl: string;
    AssetName: string;
    AssetDownloadUrl: string;
  end;

  TGitHubReleaseClient = class sealed
  public
    class function GetLatest: TGitHubReleaseInfo; static;
    class procedure DownloadAsset(const AUrl, ADestinationFile: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  uAppInfo;

const
  CLatestReleaseUrl =
    'https://api.github.com/repos/Blondie-61/MailNotesAgent/releases/latest';

function JsonString(const AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value <> nil then
    Result := Value.Value;
end;

function CreateHeaders: TNetHeaders;
begin
  SetLength(Result, 3);
  Result[0] := TNameValuePair.Create('Accept', 'application/vnd.github+json');
  Result[1] := TNameValuePair.Create('User-Agent',
    'MailNotesAgent/' + TAppInfo.Version);
  Result[2] := TNameValuePair.Create('X-GitHub-Api-Version', '2022-11-28');
end;

class function TGitHubReleaseClient.GetLatest: TGitHubReleaseInfo;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Root: TJSONObject;
  Assets: TJSONArray;
  Asset: TJSONObject;
  Headers: TNetHeaders;
  I: Integer;
  CandidateName: string;
begin
  Result := Default(TGitHubReleaseInfo);
  Headers := CreateHeaders;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 10000;
    Client.ResponseTimeout := 20000;
    Response := Client.Get(CLatestReleaseUrl, nil, Headers);

    if Response.StatusCode <> 200 then
      raise Exception.CreateFmt('GitHub antwortete mit HTTP %d (%s).',
        [Response.StatusCode, Response.StatusText]);

    Root := TJSONObject.ParseJSONValue(
      Response.ContentAsString(TEncoding.UTF8)) as TJSONObject;
    try
      if Root = nil then
        raise Exception.Create('Die Release-Informationen sind ungültig.');

      Result.TagName := JsonString(Root, 'tag_name');
      Result.ReleaseName := JsonString(Root, 'name');
      Result.ReleasePageUrl := JsonString(Root, 'html_url');

      Assets := Root.GetValue<TJSONArray>('assets');
      if Assets <> nil then
        for I := 0 to Assets.Count - 1 do
        begin
          Asset := Assets.Items[I] as TJSONObject;
          CandidateName := JsonString(Asset, 'name');
          if CandidateName.EndsWith('.exe', True) and
             (CandidateName.ToLower.Contains('setup') or
              CandidateName.ToLower.Contains('installer')) then
          begin
            Result.AssetName := CandidateName;
            Result.AssetDownloadUrl :=
              JsonString(Asset, 'browser_download_url');
            Break;
          end;
        end;

      if Result.TagName = '' then
        raise Exception.Create('Das Release enthält keine Versionsnummer.');
    finally
      Root.Free;
    end;
  finally
    Client.Free;
  end;
end;

class procedure TGitHubReleaseClient.DownloadAsset(const AUrl,
  ADestinationFile: string);
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Stream: TFileStream;
  Headers: TNetHeaders;
begin
  if AUrl = '' then
    raise Exception.Create('Für dieses Release wurde kein Setup gefunden.');

  Headers := CreateHeaders;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 15000;
    Client.ResponseTimeout := 120000;
    Stream := TFileStream.Create(ADestinationFile, fmCreate);
    try
      Response := Client.Get(AUrl, Stream, Headers);
      if Response.StatusCode <> 200 then
        raise Exception.CreateFmt('Der Download ist fehlgeschlagen: HTTP %d (%s).',
          [Response.StatusCode, Response.StatusText]);
    finally
      Stream.Free;
    end;
  finally
    Client.Free;
  end;
end;

end.
