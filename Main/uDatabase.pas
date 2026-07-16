unit uDatabase;

interface

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  System.NetEncoding,
  System.Generics.Collections,

  FireDAC.DApt,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Comp.Client,

  uNote,
  uLinkBuffer,
  uRepairQueue;

type
  TDatabase = class
  public
    constructor Create;
    destructor Destroy; override;

    procedure Open;
    procedure Close;

    procedure Save(Note: TNote);
    procedure RefreshMailIdentity(Note: TNote);

    function FindByMessageID(const MessageID: string): TNote;
    function FindByMailNotesID(const MailNotesID: string): TNote;
    function FindMailByLinkToken(const LinkToken: string): TNote;

    function GetBacklinks(
      const TargetToken: string
    ): TObjectList<TNote>;

    procedure SaveLinkBuffer(LinkBuffer: TLinkBuffer);
    function LoadLinkBuffer: TLinkBuffer;
    procedure ClearLinkBuffer;

    procedure AddRepairQueueItem(Item: TRepairQueueItem);
    function GetRepairQueueCount: Integer;
    function GetRepairQueue: TObjectList<TRepairQueueItem>;
    procedure SetRepairQueueStatus(const ID, Status: Integer);
    procedure CompleteRepairQueueByIdentity(const MailNotesID, MessageID: string);

  private
    FConnection: TFDConnection;

    function FindDatabasePath: string;
    function GetCurrentUTC: string;
    function CreateMailNotesID: string;

    procedure EnsureSchema;

    procedure EnsureMailForNote(Note: TNote);
    procedure EnsureMailForBuffer(LinkBuffer: TLinkBuffer);

    function FindMailNotesIDByMessageID(
      const MessageID: string
    ): string;

    function FindMailNotesIDByToken(
      const Token: string
    ): string;

    procedure UpdateMailLinks(
      const SourceMailNotesID: string;
      const Links: string
    );

    function ExtractMailNotesToken(
      const Link: string
    ): string;

    function LoadNoteByWhere(
      const WhereClause: string;
      const ParamName: string;
      const ParamValue: string
    ): TNote;
  end;

implementation

constructor TDatabase.Create;
begin
  inherited Create;
  FConnection := TFDConnection.Create(nil);
end;

destructor TDatabase.Destroy;
begin
  Close;
  FConnection.Free;
  inherited;
end;

procedure TDatabase.Open;
var
  DatabaseFile: string;
begin
  DatabaseFile := FindDatabasePath;

  if DatabaseFile = '' then
    raise Exception.Create('MailNotes.sqlite not found.');

  FConnection.DriverName := 'SQLite';
  FConnection.Params.Database := DatabaseFile;

  if not FConnection.Connected then
    FConnection.Connected := True;

  FConnection.ExecSQL('PRAGMA foreign_keys = ON');
  EnsureSchema;
end;


procedure TDatabase.EnsureSchema;
begin
  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS SHLRepairQueue (' +
    ' ID INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,' +
    ' MailNotesID TEXT NOT NULL,' +
    ' OldItemID TEXT,' +
    ' InternetMessageID TEXT,' +
    ' Subject TEXT,' +
    ' SenderName TEXT,' +
    ' SenderAddress TEXT,' +
    ' ReceivedUTC TEXT,' +
    ' Reason TEXT NOT NULL,' +
    ' CreatedUTC TEXT NOT NULL,' +
    ' ModifiedUTC TEXT NOT NULL,' +
    ' RetryCount INTEGER NOT NULL DEFAULT 0,' +
    ' Status INTEGER NOT NULL DEFAULT 0,' +
    ' FOREIGN KEY (MailNotesID) REFERENCES Mail(MailNotesID)' +
    '   ON UPDATE CASCADE ON DELETE CASCADE,' +
    ' UNIQUE (MailNotesID),' +
    ' CHECK (Status IN (0, 1, 2, 3))' +
    ')'
  );

  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS IX_SHLRepairQueue_Status ' +
    'ON SHLRepairQueue(Status, CreatedUTC)'
  );

  FConnection.ExecSQL(
    'UPDATE SchemaInfo SET SchemaVersion = 2 ' +
    'WHERE SchemaVersion < 2'
  );
