unit uGraphAuth;

interface

uses
  System.SysUtils;

type
  TGraphTokenResult = record
    AccessToken: string;
    RefreshToken: string;
    TokenType: string;
    Scope: string;
    ExpiresIn: Integer;
  end;

  TGraphUserInfo = record
    ID: string;
    DisplayName: string;
    UserPrincipalName: string;
    Mail: string;
  end;

  TGraphAuthorizationResult = record
    AuthorizationCode: string;
    State: string;
    Error: string;
    ErrorDescription: string;
  end;

  TGraphAuth = class sealed
  private const
    ClientID = '43aec977-56b4-45e4-890c-3eaeea99db5d';
    TenantID = '56415211-3350-4c93-8b0d-939d4f7015e3';
    RedirectURI = 'http://localhost:8400';
    CallbackPort = 8400;
  private
    class function NewVerifier: string; static;
    class function NewState: string; static;
    class function Base64UrlNoPadding(const Bytes: TBytes): string; static;
    class function CodeChallenge(const Verifier: string): string; static;
    class function UrlEncode(const Value: string): string; static;
    class procedure OpenBrowser(const URL: string); static;
  public
    class function BuildAuthorizationURL(
      out Verifier, State: string
    ): string; static;
    class function Authorize(
      out Verifier: string;
      out ResultInfo: TGraphAuthorizationResult;
      const TimeoutMS: Cardinal = 120000
    ): Boolean; static;
    class function ConfiguredTenantID: string; static;
    class function ExchangeAuthorizationCode(
      const AuthorizationCode, Verifier: string;
      out Tokens: TGraphTokenResult;
      out ErrorText: string
    ): Boolean; static;
    class function RefreshAccessToken(
      const RefreshToken: string;
      out Tokens: TGraphTokenResult;
      out ErrorText: string
    ): Boolean; static;
    class function GetMe(
      const AccessToken: string;
      out UserInfo: TGraphUserInfo;
      out ErrorText: string
    ): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Hash,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.JSON,
  System.SyncObjs,
  IdContext,
  IdCustomHTTPServer,
  IdHTTPServer,
{$IF Defined(MSWINDOWS)}
  Winapi.Windows,
  Winapi.ShellAPI;
{$ELSEIF Defined(MACOS)}
  Macapi.AppKit,
  Macapi.Foundation;
{$ENDIF}

type
  TGraphCallbackServer = class
  private
    FServer: TIdHTTPServer;
    FEvent: TEvent;
    FExpectedState: string;
    FResult: TGraphAuthorizationResult;
    procedure HandleGet(
      AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo
    );
  public
    constructor Create(const ExpectedState: string);
    destructor Destroy; override;
    procedure Start;
    function WaitForResult(
      const TimeoutMS: Cardinal;
      out ResultInfo: TGraphAuthorizationResult
    ): Boolean;
  end;



