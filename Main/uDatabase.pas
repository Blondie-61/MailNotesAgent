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
  System.Variants,

  FireDAC.UI.Intf,
{$IF Defined(MSWINDOWS)}
  FireDAC.VCLUI.Wait,
{$ELSE}
  FireDAC.ConsoleUI.Wait,
{$ENDIF}
  FireDAC.DApt,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper,
  FireDAC.Phys.SQLiteWrapper.Stat,
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
    function ChangeDatabasePath(const APath: string; out AMode: string): string;
    function CreateBackup(const ADestinationDirectory: string; const ARetentionCount: Integer = 3): string;

    procedure Save(Note: TNote);
    procedure RefreshMailIdentity(Note: TNote);

    function FindByMessageID(const MessageID: string): TNote;
    function FindByMailNotesID(const MailNotesID: string): TNote;
    function FindMailByLinkToken(const LinkToken: string): TNote;

    function GetBacklinks(
      const TargetToken: string
    ): TObjectList<TNote>;
    function DeleteBacklink(
      const SourceMailNotesID, TargetToken, SourceLink: string
    ): Boolean;

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
    function DeleteNote(
      const MailNotesID, MessageID: string
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
    function CompleteRepairQueueByIdentity(const MailNotesID, MessageID: string): Boolean;

    procedure UpsertGraphAccount(
      const MailboxAddress, TenantID, UserID: string;
      const GraphState: Integer;
      const LastCheckedUTC, LastSuccessUTC, LastError: string
    );
    function LoadGraphAccount(
      const MailboxAddress: string;
      out TenantID, UserID: string;
      out GraphState: Integer;
      out LastCheckedUTC, LastSuccessUTC, LastError: string
    ): Boolean;

  private
    FConnection: TFDConnection;
    FSQLiteDriverLink: TFDPhysSQLiteDriverLink;

    function PrepareDatabaseFile: string;
    procedure CreateSQLiteSnapshot(const ATargetFile: string);
    procedure VerifySQLiteDatabase(const ADatabaseFile: string);
    procedure RotateBackups(const ADirectory: string; const ARetentionCount: Integer);
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
  FSQLiteDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  FConnection := TFDConnection.Create(nil);
end;

destructor TDatabase.Destroy;
begin
  Close;
  FConnection.Free;
  FSQLiteDriverLink.Free;
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



function TDatabase.ChangeDatabasePath(const APath: string; out AMode: string): string;
var
  OldFile: string;
  TargetFile: string;
  TargetDirectory: string;
  TemporaryFile: string;
  CreatedTarget: Boolean;
begin
  OldFile := TPath.GetFullPath(FConnection.Params.Database);
  TargetFile := Trim(APath);

  if TargetFile = '' then
    raise Exception.Create('Es wurde kein Datenbankpfad angegeben.');

  // Komfort: Es darf entweder ein Ordner oder eine konkrete .sqlite-Datei
  // angegeben werden. Bei einem Ordner verwenden wir MailNotes.sqlite.
  if TDirectory.Exists(TargetFile) or
     ((TPath.GetExtension(TargetFile) = '') and not TFile.Exists(TargetFile)) then
    TargetFile := TPath.Combine(TargetFile, 'MailNotes.sqlite');

  TargetFile := TPath.GetFullPath(TargetFile);
  if SameText(TargetFile, OldFile) then
  begin
    AMode := 'unchanged';
    Exit(OldFile);
  end;

  TargetDirectory := ExtractFilePath(TargetFile);
  if TargetDirectory = '' then
    raise Exception.Create('Der Zielordner konnte nicht ermittelt werden.');

  TDirectory.CreateDirectory(TargetDirectory);
  CreatedTarget := False;
  TemporaryFile := TargetFile + '.mailnotes-tmp';

  try
    if TFile.Exists(TargetFile) then
    begin
      // Eine vorhandene Datei wird nur übernommen, wenn SQLite selbst ihre
      // Integrität bestätigt. Die aktive Datenbank bleibt bis dahin geöffnet.
      VerifySQLiteDatabase(TargetFile);
      AMode := 'adopted';
    end
    else
    begin
      // Nicht die geöffnete SQLite-Datei mit TFile.Copy kopieren. Der
      // SQLite-Online-Backup-Mechanismus erzeugt einen konsistenten Snapshot,
      // auch wenn die Quelldatenbank geöffnet ist oder WAL verwendet.
      if TFile.Exists(TemporaryFile) then
        TFile.Delete(TemporaryFile);

      CreateSQLiteSnapshot(TemporaryFile);
      VerifySQLiteDatabase(TemporaryFile);

      // Erst die vollständig geprüfte, geschlossene Snapshot-Datei bekommt
      // ihren endgültigen Namen. Da Temp- und Zieldatei im selben Ordner
      // liegen, ist dies kein erneuter Datenbank-Kopiervorgang.
      TFile.Move(TemporaryFile, TargetFile);
      CreatedTarget := True;
      AMode := 'moved';
    end;

    // Erst nach erfolgreicher Prüfung auf die Zieldatenbank umschalten.
    if FConnection.Connected then
      FConnection.Close;

    FConnection.Params.Database := TargetFile;
    FConnection.Connected := True;
    FConnection.ExecSQL('PRAGMA foreign_keys = ON');
    EnsureSchema;

    TAppPaths.SetDatabaseFile(TargetFile);
    Result := TargetFile;
  except
    on E: Exception do
    begin
      if TFile.Exists(TemporaryFile) then
      begin
        try
          TFile.Delete(TemporaryFile);
        except
        end;
      end;

      try
        if FConnection.Connected then
          FConnection.Close;
        FConnection.Params.Database := OldFile;
        FConnection.Connected := True;
        FConnection.ExecSQL('PRAGMA foreign_keys = ON');
        EnsureSchema;
      except
        // Die ursprüngliche Fehlermeldung ist für den Benutzer wichtiger.
      end;

      if CreatedTarget and TFile.Exists(TargetFile) then
      begin
        try
          TFile.Delete(TargetFile);
        except
        end;
      end;

      raise Exception.CreateFmt(
        'Datenbankpfad konnte nicht geändert werden: %s',
        [E.Message]
      );
    end;
  end;
end;


procedure TDatabase.CreateSQLiteSnapshot(const ATargetFile: string);
var
  Backup: TFDSQLiteBackup;
begin
  if not FConnection.Connected then
    raise Exception.Create('Die MailNotes-Datenbank ist nicht geöffnet.');

  if Trim(ATargetFile) = '' then
    raise Exception.Create('Für die Sicherung wurde keine Zieldatei angegeben.');

  if TFile.Exists(ATargetFile) then
    TFile.Delete(ATargetFile);

  Backup := TFDSQLiteBackup.Create(nil);
  try
    Backup.DriverLink := FSQLiteDriverLink;
    Backup.DatabaseObj := FConnection.CliObj;
    Backup.DestDatabase := ATargetFile;
    Backup.DestMode := smCreate;
    Backup.WaitForLocks := True;
    Backup.BusyTimeout := 5000;
    Backup.Backup;
  finally
    Backup.Free;
  end;
end;


procedure TDatabase.VerifySQLiteDatabase(const ADatabaseFile: string);
var
  CheckConnection: TFDConnection;
  Query: TFDQuery;
  CheckResult: string;
begin
  if not TFile.Exists(ADatabaseFile) then
    raise Exception.CreateFmt(
      'Die SQLite-Datei wurde nicht erstellt: %s',
      [ADatabaseFile]
    );

  CheckConnection := TFDConnection.Create(nil);
  try
    CheckConnection.DriverName := 'SQLite';
    CheckConnection.Params.Database := ADatabaseFile;
    CheckConnection.Params.Values['BusyTimeout'] := '5000';
    CheckConnection.Connected := True;

    Query := TFDQuery.Create(nil);
    try
      Query.Connection := CheckConnection;
      Query.Open('PRAGMA integrity_check');

      if Query.Eof then
        CheckResult := ''
      else
        CheckResult := VarToStr(Query.Fields[0].Value);
    finally
      Query.Free;
    end;
  finally
    CheckConnection.Free;
  end;

  if not SameText(Trim(CheckResult), 'ok') then
    raise Exception.CreateFmt(
      'SQLite-Integritätsprüfung fehlgeschlagen (%s): %s',
      [ExtractFileName(ADatabaseFile), CheckResult]
    );
end;


procedure TDatabase.RotateBackups(
  const ADirectory: string;
  const ARetentionCount: Integer
);
var
  Files: TArray<string>;
  I: Integer;
  DeleteCount: Integer;
begin
  if ARetentionCount <= 0 then
    Exit;

  Files := TDirectory.GetFiles(ADirectory, 'MailNotes-*.sqlite', TSearchOption.soTopDirectoryOnly);
  TArray.Sort<string>(Files);

  DeleteCount := Length(Files) - ARetentionCount;
  for I := 0 to DeleteCount - 1 do
  begin
    try
      TFile.Delete(Files[I]);
    except
      // Ein nicht löschbares altes Backup macht das neue Backup nicht ungültig.
    end;
  end;
end;


function TDatabase.CreateBackup(
  const ADestinationDirectory: string;
  const ARetentionCount: Integer
): string;
var
  DestinationDirectory: string;
  FinalFile: string;
  TemporaryFile: string;
begin
  DestinationDirectory := Trim(ADestinationDirectory);
  if DestinationDirectory = '' then
    raise Exception.Create('Es wurde kein Backup-Zielordner angegeben.');

  DestinationDirectory := TPath.GetFullPath(DestinationDirectory);
  TDirectory.CreateDirectory(DestinationDirectory);

  FinalFile := TPath.Combine(
    DestinationDirectory,
    'MailNotes-' + FormatDateTime('yyyy-mm-dd-hhnnss', Now) + '.sqlite'
  );

  // Bei zwei Backups innerhalb derselben Sekunde keines still überschreiben.
  if TFile.Exists(FinalFile) then
    FinalFile := TPath.Combine(
      DestinationDirectory,
      'MailNotes-' + FormatDateTime('yyyy-mm-dd-hhnnss-zzz', Now) + '.sqlite'
    );

  TemporaryFile := FinalFile + '.tmp';
  if TFile.Exists(TemporaryFile) then
    TFile.Delete(TemporaryFile);

  try
    CreateSQLiteSnapshot(TemporaryFile);
    VerifySQLiteDatabase(TemporaryFile);
    TFile.Move(TemporaryFile, FinalFile);
  except
    if TFile.Exists(TemporaryFile) then
    begin
      try
        TFile.Delete(TemporaryFile);
      except
      end;
    end;
    raise;
  end;

  // Rotation erst nach einem vollständig erstellten und geprüften Backup.
  RotateBackups(DestinationDirectory, ARetentionCount);
  Result := FinalFile;
end;

procedure TDatabase.EnsureSchema;
begin
  // Graph ist eine kontobezogene, zur Laufzeit festgestellte Faehigkeit.
  // OAuth-Tokens werden ausdruecklich nicht in der SQLite-Datenbank gespeichert.
  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS GraphAccount (' +
    ' MailboxAddress TEXT NOT NULL PRIMARY KEY,' +
    ' TenantID TEXT,' +
    ' UserID TEXT,' +
    ' GraphState INTEGER NOT NULL DEFAULT 0,' +
    ' LastCheckedUTC TEXT,' +
    ' LastSuccessUTC TEXT,' +
    ' LastError TEXT,' +
    ' CHECK (length(MailboxAddress) > 0),' +
    ' CHECK (GraphState IN (0, 1, 2, 3, 4))' +
    ')'
  );

  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS IX_GraphAccount_User ' +
    'ON GraphAccount(TenantID, UserID)'
  );

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
    'UPDATE SchemaInfo SET SchemaVersion = 6 ' +
    'WHERE SchemaVersion < 6'
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

          // Erlaubt sind Buchstaben, normale Leerzeichen, Bindestrich
          // sowie gerade und typografische Apostrophe.
          // TAB (#9) beendet einen Personentag explizit. Im Editor wird
          // TAB optisch wie ein einzelnes Leerzeichen dargestellt.
          if TCharacter.IsLetter(Ch) or
             (Ch = ' ') or
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