end;

procedure TDatabase.Close;
begin
  if FConnection.Connected then
    FConnection.Close;
end;

function TDatabase.FindDatabasePath: string;
var
  BaseDir: string;
  Candidate: string;
  I: Integer;
begin
  BaseDir := TPath.GetFullPath(ExtractFilePath(ParamStr(0)));

  for I := 0 to 6 do
  begin
    Candidate := TPath.Combine(
      TPath.Combine(BaseDir, 'Data'),
      'MailNotes.sqlite'
    );

    if TFile.Exists(Candidate) then
      Exit(Candidate);

    BaseDir := TPath.GetFullPath(TPath.Combine(BaseDir, '..'));
  end;

  Result := '';
end;

function TDatabase.GetCurrentUTC: string;
begin
  Result := FormatDateTime(
    'yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"',
    TTimeZone.Local.ToUniversalTime(Now)
  );
end;

function TDatabase.CreateMailNotesID: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := GUIDToString(G);
  Result := Copy(Result, 2, Length(Result) - 2).ToLower;
end;

function TDatabase.LoadNoteByWhere(
  const WhereClause: string;
  const ParamName: string;
  const ParamValue: string
): TNote;
var
  Query: TFDQuery;
begin
  Result := nil;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT ' +
      '  N.ID, M.MailNotesID, N.Content, N.Links, ' +
      '  N.CreatedUTC, N.ModifiedUTC, N.IsFavorite, ' +
      '  N.IsDeleted, N.DeletedUTC, ' +
      '  M.ItemID, M.ImmutableID, M.InternetMessageID, ' +
      '  M.ConversationID, M.MailboxAddress, M.Subject, ' +
      '  M.SenderName, M.SenderAddress, M.ReceivedUTC ' +
      'FROM Mail M ' +
      'LEFT JOIN Note N ON N.MailNotesID = M.MailNotesID ' +
      'WHERE ' + WhereClause + ' ' +
      'LIMIT 1';

    Query.ParamByName(ParamName).AsString := ParamValue;
    Query.Open;

    if Query.Eof then
      Exit;

    Result := TNote.Create;

    Result.MailNotesID := Query.FieldByName('MailNotesID').AsString;
    Result.ItemID := Query.FieldByName('ItemID').AsString;
    Result.ImmutableID := Query.FieldByName('ImmutableID').AsString;
    Result.MessageID := Query.FieldByName('InternetMessageID').AsString;
    Result.ConversationID := Query.FieldByName('ConversationID').AsString;
    Result.MailboxAddress := Query.FieldByName('MailboxAddress').AsString;
    Result.Subject := Query.FieldByName('Subject').AsString;
    Result.SenderName := Query.FieldByName('SenderName').AsString;
    Result.SenderAddress := Query.FieldByName('SenderAddress').AsString;
    Result.MailDate := Query.FieldByName('ReceivedUTC').AsString;

    if not Query.FieldByName('ID').IsNull then
    begin
      Result.ID := Query.FieldByName('ID').AsInteger;
      Result.Content := Query.FieldByName('Content').AsString;
      Result.Links := Query.FieldByName('Links').AsString;
      Result.CreatedAt := Query.FieldByName('CreatedUTC').AsString;
      Result.ModifiedAt := Query.FieldByName('ModifiedUTC').AsString;
      Result.IsFavorite := Query.FieldByName('IsFavorite').AsInteger <> 0;
      Result.IsDeleted := Query.FieldByName('IsDeleted').AsInteger <> 0;
      Result.DeletedAt := Query.FieldByName('DeletedUTC').AsString;
    end;
  finally
    Query.Free;
  end;
