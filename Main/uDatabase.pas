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

  uNote;

type
  TDatabase = class
  public
    constructor Create;
    destructor Destroy; override;

    procedure Open;
    procedure Close;

    procedure Save(Note: TNote);

    function FindByMessageID(const MessageID: string): TNote;
    function GetBacklinks(
      const TargetMessageID: string
    ): TObjectList<TNote>;

  private
    FConnection: TFDConnection;

    function FindDatabasePath: string;
    function GetCurrentUTC: string;

    procedure UpdateMailLinks(
      const SourceMessageID: string;
      const Links: string
    );

    function ExtractMailNotesMessageID(
      const Link: string
    ): string;
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
end;

procedure TDatabase.Close;
begin
  if FConnection.Connected then
    FConnection.Close;
end;

function TDatabase.FindByMessageID(const MessageID: string): TNote;
var
  Query: TFDQuery;
begin
  Result := nil;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;

    Query.SQL.Text :=
      'SELECT ' +
      '  ID, MessageID, ConversationID, ItemID, Content, Links, ' +
      '  Subject, SenderName, MailDate, ' +
      '  CreatedAt, ModifiedAt, IsFavorite, IsDeleted, DeletedAt ' +
      'FROM Note ' +
      'WHERE MessageID = :MessageID ' +
      '  AND IsDeleted = 0 ' +
      'LIMIT 1';

    Query.ParamByName('MessageID').AsString := MessageID;
    Query.Open;

    if not Query.Eof then
    begin
      Result := TNote.Create;

      Result.ID             := Query.FieldByName('ID'            ).AsInteger;
      Result.MessageID      := Query.FieldByName('MessageID'     ).AsString;
      Result.ConversationID := Query.FieldByName('ConversationID').AsString;
      Result.ItemID         := Query.FieldByName('ItemID'        ).AsString;
      Result.Content        := Query.FieldByName('Content'       ).AsString;
      Result.Links          := Query.FieldByName('Links'         ).AsString;
      Result.Subject        := Query.FieldByName('Subject'       ).AsString;
      Result.SenderName     := Query.FieldByName('SenderName'    ).AsString;
      Result.MailDate       := Query.FieldByName('MailDate'      ).AsString;
      Result.CreatedAt      := Query.FieldByName('CreatedAt'     ).AsString;
      Result.ModifiedAt     := Query.FieldByName('ModifiedAt'    ).AsString;
      Result.IsFavorite     := Query.FieldByName('IsFavorite'    ).AsInteger <> 0;
      Result.IsDeleted      := Query.FieldByName('IsDeleted'     ).AsInteger <> 0;
      Result.DeletedAt      := Query.FieldByName('DeletedAt'     ).AsString;
    end;

  finally
    Query.Free;
  end;
end;

function TDatabase.FindDatabasePath: string;
var
  BaseDir: string;
  Candidate: string;
  I: Integer;
begin
  BaseDir :=
    TPath.GetFullPath(ExtractFilePath(ParamStr(0)));

  for I := 0 to 6 do
  begin
    Candidate := TPath.Combine(
      TPath.Combine(BaseDir, 'Data'),
      'MailNotes.sqlite'
    );

    if TFile.Exists(Candidate) then
      Exit(Candidate);

    BaseDir :=
      TPath.GetFullPath(TPath.Combine(BaseDir, '..'));
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

procedure TDatabase.Save(Note: TNote);
var
  Query: TFDQuery;
  NowUTC: string;