function JsonString(const Obj: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if Obj = nil then
    Exit;
  Value := Obj.GetValue(Name);
  if Value <> nil then
    Result := Value.Value;
end;

function JsonInteger(const Obj: TJSONObject; const Name: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  if Obj = nil then
    Exit;
  Value := Obj.GetValue(Name);
  if Value <> nil then
    TryStrToInt(Value.Value, Result);
end;

function OAuthErrorText(const Obj: TJSONObject; const HTTPStatus: Integer;
  const HTTPStatusText: string): string;
var
  Code, Description: string;
begin
  Code := JsonString(Obj, 'error');
  Description := JsonString(Obj, 'error_description');
  if (Code <> '') or (Description <> '') then
  begin
    Result := Code;
    if (Result <> '') and (Description <> '') then
      Result := Result + ': ';
    Result := Result + Description;
  end
  else
    Result := Format('HTTP %d (%s)', [HTTPStatus, HTTPStatusText]);
end;

function GuidText: string;
var
  G: TGUID;
begin
  if CreateGUID(G) <> 0 then
    raise Exception.Create('Zufallswert für Graph-Anmeldung konnte nicht erzeugt werden.');
  Result := GUIDToString(G).Replace('{', '').Replace('}', '').Replace('-', '');
end;

constructor TGraphCallbackServer.Create(const ExpectedState: string);
begin
  inherited Create;
  FExpectedState := ExpectedState;
  FEvent := TEvent.Create(nil, True, False, '');
  FServer := TIdHTTPServer.Create(nil);
  FServer.OnCommandGet := HandleGet;
end;

destructor TGraphCallbackServer.Destroy;
begin
  if FServer.Active then
    FServer.Active := False;
  FServer.Free;
  FEvent.Free;
  inherited;
end;

procedure TGraphCallbackServer.Start;
begin
  FServer.Bindings.Clear;
  with FServer.Bindings.Add do
  begin
    IP := '127.0.0.1';
    Port := TGraphAuth.CallbackPort;
  end;
  FServer.DefaultPort := TGraphAuth.CallbackPort;
  FServer.Active := True;
end;

procedure TGraphCallbackServer.HandleGet(
  AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
begin
  if ARequestInfo.Document <> '/' then
  begin
    AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentText := 'Not found';
    Exit;
  end;

  FResult.AuthorizationCode := ARequestInfo.Params.Values['code'];
  FResult.State := ARequestInfo.Params.Values['state'];
  FResult.Error := ARequestInfo.Params.Values['error'];
  FResult.ErrorDescription := ARequestInfo.Params.Values['error_description'];

  if not SameText(FResult.State, FExpectedState) then
  begin
    FResult.AuthorizationCode := '';
    FResult.Error := 'state_mismatch';
    FResult.ErrorDescription := 'Der OAuth-State stimmt nicht mit der gestarteten Anmeldung überein.';
  end;

  AResponseInfo.ContentType := 'text/html; charset=utf-8';
  if (FResult.Error = '') and (FResult.AuthorizationCode <> '') then
    AResponseInfo.ContentText :=
      '<!doctype html><html><body><h2>MailNotes</h2>' +
      '<p>Anmeldung empfangen. Dieses Fenster kann geschlossen werden.</p></body></html>'
  else
    AResponseInfo.ContentText :=
      '<!doctype html><html><body><h2>MailNotes</h2>' +
      '<p>Die Anmeldung konnte nicht abgeschlossen werden.</p></body></html>';

  FEvent.SetEvent;
end;

function TGraphCallbackServer.WaitForResult(
  const TimeoutMS: Cardinal;
  out ResultInfo: TGraphAuthorizationResult
): Boolean;
begin
  Result := FEvent.WaitFor(TimeoutMS) = wrSignaled;
  if Result then
  begin
    // HandleGet signalisiert, bevor Indy die HTTP-Antwort vollstaendig
    // an den Browser uebertragen hat. Den Listener daher nicht sofort abbauen.
    Sleep(250);
    ResultInfo := FResult;
  end
  else
  begin
    ResultInfo := Default(TGraphAuthorizationResult);
    ResultInfo.Error := 'timeout';
    ResultInfo.ErrorDescription := 'Zeitüberschreitung beim Warten auf die Graph-Anmeldung.';
  end;
end;

class function TGraphAuth.NewVerifier: string;
begin
  // RFC 7636: 43..128 Zeichen. Vier OS-erzeugte GUIDs liefern 128 Hex-Zeichen.
  Result := GuidText + GuidText + GuidText + GuidText;
end;

class function TGraphAuth.NewState: string;
begin
  Result := GuidText + GuidText;
end;

class function TGraphAuth.Base64UrlNoPadding(const Bytes: TBytes): string;
begin
  Result := TNetEncoding.Base64.EncodeBytesToString(Bytes);
  Result := Result.Replace('+', '-').Replace('/', '_').Replace('=', '');
end;

class function TGraphAuth.CodeChallenge(const Verifier: string): string;
begin
  Result := Base64UrlNoPadding(THashSHA2.GetHashBytes(Verifier, SHA256));
end;

class function TGraphAuth.UrlEncode(const Value: string): string;
begin
  Result := TNetEncoding.URL.Encode(Value);
end;

class function TGraphAuth.BuildAuthorizationURL(
  out Verifier, State: string
): string;
var
  Challenge: string;
begin
  Verifier := NewVerifier;
  State := NewState;
  Challenge := CodeChallenge(Verifier);

  Result :=
    'https://login.microsoftonline.com/' + TenantID + '/oauth2/v2.0/authorize' +
    '?client_id=' + UrlEncode(ClientID) +
    '&response_type=code' +
    '&redirect_uri=' + UrlEncode(RedirectURI) +
    '&response_mode=query' +
    '&scope=' + UrlEncode('openid profile offline_access User.Read Mail.Read') +
    '&code_challenge=' + UrlEncode(Challenge) +
    '&code_challenge_method=S256' +
    '&state=' + UrlEncode(State) +
    '&prompt=select_account';
end;

class procedure TGraphAuth.OpenBrowser(const URL: string);
{$IF Defined(MACOS)}
var
  Workspace: NSWorkspace;
  NSUrl: NSURL;
{$ENDIF}
begin
{$IF Defined(MSWINDOWS)}
  if ShellExecuteW(0, 'open', PWideChar(URL), nil, nil, SW_SHOWNORMAL) <= 32 then
    raise Exception.Create('Browser für Graph-Anmeldung konnte nicht geöffnet werden.');
{$ELSEIF Defined(MACOS)}
  Workspace := TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace);
  NSUrl := TNSURL.Wrap(TNSURL.OCClass.URLWithString(StrToNSStr(URL)));
  if (NSUrl = nil) or not Workspace.openURL(NSUrl) then
    raise Exception.Create('Browser für Graph-Anmeldung konnte nicht geöffnet werden.');
{$ELSE}
  raise Exception.Create('Graph-Anmeldung wird auf dieser Plattform nicht unterstützt.');
{$ENDIF}
end;

class function TGraphAuth.Authorize(
  out Verifier: string;
  out ResultInfo: TGraphAuthorizationResult;
  const TimeoutMS: Cardinal
): Boolean;
var
  State: string;
  URL: string;
  Callback: TGraphCallbackServer;
begin
  ResultInfo := Default(TGraphAuthorizationResult);
  URL := BuildAuthorizationURL(Verifier, State);

  Callback := TGraphCallbackServer.Create(State);
  try
    // Listener muss vor dem Browser bereit sein, damit kein schneller Redirect verloren geht.
    Callback.Start;
    OpenBrowser(URL);
    Result := Callback.WaitForResult(TimeoutMS, ResultInfo);
    Result := Result and (ResultInfo.Error = '') and
      (ResultInfo.AuthorizationCode <> '');
  finally
    Callback.Free;
  end;
end;


class function TGraphAuth.ExchangeAuthorizationCode(
  const AuthorizationCode, Verifier: string;
  out Tokens: TGraphTokenResult;
  out ErrorText: string
): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Body: TStringStream;
  Root: TJSONObject;
  FormData: string;
begin
  Tokens := Default(TGraphTokenResult);
  ErrorText := '';

  FormData :=
    'client_id=' + UrlEncode(ClientID) +
    '&scope=' + UrlEncode('openid profile offline_access User.Read Mail.Read') +
    '&code=' + UrlEncode(AuthorizationCode) +
    '&redirect_uri=' + UrlEncode(RedirectURI) +
    '&grant_type=authorization_code' +
    '&code_verifier=' + UrlEncode(Verifier);

  Client := THTTPClient.Create;
  try
    try
      Client.ConnectionTimeout := 10000;
      Client.ResponseTimeout := 30000;
      Body := TStringStream.Create(FormData, TEncoding.UTF8);
    try
      Response := Client.Post(
        'https://login.microsoftonline.com/' + TenantID + '/oauth2/v2.0/token',
        Body,
        nil,
        [TNameValuePair.Create('Content-Type', 'application/x-www-form-urlencoded')]
      );
    finally
      Body.Free;
    end;

    Root := TJSONObject.ParseJSONValue(
      Response.ContentAsString(TEncoding.UTF8)) as TJSONObject;
    try
      if Response.StatusCode <> 200 then
      begin
        ErrorText := OAuthErrorText(Root, Response.StatusCode, Response.StatusText);
        Exit(False);
      end;

      if Root = nil then
      begin
        ErrorText := 'Die Token-Antwort ist kein gültiges JSON.';
        Exit(False);
      end;

      Tokens.AccessToken := JsonString(Root, 'access_token');
      Tokens.RefreshToken := JsonString(Root, 'refresh_token');
      Tokens.TokenType := JsonString(Root, 'token_type');
      Tokens.Scope := JsonString(Root, 'scope');
      Tokens.ExpiresIn := JsonInteger(Root, 'expires_in');

      if Tokens.AccessToken = '' then
      begin
        ErrorText := 'Die Token-Antwort enthält kein Access Token.';
        Exit(False);
      end;

      Result := True;
    finally
      Root.Free;
    end;
    except
      on E: Exception do
      begin
        ErrorText := E.Message;
        Result := False;
      end;
    end;
  finally
    Client.Free;
  end;
end;


class function TGraphAuth.ConfiguredTenantID: string;
begin
  Result := TenantID;
end;

class function TGraphAuth.RefreshAccessToken(
  const RefreshToken: string;
  out Tokens: TGraphTokenResult;
  out ErrorText: string
): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Body: TStringStream;
  Root: TJSONObject;
  FormData: string;
begin
  Tokens := Default(TGraphTokenResult);
  ErrorText := '';

  if RefreshToken = '' then
  begin
    ErrorText := 'Kein Refresh Token vorhanden.';
    Exit(False);
  end;

  FormData :=
    'client_id=' + UrlEncode(ClientID) +
    '&scope=' + UrlEncode('openid profile offline_access User.Read Mail.Read') +
    '&refresh_token=' + UrlEncode(RefreshToken) +
    '&grant_type=refresh_token';

  Client := THTTPClient.Create;
  try
    try
      Client.ConnectionTimeout := 10000;
      Client.ResponseTimeout := 30000;
      Body := TStringStream.Create(FormData, TEncoding.UTF8);
      try
        Response := Client.Post(
          'https://login.microsoftonline.com/' + TenantID + '/oauth2/v2.0/token',
          Body, nil,
          [TNameValuePair.Create('Content-Type', 'application/x-www-form-urlencoded')]
        );
      finally
        Body.Free;
      end;

      Root := TJSONObject.ParseJSONValue(
        Response.ContentAsString(TEncoding.UTF8)) as TJSONObject;
      try
        if Response.StatusCode <> 200 then
        begin
          ErrorText := OAuthErrorText(Root, Response.StatusCode, Response.StatusText);
          Exit(False);
        end;
        if Root = nil then
        begin
          ErrorText := 'Die Refresh-Antwort ist kein gültiges JSON.';
          Exit(False);
        end;

        Tokens.AccessToken := JsonString(Root, 'access_token');
        Tokens.RefreshToken := JsonString(Root, 'refresh_token');
        Tokens.TokenType := JsonString(Root, 'token_type');
        Tokens.Scope := JsonString(Root, 'scope');
        Tokens.ExpiresIn := JsonInteger(Root, 'expires_in');
        if Tokens.AccessToken = '' then
        begin
          ErrorText := 'Die Refresh-Antwort enthält kein Access Token.';
          Exit(False);
        end;
        Result := True;
      finally
        Root.Free;
      end;
    except
      on E: Exception do
      begin
        ErrorText := E.Message;
        Result := False;
      end;
    end;
  finally
    Client.Free;
  end;
end;

class function TGraphAuth.GetMe(
  const AccessToken: string;
  out UserInfo: TGraphUserInfo;
  out ErrorText: string
): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Root: TJSONObject;
  Headers: TNetHeaders;
begin
  UserInfo := Default(TGraphUserInfo);
  ErrorText := '';
  SetLength(Headers, 2);
  Headers[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken);
  Headers[1] := TNameValuePair.Create('Accept', 'application/json');

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 10000;
    Client.ResponseTimeout := 30000;
    try
      Response := Client.Get(
        'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName,mail',
        nil,
        Headers
      );

      Root := TJSONObject.ParseJSONValue(
        Response.ContentAsString(TEncoding.UTF8)) as TJSONObject;
      try
        if Response.StatusCode <> 200 then
        begin
          ErrorText := OAuthErrorText(Root, Response.StatusCode, Response.StatusText);
          Exit(False);
        end;

        if Root = nil then
        begin
          ErrorText := 'Die Graph-Antwort auf /me ist kein gültiges JSON.';
          Exit(False);
        end;

        UserInfo.ID := JsonString(Root, 'id');
        UserInfo.DisplayName := JsonString(Root, 'displayName');
        UserInfo.UserPrincipalName := JsonString(Root, 'userPrincipalName');
        UserInfo.Mail := JsonString(Root, 'mail');

        if UserInfo.ID = '' then
        begin
          ErrorText := 'Die Graph-Antwort auf /me enthält keine Benutzer-ID.';
          Exit(False);
        end;

        Result := True;
      finally
        Root.Free;
      end;
    except
      on E: Exception do
      begin
        ErrorText := E.Message;
        Result := False;
      end;
    end;
  finally
    Client.Free;
  end;
end;


end.