end;

function TDatabase.FindByMessageID(const MessageID: string): TNote;
begin
  Result := LoadNoteByWhere(
    'M.InternetMessageID = :MessageID',
    'MessageID',
    MessageID
  );

  if Assigned(Result) and Result.IsDeleted then
    FreeAndNil(Result);
end;

function TDatabase.FindByMailNotesID(const MailNotesID: string): TNote;
begin
  Result := LoadNoteByWhere(
    'M.MailNotesID = :MailNotesID',
    'MailNotesID',
    MailNotesID
  );

  if Assigned(Result) and Result.IsDeleted then
    FreeAndNil(Result);
end;

function TDatabase.FindMailByLinkToken(const LinkToken: string): TNote;
begin
  Result := FindByMailNotesID(LinkToken);

  if not Assigned(Result) then
    Result := FindByMessageID(LinkToken);
end;

function TDatabase.FindMailNotesIDByMessageID(
  const MessageID: string
): string;
var
  Query: TFDQuery;
begin
  Result := '';

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT MailNotesID FROM Mail ' +
      'WHERE InternetMessageID = :MessageID ' +
      'LIMIT 1';
    Query.ParamByName('MessageID').AsString := MessageID;
    Query.Open;

    if not Query.Eof then
      Result := Query.Fields[0].AsString;
  finally
    Query.Free;
  end;
end;

function TDatabase.FindMailNotesIDByToken(
  const Token: string
): string;
var
  Query: TFDQuery;
begin
  Result := '';

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT MailNotesID FROM Mail ' +
      'WHERE MailNotesID = :Token ' +
      '   OR InternetMessageID = :Token ' +
      'LIMIT 1';
    Query.ParamByName('Token').AsString := Token;
    Query.Open;

    if not Query.Eof then
      Result := Query.Fields[0].AsString;
  finally
    Query.Free;
  end;
end;

procedure TDatabase.EnsureMailForNote(Note: TNote);
var
  Query: TFDQuery;
  NowUTC: string;
