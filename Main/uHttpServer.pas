unit uHttpServer;

interface

uses
  System.SysUtils,
  System.NetEncoding,
  System.Generics.Collections,

  IdHTTPServer,
  IdContext,
  IdCustomHTTPServer,

  uDatabase,
  uNote,
  uLinkBuffer;

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
    procedure HandleResolve(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleBacklinks(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferSet(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferGet(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferClear(AResponseInfo: TIdHTTPResponseInfo);

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
    else if SameText(ARequestInfo.Document, '/linkbuffer') then
      HandleLinkBufferSet(ARequestInfo, AResponseInfo)
    else
      HandleNotFound(AResponseInfo);
    Exit;
  end;

  if SameText(ARequestInfo.Command, 'DELETE') then
  begin
    if SameText(ARequestInfo.Document, '/linkbuffer') then
      HandleLinkBufferClear(AResponseInfo)
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
  else if SameText(ARequestInfo.Document, '/resolve') then
    HandleResolve(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/backlinks') then
    HandleBacklinks(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/linkbuffer') then
    HandleLinkBufferGet(AResponseInfo)
  else
    HandleNotFound(AResponseInfo);
end;

procedure THttpServer.HandlePing(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(AResponseInfo, '{"status":"ok","version":"0.2.0","schema":1}');
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

  Note := FDatabase.FindByMessageID(MessageID);
  try
    if not Assigned(Note) or (Note.ID = 0) then
    begin
      SendJson(AResponseInfo, '{"found":false}');
      Exit;
    end;

    SendJson(
      AResponseInfo,
      '{' +
      '"found":true,' +
      '"mailNotesId":"' + JsonEscape(Note.MailNotesID) + '",' +
      '"content":"' + JsonEscape(Note.Content) + '",' +
      '"links":"' + JsonEscape(Note.Links) + '",' +
      '"createdAt":"' + JsonEscape(Note.CreatedAt) + '",' +
      '"modifiedAt":"' + JsonEscape(Note.ModifiedAt) + '"' +
      '}'
    );
  finally
    Note.Free;
  end;
end;

procedure THttpServer.HandleSave(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
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

  Note := FDatabase.FindByMessageID(MessageID);
  if not Assigned(Note) then
    Note := TNote.Create(MessageID);

  try
    Note.MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
    Note.ConversationID := ARequestInfo.Params.Values['conversationId'];
    Note.ItemID := ARequestInfo.Params.Values['itemId'];
    Note.ImmutableID := ARequestInfo.Params.Values['immutableId'];
    Note.MailboxAddress := ARequestInfo.Params.Values['mailboxAddress'];
    Note.Subject := ARequestInfo.Params.Values['subject'];
    Note.SenderName := ARequestInfo.Params.Values['senderName'];
    Note.SenderAddress := ARequestInfo.Params.Values['senderAddress'];
    Note.MailDate := ARequestInfo.Params.Values['mailDate'];
    Note.Content := ARequestInfo.Params.Values['content'];
    Note.Links := ARequestInfo.Params.Values['links'];

    FDatabase.Save(Note);

    SendJson(
      AResponseInfo,
      '{' +
      '"saved":true,' +
      '"id":' + Note.ID.ToString + ',' +
      '"mailNotesId":"' + JsonEscape(Note.MailNotesID) + '"' +
      '}'
    );
  finally
    Note.Free;
  end;
end;

procedure THttpServer.HandleResolve(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Link: string;
  Token: string;
  Note: TNote;
begin
  Link := ARequestInfo.Params.Values['link'];
  if Link = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_link"}', 400);
    Exit;
  end;

  if not Link.StartsWith('mailnotes:', True) then
  begin
    SendJson(AResponseInfo, '{"found":false,"type":"unknown"}');
    Exit;
  end;

  Token := Copy(Link, Length('mailnotes:') + 1, MaxInt);
  try
    Token := TNetEncoding.URL.Decode(Token);
  except
    { Token war bereits dekodiert. }
  end;

  Note := FDatabase.FindMailByLinkToken(Token);
  try
    if not Assigned(Note) then
    begin
      SendJson(AResponseInfo, '{"found":false,"type":"mail"}');
      Exit;
    end;

    SendJson(
      AResponseInfo,
      '{' +
      '"found":true,' +
      '"type":"mail",' +
      '"mailNotesId":"' + JsonEscape(Note.MailNotesID) + '",' +
      '"title":"' + JsonEscape(Note.Subject) + '",' +
      '"subtitle":"' + JsonEscape(Note.SenderName) + ' · ' + JsonEscape(Note.MailDate) + '",' +
      '"messageId":"' + JsonEscape(Note.MessageID) + '",' +
      '"itemId":"' + JsonEscape(Note.ItemID) + '"' +
      '}'
    );
  finally
    Note.Free;
  end;
end;

procedure THttpServer.HandleBacklinks(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  MessageID: string;
  Backlinks: TObjectList<TNote>;
  Note: TNote;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  MessageID := ARequestInfo.Params.Values['messageId'];
  if MessageID = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_messageId"}', 400);
    Exit;
  end;

  Backlinks := FDatabase.GetBacklinks(MessageID);
  Json := TStringBuilder.Create;
  try
    Json.Append('{"found":');
    Json.Append(LowerCase(BoolToStr(Backlinks.Count > 0, True)));
    Json.Append(',"items":[');

    IsFirst := True;
    for Note in Backlinks do
    begin
      if not IsFirst then
        Json.Append(',');
      IsFirst := False;

      Json.Append('{');
      Json.Append('"mailNotesId":"' + JsonEscape(Note.MailNotesID) + '",');
      Json.Append('"messageId":"' + JsonEscape(Note.MessageID) + '",');
      Json.Append('"itemId":"' + JsonEscape(Note.ItemID) + '",');
      Json.Append('"subject":"' + JsonEscape(Note.Subject) + '",');
      Json.Append('"senderName":"' + JsonEscape(Note.SenderName) + '",');
      Json.Append('"mailDate":"' + JsonEscape(Note.MailDate) + '"');
      Json.Append('}');
    end;

    Json.Append(']}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Backlinks.Free;
  end;
end;

procedure THttpServer.HandleLinkBufferSet(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  LinkBuffer: TLinkBuffer;
begin
  LinkBuffer := TLinkBuffer.Create;
  try
    LinkBuffer.MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
    LinkBuffer.MessageID := ARequestInfo.Params.Values['messageId'];
    LinkBuffer.ItemID := ARequestInfo.Params.Values['itemId'];
    LinkBuffer.ImmutableID := ARequestInfo.Params.Values['immutableId'];
    LinkBuffer.ConversationID := ARequestInfo.Params.Values['conversationId'];
    LinkBuffer.MailboxAddress := ARequestInfo.Params.Values['mailboxAddress'];
    LinkBuffer.Subject := ARequestInfo.Params.Values['subject'];
    LinkBuffer.SenderName := ARequestInfo.Params.Values['senderName'];
    LinkBuffer.SenderAddress := ARequestInfo.Params.Values['senderAddress'];
    LinkBuffer.MailDate := ARequestInfo.Params.Values['mailDate'];

    if LinkBuffer.MessageID = '' then
    begin
      SendJson(AResponseInfo, '{"error":"missing_messageId"}', 400);
      Exit;
    end;

    FDatabase.SaveLinkBuffer(LinkBuffer);

    SendJson(
      AResponseInfo,
      '{' +
      '"saved":true,' +
      '"mailNotesId":"' + JsonEscape(LinkBuffer.MailNotesID) + '",' +
      '"messageId":"' + JsonEscape(LinkBuffer.MessageID) + '",' +
      '"modifiedAt":"' + JsonEscape(LinkBuffer.ModifiedAt) + '"' +
      '}'
    );
  finally
    LinkBuffer.Free;
  end;
end;

procedure THttpServer.HandleLinkBufferGet(AResponseInfo: TIdHTTPResponseInfo);
var
  LinkBuffer: TLinkBuffer;
begin
  LinkBuffer := FDatabase.LoadLinkBuffer;
  try
    if not Assigned(LinkBuffer) then
    begin
      SendJson(AResponseInfo, '{"found":false}');
      Exit;
    end;

    SendJson(
      AResponseInfo,
      '{' +
      '"found":true,' +
      '"mailNotesId":"' + JsonEscape(LinkBuffer.MailNotesID) + '",' +
      '"messageId":"' + JsonEscape(LinkBuffer.MessageID) + '",' +
      '"itemId":"' + JsonEscape(LinkBuffer.ItemID) + '",' +
      '"conversationId":"' + JsonEscape(LinkBuffer.ConversationID) + '",' +
      '"subject":"' + JsonEscape(LinkBuffer.Subject) + '",' +
      '"senderName":"' + JsonEscape(LinkBuffer.SenderName) + '",' +
      '"senderAddress":"' + JsonEscape(LinkBuffer.SenderAddress) + '",' +
      '"mailDate":"' + JsonEscape(LinkBuffer.MailDate) + '",' +
      '"createdAt":"' + JsonEscape(LinkBuffer.CreatedAt) + '",' +
      '"modifiedAt":"' + JsonEscape(LinkBuffer.ModifiedAt) + '"' +
      '}'
    );
  finally
    LinkBuffer.Free;
  end;
end;

procedure THttpServer.HandleLinkBufferClear(AResponseInfo: TIdHTTPResponseInfo);
begin
  FDatabase.ClearLinkBuffer;
  SendJson(AResponseInfo, '{"cleared":true}');
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