begin
  if not Assigned(Note) then
    raise Exception.Create('Note is not assigned.');

  NowUTC := GetCurrentUTC;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;

    if not FConnection.InTransaction then
      FConnection.StartTransaction;

    try
      if Note.ID = 0 then
      begin
        Note.CreatedAt := NowUTC;
        Note.ModifiedAt := NowUTC;

        Query.SQL.Text :=
          'INSERT INTO Note ' +
          '(' +
          '  MessageID, ConversationID, ItemID, Subject, SenderName, ' +
          '  MailDate, Content, Links, CreatedAt, ModifiedAt, ' +
          '  IsFavorite, IsDeleted' +
          ') ' +
          'VALUES ' +
          '(' +
          '  :MessageID, :ConversationID, :ItemID, :Subject, :SenderName, ' +
          '  :MailDate, :Content, :Links, :CreatedAt, :ModifiedAt, ' +
          '  :IsFavorite, 0' +
          ')';

        Query.ParamByName('MessageID').AsString :=
          Note.MessageID;

        Query.ParamByName('ConversationID').AsString :=
          Note.ConversationID;

        Query.ParamByName('ItemID').AsString :=
          Note.ItemID;

        Query.ParamByName('Subject').AsString :=
          Note.Subject;

        Query.ParamByName('SenderName').AsString :=
          Note.SenderName;

        Query.ParamByName('MailDate').AsString :=
          Note.MailDate;

        Query.ParamByName('Content').AsString :=
          Note.Content;

        Query.ParamByName('Links').AsString :=
          Note.Links;

        Query.ParamByName('CreatedAt').AsString :=
          Note.CreatedAt;

        Query.ParamByName('ModifiedAt').AsString :=
          Note.ModifiedAt;

        Query.ParamByName('IsFavorite').AsInteger :=
          Ord(Note.IsFavorite);

        Query.ExecSQL;

        Note.ID :=
          FConnection.GetLastAutoGenValue('');
      end
      else
      begin
        Note.ModifiedAt := NowUTC;

        Query.SQL.Text :=
          'UPDATE Note SET ' +
          '  ConversationID = :ConversationID, ' +
          '  ItemID = :ItemID, ' +
          '  Subject = :Subject, ' +
          '  SenderName = :SenderName, ' +
          '  MailDate = :MailDate, ' +
          '  Content = :Content, ' +
          '  Links = :Links, ' +
          '  ModifiedAt = :ModifiedAt, ' +
          '  IsFavorite = :IsFavorite ' +
          'WHERE ID = :ID';

        Query.ParamByName('ConversationID').AsString :=
          Note.ConversationID;

        Query.ParamByName('ItemID').AsString :=
          Note.ItemID;

        Query.ParamByName('Subject').AsString :=
          Note.Subject;

        Query.ParamByName('SenderName').AsString :=
          Note.SenderName;

        Query.ParamByName('MailDate').AsString :=
          Note.MailDate;

        Query.ParamByName('Content').AsString :=
          Note.Content;

        Query.ParamByName('Links').AsString :=
          Note.Links;

        Query.ParamByName('ModifiedAt').AsString :=
          Note.ModifiedAt;

        Query.ParamByName('IsFavorite').AsInteger :=
          Ord(Note.IsFavorite);

        Query.ParamByName('ID').AsInteger :=
          Note.ID;

        Query.ExecSQL;
      end;

      UpdateMailLinks(
        Note.MessageID,
        Note.Links
      );

      FConnection.Commit;

    except
      if FConnection.InTransaction then
        FConnection.Rollback;

      raise;
    end;

  finally
    Query.Free;
  end;
end;

procedure TDatabase.UpdateMailLinks(
  const SourceMessageID: string;
  const Links: string
);
var
  Query: TFDQuery;
  LinkLines: TStringList;
  Line: string;
  TargetMessageID: string;