begin
  if (Note.MailNotesID = '') and (Note.MessageID = '') then
    raise Exception.Create('MailNotesID and MessageID are empty.');

  if (Note.MailNotesID = '') and (Note.MessageID <> '') then
    Note.MailNotesID := FindMailNotesIDByMessageID(Note.MessageID);

  if Note.MailNotesID = '' then
    Note.MailNotesID := CreateMailNotesID;

  NowUTC := GetCurrentUTC;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'INSERT INTO Mail ' +
      '(' +
      ' MailNotesID, ItemID, ImmutableID, InternetMessageID, ' +
      ' ConversationID, MailboxAddress, Subject, SenderName, ' +
      ' SenderAddress, ReceivedUTC, CreatedUTC, ModifiedUTC, ResolveState' +
      ') VALUES (' +
      ' :MailNotesID, :ItemID, :ImmutableID, :MessageID, ' +
      ' :ConversationID, :MailboxAddress, :Subject, :SenderName, ' +
      ' :SenderAddress, :ReceivedUTC, :CreatedUTC, :ModifiedUTC, 0' +
      ') ' +
      'ON CONFLICT(MailNotesID) DO UPDATE SET ' +
      ' ItemID = COALESCE(NULLIF(excluded.ItemID, ''''), Mail.ItemID), ' +
      ' ImmutableID = COALESCE(NULLIF(excluded.ImmutableID, ''''), Mail.ImmutableID), ' +
      ' InternetMessageID = COALESCE(NULLIF(excluded.InternetMessageID, ''''), Mail.InternetMessageID), ' +
      ' ConversationID = COALESCE(NULLIF(excluded.ConversationID, ''''), Mail.ConversationID), ' +
      ' MailboxAddress = COALESCE(NULLIF(excluded.MailboxAddress, ''''), Mail.MailboxAddress), ' +
      ' Subject = COALESCE(NULLIF(excluded.Subject, ''''), Mail.Subject), ' +
      ' SenderName = COALESCE(NULLIF(excluded.SenderName, ''''), Mail.SenderName), ' +
      ' SenderAddress = COALESCE(NULLIF(excluded.SenderAddress, ''''), Mail.SenderAddress), ' +
      ' ReceivedUTC = COALESCE(NULLIF(excluded.ReceivedUTC, ''''), Mail.ReceivedUTC), ' +
      ' ModifiedUTC = excluded.ModifiedUTC';

    Query.ParamByName('MailNotesID').AsString := Note.MailNotesID;
    Query.ParamByName('ItemID').AsString := Note.ItemID;
    Query.ParamByName('ImmutableID').AsString := Note.ImmutableID;
    Query.ParamByName('MessageID').AsString := Note.MessageID;
    Query.ParamByName('ConversationID').AsString := Note.ConversationID;
    Query.ParamByName('MailboxAddress').AsString := Note.MailboxAddress;
    Query.ParamByName('Subject').AsString := Note.Subject;
    Query.ParamByName('SenderName').AsString := Note.SenderName;
    Query.ParamByName('SenderAddress').AsString := Note.SenderAddress;
    Query.ParamByName('ReceivedUTC').AsString := Note.MailDate;
    Query.ParamByName('CreatedUTC').AsString := NowUTC;
    Query.ParamByName('ModifiedUTC').AsString := NowUTC;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

procedure TDatabase.EnsureMailForBuffer(LinkBuffer: TLinkBuffer);
var
  Note: TNote;
begin
  Note := TNote.Create(LinkBuffer.MessageID);
  try
    Note.MailNotesID := LinkBuffer.MailNotesID;
    Note.ItemID := LinkBuffer.ItemID;
    Note.ImmutableID := LinkBuffer.ImmutableID;
    Note.ConversationID := LinkBuffer.ConversationID;
    Note.MailboxAddress := LinkBuffer.MailboxAddress;
    Note.Subject := LinkBuffer.Subject;
    Note.SenderName := LinkBuffer.SenderName;
    Note.SenderAddress := LinkBuffer.SenderAddress;
    Note.MailDate := LinkBuffer.MailDate;

    EnsureMailForNote(Note);
    LinkBuffer.MailNotesID := Note.MailNotesID;
  finally
    Note.Free;
  end;
end;

procedure TDatabase.RefreshMailIdentity(Note: TNote);
begin
  if not Assigned(Note) then
    raise Exception.Create('Note is not assigned.');

  if not FConnection.InTransaction then
    FConnection.StartTransaction;

  try
    EnsureMailForNote(Note);
    FConnection.Commit;
  except
    if FConnection.InTransaction then
      FConnection.Rollback;
    raise;
  end;
end;

procedure TDatabase.Save(Note: TNote);
var
  Query: TFDQuery;
  NowUTC: string;
begin
  if not Assigned(Note) then
    raise Exception.Create('Note is not assigned.');

  if not FConnection.InTransaction then
    FConnection.StartTransaction;

  try
    EnsureMailForNote(Note);
    NowUTC := GetCurrentUTC;

    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'INSERT INTO Note ' +
        '(MailNotesID, Content, Links, CreatedUTC, ModifiedUTC, IsFavorite, IsDeleted) ' +
        'VALUES ' +
        '(:MailNotesID, :Content, :Links, :CreatedUTC, :ModifiedUTC, :IsFavorite, 0) ' +
        'ON CONFLICT(MailNotesID) DO UPDATE SET ' +
        ' Content = excluded.Content, ' +
        ' Links = excluded.Links, ' +
        ' ModifiedUTC = excluded.ModifiedUTC, ' +
        ' IsFavorite = excluded.IsFavorite, ' +
        ' IsDeleted = 0, DeletedUTC = NULL';

      if Note.CreatedAt = '' then
        Note.CreatedAt := NowUTC;
      Note.ModifiedAt := NowUTC;

      Query.ParamByName('MailNotesID').AsString := Note.MailNotesID;
      Query.ParamByName('Content').AsString := Note.Content;
      Query.ParamByName('Links').AsString := Note.Links;
      Query.ParamByName('CreatedUTC').AsString := Note.CreatedAt;
      Query.ParamByName('ModifiedUTC').AsString := Note.ModifiedAt;
      Query.ParamByName('IsFavorite').AsInteger := Ord(Note.IsFavorite);
      Query.ExecSQL;

      if Note.ID = 0 then
      begin
        Query.Close;
        Query.SQL.Text :=
          'SELECT ID, CreatedUTC FROM Note WHERE MailNotesID = :MailNotesID';
        Query.ParamByName('MailNotesID').AsString := Note.MailNotesID;
        Query.Open;
        Note.ID := Query.FieldByName('ID').AsInteger;
        Note.CreatedAt := Query.FieldByName('CreatedUTC').AsString;
      end;
    finally
      Query.Free;
    end;

    UpdateMailLinks(Note.MailNotesID, Note.Links);
    FConnection.Commit;
  except
    if FConnection.InTransaction then
      FConnection.Rollback;
    raise;
  end;
end;

function TDatabase.ExtractMailNotesToken(
  const Link: string
): string;
var
  EncodedToken: string;
begin
  Result := '';

  if not Link.StartsWith('mailnotes:', True) then
    Exit;

  EncodedToken := Copy(Link, Length('mailnotes:') + 1, MaxInt);
  if EncodedToken = '' then
    Exit;

  try
    Result := TNetEncoding.URL.Decode(EncodedToken);
  except
    Result := EncodedToken;
  end;
end;

procedure TDatabase.UpdateMailLinks(
  const SourceMailNotesID: string;
  const Links: string
);
var
  Query: TFDQuery;
  LinkLines: TStringList;
  Line: string;
  Token: string;
  TargetMailNotesID: string;
begin
  Query := TFDQuery.Create(nil);
  LinkLines := TStringList.Create;
  try
    Query.Connection := FConnection;

    Query.SQL.Text :=
      'DELETE FROM MailLink WHERE SourceMailNotesID = :SourceMailNotesID';
    Query.ParamByName('SourceMailNotesID').AsString := SourceMailNotesID;
    Query.ExecSQL;

    LinkLines.Text := Links;
    for Line in LinkLines do
    begin
      Token := ExtractMailNotesToken(Trim(Line));
      if Token = '' then
        Continue;

      TargetMailNotesID := FindMailNotesIDByToken(Token);
      if TargetMailNotesID = '' then
        Continue;

      if SameText(TargetMailNotesID, SourceMailNotesID) then
        Continue;

      Query.Close;
      Query.SQL.Text :=
        'INSERT OR IGNORE INTO MailLink ' +
        '(SourceMailNotesID, TargetMailNotesID, CreatedUTC) ' +
        'VALUES (:SourceMailNotesID, :TargetMailNotesID, :CreatedUTC)';
      Query.ParamByName('SourceMailNotesID').AsString := SourceMailNotesID;
      Query.ParamByName('TargetMailNotesID').AsString := TargetMailNotesID;
      Query.ParamByName('CreatedUTC').AsString := GetCurrentUTC;
      Query.ExecSQL;
    end;
  finally
    LinkLines.Free;
    Query.Free;
  end;
end;

procedure TDatabase.SaveLinkBuffer(LinkBuffer: TLinkBuffer);
var
  Query: TFDQuery;
  NowUTC: string;
begin
  if not Assigned(LinkBuffer) then
    raise Exception.Create('LinkBuffer is not assigned.');

  if (LinkBuffer.MailNotesID = '') and (LinkBuffer.MessageID = '') then
    raise Exception.Create('LinkBuffer.MailNotesID and MessageID are empty.');

  if not FConnection.InTransaction then
    FConnection.StartTransaction;

  try
    EnsureMailForBuffer(LinkBuffer);
    NowUTC := GetCurrentUTC;

    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'INSERT INTO AppState (Key, Value, ModifiedUTC) ' +
        'VALUES (''ActiveLinkBuffer'', :MailNotesID, :ModifiedUTC) ' +
        'ON CONFLICT(Key) DO UPDATE SET ' +
        ' Value = excluded.Value, ModifiedUTC = excluded.ModifiedUTC';
      Query.ParamByName('MailNotesID').AsString := LinkBuffer.MailNotesID;
      Query.ParamByName('ModifiedUTC').AsString := NowUTC;
      Query.ExecSQL;
    finally
      Query.Free;
    end;

    LinkBuffer.ModifiedAt := NowUTC;
    if LinkBuffer.CreatedAt = '' then
      LinkBuffer.CreatedAt := NowUTC;

    FConnection.Commit;
  except
    if FConnection.InTransaction then
      FConnection.Rollback;
    raise;
  end;
end;

function TDatabase.LoadLinkBuffer: TLinkBuffer;
var
  Query: TFDQuery;
begin
  Result := nil;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT ' +
      ' M.MailNotesID, M.ItemID, M.ImmutableID, M.InternetMessageID, ' +
      ' M.ConversationID, M.MailboxAddress, M.Subject, M.SenderName, ' +
      ' M.SenderAddress, M.ReceivedUTC, M.CreatedUTC, A.ModifiedUTC ' +
      'FROM AppState A ' +
      'INNER JOIN Mail M ON M.MailNotesID = A.Value ' +
      'WHERE A.Key = ''ActiveLinkBuffer'' AND A.Value IS NOT NULL ' +
      'LIMIT 1';
    Query.Open;

    if Query.Eof then
      Exit;

    Result := TLinkBuffer.Create;
    Result.MailNotesID := Query.FieldByName('MailNotesID').AsString;
    Result.ItemID := Query.FieldByName('ItemID').AsString;
    Result.ImmutableID := Query.FieldByName('ImmutableID').AsString;
    Result.MessageID := Query.FieldByName('InternetMessageID').AsString;
    Result.ConversationID := Query.FieldByName('ConversationID').AsString;
    Result.MailboxAddress := Query.FieldByName('MailboxAddress').AsString;
    Result.Subject := Query.FieldByName('Subject').AsString;
    Result.SenderName := Query.FieldByName('SenderName').AsString;
    Result.SenderAddress := Query.FieldByName('SenderAddress').AsString;
    Result.MailDate := Query.FieldByName('ReceivedUTC').AsString;
    Result.CreatedAt := Query.FieldByName('CreatedUTC').AsString;
    Result.ModifiedAt := Query.FieldByName('ModifiedUTC').AsString;
  finally
    Query.Free;
  end;
end;

procedure TDatabase.ClearLinkBuffer;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'UPDATE AppState SET Value = NULL, ModifiedUTC = :ModifiedUTC ' +
      'WHERE Key = ''ActiveLinkBuffer''';
    Query.ParamByName('ModifiedUTC').AsString := GetCurrentUTC;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TDatabase.GetBacklinks(
  const TargetToken: string
): TObjectList<TNote>;
var
  TargetMailNotesID: string;
  Query: TFDQuery;
  Note: TNote;
