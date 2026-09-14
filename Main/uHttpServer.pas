unit uHttpServer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.NetEncoding,
  System.Generics.Collections,

  IdHTTPServer,
  IdContext,
  IdCustomHTTPServer,
{$IF Defined(MACOS)}
  IdGlobal,
{$ENDIF}
{$IF Defined(MSWINDOWS) or Defined(MACOS)}
  IdSecOpenSSL,
  IdSecOpenSSLOptions,
{$ENDIF}
{$IF Defined(MACOS)}
  OpenSSLAPI,
{$ENDIF}

  uDatabase,
  uNote,
  uLinkBuffer,
  uRepairQueue,
  uAppPaths,
  uAppInfo,
  uRuntimeConfig;

type
  THttpServer = class
  private
    FServer: TIdHTTPServer;
{$IF Defined(MSWINDOWS) or Defined(MACOS)}
    FSSLIOHandler: TIdSecServerIOHandlerSSLOpenSSL;
{$ENDIF}
    FDatabase: TDatabase;
    FDatabaseLock: TObject;
    FLogLock: TObject;

    procedure HandleCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
{$IF Defined(MSWINDOWS) or Defined(MACOS)}
    procedure HandleQuerySSLPort(APort: Word; var VUseSSL: Boolean);
{$ENDIF}
    procedure RouteRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    function TryServeAddinFile(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;
    function ContentTypeForFile(const AFileName: string): string;

    procedure HandlePing(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleVersion(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleStats(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleDatabasePathGet(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleDatabasePath(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleDatabaseBackup(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNotFound(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNote(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNoteDelete(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleSave(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLog(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleMailRefresh(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleResolve(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleBacklinks(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleBacklinkDelete(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleSearch(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleFavorites(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleTags(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNoteTags(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandlePersons(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleNotePersons(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleFavoriteSet(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferSet(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferGet(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleLinkBufferClear(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueAdd(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueCount(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueList(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleRepairQueueStatus(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);

    procedure ApplyCors(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure SendJson(AResponseInfo: TIdHTTPResponseInfo; const AJson: string; AStatusCode: Integer = 200);
    function JsonEscape(const S: string): string;
    procedure LogToFile(const ASource, AEvent, AData: string);

  public
    constructor Create(ADatabase: TDatabase);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    function ChangeDatabasePath(const APath: string; out AMode: string): string;
    function CreateDatabaseBackup(const ADestinationDirectory: string; const ARetentionCount: Integer = 0): string;
  end;

implementation


constructor THttpServer.Create(ADatabase: TDatabase);
begin
  inherited Create;
  FDatabase := ADatabase;
  FDatabaseLock := TObject.Create;
  FLogLock := TObject.Create;
  FServer := TIdHTTPServer.Create(nil);
  FServer.OnCommandGet := HandleCommandGet;
  FServer.OnCommandOther := HandleCommandGet;
{$IF Defined(MSWINDOWS) or Defined(MACOS)}
  FSSLIOHandler := nil;
  if TRuntimeConfig.UseHttps then
  begin
{$IF Defined(MACOS)}
    // OpenSSL wird zusammen mit MailNotesAgent.app ausgeliefert.
    // IndySecOpenSSL soll deshalb zuerst direkt neben dem Executable suchen:
    //   MailNotesAgent.app/Contents/MacOS/libssl.3.dylib
    //   MailNotesAgent.app/Contents/MacOS/libcrypto.3.dylib
    GetIOpenSSLDDL.SetOpenSSLPath(ExtractFilePath(ParamStr(0)));
{$ENDIF}
    FSSLIOHandler := TIdSecServerIOHandlerSSLOpenSSL.Create(nil);
    FServer.IOHandler := FSSLIOHandler;
    FServer.OnQuerySSLPort := HandleQuerySSLPort;
  end;
{$ENDIF}
end;

destructor THttpServer.Destroy;
begin
  try
    Stop;
  finally
    FServer.Free;
{$IF Defined(MSWINDOWS) or Defined(MACOS)}
    FSSLIOHandler.Free;
{$ENDIF}
    FLogLock.Free;
    FDatabaseLock.Free;
  end;
  inherited;
end;

procedure THttpServer.Start;
begin
  if FServer.Active then
    Exit;

{$IF Defined(MSWINDOWS) or Defined(MACOS)}
  if TRuntimeConfig.UseHttps then
  begin
    if not TFile.Exists(TAppPaths.TlsCertificateFile) then
      raise Exception.CreateFmt(
        'TLS-Zertifikat nicht gefunden: %s',
        [TAppPaths.TlsCertificateFile]
      );

    if not TFile.Exists(TAppPaths.TlsPrivateKeyFile) then
      raise Exception.CreateFmt(
        'TLS-Schlüssel nicht gefunden: %s',
        [TAppPaths.TlsPrivateKeyFile]
      );

    FSSLIOHandler.SSLOptions.CertFile := TAppPaths.TlsCertificateFile;
    FSSLIOHandler.SSLOptions.KeyFile := TAppPaths.TlsPrivateKeyFile;
    // IndySecOpenSSL verwendet mit OpenSSL 3 standardmäßig TLS 1.2/1.3.
    // Wir setzen dies explizit, damit ältere Protokolle nie angeboten werden.
    FSSLIOHandler.SSLOptions.SSLVersions := [sslvTLSv1_2, sslvTLSv1_3];
  end;
{$ENDIF}

  FServer.Bindings.Clear;
  with FServer.Bindings.Add do
  begin
    IP := TRuntimeConfig.HttpBindAddress;
    Port := TRuntimeConfig.HttpPort;
  end;
{$IF Defined(MACOS) and not Defined(DEBUG)}
  // Outlook/macOS kann "localhost" bevorzugt als ::1 auflösen.
  // Deshalb im Produktionsbetrieb zusätzlich explizit auf IPv6-Loopback lauschen.
  with FServer.Bindings.Add do
  begin
    IPVersion := Id_IPv6;
    IP := '::1';
    Port := TRuntimeConfig.HttpPort;
  end;
{$ENDIF}
  FServer.DefaultPort := TRuntimeConfig.HttpPort;
  FServer.Active := True;
end;

procedure THttpServer.Stop;
begin
  if FServer.Active then
    FServer.Active := False;
end;

function THttpServer.ChangeDatabasePath(
  const APath: string;
  out AMode: string
): string;
begin
  TMonitor.Enter(FDatabaseLock);
  try
    Result := FDatabase.ChangeDatabasePath(APath, AMode);
  finally
    TMonitor.Exit(FDatabaseLock);
  end;
end;

function THttpServer.CreateDatabaseBackup(
  const ADestinationDirectory: string;
  const ARetentionCount: Integer
): string;
var
  RetentionCount: Integer;
begin
  RetentionCount := ARetentionCount;
  if RetentionCount <= 0 then
    RetentionCount := TAppPaths.BackupRetentionCount;

  TMonitor.Enter(FDatabaseLock);
  try
    Result := FDatabase.CreateBackup(ADestinationDirectory, RetentionCount);
    TAppPaths.SetLastSuccessfulBackup(Result);
  finally
    TMonitor.Exit(FDatabaseLock);
  end;
end;

{$IF Defined(MSWINDOWS) or Defined(MACOS)}
procedure THttpServer.HandleQuerySSLPort(APort: Word; var VUseSSL: Boolean);
begin
  VUseSSL := TRuntimeConfig.UseHttps and (APort = TRuntimeConfig.HttpPort);
end;
{$ENDIF}

procedure THttpServer.HandleCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  ApplyCors(ARequestInfo, AResponseInfo);

  if SameText(ARequestInfo.Command, 'OPTIONS') then
  begin
    AResponseInfo.ResponseNo := 204;
    AResponseInfo.ContentText := '';
    Exit;
  end;

  if SameText(ARequestInfo.Command, 'GET') and
     TRuntimeConfig.ServeAddinFiles and
     TryServeAddinFile(ARequestInfo, AResponseInfo) then
    Exit;

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
      else if SameText(ARequestInfo.Document, '/favorite') then
        HandleFavoriteSet(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/linkbuffer') then
        HandleLinkBufferSet(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/repairqueue') then
        HandleRepairQueueAdd(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/repairqueue/status') then
        HandleRepairQueueStatus(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/database/path') then
        HandleDatabasePath(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/database/backup') then
        HandleDatabaseBackup(ARequestInfo, AResponseInfo)
      else
        HandleNotFound(AResponseInfo);
      Exit;
    end;

    if SameText(ARequestInfo.Command, 'DELETE') then
    begin
      if SameText(ARequestInfo.Document, '/note') then
        HandleNoteDelete(ARequestInfo, AResponseInfo)
      else if SameText(ARequestInfo.Document, '/linkbuffer') then
        HandleLinkBufferClear(AResponseInfo)
      else if SameText(ARequestInfo.Document, '/backlinks') then
        HandleBacklinkDelete(ARequestInfo, AResponseInfo)
      else
        HandleNotFound(AResponseInfo);
      Exit;
    end;

    RouteRequest(ARequestInfo, AResponseInfo);
  finally
    TMonitor.Exit(FDatabaseLock);
  end;
end;

function THttpServer.ContentTypeForFile(const AFileName: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(TPath.GetExtension(AFileName));

  if Ext = '.html' then
    Exit('text/html; charset=utf-8');
  if Ext = '.js' then
    Exit('application/javascript; charset=utf-8');
  if Ext = '.css' then
    Exit('text/css; charset=utf-8');
  if Ext = '.png' then
    Exit('image/png');
  if Ext = '.ico' then
    Exit('image/x-icon');
  if Ext = '.xml' then
    Exit('application/xml; charset=utf-8');

  Result := 'application/octet-stream';
end;

function THttpServer.TryServeAddinFile(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
): Boolean;
var
  RequestPath: string;
  RelativePath: string;
  BaseDirectory: string;
  FullName: string;
  Allowed: Boolean;
begin
  Result := False;
  RequestPath := ARequestInfo.Document;

  if RequestPath = '/' then
    RequestPath := '/taskpane.html';

  while RequestPath.StartsWith('/') do
    Delete(RequestPath, 1, 1);

  RelativePath := RequestPath.Replace('/', PathDelim);

  Allowed :=
    SameText(RelativePath, 'taskpane.html') or
    SameText(RelativePath, 'taskpane.js') or
    SameText(RelativePath, 'commands.html') or
    SameText(RelativePath, 'commands.js') or
    SameText(RelativePath, 'polyfill.js') or
    SameText(RelativePath, 'manifest.xml') or
    SameText(TPath.GetExtension(RelativePath), '.css') or
    RelativePath.StartsWith('assets' + PathDelim, True);

  if not Allowed then
    Exit(False);

  BaseDirectory := IncludeTrailingPathDelimiter(
    TPath.GetFullPath(TAppPaths.AddinDirectory)
  );
  FullName := TPath.GetFullPath(TPath.Combine(BaseDirectory, RelativePath));

  // Kein Directory Traversal außerhalb des Add-in-Verzeichnisses.
  if not FullName.StartsWith(BaseDirectory, True) then
    Exit(False);

  if not TFile.Exists(FullName) then
    Exit(False);

  AResponseInfo.ResponseNo := 200;
  AResponseInfo.ContentType := ContentTypeForFile(FullName);
  AResponseInfo.CacheControl := 'no-cache';
  AResponseInfo.ContentStream := TFileStream.Create(
    FullName,
    fmOpenRead or fmShareDenyNone
  );
  AResponseInfo.FreeContentStream := True;
  Result := True;
end;

procedure THttpServer.RouteRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  if SameText(ARequestInfo.Document, '/ping') then
    HandlePing(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/version') then
    HandleVersion(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/stats') then
    HandleStats(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/database/path') then
    HandleDatabasePathGet(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/note') then
    HandleNote(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/resolve') then
    HandleResolve(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/backlinks') then
    HandleBacklinks(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/search') then
    HandleSearch(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/favorites') then
    HandleFavorites(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/tags') then
    HandleTags(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/note/tags') then
    HandleNoteTags(ARequestInfo, AResponseInfo)
  else if SameText(ARequestInfo.Document, '/persons') then
    HandlePersons(AResponseInfo)
  else if SameText(ARequestInfo.Document, '/note/persons') then
    HandleNotePersons(ARequestInfo, AResponseInfo)
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
    '"schema":5,' +
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
    '"port":' + TRuntimeConfig.HttpPort.ToString + ',' +
    '"agentPath":"' + JsonEscape(TAppPaths.AgentFile) + '",' +
    '"addinPath":"' + JsonEscape(TAppPaths.AddinDirectory) + '",' +
    '"databasePath":"' + JsonEscape(TAppPaths.DatabaseFile) + '"' +
    '}'
  );
end;


procedure THttpServer.HandleDatabasePathGet(AResponseInfo: TIdHTTPResponseInfo);
begin
  SendJson(
    AResponseInfo,
    '{"databasePath":"' + JsonEscape(TAppPaths.DatabaseFile) + '"}'
  );
end;


procedure THttpServer.HandleDatabasePath(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  RequestedPath: string;
  NewPath: string;
  Mode: string;
begin
  RequestedPath := Trim(ARequestInfo.Params.Values['path']);
  if RequestedPath = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_path"}', 400);
    Exit;
  end;

  try
    NewPath := FDatabase.ChangeDatabasePath(RequestedPath, Mode);
    SendJson(
      AResponseInfo,
      '{' +
      '"ok":true,' +
      '"mode":"' + JsonEscape(Mode) + '",' +
      '"databasePath":"' + JsonEscape(NewPath) + '"' +
      '}'
    );
  except
    on E: Exception do
      SendJson(
        AResponseInfo,
        '{"error":"database_path_change_failed","message":"' +
        JsonEscape(E.Message) + '"}',
        400
      );
  end;
end;

procedure THttpServer.HandleStats(AResponseInfo: TIdHTTPResponseInfo);
var
  NoteCount: Integer;
  MailLinkCount: Integer;
  FavoriteCount: Integer;
  TagCount: Integer;
  PersonCount: Integer;
begin
  FDatabase.GetStatistics(NoteCount, MailLinkCount, FavoriteCount, TagCount, PersonCount);

  SendJson(
    AResponseInfo,
    '{' +
    '"notes":' + NoteCount.ToString + ',' +
    '"mailLinks":' + MailLinkCount.ToString + ',' +
    '"favorites":' + FavoriteCount.ToString + ',' +
    '"tags":' + TagCount.ToString + ',' +
    '"persons":' + PersonCount.ToString + ',' +
    '"version":"' + JsonEscape(TAppInfo.Version) + '"' +
    '}'
  );
end;

procedure THttpServer.HandleDatabaseBackup(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  DestinationDirectory: string;
  BackupFile: string;
begin
  DestinationDirectory := Trim(ARequestInfo.Params.Values['path']);

  if DestinationDirectory = '' then
  begin
    SendJson(
      AResponseInfo,
      '{"ok":false,"message":"Backup-Zielordner fehlt."}',
      400
    );
    Exit;
  end;

  try
    BackupFile := CreateDatabaseBackup(DestinationDirectory);
    SendJson(
      AResponseInfo,
      '{"ok":true,"backupPath":"' + JsonEscape(BackupFile) + '"}'
    );
  except
    on E: Exception do
      SendJson(
        AResponseInfo,
        '{"ok":false,"message":"' + JsonEscape(E.Message) + '"}',
        500
      );
  end;
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
      '"modifiedAt":"' + JsonEscape(Note.ModifiedAt) + '",' +
      '"isFavorite":' + LowerCase(BoolToStr(Note.IsFavorite, True)) +
      '}'
    );
  finally
    Note.Free;
  end;
end;

procedure THttpServer.HandleNoteDelete(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  MailNotesID: string;
  MessageID: string;
  Deleted: Boolean;
begin
  MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
  MessageID := ARequestInfo.Params.Values['messageId'];

  if (MailNotesID = '') and (MessageID = '') then
  begin
    SendJson(AResponseInfo, '{"error":"missing_mail_identity"}', 400);
    Exit;
  end;

  Deleted := FDatabase.DeleteNote(MailNotesID, MessageID);
  if not Deleted then
  begin
    SendJson(AResponseInfo, '{"error":"note_not_found"}', 404);
    Exit;
  end;

  SendJson(AResponseInfo, '{"deleted":true}');
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
  if not TRuntimeConfig.EnableLogging then
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
  RepairCompleted: Boolean;
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
    RepairCompleted := FDatabase.CompleteRepairQueueByIdentity(
      Note.MailNotesID,
      Note.MessageID
    );

    if WasUpdated or RepairCompleted then
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
      '"repairCompleted":' + LowerCase(BoolToStr(RepairCompleted, True)) + ',' +
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
      Json.Append('"mailDate":"' + JsonEscape(Note.MailDate) + '",');
      Json.Append('"sourceLink":"' + JsonEscape(Note.BacklinkLink) + '"');
      Json.Append('}');
    end;

    Json.Append(']}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Backlinks.Free;
  end;
end;

procedure THttpServer.HandleBacklinkDelete(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  SourceMailNotesID: string;
  TargetToken: string;
  SourceLink: string;
  Deleted: Boolean;
begin
  SourceMailNotesID := Trim(
    ARequestInfo.Params.Values['sourceMailNotesId']
  );
  TargetToken := Trim(
    ARequestInfo.Params.Values['targetMailIdentity']
  );
  SourceLink := Trim(
    ARequestInfo.Params.Values['sourceLink']
  );

  if SourceMailNotesID = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_source_mailnotes_id"}', 400);
    Exit;
  end;

  if TargetToken = '' then
  begin
    SendJson(AResponseInfo, '{"error":"missing_target_mail_identity"}', 400);
    Exit;
  end;

  Deleted := FDatabase.DeleteBacklink(
    SourceMailNotesID,
    TargetToken,
    SourceLink
  );
  if Deleted then
    SendJson(AResponseInfo, '{"ok":true}')
  else
    SendJson(
      AResponseInfo,
      '{"ok":false,"error":"backlink_not_found"}',
      404
    );
end;


procedure THttpServer.HandleSearch(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  SearchText: string;
  MaxResults: Integer;
  FavoriteOnly: Boolean;
  TagNormalizedNames: TArray<string>;
  TagParam: string;
  PersonNormalizedNames: TArray<string>;
  PersonParam: string;
  Items: TObjectList<TNote>;
  Note: TNote;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  SearchText := Trim(ARequestInfo.Params.Values['q']);
  TagParam := Trim(ARequestInfo.Params.Values['tags']);
  if TagParam = '' then
    TagParam := Trim(ARequestInfo.Params.Values['tag']);
  if TagParam = '' then
    SetLength(TagNormalizedNames, 0)
  else
    TagNormalizedNames := TagParam.Split(['|']);
  PersonParam := Trim(ARequestInfo.Params.Values['persons']);
  if PersonParam = '' then
    PersonParam := Trim(ARequestInfo.Params.Values['person']);
  if PersonParam = '' then
    SetLength(PersonNormalizedNames, 0)
  else
    PersonNormalizedNames := PersonParam.Split(['|']);
  if (SearchText = '') and (Length(TagNormalizedNames) = 0) and
     (Length(PersonNormalizedNames) = 0) and
     not (SameText(ARequestInfo.Params.Values['favorite'], 'true') or
          (ARequestInfo.Params.Values['favorite'] = '1')) then
  begin
    SendJson(AResponseInfo, '{"items":[],"count":0}');
    Exit;
  end;

  MaxResults := StrToIntDef(ARequestInfo.Params.Values['limit'], 50);
  FavoriteOnly := SameText(ARequestInfo.Params.Values['favorite'], 'true') or
                  (ARequestInfo.Params.Values['favorite'] = '1');
  Items := FDatabase.SearchNotes(
    SearchText, MaxResults, FavoriteOnly, TagNormalizedNames, PersonNormalizedNames
  );
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


procedure THttpServer.HandleFavorites(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  MaxResults: Integer;
  Items: TObjectList<TNote>;
  Note: TNote;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  MaxResults := StrToIntDef(ARequestInfo.Params.Values['limit'], 100);
  Items := FDatabase.GetFavorites(MaxResults);
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

procedure THttpServer.HandleTags(AResponseInfo: TIdHTTPResponseInfo);
var
  Tags: TObjectList<TTagInfo>;
  Tag: TTagInfo;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  Tags := FDatabase.GetTags;
  Json := TStringBuilder.Create;
  try
    Json.Append('{"items":[');
    IsFirst := True;
    for Tag in Tags do
    begin
      if not IsFirst then
        Json.Append(',');
      IsFirst := False;
      Json.Append('{');
      Json.Append('"name":"' + JsonEscape(Tag.Name) + '",');
      Json.Append('"normalizedName":"' + JsonEscape(Tag.NormalizedName) + '",');
      Json.Append('"count":' + Tag.UsageCount.ToString);
      Json.Append('}');
    end;
    Json.Append('],"count":' + Tags.Count.ToString + '}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Tags.Free;
  end;
end;

procedure THttpServer.HandleNoteTags(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  MailNotesID: string;
  Tags: TObjectList<TTagInfo>;
  Tag: TTagInfo;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  MailNotesID := Trim(ARequestInfo.Params.Values['mailNotesId']);
  if MailNotesID = '' then
  begin
    SendJson(AResponseInfo, '{"items":[],"count":0}');
    Exit;
  end;

  Tags := FDatabase.GetNoteTags(MailNotesID);
  Json := TStringBuilder.Create;
  try
    Json.Append('{"items":[');
    IsFirst := True;
    for Tag in Tags do
    begin
      if not IsFirst then
        Json.Append(',');
      IsFirst := False;
      Json.Append('{');
      Json.Append('"name":"' + JsonEscape(Tag.Name) + '",');
      Json.Append('"normalizedName":"' + JsonEscape(Tag.NormalizedName) + '"');
      Json.Append('}');
    end;
    Json.Append('],"count":' + Tags.Count.ToString + '}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Tags.Free;
  end;
end;

procedure THttpServer.HandlePersons(AResponseInfo: TIdHTTPResponseInfo);
var
  Persons: TObjectList<TPersonInfo>;
  Person: TPersonInfo;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  Persons := FDatabase.GetPersons;
  Json := TStringBuilder.Create;
  try
    Json.Append('{"items":[');
    IsFirst := True;
    for Person in Persons do
    begin
      if not IsFirst then
        Json.Append(',');
      IsFirst := False;
      Json.Append('{');
      Json.Append('"name":"' + JsonEscape(Person.Name) + '",');
      Json.Append('"normalizedName":"' + JsonEscape(Person.NormalizedName) + '",');
      Json.Append('"count":' + Person.UsageCount.ToString);
      Json.Append('}');
    end;
    Json.Append('],"count":' + Persons.Count.ToString + '}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Persons.Free;
  end;
end;

procedure THttpServer.HandleNotePersons(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  MailNotesID: string;
  Persons: TObjectList<TPersonInfo>;
  Person: TPersonInfo;
  Json: TStringBuilder;
  IsFirst: Boolean;
begin
  MailNotesID := Trim(ARequestInfo.Params.Values['mailNotesId']);
  if MailNotesID = '' then
  begin
    SendJson(AResponseInfo, '{"items":[],"count":0}');
    Exit;
  end;

  Persons := FDatabase.GetNotePersons(MailNotesID);
  Json := TStringBuilder.Create;
  try
    Json.Append('{"items":[');
    IsFirst := True;
    for Person in Persons do
    begin
      if not IsFirst then
        Json.Append(',');
      IsFirst := False;
      Json.Append('{');
      Json.Append('"name":"' + JsonEscape(Person.Name) + '",');
      Json.Append('"normalizedName":"' + JsonEscape(Person.NormalizedName) + '"');
      Json.Append('}');
    end;
    Json.Append('],"count":' + Persons.Count.ToString + '}');
    SendJson(AResponseInfo, Json.ToString);
  finally
    Json.Free;
    Persons.Free;
  end;
end;

procedure THttpServer.HandleFavoriteSet(
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  MailNotesID: string;
  MessageID: string;
  IsFavorite: Boolean;
begin
  MailNotesID := ARequestInfo.Params.Values['mailNotesId'];
  MessageID := ARequestInfo.Params.Values['messageId'];

  if (MailNotesID = '') and (MessageID = '') then
  begin
    SendJson(AResponseInfo, '{"error":"missing_mail_identity"}', 400);
    Exit;
  end;

  IsFavorite := SameText(ARequestInfo.Params.Values['favorite'], 'true') or
                (ARequestInfo.Params.Values['favorite'] = '1');

  if not FDatabase.SetFavorite(MailNotesID, MessageID, IsFavorite) then
  begin
    SendJson(AResponseInfo, '{"error":"note_not_found"}', 404);
    Exit;
  end;

  SendJson(
    AResponseInfo,
    '{"saved":true,"isFavorite":' +
    LowerCase(BoolToStr(IsFavorite, True)) + '}'
  );
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


procedure THttpServer.ApplyCors(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Origin: string;
begin
  Origin := ARequestInfo.RawHeaders.Values['Origin'];
  if not TRuntimeConfig.IsAllowedCorsOrigin(Origin) then
    Exit;

  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Origin'] := Origin;
  AResponseInfo.CustomHeaders.Values['Vary'] := 'Origin';
  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Methods'] := 'GET, POST, DELETE, OPTIONS';
  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Headers'] := 'Content-Type';
  AResponseInfo.CustomHeaders.Values['Access-Control-Max-Age'] := '600';
end;

procedure THttpServer.SendJson(AResponseInfo: TIdHTTPResponseInfo; const AJson: string; AStatusCode: Integer);
begin
  AResponseInfo.ResponseNo := AStatusCode;
  AResponseInfo.ContentType := 'application/json; charset=utf-8';
  AResponseInfo.CacheControl := 'no-store';
  AResponseInfo.ContentText := AJson;
end;

function THttpServer.JsonEscape(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

end.
