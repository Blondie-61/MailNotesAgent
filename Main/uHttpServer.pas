unit uHttpServer;

interface

uses
  System.SysUtils,
  System.NetEncoding,

  IdHTTPServer,
  IdContext,
  IdCustomHTTPServer,

  uDatabase,
  uNote;

type
  THttpServer = class
  private
    FServer: TIdHTTPServer;
    FDatabase: TDatabase;

    procedure HandleCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure RouteRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);

    procedure HandlePing(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNotFound(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNote(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleSave(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);

    procedure SendJson(AResponseInfo: TIdHTTPResponseInfo; const AJson: string; AStatusCode: Integer = 200);
    function JsonEscape(const S: string): string;

  public
    constructor Create(ADatabase: TDatabase);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
  end;

implementation

constructor THttpServer.Create(ADatabase: TDatabase);
begin
  inherited Create;

  FDatabase := ADatabase;

  FServer := TIdHTTPServer.Create(nil);
  FServer.OnCommandGet := HandleCommandGet;
end;

destructor THttpServer.Destroy;
begin
  try
    Stop;
  finally
    FServer.Free;
  end;

  inherited;
end;

procedure THttpServer.Start;
begin
  if FServer.Active then
    Exit;

  FServer.Bindings.Clear;
  FServer.DefaultPort := 48571;
  FServer.Active := True;
end;

procedure THttpServer.Stop;
begin
  if FServer.Active then
    FServer.Active := False;
end;

procedure THttpServer.HandleCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  if SameText(ARequestInfo.Command, 'POST') then
  begin
    if SameText(ARequestInfo.Document, '/note') then
      HandleSave(ARequestInfo, AResponseInfo)
    else
      HandleNotFound(AResponseInfo);

    Exit;
  end;

  RouteRequest(ARequestInfo, AResponseInfo);
end;

procedure THttpServer.RouteRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  if SameText(ARequestInfo.Document, '/ping') then
    HandlePing(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/note') then
    HandleNote(ARequestInfo, AResponseInfo)
  else
    HandleNotFound(AResponseInfo);
end;

procedure THttpServer.HandlePing(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(AResponseInfo, '{"status":"ok","version":"0.1.0"}');
end;

procedure THttpServer.HandleNotFound(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(AResponseInfo, '{"error":"not_found"}', 404);
end;

procedure THttpServer.HandleNote(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  MessageID: string;
  Note: TNote;
begin
  MessageID := ARequestInfo.Params.Values['messageId'];

  if MessageID = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_messageId"}', 400);
    Exit;
  end;

  MessageID := TNetEncoding.URL.Decode(MessageID);

  Note := FDatabase.FindByMessageID(MessageID);
  try
    if not Assigned(Note) then
    begin
      SendJson(AResponseInfo, '{"found":false}');
      Exit;
    end;

    SendJson(AResponseInfo,
      '{"found":true,' +
      '"content":"' + JsonEscape(Note.Content) + '",' +
      '"links":"' + JsonEscape(Note.Links) + '",' +
      '"createdAt":"' + JsonEscape(Note.CreatedAt) + '",' +
      '"modifiedAt":"' + JsonEscape(Note.ModifiedAt) + '"' +
      '}');
  finally
    Note.Free;
  end;
end;

procedure THttpServer.HandleSave(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  MessageID: string;
  ConversationID: string;
  Content: string;
  Links: string;
  Note: TNote;
begin
  MessageID := ARequestInfo.Params.Values['messageId'];
  ConversationID := ARequestInfo.Params.Values['conversationId'];
  Content := ARequestInfo.Params.Values['content'];
  Links := ARequestInfo.Params.Values['links'];

  if MessageID = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_messageId"}', 400);
    Exit;
  end;

  Note := FDatabase.FindByMessageID(MessageID);

  if not Assigned(Note) then
    Note := TNote.Create(MessageID);

  try
    Note.ConversationID := ConversationID;
    Note.Content := Content;
    Note.Links := Links;

    FDatabase.Save(Note);

    SendJson(AResponseInfo,
      '{"saved":true,"id":' + Note.ID.ToString + '}');
  finally
    Note.Free;
  end;
end;

procedure THttpServer.SendJson(AResponseInfo: TIdHTTPResponseInfo; const AJson: string; AStatusCode: Integer);
begin
  AResponseInfo.ResponseNo := AStatusCode;
  AResponseInfo.ContentType := 'application/json; charset=utf-8';
  AResponseInfo.ContentText := AJson;
end;

function THttpServer.JsonEscape(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

end.