begin
  Result := TObjectList<TNote>.Create(True);
  TargetMailNotesID := FindMailNotesIDByToken(TargetToken);

  if TargetMailNotesID = '' then
    Exit;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT ' +
      ' N.ID, N.MailNotesID, N.Content, N.Links, N.CreatedUTC, N.ModifiedUTC, ' +
      ' N.IsFavorite, N.IsDeleted, N.DeletedUTC, ' +
      ' M.ItemID, M.InternetMessageID, M.ConversationID, M.Subject, ' +
      ' M.SenderName, M.SenderAddress, M.ReceivedUTC ' +
      'FROM MailLink ML ' +
      'INNER JOIN Note N ON N.MailNotesID = ML.SourceMailNotesID ' +
      'INNER JOIN Mail M ON M.MailNotesID = N.MailNotesID ' +
      'WHERE ML.TargetMailNotesID = :TargetMailNotesID ' +
      '  AND N.IsDeleted = 0 ' +
      'ORDER BY M.ReceivedUTC DESC';
    Query.ParamByName('TargetMailNotesID').AsString := TargetMailNotesID;
    Query.Open;

    while not Query.Eof do
    begin
      Note := TNote.Create;
      Note.ID := Query.FieldByName('ID').AsInteger;
      Note.MailNotesID := Query.FieldByName('MailNotesID').AsString;
      Note.MessageID := Query.FieldByName('InternetMessageID').AsString;
      Note.ItemID := Query.FieldByName('ItemID').AsString;
      Note.ConversationID := Query.FieldByName('ConversationID').AsString;
      Note.Subject := Query.FieldByName('Subject').AsString;
      Note.SenderName := Query.FieldByName('SenderName').AsString;
      Note.SenderAddress := Query.FieldByName('SenderAddress').AsString;
      Note.MailDate := Query.FieldByName('ReceivedUTC').AsString;
      Note.Content := Query.FieldByName('Content').AsString;
      Note.Links := Query.FieldByName('Links').AsString;
      Note.CreatedAt := Query.FieldByName('CreatedUTC').AsString;
      Note.ModifiedAt := Query.FieldByName('ModifiedUTC').AsString;
      Note.IsFavorite := Query.FieldByName('IsFavorite').AsInteger <> 0;
      Note.IsDeleted := Query.FieldByName('IsDeleted').AsInteger <> 0;
      Note.DeletedAt := Query.FieldByName('DeletedUTC').AsString;
      Result.Add(Note);
      Query.Next;
    end;
  except
    Result.Free;
    raise;
  end;

  Query.Free;