function TDatabase.DeleteNote(
  const MailNotesID, MessageID: string
): Boolean;
var
  EffectiveMailNotesID: string;
  NoteID: Integer;
  NowUTC: string;
  Query: TFDQuery;
begin
  Result := False;
  EffectiveMailNotesID := MailNotesID;

  if (EffectiveMailNotesID = '') and (MessageID <> '') then
    EffectiveMailNotesID := FindMailNotesIDByMessageID(MessageID);

  if EffectiveMailNotesID = '' then
    Exit;

  if not FConnection.InTransaction then
    FConnection.StartTransaction;

  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'SELECT ID FROM Note ' +
        'WHERE MailNotesID = :MailNotesID AND IsDeleted = 0';
      Query.ParamByName('MailNotesID').AsString := EffectiveMailNotesID;
      Query.Open;

      if Query.Eof then
      begin
        FConnection.Commit;
        Exit;
      end;

      NoteID := Query.FieldByName('ID').AsInteger;
      Query.Close;

      NowUTC := GetCurrentUTC;
      Query.SQL.Text :=
        'UPDATE Note SET IsDeleted = 1, DeletedUTC = :DeletedUTC, ' +
        'IsFavorite = 0, ModifiedUTC = :ModifiedUTC ' +
        'WHERE ID = :NoteID AND IsDeleted = 0';
      Query.ParamByName('DeletedUTC').AsString := NowUTC;
      Query.ParamByName('ModifiedUTC').AsString := NowUTC;
      Query.ParamByName('NoteID').AsInteger := NoteID;
      Query.ExecSQL;
      Result := Query.RowsAffected > 0;

      if Result then
      begin
        Query.Close;
        Query.SQL.Text := 'DELETE FROM NoteTag WHERE NoteID = :NoteID';
        Query.ParamByName('NoteID').AsInteger := NoteID;
        Query.ExecSQL;

        Query.Close;
        Query.SQL.Text := 'DELETE FROM NotePerson WHERE NoteID = :NoteID';
        Query.ParamByName('NoteID').AsInteger := NoteID;
        Query.ExecSQL;

        Query.Close;
        Query.SQL.Text :=
          'DELETE FROM MailLink WHERE SourceMailNotesID = :MailNotesID';
        Query.ParamByName('MailNotesID').AsString := EffectiveMailNotesID;
        Query.ExecSQL;

        DeleteUnusedTags;
        DeleteUnusedPersons;
        UpdateSearchEntry(EffectiveMailNotesID);
      end;
    finally
      Query.Free;
    end;

    FConnection.Commit;
  except
    if FConnection.InTransaction then
      FConnection.Rollback;
    raise;
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
  LinkLines: TStringList;
  Line: string;
  Token: string;
  TargetInternetMessageID: string;
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
      ' M.SenderName, M.SenderAddress, M.ReceivedUTC, ' +
      ' TM.InternetMessageID AS TargetInternetMessageID ' +
      'FROM MailLink ML ' +
      'INNER JOIN Note N ON N.MailNotesID = ML.SourceMailNotesID ' +
      'INNER JOIN Mail M ON M.MailNotesID = N.MailNotesID ' +
      'INNER JOIN Mail TM ON TM.MailNotesID = ML.TargetMailNotesID ' +
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

      // Den exakt gespeicherten Link der Quellnotiz mitgeben. Dabei nicht
      // erneut über Outlook auflösen, sondern nur die in SQLite bekannten
      // stabilen Identitäten vergleichen.
      TargetInternetMessageID :=
        Query.FieldByName('TargetInternetMessageID').AsString;
      LinkLines := TStringList.Create;
      try
        LinkLines.Text := Note.Links;
        for Line in LinkLines do
        begin
          Token := ExtractMailNotesToken(Trim(Line));
          if (Token <> '') and
             (SameText(Token, TargetMailNotesID) or
              SameText(Token, TargetInternetMessageID)) then
          begin
            Note.BacklinkLink := Trim(Line);
            Break;
          end;
        end;
      finally
        LinkLines.Free;
      end;

      Result.Add(Note);
      Query.Next;
    end;
  except
    Result.Free;
    raise;
  end;

  Query.Free;
