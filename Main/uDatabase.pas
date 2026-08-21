unit uDatabase;

interface

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  System.NetEncoding,
  System.Generics.Collections,
  System.Character,

  FireDAC.UI.Intf,
{$IF Defined(MSWINDOWS)}
  FireDAC.VCLUI.Wait,
{$ELSE}
  FireDAC.ConsoleUI.Wait,
{$ENDIF}
  FireDAC.Phys.SQLiteWrapper.Stat,
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
  uRepairQueue,
  uAppPaths;

type
  TTagInfo = class
  public
    Name: string;
    NormalizedName: string;
    UsageCount: Integer;
  end;

  TPersonInfo = class
  public
    Name: string;
    NormalizedName: string;
    UsageCount: Integer;
  end;

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

    function SearchNotes(
      const SearchText: string;
      const MaxResults: Integer;
      const FavoriteOnly: Boolean;
      const TagNormalizedNames: TArray<string>;
      const PersonNormalizedNames: TArray<string>
    ): TObjectList<TNote>;
    function GetFavorites(
      const MaxResults: Integer = 100
    ): TObjectList<TNote>;
    function SetFavorite(
      const MailNotesID, MessageID: string;
      const IsFavorite: Boolean
    ): Boolean;

    procedure SaveLinkBuffer(LinkBuffer: TLinkBuffer);
    function LoadLinkBuffer: TLinkBuffer;
    procedure ClearLinkBuffer;

    procedure AddRepairQueueItem(Item: TRepairQueueItem);
    function GetRepairQueueCount: Integer;
    procedure GetStatistics(
      out NoteCount, MailLinkCount, FavoriteCount, TagCount, PersonCount: Integer
    );
    function GetTags: TObjectList<TTagInfo>;
    function GetNoteTags(const MailNotesID: string): TObjectList<TTagInfo>;
    function GetPersons: TObjectList<TPersonInfo>;
    function GetNotePersons(const MailNotesID: string): TObjectList<TPersonInfo>;
    function GetRepairQueue: TObjectList<TRepairQueueItem>;
    procedure SetRepairQueueStatus(const ID, Status: Integer);
    procedure CompleteRepairQueueByIdentity(const MailNotesID, MessageID: string);

  private
    FConnection: TFDConnection;

    function PrepareDatabaseFile: string;
    function GetCurrentUTC: string;
    function CreateMailNotesID: string;

    procedure EnsureSchema;

    procedure EnsureMailForNote(Note: TNote);
    procedure EnsureMailForBuffer(LinkBuffer: TLinkBuffer);
    procedure UpdateSearchEntry(const MailNotesID: string);
    function BuildSearchExpression(const SearchText: string): string;
    function ExtractTagsFromText(const Content: string): TDictionary<string, string>;
    procedure SyncNoteTags(const NoteID: Integer; const Content: string);
    procedure DeleteUnusedTags;
    procedure RebuildTagIndex;
    function NormalizePersonName(const Name: string): string;
    function ExtractPersonsFromText(const Content: string): TDictionary<string, string>;
    procedure SyncNotePersons(const NoteID: Integer; const Content: string);
    procedure DeleteUnusedPersons;
    procedure RebuildPersonIndex;

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
  DatabaseFile := PrepareDatabaseFile;

  FConnection.DriverName := 'SQLite';
  FConnection.Params.Database := DatabaseFile;
  FConnection.Params.Values['BusyTimeout'] := '5000';

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
    'CREATE TABLE IF NOT EXISTS Tag (' +
    ' ID INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,' +
    ' Name TEXT NOT NULL,' +
    ' NormalizedName TEXT NOT NULL UNIQUE,' +
    ' CHECK (length(Name) > 0),' +
    ' CHECK (length(NormalizedName) > 0)' +
    ')'
  );

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS NoteTag (' +
    ' NoteID INTEGER NOT NULL,' +
    ' TagID INTEGER NOT NULL,' +
    ' PRIMARY KEY (NoteID, TagID),' +
    ' FOREIGN KEY (NoteID) REFERENCES Note(ID)' +
    '   ON UPDATE CASCADE ON DELETE CASCADE,' +
    ' FOREIGN KEY (TagID) REFERENCES Tag(ID)' +
    '   ON UPDATE CASCADE ON DELETE CASCADE' +
    ')'
  );

  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS IX_NoteTag_TagID ON NoteTag(TagID)'
  );

  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS IX_Tag_Name ON Tag(Name COLLATE NOCASE)'
  );

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS Person (' +
    ' ID INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,' +
    ' Name TEXT NOT NULL,' +
    ' NormalizedName TEXT NOT NULL UNIQUE,' +
    ' CHECK (length(Name) > 0),' +
    ' CHECK (length(NormalizedName) > 0)' +
    ')'
  );

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS NotePerson (' +
    ' NoteID INTEGER NOT NULL,' +
    ' PersonID INTEGER NOT NULL,' +
    ' PRIMARY KEY (NoteID, PersonID),' +
    ' FOREIGN KEY (NoteID) REFERENCES Note(ID)' +
    '   ON UPDATE CASCADE ON DELETE CASCADE,' +
    ' FOREIGN KEY (PersonID) REFERENCES Person(ID)' +
    '   ON UPDATE CASCADE ON DELETE CASCADE' +
    ')'
  );

  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS IX_NotePerson_PersonID ON NotePerson(PersonID)'
  );

  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS IX_Person_Name ON Person(Name COLLATE NOCASE)'
  );

  RebuildTagIndex;
  RebuildPersonIndex;

  FConnection.ExecSQL(
    'CREATE VIRTUAL TABLE IF NOT EXISTS MailNoteSearch USING fts5(' +
    ' MailNotesID UNINDEXED,' +
    ' Content,' +
    ' Subject,' +
    ' SenderName,' +
    ' SenderAddress,' +
    ' tokenize = ''unicode61 remove_diacritics 2''' +
    ')'
  );

  // Der Index wird beim Start aus den Fachdaten neu aufgebaut. Das ist bei
  // lokalen MailNotes-Daten schnell und vermeidet fragile Triggerlogik.
  FConnection.ExecSQL('DELETE FROM MailNoteSearch');
  FConnection.ExecSQL(
    'INSERT INTO MailNoteSearch ' +
    '(MailNotesID, Content, Subject, SenderName, SenderAddress) ' +
    'SELECT M.MailNotesID, N.Content, M.Subject, M.SenderName, M.SenderAddress ' +
    'FROM Note N ' +
    'JOIN Mail M ON M.MailNotesID = N.MailNotesID ' +
    'WHERE N.IsDeleted = 0'
  );

  FConnection.ExecSQL(
    'UPDATE SchemaInfo SET SchemaVersion = 5 ' +
    'WHERE SchemaVersion < 5'
  );