end;


procedure TDatabase.AddRepairQueueItem(Item: TRepairQueueItem);
var
  Query: TFDQuery;
  NowUTC: string;
begin
  if Item.MailNotesID = '' then
    raise Exception.Create('MailNotesID is empty.');

  NowUTC := GetCurrentUTC;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'INSERT INTO SHLRepairQueue (' +
      ' MailNotesID, OldItemID, InternetMessageID, Subject, SenderName,' +
      ' SenderAddress, ReceivedUTC, Reason, CreatedUTC, ModifiedUTC,' +
      ' RetryCount, Status' +
      ') VALUES (' +
      ' :MailNotesID, :OldItemID, :MessageID, :Subject, :SenderName,' +
      ' :SenderAddress, :ReceivedUTC, :Reason, :CreatedUTC, :ModifiedUTC,' +
      ' 0, 0' +
      ') ON CONFLICT(MailNotesID) DO UPDATE SET' +
      ' OldItemID = excluded.OldItemID,' +
      ' InternetMessageID = COALESCE(NULLIF(excluded.InternetMessageID, ''''), SHLRepairQueue.InternetMessageID),' +
      ' Subject = COALESCE(NULLIF(excluded.Subject, ''''), SHLRepairQueue.Subject),' +
      ' SenderName = COALESCE(NULLIF(excluded.SenderName, ''''), SHLRepairQueue.SenderName),' +
      ' SenderAddress = COALESCE(NULLIF(excluded.SenderAddress, ''''), SHLRepairQueue.SenderAddress),' +
      ' ReceivedUTC = COALESCE(NULLIF(excluded.ReceivedUTC, ''''), SHLRepairQueue.ReceivedUTC),' +
      ' Reason = excluded.Reason,' +
      ' ModifiedUTC = excluded.ModifiedUTC,' +
      ' RetryCount = SHLRepairQueue.RetryCount + 1,' +
      ' Status = 0';

    Query.ParamByName('MailNotesID').AsString := Item.MailNotesID;
    Query.ParamByName('OldItemID').AsString := Item.OldItemID;
    Query.ParamByName('MessageID').AsString := Item.MessageID;
    Query.ParamByName('Subject').AsString := Item.Subject;
    Query.ParamByName('SenderName').AsString := Item.SenderName;
    Query.ParamByName('SenderAddress').AsString := Item.SenderAddress;
    Query.ParamByName('ReceivedUTC').AsString := Item.MailDate;
    Query.ParamByName('Reason').AsString := Item.Reason;
    Query.ParamByName('CreatedUTC').AsString := NowUTC;
    Query.ParamByName('ModifiedUTC').AsString := NowUTC;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TDatabase.GetRepairQueueCount: Integer;
begin
  Result := FConnection.ExecSQLScalar(
    'SELECT COUNT(*) FROM SHLRepairQueue WHERE Status IN (0, 1)'
  );
end;

function TDatabase.GetRepairQueue: TObjectList<TRepairQueueItem>;
var
  Query: TFDQuery;
  Item: TRepairQueueItem;
begin
  Result := TObjectList<TRepairQueueItem>.Create(True);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT ID, MailNotesID, OldItemID, InternetMessageID, Subject,' +
      ' SenderName, SenderAddress, ReceivedUTC, Reason, CreatedUTC,' +
      ' ModifiedUTC, RetryCount, Status' +
      ' FROM SHLRepairQueue WHERE Status IN (0, 1)' +
      ' ORDER BY CreatedUTC, ID';
    Query.Open;

    while not Query.Eof do
    begin
      Item := TRepairQueueItem.Create;
      Item.ID := Query.FieldByName('ID').AsInteger;
      Item.MailNotesID := Query.FieldByName('MailNotesID').AsString;
      Item.OldItemID := Query.FieldByName('OldItemID').AsString;
      Item.MessageID := Query.FieldByName('InternetMessageID').AsString;
      Item.Subject := Query.FieldByName('Subject').AsString;
      Item.SenderName := Query.FieldByName('SenderName').AsString;
      Item.SenderAddress := Query.FieldByName('SenderAddress').AsString;
      Item.MailDate := Query.FieldByName('ReceivedUTC').AsString;
      Item.Reason := Query.FieldByName('Reason').AsString;
      Item.CreatedAt := Query.FieldByName('CreatedUTC').AsString;
      Item.ModifiedAt := Query.FieldByName('ModifiedUTC').AsString;
      Item.RetryCount := Query.FieldByName('RetryCount').AsInteger;
      Item.Status := Query.FieldByName('Status').AsInteger;
      Result.Add(Item);
      Query.Next;
    end;
  except
    Query.Free;
    Result.Free;
    raise;
  end;
  Query.Free;
end;

procedure TDatabase.SetRepairQueueStatus(const ID, Status: Integer);
begin
  FConnection.ExecSQL(
    'UPDATE SHLRepairQueue SET Status = :Status, ModifiedUTC = :ModifiedUTC' +
    ' WHERE ID = :ID',
    [Status, GetCurrentUTC, ID]
  );
end;

procedure TDatabase.CompleteRepairQueueByIdentity(
  const MailNotesID, MessageID: string
);
begin
  if (MailNotesID = '') and (MessageID = '') then
    Exit;

  FConnection.ExecSQL(
    'UPDATE SHLRepairQueue SET Status = 2, ModifiedUTC = :ModifiedUTC' +
    ' WHERE Status IN (0, 1)' +
    ' AND (MailNotesID = :MailNotesID OR InternetMessageID = :MessageID)',
    [GetCurrentUTC, MailNotesID, MessageID]
  );
end;


end.
