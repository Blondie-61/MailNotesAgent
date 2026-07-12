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
    procedure HandleResolve(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleBacklinks(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);

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
  else if SameText(ARequestInfo.Document, '/resolve') then
    HandleResolve(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/backlinks') then
    HandleBacklinks(ARequestInfo, AResponseInfo)
  else
    HandleNotFound(AResponseInfo);
end;

procedure THttpServer.HandlePing(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(
    AResponseInfo,
    '{"status":"ok","version":"0.1.0"}'
  );
end;

procedure THttpServer.HandleNotFound(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(
    AResponseInfo,
    '{"error":"not_found"}',
    404
  );
end;

procedure THttpServer.HandleNote(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  MessageID: string;
  Note: TNote;
begin
  MessageID := ARequestInfo.Params.Values['messageId'];

  if MessageID = '' then
  begin
    SendJson(
      AResponseInfo,
      '{"error":"missing_messageId"}',
      400
    );

    Exit;
  end;

  Note := FDatabase.FindByMessageID(MessageID);

  try
    if not Assigned(Note) then
    begin
      SendJson(
        AResponseInfo,
        '{"found":false}'
      );

      Exit;
    end;

    SendJson(
      AResponseInfo,
      '{' +
      '"found":true,' +
      '"content":"' +
        JsonEscape(Note.Content) +
      '",' +
      '"links":"' +
        JsonEscape(Note.Links) +
      '",' +
      '"createdAt":"' +
        JsonEscape(Note.CreatedAt) +
      '",' +
      '"modifiedAt":"' +
        JsonEscape(Note.ModifiedAt) +
      '"' +
      '}'
    );

  finally
    Note.Free;
  end;
end;

procedure THttpServer.HandleSave(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  MessageID: string;
  ConversationID: string;
  ItemID: string;
  Subject: string;
  SenderName: string;
  MailDate: string;
  Content: string;
  Links: string;
  Note: TNote;
begin
  MessageID      := ARequestInfo.Params.Values['messageId'     ];
  ConversationID := ARequestInfo.Params.Values['conversationId'];
  ItemID         := ARequestInfo.Params.Values['itemId'        ];
  Subject        := ARequestInfo.Params.Values['subject'       ];
  SenderName     := ARequestInfo.Params.Values['senderName'    ];
  MailDate       := ARequestInfo.Params.Values['mailDate'      ];
  Content        := ARequestInfo.Params.Values['content'       ];
  Links          := ARequestInfo.Params.Values['links'         ];

  if MessageID = '' then
  begin
    SendJson(
      AResponseInfo,
      '{"error":"missing_messageId"}',
      400
    );

    Exit;
  end;

  Note := FDatabase.FindByMessageID(MessageID);

  if not Assigned(Note) then
    Note := TNote.Create(MessageID);

  try
    Note.ConversationID := ConversationID;
    Note.ItemID         := ItemID;
    Note.Subject        := Subject;
    Note.SenderName     := SenderName;
    Note.MailDate       := MailDate;
    Note.Content        := Content;
    Note.Links          := Links;

    FDatabase.Save(Note);

    SendJson(
      AResponseInfo,
      '{"saved":true,"id":' +
      Note.ID.ToString +
      '}'
    );

  finally
    Note.Free;
  end;
end;

procedure THttpServer.HandleResolve(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Link: string;
  MessageID: string;
  Note: TNote;
begin
  Link := ARequestInfo.Params.Values['link'];

  if Link = '' then
  begin
    SendJson(
      AResponseInfo,
      '{"error":"missing_link"}',
      400
    );

    Exit;
  end;

  if not Link.StartsWith('mailnotes:', True) then
  begin
    SendJson(
      AResponseInfo,
      '{"found":false,"type":"unknown"}'
    );

    Exit;
  end;

  MessageID := Copy(
    Link,
    Length('mailnotes:') + 1,
    MaxInt
  );

  try
    MessageID := TNetEncoding.URL.Decode(MessageID);
  except
    { Bereits dekodiert oder ungültige Kodierung. }
  end;

  Note := FDatabase.FindByMessageID(MessageID);

  try
    if not Assigned(Note) then
    begin
      SendJson(
        AResponseInfo,
        '{"found":false,"type":"mail"}'
      );

      Exit;
    end;

SendJson(
  AResponseInfo,
  '{' +
  '"found":true,' +
  '"type":"mail",' +
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
    SendJson(
      AResponseInfo,
      '{"error":"missing_messageId"}',
      400
    );

    Exit;
  end;

  Backlinks := FDatabase.GetBacklinks(MessageID);
  Json := TStringBuilder.Create;

  try
    Json.Append('{');
    Json.Append('"found":');
    Json.Append(
      LowerCase(
        BoolToStr(
          Backlinks.Count > 0,
          True
        )
      )
    );
    Json.Append(',');
    Json.Append('"items":[');

    IsFirst := True;

    for Note in Backlinks do
    begin
      if not IsFirst then
        Json.Append(',');

      IsFirst := False;

      Json.Append('{');

      Json.Append('"messageId":"');
      Json.Append(JsonEscape(Note.MessageID));
      Json.Append('",');

      Json.Append('"itemId":"');
      Json.Append(JsonEscape(Note.ItemID));
      Json.Append('",');

      Json.Append('"subject":"');
      Json.Append(JsonEscape(Note.Subject));
      Json.Append('",');

      Json.Append('"senderName":"');
      Json.Append(JsonEscape(Note.SenderName));
      Json.Append('",');

      Json.Append('"mailDate":"');
      Json.Append(JsonEscape(Note.MailDate));
      Json.Append('"');

      Json.Append('}');
    end;

    Json.Append(']');
    Json.Append('}');

    SendJson(
      AResponseInfo,
      Json.ToString
    );

  finally
    Json.Free;
    Backlinks.Free;
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