end;


function TDatabase.DeleteBacklink(
  const SourceMailNotesID, TargetToken, SourceLink: string
): Boolean;
var
  TargetMailNotesID: string;
  SourceNote: TNote;
  LinkLines: TStringList;
  Query: TFDQuery;
  I: Integer;
  Token: string;
  ResolvedTargetMailNotesID: string;
  LinksChanged: Boolean;
  NewLinks: string;
begin
  Result := False;

  if (Trim(SourceMailNotesID) = '') or (Trim(TargetToken) = '') then
    Exit;

  // Ausschließlich gegen die lokale MailNotes-Datenbank auflösen.
  // Die Outlook-Mail selbst muss zum Löschen nicht mehr existieren.
  TargetMailNotesID := FindMailNotesIDByToken(TargetToken);
  if TargetMailNotesID = '' then
    Exit;

  SourceNote := FindByMailNotesID(SourceMailNotesID);
  try
    LinksChanged := False;

    if Assigned(SourceNote) then
    begin
      LinkLines := TStringList.Create;
      try
        LinkLines.Text := SourceNote.Links;

        for I := LinkLines.Count - 1 downto 0 do
        begin
          // Bevorzugt exakt den Link löschen, den die Backlink-API aus der
          // Quellnotiz geliefert hat. Dadurch hängt das Entfernen nicht von
          // einer erneuten Zielauflösung ab.
          if (Trim(SourceLink) <> '') and
             SameText(Trim(LinkLines[I]), Trim(SourceLink)) then
          begin
            LinkLines.Delete(I);
            LinksChanged := True;
            Continue;
          end;

          // Fallback für ältere Clients bzw. Backlinks ohne sourceLink.
          Token := ExtractMailNotesToken(Trim(LinkLines[I]));
          if Token = '' then
            Continue;

          ResolvedTargetMailNotesID := FindMailNotesIDByToken(Token);
          if SameText(ResolvedTargetMailNotesID, TargetMailNotesID) then
          begin
            LinkLines.Delete(I);
            LinksChanged := True;
          end;
        end;

        if LinksChanged then
        begin
          NewLinks := LinkLines.Text;
          while NewLinks.EndsWith(sLineBreak) do
            Delete(
              NewLinks,
              Length(NewLinks) - Length(sLineBreak) + 1,
              Length(sLineBreak)
            );

          SourceNote.Links := NewLinks;
          Save(SourceNote);
          Result := True;
        end;
      finally
        LinkLines.Free;
      end;
    end;

    // Zusätzlich die persistierte Beziehung direkt entfernen. So kann auch
    // ein verwaister Backlink gelöscht werden, dessen ursprünglicher Linktext
    // inzwischen ungültig oder nicht mehr zuordenbar ist.
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'DELETE FROM MailLink ' +
        'WHERE SourceMailNotesID = :SourceMailNotesID ' +
        '  AND TargetMailNotesID = :TargetMailNotesID';
      Query.ParamByName('SourceMailNotesID').AsString := SourceMailNotesID;
      Query.ParamByName('TargetMailNotesID').AsString := TargetMailNotesID;
      Query.ExecSQL;

      if Query.RowsAffected > 0 then
        Result := True;
    finally
      Query.Free;
    end;
  finally
    SourceNote.Free;
  end;
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