end;

procedure TDatabase.Close;
begin
  if FConnection.Connected then
    FConnection.Close;
end;

function TDatabase.PrepareDatabaseFile: string;
var
  BundledDatabaseFile: string;
begin
  TAppPaths.EnsureDataDirectory;
  Result := TAppPaths.DatabaseFile;

  if TFile.Exists(Result) then
    Exit;

  BundledDatabaseFile := TAppPaths.BundledDatabaseFile;

  if not TFile.Exists(BundledDatabaseFile) then
    raise Exception.CreateFmt(
      'Datenbankvorlage nicht gefunden: %s',
      [BundledDatabaseFile]
    );

  TFile.Copy(BundledDatabaseFile, Result, False);
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

procedure TDatabase.UpdateSearchEntry(const MailNotesID: string);
var
  Query: TFDQuery;
begin
  if MailNotesID = '' then
    Exit;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'DELETE FROM MailNoteSearch WHERE MailNotesID = :MailNotesID';
    Query.ParamByName('MailNotesID').AsString := MailNotesID;
    Query.ExecSQL;

    Query.SQL.Text :=
      'INSERT INTO MailNoteSearch ' +
      '(MailNotesID, Content, Subject, SenderName, SenderAddress) ' +
      'SELECT M.MailNotesID, N.Content, M.Subject, M.SenderName, M.SenderAddress ' +
      'FROM Note N ' +
      'JOIN Mail M ON M.MailNotesID = N.MailNotesID ' +
      'WHERE N.MailNotesID = :MailNotesID AND N.IsDeleted = 0';
    Query.ParamByName('MailNotesID').AsString := MailNotesID;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TDatabase.BuildSearchExpression(const SearchText: string): string;
var
  Parts: TStringList;
  SearchWords: TStringList;
  Word: string;
  CleanText: string;
