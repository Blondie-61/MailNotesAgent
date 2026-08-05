unit uHttpServer;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.NetEncoding,
  System.Generics.Collections,

  IdHTTPServer,
  IdContext,
  IdCustomHTTPServer,

  uDatabase,
  uNote,
  uLinkBuffer,
  uRepairQueue,
  uAppPaths,
  uAppInfo;

type
  THttpServer = class
  private
    FServer: TIdHTTPServer;
    FDatabase: TDatabase;
    FDatabaseLock: TObject;
    FLogLock: TObject;

    procedure HandleCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure RouteRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);

    procedure HandlePing(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleVersion(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNotFound(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNote(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleSave(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLog(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleMailRefresh(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleResolve(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleBacklinks(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleSearch(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferSet(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferGet(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferClear(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueAdd(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueCount(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueList(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueStatus(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);

    procedure SendJson(AResponseInfo: TIdHTTPResponseInfo; const AJson: string; AStatusCode: Integer = 200);
    function JsonEscape(const S: string): string;
    procedure LogToFile(const ASource, AEvent, AData: string);

  public
    constructor Create(ADatabase: TDatabase);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
  end;

implementation

const
  ENABLE_LOGGING = False;

constructor THttpServer.Create(ADatabase: TDatabase);
begin
  inherited Create;
  FDatabase := ADatabase;
  FDatabaseLock := TObject.Create;
  FLogLock := TObject.Create;
  FServer := TIdHTTPServer.Create(nil);
  FServer.OnCommandGet := HandleCommandGet;
end;

destructor THttpServer.Destroy;
begin
  try
    Stop;
  finally
    FServer.Free;
    FLogLock.Free;
    FDatabaseLock.Free;
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
  // Indy verarbeitet gleichzeitige HTTP-Anfragen in unterschiedlichen Threads.
  // Sämtliche Handler teilen sich jedoch eine FireDAC-Verbindung. FireDAC-
  // Verbindungen dürfen nicht parallel von mehreren Threads verwendet werden.
  // Deshalb wird eine Anfrage vollständig abgearbeitet, bevor die nächste auf
  // die gemeinsame Datenbank zugreifen kann.
  TMonitor.Enter(FDatabaseLock);
  try
    if SameText(ARequestInfo.Command, 'POST') then
    begin
      if SameText(ARequestInfo.Document, '/note') then
        HandleSave(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/log') then
        HandleLog(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/mail/refresh') then
        HandleMailRefresh(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/linkbuffer') then
        HandleLinkBufferSet(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/repairqueue') then
        HandleRepairQueueAdd(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/repairqueue/status') then
        HandleRepairQueueStatus(ARequestInfo, AResponseInfo)
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
  finally
    TMonitor.Exit(FDatabaseLock);
  end;
end;

procedure THttpServer.RouteRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  if SameText(ARequestInfo.Document, '/ping') then
    HandlePing(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/version') then
    HandleVersion(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/note') then
    HandleNote(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/resolve') then
    HandleResolve(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/backlinks') then
    HandleBacklinks(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/search') then
    HandleSearch(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/linkbuffer') then
    HandleLinkBufferGet(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/repairqueue/count') then
    HandleRepairQueueCount(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/repairqueue') then
    HandleRepairQueueList(AResponseInfo)
  else
    HandleNotFound(AResponseInfo);
end;

procedure THttpServer.HandlePing(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(
    AResponseInfo,
    '{' +
    '"status":"ok",' +
    '"version":"' + JsonEscape(TAppInfo.Version) + '",' +
    '"schema":3,' +
    '"identity":"MailNotesID"' +
    '}'
  );
end;

procedure THttpServer.HandleVersion(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(
    AResponseInfo,
    '{' +
    '"name":"MailNotesAgent",' +
    '"version":"' + JsonEscape(TAppInfo.Version) + '",' +
    '"platform":"' + JsonEscape(TAppInfo.PlatformName) + '",' +
    '"port":48571,' +
    '"agentPath":"' + JsonEscape(TAppPaths.AgentFile) + '",' +
    '"addinPath":"' + JsonEscape(TAppPaths.AddinDirectory) + '",' +
    '"databasePath":"' + JsonEscape(TAppPaths.DatabaseFile) + '"' +
    '}'
  );
end;

procedure THttpServer.HandleNotFound(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(AResponseInfo, '{"error":"not_found"}', 404);
end;

procedure THttpServer.HandleNote(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  MailNotesID: string;
  MessageID: string;
  Note: TNote;
begin
  MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
  MessageID := ARequestInfo.Params.Values['messageId'];

  if (MailNotesID = '') and (MessageID = '') then
  begin
    SendJson(AResponseInfo, '{"error":"missing_mail_identity"}', 400);
    Exit;
  end;

  if MailNotesID <> '' then
    Note := FDatabase.FindByMailNotesID(MailNotesID)
  else
    Note := FDatabase.FindByMessageID(MessageID);

  try
    if not Assigned(Note) then
    begin
      SendJson(AResponseInfo, '{"found":false}');
      Exit;
    end;

    // Eine Mail kann bereits durch einen MailLink bekannt sein, ohne selbst
    // eine Notiz zu besitzen. Die MailNotesID muss trotzdem an das Taskpane
    // zurückgegeben werden, damit SHL ihre technische Outlook-ID aktualisiert.
    if Note.ID = 0 then
    begin
      SendJson(
        AResponseInfo,
        '{' +
        '"found":false,' +
        '"mailNotesId":"' + JsonEscape(Note.MailNotesID) + '"' +
        '}'
      );
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
  MailNotesID: string;
  MessageID: string;
  Note: TNote;
begin
  MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
  MessageID := ARequestInfo.Params.Values['messageId'];

  if (MailNotesID = '') and (MessageID = '') then
  begin
    SendJson(AResponseInfo, '{"error":"missing_mail_identity"}', 400);
    Exit;
  end;

  if MailNotesID <> '' then
    Note := FDatabase.FindByMailNotesID(MailNotesID)
  else
    Note := FDatabase.FindByMessageID(MessageID);

  if not Assigned(Note) then
  begin
    Note := TNote.Create(MessageID);
    Note.MailNotesID := MailNotesID;
  end;

  try
    if MailNotesID <> '' then
      Note.MailNotesID := MailNotesID;
    if MessageID <> '' then
      Note.MessageID := MessageID;

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

procedure THttpServer.LogToFile(const ASource, AEvent, AData: string);
var
  Line: string;
  LogFileName: string;
begin
  if not ENABLE_LOGGING then
    Exit;

  TAppPaths.EnsureDataDirectory;
  LogFileName := TAppPaths.LogFile;
  Line :=
    FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
    ' [' + ASource + '] ' + AEvent;

  if AData <> '' then
    Line := Line + ' ' + AData;

  TMonitor.Enter(FLogLock);
  try
    TFile.AppendAllText(LogFileName, Line + sLineBreak, TEncoding.UTF8);
  finally
    TMonitor.Exit(FLogLock);
  end;
end;

procedure THttpServer.HandleLog(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  LogToFile(
    'Outlook Add-in',
    ARequestInfo.Params.Values['event'],
    ARequestInfo.Params.Values['data']
  );

  SendJson(AResponseInfo, '{"logged":true}');
end;

procedure THttpServer.HandleMailRefresh(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  MailNotesID: string;
  MessageID: string;
  OldItemID: string;
  Note: TNote;
  WasUpdated: Boolean;
begin
  MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
  MessageID := ARequestInfo.Params.Values['messageId'];

  if (MailNotesID = '') and (MessageID = '') then
  begin
    SendJson(AResponseInfo, '{"error":"missing_mail_identity"}', 400);
    Exit;
  end;

  if MailNotesID <> '' then
    Note := FDatabase.FindByMailNotesID(MailNotesID)
  else
    Note := FDatabase.FindByMessageID(MessageID);

  if not Assigned(Note) then
  begin
    // Eine bisher unbekannte Mail wird hier nur in der Mail-Tabelle
    // registriert. Es wird keine leere Notiz angelegt.
    Note := TNote.Create(MessageID);
    Note.MailNotesID := MailNotesID;
  end;

  try
    OldItemID := Note.ItemID;

    if MessageID <> '' then
      Note.MessageID := MessageID;

    Note.ItemID := ARequestInfo.Params.Values['itemId'];
    Note.ImmutableID := ARequestInfo.Params.Values['immutableId'];
    Note.ConversationID := ARequestInfo.Params.Values['conversationId'];
    Note.MailboxAddress := ARequestInfo.Params.Values['mailboxAddress'];
    Note.Subject := ARequestInfo.Params.Values['subject'];
    Note.SenderName := ARequestInfo.Params.Values['senderName'];
    Note.SenderAddress := ARequestInfo.Params.Values['senderAddress'];
    Note.MailDate := ARequestInfo.Params.Values['mailDate'];

    WasUpdated :=
      (Note.ItemID <> '') and
      (OldItemID <> '') and
      not SameText(Note.ItemID, OldItemID);

    FDatabase.RefreshMailIdentity(Note);
    FDatabase.CompleteRepairQueueByIdentity(Note.MailNotesID, Note.MessageID);

    if WasUpdated then
      LogToFile(
        'Agent',
        'SHL repaired',
        'oldItemId=' + OldItemID +
        ' itemId=' + Note.ItemID +
        ' mailNotesId=' + Note.MailNotesID
      );

    SendJson(
      AResponseInfo,
      '{' +
      '"found":true,' +
      '"updated":' + LowerCase(BoolToStr(WasUpdated, True)) + ',' +
      '"mailNotesId":"' + JsonEscape(Note.MailNotesID) + '",' +
      '"oldItemId":"' + JsonEscape(OldItemID) + '",' +
      '"itemId":"' + JsonEscape(Note.ItemID) + '"' +
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
  TargetToken: string;
  Backlinks: TObjectList<TNote>;
  Note: TNote;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  TargetToken := ARequestInfo.Params.Values['mailNotesId'];
  if TargetToken = '' then
    TargetToken := ARequestInfo.Params.Values['messageId'];

  if TargetToken = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_mail_identity"}', 400);
    Exit;
  end;

  Backlinks := FDatabase.GetBacklinks(TargetToken);
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

procedure THttpServer.HandleSearch(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  SearchText: string;
  MaxResults: Integer;
  Items: TObjectList<TNote>;
  Note: TNote;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  SearchText := Trim(ARequestInfo.Params.Values['q']);
  if SearchText = '' then
  begin
    SendJson(AResponseInfo, '{"items":[],"count":0}');
    Exit;
  end;

  MaxResults := StrToIntDef(ARequestInfo.Params.Values['limit'], 50);
  Items := FDatabase.SearchNotes(SearchText, MaxResults);
  Json := TStringBuilder.Create;
  try
    Json.Append('{"items":[');
    IsFirst := True;
    for Note in Items do
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
      Json.Append('"senderAddress":"' + JsonEscape(Note.SenderAddress) + '",');
      Json.Append('"mailDate":"' + JsonEscape(Note.MailDate) + '",');
      Json.Append('"modifiedAt":"' + JsonEscape(Note.ModifiedAt) + '",');
      Json.Append('"snippet":"' + JsonEscape(Note.SearchSnippet) + '"');
      Json.Append('}');
    end;
    Json.Append('],"count":' + Items.Count.ToString + '}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Items.Free;
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

    if (LinkBuffer.MailNotesID = '') and (LinkBuffer.MessageID = '') then
    begin
      SendJson(AResponseInfo, '{"error":"missing_mail_identity"}', 400);
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


procedure THttpServer.HandleRepairQueueAdd(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  Item: TRepairQueueItem;
begin
  Item := TRepairQueueItem.Create;
  try
    Item.MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
    Item.OldItemID := ARequestInfo.Params.Values['oldItemId'];
    Item.MessageID := ARequestInfo.Params.Values['messageId'];
    Item.Subject := ARequestInfo.Params.Values['subject'];
    Item.SenderName := ARequestInfo.Params.Values['senderName'];
    Item.SenderAddress := ARequestInfo.Params.Values['senderAddress'];
    Item.MailDate := ARequestInfo.Params.Values['mailDate'];
    Item.Reason := ARequestInfo.Params.Values['reason'];

    if Item.MailNotesID = '' then
    begin
      SendJson(AResponseInfo, '{"error":"missing_mailnotes_id"}', 400);
      Exit;
    end;

    if Item.Reason = '' then
      Item.Reason := 'stored_item_id_invalid';

    FDatabase.AddRepairQueueItem(Item);
    SendJson(AResponseInfo, '{"queued":true}');
  finally
    Item.Free;
  end;
end;

procedure THttpServer.HandleRepairQueueCount(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(
    AResponseInfo,
    '{"count":' + FDatabase.GetRepairQueueCount.ToString + '}'
  );
end;

procedure THttpServer.HandleRepairQueueList(AResponseInfo: TIdHTTPResponseInfo);
var
  Items: TObjectList<TRepairQueueItem>;
  Item: TRepairQueueItem;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  Items := FDatabase.GetRepairQueue;
  Json := TStringBuilder.Create;
  try
    Json.Append('{"items":[');
    IsFirst := True;
    for Item in Items do
    begin
      if not IsFirst then
        Json.Append(',');
      IsFirst := False;

      Json.Append('{');
      Json.Append('"id":' + Item.ID.ToString + ',');
      Json.Append('"mailNotesId":"' + JsonEscape(Item.MailNotesID) + '",');
      Json.Append('"oldItemId":"' + JsonEscape(Item.OldItemID) + '",');
      Json.Append('"messageId":"' + JsonEscape(Item.MessageID) + '",');
      Json.Append('"subject":"' + JsonEscape(Item.Subject) + '",');
      Json.Append('"senderName":"' + JsonEscape(Item.SenderName) + '",');
      Json.Append('"senderAddress":"' + JsonEscape(Item.SenderAddress) + '",');
      Json.Append('"mailDate":"' + JsonEscape(Item.MailDate) + '",');
      Json.Append('"reason":"' + JsonEscape(Item.Reason) + '",');
      Json.Append('"retryCount":' + Item.RetryCount.ToString + ',');
      Json.Append('"status":' + Item.Status.ToString);
      Json.Append('}');
    end;
    Json.Append(']}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Items.Free;
  end;
end;

procedure THttpServer.HandleRepairQueueStatus(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  ID: Integer;
  Status: Integer;
begin
  ID := StrToIntDef(ARequestInfo.Params.Values['id'], 0);
  Status := StrToIntDef(ARequestInfo.Params.Values['status'], -1);

  if (ID <= 0) or not (Status in [0, 1, 2, 3]) then
  begin
    SendJson(AResponseInfo, '{"error":"invalid_status_request"}', 400);
    Exit;
  end;

  FDatabase.SetRepairQueueStatus(ID, Status);
  SendJson(AResponseInfo, '{"updated":true}');
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