begin
  Query := TFDQuery.Create(nil);
  LinkLines := TStringList.Create;

  try
    Query.Connection := FConnection;

    Query.SQL.Text :=
      'DELETE FROM MailLink ' +
      'WHERE SourceMessageID = :SourceMessageID';

    Query.ParamByName('SourceMessageID').AsString :=
      SourceMessageID;

    Query.ExecSQL;

    LinkLines.Text := Links;

    for Line in LinkLines do
    begin
      TargetMessageID :=
        ExtractMailNotesMessageID(Trim(Line));

      if TargetMessageID = '' then
        Continue;

      { Keine Verknüpfung einer Mail mit sich selbst. }
      if SameText(TargetMessageID, SourceMessageID) then
        Continue;

      Query.Close;

      Query.SQL.Text :=
        'INSERT OR IGNORE INTO MailLink ' +
        '(' +
        '  SourceMessageID, TargetMessageID, CreatedAt' +
        ') ' +
        'VALUES ' +
        '(' +
        '  :SourceMessageID, :TargetMessageID, :CreatedAt' +
        ')';

      Query.ParamByName('SourceMessageID').AsString :=
        SourceMessageID;

      Query.ParamByName('TargetMessageID').AsString :=
        TargetMessageID;

      Query.ParamByName('CreatedAt').AsString :=
        GetCurrentUTC;

      Query.ExecSQL;
    end;

  finally
    LinkLines.Free;
    Query.Free;
  end;
end;

function TDatabase.ExtractMailNotesMessageID(
  const Link: string
): string;
var
  EncodedMessageID: string;
begin
  Result := '';

  if not Link.StartsWith('mailnotes:', True) then
    Exit;

  EncodedMessageID :=
    Copy(
      Link,
      Length('mailnotes:') + 1,
      MaxInt
    );

  if EncodedMessageID = '' then
    Exit;

  try
    Result :=
      TNetEncoding.URL.Decode(EncodedMessageID);
  except
    Result := EncodedMessageID;
  end;
end;

function TDatabase.GetBacklinks(
  const TargetMessageID: string
): TObjectList<TNote>;
var
  Query: TFDQuery;
  Note: TNote;
begin
  Result := TObjectList<TNote>.Create(True);

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;

    Query.SQL.Text :=
      'SELECT ' +
      '  N.ID, N.MessageID, N.ConversationID, ' +
      '  N.Subject, N.SenderName, N.MailDate, ' +
      '  N.Content, N.Links, N.CreatedAt, N.ModifiedAt, ' +
      '  N.IsFavorite, N.IsDeleted, N.DeletedAt ' +
      'FROM MailLink ML ' +
      'INNER JOIN Note N ' +
      '  ON N.MessageID = ML.SourceMessageID ' +
      'WHERE ML.TargetMessageID = :TargetMessageID ' +
      '  AND N.IsDeleted = 0 ' +
      'ORDER BY N.MailDate DESC';

    Query.ParamByName('TargetMessageID').AsString :=
      TargetMessageID;

    Query.Open;

    while not Query.Eof do
    begin
      Note := TNote.Create;

      Note.ID :=
        Query.FieldByName('ID').AsInteger;

      Note.MessageID :=
        Query.FieldByName('MessageID').AsString;

      Note.ConversationID :=
        Query.FieldByName('ConversationID').AsString;

      Note.Subject :=
        Query.FieldByName('Subject').AsString;

      Note.SenderName :=
        Query.FieldByName('SenderName').AsString;

      Note.MailDate :=
        Query.FieldByName('MailDate').AsString;

      Note.Content :=
        Query.FieldByName('Content').AsString;

      Note.Links :=
        Query.FieldByName('Links').AsString;

      Note.CreatedAt :=
        Query.FieldByName('CreatedAt').AsString;

      Note.ModifiedAt :=
        Query.FieldByName('ModifiedAt').AsString;

      Note.IsFavorite :=
        Query.FieldByName('IsFavorite').AsInteger <> 0;

      Note.IsDeleted :=
        Query.FieldByName('IsDeleted').AsInteger <> 0;

      Note.DeletedAt :=
        Query.FieldByName('DeletedAt').AsString;

      Result.Add(Note);

      Query.Next;
    end;

  except
    Result.Free;
    raise;
  end;

  Query.Free;
end;

end.