function TDatabase.CompleteRepairQueueByIdentity(
  const MailNotesID, MessageID: string
): Boolean;
begin
  Result := False;

  if (MailNotesID = '') and (MessageID = '') then
    Exit;

  Result := FConnection.ExecSQL(
    'UPDATE SHLRepairQueue SET Status = 2, ModifiedUTC = :ModifiedUTC' +
    ' WHERE Status IN (0, 1)' +
    ' AND (MailNotesID = :MailNotesID OR InternetMessageID = :MessageID)',
    [GetCurrentUTC, MailNotesID, MessageID]
  ) > 0;
end;



procedure TDatabase.UpsertGraphAccount(
  const MailboxAddress, TenantID, UserID: string;
  const GraphState: Integer;
  const LastCheckedUTC, LastSuccessUTC, LastError: string
);
var
  Q: TFDQuery;
begin
  if Trim(MailboxAddress) = '' then
    raise Exception.Create('MailboxAddress darf nicht leer sein.');

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'INSERT INTO GraphAccount (' +
      ' MailboxAddress, TenantID, UserID, GraphState,' +
      ' LastCheckedUTC, LastSuccessUTC, LastError' +
      ') VALUES (' +
      ' :MailboxAddress, :TenantID, :UserID, :GraphState,' +
      ' :LastCheckedUTC, :LastSuccessUTC, :LastError' +
      ') ON CONFLICT(MailboxAddress) DO UPDATE SET ' +
      ' TenantID = COALESCE(NULLIF(excluded.TenantID, ''''), GraphAccount.TenantID),' +
      ' UserID = COALESCE(NULLIF(excluded.UserID, ''''), GraphAccount.UserID),' +
      ' GraphState = excluded.GraphState,' +
      ' LastCheckedUTC = excluded.LastCheckedUTC,' +
      ' LastSuccessUTC = COALESCE(NULLIF(excluded.LastSuccessUTC, ''''), GraphAccount.LastSuccessUTC),' +
      ' LastError = excluded.LastError';

    Q.ParamByName('MailboxAddress').AsString := Trim(LowerCase(MailboxAddress));
    Q.ParamByName('TenantID').AsString := Trim(TenantID);
    Q.ParamByName('UserID').AsString := Trim(UserID);
    Q.ParamByName('GraphState').AsInteger := GraphState;
    Q.ParamByName('LastCheckedUTC').AsString := LastCheckedUTC;
    Q.ParamByName('LastSuccessUTC').AsString := LastSuccessUTC;
    Q.ParamByName('LastError').AsString := LastError;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDatabase.LoadGraphAccount(
  const MailboxAddress: string;
  out TenantID, UserID: string;
  out GraphState: Integer;
  out LastCheckedUTC, LastSuccessUTC, LastError: string
): Boolean;
var
  Q: TFDQuery;
begin
  TenantID := '';
  UserID := '';
  GraphState := 0;
  LastCheckedUTC := '';
  LastSuccessUTC := '';
  LastError := '';

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'SELECT TenantID, UserID, GraphState, LastCheckedUTC, LastSuccessUTC, LastError ' +
      'FROM GraphAccount WHERE MailboxAddress = :MailboxAddress';
    Q.ParamByName('MailboxAddress').AsString := Trim(LowerCase(MailboxAddress));
    Q.Open;

    Result := not Q.Eof;
    if not Result then
      Exit;

    TenantID := Q.FieldByName('TenantID').AsString;
    UserID := Q.FieldByName('UserID').AsString;
    GraphState := Q.FieldByName('GraphState').AsInteger;
    LastCheckedUTC := Q.FieldByName('LastCheckedUTC').AsString;
    LastSuccessUTC := Q.FieldByName('LastSuccessUTC').AsString;
    LastError := Q.FieldByName('LastError').AsString;
  finally
    Q.Free;
  end;
end;

end.