begin
  Result := '';
  CleanText := StringReplace(SearchText, #9, ' ', [rfReplaceAll]);
  CleanText := StringReplace(CleanText, #13, ' ', [rfReplaceAll]);
  CleanText := StringReplace(CleanText, #10, ' ', [rfReplaceAll]);

  Parts := TStringList.Create;
  SearchWords := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ' ';
    Parts.DelimitedText := CleanText;

    for Word in Parts do
      if Trim(Word) <> '' then
        SearchWords.Add('"' + StringReplace(Trim(Word), '"', '""', [rfReplaceAll]) + '"*');

    Result := StringReplace(Trim(SearchWords.Text), sLineBreak, ' AND ', [rfReplaceAll]);
  finally
    SearchWords.Free;
    Parts.Free;
  end;
end;

function TDatabase.ExtractTagsFromText(
  const Content: string
): TDictionary<string, string>;
var
  I: Integer;
  StartPos: Integer;
  TagName: string;
  NormalizedName: string;
  function IsTagChar(const AChar: Char): Boolean;
  begin
    Result := TCharacter.IsLetterOrDigit(AChar) or (AChar = '_') or (AChar = '-');
  end;

begin
  Result := TDictionary<string, string>.Create;
  I := 1;

  while I <= Length(Content) do
  begin
    if Content[I] <> '#' then
    begin
      Inc(I);
      Continue;
    end;

    StartPos := I + 1;
    I := StartPos;

    while (I <= Length(Content)) and IsTagChar(Content[I]) do
      Inc(I);

    if I = StartPos then
      Continue;

    TagName := Copy(Content, StartPos, I - StartPos);
    NormalizedName := LowerCase(TagName);

    if not Result.ContainsKey(NormalizedName) then
      Result.Add(NormalizedName, TagName);
  end;
end;

procedure TDatabase.DeleteUnusedTags;
begin
  FConnection.ExecSQL(
    'DELETE FROM NoteTag ' +
    'WHERE NoteID IN (SELECT ID FROM Note WHERE IsDeleted <> 0)'
  );

  FConnection.ExecSQL(
    'DELETE FROM Tag ' +
    'WHERE NOT EXISTS (' +
    ' SELECT 1 FROM NoteTag NT WHERE NT.TagID = Tag.ID' +
    ')'
  );
end;

procedure TDatabase.RebuildTagIndex;
var
  Query: TFDQuery;
  Notes: TObjectList<TNote>;
  Note: TNote;
begin
  Notes := TObjectList<TNote>.Create(True);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT ID, Content FROM Note WHERE IsDeleted = 0 ORDER BY ID';
    Query.Open;
    while not Query.Eof do
    begin
      Note := TNote.Create;
      Note.ID := Query.FieldByName('ID').AsInteger;
      Note.Content := Query.FieldByName('Content').AsString;
      Notes.Add(Note);
      Query.Next;
    end;
    Query.Close;

    FConnection.ExecSQL('DELETE FROM NoteTag');
    FConnection.ExecSQL('DELETE FROM Tag');

    for Note in Notes do
      SyncNoteTags(Note.ID, Note.Content);
  finally
    Query.Free;
    Notes.Free;
  end;
end;

procedure TDatabase.SyncNoteTags(
  const NoteID: Integer;
  const Content: string
);
var
  Tags: TDictionary<string, string>;
  Pair: TPair<string, string>;
  Query: TFDQuery;
  TagID: Integer;
begin
  if NoteID <= 0 then
    Exit;

  Tags := ExtractTagsFromText(Content);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;

    Query.SQL.Text := 'DELETE FROM NoteTag WHERE NoteID = :NoteID';
    Query.ParamByName('NoteID').AsInteger := NoteID;
    Query.ExecSQL;

    for Pair in Tags do
    begin
      Query.SQL.Text :=
        'INSERT INTO Tag (Name, NormalizedName) ' +
        'VALUES (:Name, :NormalizedName) ' +
        'ON CONFLICT(NormalizedName) DO NOTHING';
      Query.ParamByName('Name').AsString := Pair.Value;
      Query.ParamByName('NormalizedName').AsString := Pair.Key;
      Query.ExecSQL;

      Query.SQL.Text :=
        'SELECT ID FROM Tag WHERE NormalizedName = :NormalizedName';
      Query.ParamByName('NormalizedName').AsString := Pair.Key;
      Query.Open;
      TagID := 0;
      if not Query.Eof then
        TagID := Query.Fields[0].AsInteger;
      Query.Close;

      if TagID = 0 then
        Continue;

      Query.SQL.Text :=
        'INSERT OR IGNORE INTO NoteTag (NoteID, TagID) ' +
        'VALUES (:NoteID, :TagID)';
      Query.ParamByName('NoteID').AsInteger := NoteID;
      Query.ParamByName('TagID').AsInteger := TagID;
      Query.ExecSQL;
    end;

    DeleteUnusedTags;
  finally
    Query.Free;
    Tags.Free;
  end;
end;

function TDatabase.NormalizePersonName(const Name: string): string;
var
  I: Integer;
  Ch: Char;
  LastWasSpace: Boolean;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    LastWasSpace := True;
    for I := 1 to Length(Name) do
    begin
      Ch := Name[I];
      if TCharacter.IsWhiteSpace(Ch) then
      begin
        if not LastWasSpace then
        begin
          Builder.Append(' ');
          LastWasSpace := True;
        end;
      end
      else
      begin
        Builder.Append(Ch);
        LastWasSpace := False;
      end;
    end;

    Result := Trim(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

function TDatabase.ExtractPersonsFromText(
  const Content: string
): TDictionary<string, string>;
var
  LineStart: Integer;
  LineEnd: Integer;
  AtPos: Integer;
  ScanPos: Integer;
  PersonName: string;
  NormalizedName: string;
  Ch: Char;
  NextCh: Char;
  LetterCount: Integer;
  I: Integer;
begin
  Result := TDictionary<string, string>.Create;
  LineStart := 1;

  while LineStart <= Length(Content) do
  begin
    LineEnd := LineStart;
    while (LineEnd <= Length(Content)) and
          (Content[LineEnd] <> #13) and (Content[LineEnd] <> #10) do
      Inc(LineEnd);

    AtPos := LineStart;
    while AtPos < LineEnd do
    begin
      if (Content[AtPos] = '@') and
         ((AtPos = LineStart) or
          (Content[AtPos - 1] = ' ') or
          (Content[AtPos - 1] = #9)) then
      begin
        ScanPos := AtPos + 1;

        while ScanPos < LineEnd do
        begin
          Ch := Content[ScanPos];

          // Erlaubt sind Buchstaben, Leerzeichen/Tab, Bindestrich
          // sowie gerade und typografische Apostrophe.
          if TCharacter.IsLetter(Ch) or
             (Ch = ' ') or (Ch = #9) or
             (Ch = '-') or (Ch = #39) or (Ch = #$2019) then
          begin
            Inc(ScanPos);
            Continue;
          end;

          // Ein Punkt gehoert nur dann zum Namen, wenn direkt danach
          // ohne Leerzeichen ein weiterer Buchstabe folgt.
          // Beispiele: @J.R.Ewing, @Dr.Mueller
          // Dagegen beendet der Punkt @Nils Koenig. sofort.
          if Ch = '.' then
          begin
            if ScanPos + 1 < LineEnd then
            begin
              NextCh := Content[ScanPos + 1];
              if TCharacter.IsLetter(NextCh) then
              begin
                Inc(ScanPos);
                Continue;
              end;
            end;
          end;

          // Jedes andere Zeichen beendet den Personentag.
          Break;
        end;

        PersonName := NormalizePersonName(
          Copy(Content, AtPos + 1, ScanPos - AtPos - 1)
        );

        // Ein gueltiger Personenname muss mindestens zwei Buchstaben
        // enthalten. Dadurch werden versehentliche Treffer wie @x ignoriert.
        LetterCount := 0;
        for I := 1 to Length(PersonName) do
          if TCharacter.IsLetter(PersonName[I]) then
            Inc(LetterCount);

        if LetterCount >= 2 then
        begin
          NormalizedName := LowerCase(PersonName);
          if not Result.ContainsKey(NormalizedName) then
            Result.Add(NormalizedName, PersonName);
        end;

        // Nach dem gefundenen Personentag an dessen Ende weitersuchen.
        // So werden auch mehrere Personen in derselben Zeile erkannt, z. B.
        // @Daniel Meier @Karl.
        AtPos := ScanPos;
        Continue;
      end;

      Inc(AtPos);
    end;

    LineStart := LineEnd;
    if (LineStart <= Length(Content)) and (Content[LineStart] = #13) then
      Inc(LineStart);
    if (LineStart <= Length(Content)) and (Content[LineStart] = #10) then
      Inc(LineStart);
  end;
end;

procedure TDatabase.DeleteUnusedPersons;
begin
  FConnection.ExecSQL(
    'DELETE FROM NotePerson ' +
    'WHERE NoteID IN (SELECT ID FROM Note WHERE IsDeleted <> 0)'
  );

  FConnection.ExecSQL(
    'DELETE FROM Person ' +
    'WHERE NOT EXISTS (' +
    ' SELECT 1 FROM NotePerson NP WHERE NP.PersonID = Person.ID' +
    ')'
  );
end;

procedure TDatabase.RebuildPersonIndex;
var
  Query: TFDQuery;
  Notes: TObjectList<TNote>;
  Note: TNote;
begin
  Notes := TObjectList<TNote>.Create(True);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT ID, Content FROM Note WHERE IsDeleted = 0 ORDER BY ID';
    Query.Open;
    while not Query.Eof do
    begin
      Note := TNote.Create;
      Note.ID := Query.FieldByName('ID').AsInteger;
      Note.Content := Query.FieldByName('Content').AsString;
      Notes.Add(Note);
      Query.Next;
    end;
    Query.Close;

    FConnection.ExecSQL('DELETE FROM NotePerson');
    FConnection.ExecSQL('DELETE FROM Person');

    for Note in Notes do
      SyncNotePersons(Note.ID, Note.Content);
  finally
    Query.Free;
    Notes.Free;
  end;
end;

procedure TDatabase.SyncNotePersons(
  const NoteID: Integer;
  const Content: string
);
var
  Persons: TDictionary<string, string>;
  Pair: TPair<string, string>;
  Query: TFDQuery;
  PersonID: Integer;
begin
  if NoteID <= 0 then
    Exit;

  Persons := ExtractPersonsFromText(Content);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;

    Query.SQL.Text := 'DELETE FROM NotePerson WHERE NoteID = :NoteID';
    Query.ParamByName('NoteID').AsInteger := NoteID;
    Query.ExecSQL;

    for Pair in Persons do
    begin
      Query.SQL.Text :=
        'INSERT INTO Person (Name, NormalizedName) ' +
        'VALUES (:Name, :NormalizedName) ' +
        'ON CONFLICT(NormalizedName) DO NOTHING';
      Query.ParamByName('Name').AsString := Pair.Value;
      Query.ParamByName('NormalizedName').AsString := Pair.Key;
      Query.ExecSQL;

      Query.SQL.Text :=
        'SELECT ID FROM Person WHERE NormalizedName = :NormalizedName';
      Query.ParamByName('NormalizedName').AsString := Pair.Key;
      Query.Open;
      PersonID := 0;
      if not Query.Eof then
        PersonID := Query.Fields[0].AsInteger;
      Query.Close;

      if PersonID = 0 then
        Continue;

      Query.SQL.Text :=
        'INSERT OR IGNORE INTO NotePerson (NoteID, PersonID) ' +
        'VALUES (:NoteID, :PersonID)';
      Query.ParamByName('NoteID').AsInteger := NoteID;
      Query.ParamByName('PersonID').AsInteger := PersonID;
      Query.ExecSQL;
    end;

    DeleteUnusedPersons;
  finally
    Query.Free;
    Persons.Free;
  end;
end;

function TDatabase.SearchNotes(
  const SearchText: string;
  const MaxResults: Integer;
  const FavoriteOnly: Boolean;
  const TagNormalizedNames: TArray<string>;
  const PersonNormalizedNames: TArray<string>
): TObjectList<TNote>;
var
  Query: TFDQuery;
  Note: TNote;
  SearchExpression: string;
  FavoriteClause: string;
  TagClause: string;
  TagIndex: Integer;
  TagName: string;
  PersonClause: string;
  PersonIndex: Integer;
  PersonName: string;
  ResultLimit: Integer;
  Snippet: string;
begin
  Result := TObjectList<TNote>.Create(True);
  SearchExpression := BuildSearchExpression(SearchText);

  if (SearchExpression = '') and (Length(TagNormalizedNames) = 0) and
     (Length(PersonNormalizedNames) = 0) and not FavoriteOnly then
    Exit;

  ResultLimit := MaxResults;
  if ResultLimit < 1 then
    ResultLimit := 1
  else if ResultLimit > 100 then
    ResultLimit := 100;

  FavoriteClause := '';
  if FavoriteOnly then
    FavoriteClause := 'AND N.IsFavorite = 1 ';

  TagClause := '';
  for TagIndex := 0 to High(TagNormalizedNames) do
  begin
    TagName := LowerCase(Trim(TagNormalizedNames[TagIndex]));
    if TagName <> '' then
      TagClause := TagClause +
        'AND EXISTS (' +
        ' SELECT 1 FROM NoteTag NT' + IntToStr(TagIndex) + ' ' +
        ' JOIN Tag T' + IntToStr(TagIndex) + ' ON T' + IntToStr(TagIndex) +
        '.ID = NT' + IntToStr(TagIndex) + '.TagID ' +
        ' WHERE NT' + IntToStr(TagIndex) + '.NoteID = N.ID AND T' +
        IntToStr(TagIndex) + '.NormalizedName = :TagName' + IntToStr(TagIndex) +
        ') ';
  end;

  PersonClause := '';
  for PersonIndex := 0 to High(PersonNormalizedNames) do
  begin
    PersonName := LowerCase(Trim(PersonNormalizedNames[PersonIndex]));
    if PersonName <> '' then
      PersonClause := PersonClause +
        'AND EXISTS (' +
        ' SELECT 1 FROM NotePerson NP' + IntToStr(PersonIndex) + ' ' +
        ' JOIN Person P' + IntToStr(PersonIndex) + ' ON P' + IntToStr(PersonIndex) +
        '.ID = NP' + IntToStr(PersonIndex) + '.PersonID ' +
        ' WHERE NP' + IntToStr(PersonIndex) + '.NoteID = N.ID AND P' +
        IntToStr(PersonIndex) + '.NormalizedName = :PersonName' + IntToStr(PersonIndex) +
        ') ';
  end;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;

    if SearchExpression <> '' then
    begin
      Query.SQL.Text :=
        'SELECT M.MailNotesID, M.ItemID, M.InternetMessageID, M.Subject, ' +
        ' M.SenderName, M.SenderAddress, M.ReceivedUTC, N.Content, N.ModifiedUTC, ' +
        ' snippet(MailNoteSearch, 1, ''['', '']'', '' … '', 18) AS SearchSnippet, ' +
        ' bm25(MailNoteSearch, 0.0, 7.0, 4.0, 2.0, 2.0) AS SearchRank ' +
        'FROM MailNoteSearch ' +
        'JOIN Mail M ON M.MailNotesID = MailNoteSearch.MailNotesID ' +
        'JOIN Note N ON N.MailNotesID = M.MailNotesID ' +
        'WHERE MailNoteSearch MATCH :SearchExpression AND N.IsDeleted = 0 ' +
        FavoriteClause +
        TagClause +
        PersonClause +
        'ORDER BY SearchRank, N.ModifiedUTC DESC ' +
        'LIMIT :ResultLimit';
      Query.ParamByName('SearchExpression').AsString := SearchExpression;
    end
    else
    begin
      Query.SQL.Text :=
        'SELECT M.MailNotesID, M.ItemID, M.InternetMessageID, M.Subject, ' +
        ' M.SenderName, M.SenderAddress, M.ReceivedUTC, N.Content, N.ModifiedUTC ' +
        'FROM Note N ' +
        'JOIN Mail M ON M.MailNotesID = N.MailNotesID ' +
        'WHERE N.IsDeleted = 0 ' +
        FavoriteClause +
        TagClause +
        PersonClause +
        'ORDER BY N.ModifiedUTC DESC ' +
        'LIMIT :ResultLimit';
    end;

    for TagIndex := 0 to High(TagNormalizedNames) do
    begin
      TagName := LowerCase(Trim(TagNormalizedNames[TagIndex]));
      if TagName <> '' then
        Query.ParamByName('TagName' + IntToStr(TagIndex)).AsString := TagName;
    end;
    for PersonIndex := 0 to High(PersonNormalizedNames) do
    begin
      PersonName := LowerCase(Trim(PersonNormalizedNames[PersonIndex]));
      if PersonName <> '' then
        Query.ParamByName('PersonName' + IntToStr(PersonIndex)).AsString := PersonName;
    end;
    Query.ParamByName('ResultLimit').AsInteger := ResultLimit;
    Query.Open;

    while not Query.Eof do
    begin
      Note := TNote.Create;
      Note.MailNotesID := Query.FieldByName('MailNotesID').AsString;
      Note.ItemID := Query.FieldByName('ItemID').AsString;
      Note.MessageID := Query.FieldByName('InternetMessageID').AsString;
      Note.Subject := Query.FieldByName('Subject').AsString;
      Note.SenderName := Query.FieldByName('SenderName').AsString;
      Note.SenderAddress := Query.FieldByName('SenderAddress').AsString;
      Note.MailDate := Query.FieldByName('ReceivedUTC').AsString;
      Note.Content := Query.FieldByName('Content').AsString;
      Note.ModifiedAt := Query.FieldByName('ModifiedUTC').AsString;

      if SearchExpression <> '' then
      begin
        Note.SearchSnippet := Query.FieldByName('SearchSnippet').AsString;
        Note.SearchRank := Query.FieldByName('SearchRank').AsFloat;
      end
      else
      begin
        Snippet := Note.Content;
        Snippet := StringReplace(Snippet, #13, ' ', [rfReplaceAll]);
        Snippet := StringReplace(Snippet, #10, ' ', [rfReplaceAll]);
        Note.SearchSnippet := Trim(Copy(Snippet, 1, 180));
      end;

      Result.Add(Note);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;


function TDatabase.GetFavorites(
  const MaxResults: Integer
): TObjectList<TNote>;
var
  Query: TFDQuery;
  Note: TNote;
  ResultLimit: Integer;
  Snippet: string;
begin
  Result := TObjectList<TNote>.Create(True);

  ResultLimit := MaxResults;
  if ResultLimit < 1 then
    ResultLimit := 1
  else if ResultLimit > 100 then
    ResultLimit := 100;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT M.MailNotesID, M.ItemID, M.InternetMessageID, M.Subject, ' +
      ' M.SenderName, M.SenderAddress, M.ReceivedUTC, N.Content, N.ModifiedUTC ' +
      'FROM Note N ' +
      'JOIN Mail M ON M.MailNotesID = N.MailNotesID ' +
      'WHERE N.IsDeleted = 0 AND N.IsFavorite = 1 ' +
      'ORDER BY N.ModifiedUTC DESC ' +
      'LIMIT :ResultLimit';
    Query.ParamByName('ResultLimit').AsInteger := ResultLimit;
    Query.Open;

    while not Query.Eof do
    begin
      Note := TNote.Create;
      Note.MailNotesID := Query.FieldByName('MailNotesID').AsString;
      Note.ItemID := Query.FieldByName('ItemID').AsString;
      Note.MessageID := Query.FieldByName('InternetMessageID').AsString;
      Note.Subject := Query.FieldByName('Subject').AsString;
      Note.SenderName := Query.FieldByName('SenderName').AsString;
      Note.SenderAddress := Query.FieldByName('SenderAddress').AsString;
      Note.MailDate := Query.FieldByName('ReceivedUTC').AsString;
      Note.ModifiedAt := Query.FieldByName('ModifiedUTC').AsString;
      Snippet := Query.FieldByName('Content').AsString;
      Snippet := StringReplace(Snippet, #13, ' ', [rfReplaceAll]);
      Snippet := StringReplace(Snippet, #10, ' ', [rfReplaceAll]);
      Note.SearchSnippet := Trim(Copy(Snippet, 1, 180));
      Result.Add(Note);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

function TDatabase.SetFavorite(
  const MailNotesID, MessageID: string;
  const IsFavorite: Boolean
): Boolean;
var
  EffectiveMailNotesID: string;
  Query: TFDQuery;
begin
  Result := False;
  EffectiveMailNotesID := MailNotesID;

  if (EffectiveMailNotesID = '') and (MessageID <> '') then
    EffectiveMailNotesID := FindMailNotesIDByMessageID(MessageID);

  if EffectiveMailNotesID = '' then
    Exit;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'UPDATE Note SET IsFavorite = :IsFavorite ' +
      'WHERE MailNotesID = :MailNotesID AND IsDeleted = 0';
    Query.ParamByName('IsFavorite').AsInteger := Ord(IsFavorite);
    Query.ParamByName('MailNotesID').AsString := EffectiveMailNotesID;
    Query.ExecSQL;
    Result := Query.RowsAffected > 0;
  finally
    Query.Free;
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
    UpdateSearchEntry(Note.MailNotesID);
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

    SyncNoteTags(Note.ID, Note.Content);
    SyncNotePersons(Note.ID, Note.Content);
    UpdateMailLinks(Note.MailNotesID, Note.Links);
    UpdateSearchEntry(Note.MailNotesID);
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

procedure TDatabase.GetStatistics(
  out NoteCount, MailLinkCount, FavoriteCount, TagCount, PersonCount: Integer
);
begin
  NoteCount := FConnection.ExecSQLScalar(
    'SELECT COUNT(*) FROM Note WHERE IsDeleted = 0'
  );
  MailLinkCount := FConnection.ExecSQLScalar(
    'SELECT COUNT(*) FROM MailLink'
  );
  FavoriteCount := FConnection.ExecSQLScalar(
    'SELECT COUNT(*) FROM Note WHERE IsDeleted = 0 AND IsFavorite = 1'
  );
  TagCount := FConnection.ExecSQLScalar(
    'SELECT COUNT(DISTINCT T.ID) FROM Tag T ' +
    'JOIN NoteTag NT ON NT.TagID = T.ID ' +
    'JOIN Note N ON N.ID = NT.NoteID AND N.IsDeleted = 0'
  );
  PersonCount := FConnection.ExecSQLScalar(
    'SELECT COUNT(DISTINCT P.ID) FROM Person P ' +
    'JOIN NotePerson NP ON NP.PersonID = P.ID ' +
    'JOIN Note N ON N.ID = NP.NoteID AND N.IsDeleted = 0'
  );
end;

function TDatabase.GetTags: TObjectList<TTagInfo>;
var
  Query: TFDQuery;
  Tag: TTagInfo;
begin
  Result := TObjectList<TTagInfo>.Create(True);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT T.Name, T.NormalizedName, COUNT(NT.NoteID) AS UsageCount ' +
      'FROM Tag T ' +
      'JOIN NoteTag NT ON NT.TagID = T.ID ' +
      'JOIN Note N ON N.ID = NT.NoteID AND N.IsDeleted = 0 ' +
      'GROUP BY T.ID, T.Name, T.NormalizedName ' +
      'HAVING COUNT(NT.NoteID) > 0 ' +
      'ORDER BY T.Name COLLATE NOCASE';
    Query.Open;

    while not Query.Eof do
    begin
      Tag := TTagInfo.Create;
      Tag.Name := Query.FieldByName('Name').AsString;
      Tag.NormalizedName := Query.FieldByName('NormalizedName').AsString;
      Tag.UsageCount := Query.FieldByName('UsageCount').AsInteger;
      Result.Add(Tag);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

function TDatabase.GetNoteTags(
  const MailNotesID: string
): TObjectList<TTagInfo>;
var
  Query: TFDQuery;
  Tag: TTagInfo;
begin
  Result := TObjectList<TTagInfo>.Create(True);
  if MailNotesID = '' then
    Exit;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT T.Name, T.NormalizedName ' +
      'FROM Note N ' +
      'JOIN NoteTag NT ON NT.NoteID = N.ID ' +
      'JOIN Tag T ON T.ID = NT.TagID ' +
      'WHERE N.MailNotesID = :MailNotesID AND N.IsDeleted = 0 ' +
      'ORDER BY T.Name COLLATE NOCASE';
    Query.ParamByName('MailNotesID').AsString := MailNotesID;
    Query.Open;

    while not Query.Eof do
    begin
      Tag := TTagInfo.Create;
      Tag.Name := Query.FieldByName('Name').AsString;
      Tag.NormalizedName := Query.FieldByName('NormalizedName').AsString;
      Tag.UsageCount := 1;
      Result.Add(Tag);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

function TDatabase.GetPersons: TObjectList<TPersonInfo>;
var
  Query: TFDQuery;
  Person: TPersonInfo;
begin
  Result := TObjectList<TPersonInfo>.Create(True);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT P.Name, P.NormalizedName, COUNT(NP.NoteID) AS UsageCount ' +
      'FROM Person P ' +
      'JOIN NotePerson NP ON NP.PersonID = P.ID ' +
      'JOIN Note N ON N.ID = NP.NoteID AND N.IsDeleted = 0 ' +
      'GROUP BY P.ID, P.Name, P.NormalizedName ' +
      'HAVING COUNT(NP.NoteID) > 0 ' +
      'ORDER BY P.Name COLLATE NOCASE';
    Query.Open;

    while not Query.Eof do
    begin
      Person := TPersonInfo.Create;
      Person.Name := Query.FieldByName('Name').AsString;
      Person.NormalizedName := Query.FieldByName('NormalizedName').AsString;
      Person.UsageCount := Query.FieldByName('UsageCount').AsInteger;
      Result.Add(Person);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

function TDatabase.GetNotePersons(
  const MailNotesID: string
): TObjectList<TPersonInfo>;
var
  Query: TFDQuery;
  Person: TPersonInfo;
begin
  Result := TObjectList<TPersonInfo>.Create(True);
  if MailNotesID = '' then
    Exit;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'SELECT P.Name, P.NormalizedName ' +
      'FROM Note N ' +
      'JOIN NotePerson NP ON NP.NoteID = N.ID ' +
      'JOIN Person P ON P.ID = NP.PersonID ' +
      'WHERE N.MailNotesID = :MailNotesID AND N.IsDeleted = 0 ' +
      'ORDER BY P.Name COLLATE NOCASE';
    Query.ParamByName('MailNotesID').AsString := MailNotesID;
    Query.Open;

    while not Query.Eof do
    begin
      Person := TPersonInfo.Create;
      Person.Name := Query.FieldByName('Name').AsString;
      Person.NormalizedName := Query.FieldByName('NormalizedName').AsString;
      Person.UsageCount := 1;
      Result.Add(Person);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
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
