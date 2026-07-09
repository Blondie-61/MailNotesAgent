unit uDatabase;

interface

uses
  System.SysUtils,
  DateUtils,
  System.IOUtils,
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
  private
    FConnection: TFDConnection;

    function FindDatabasePath: string;
    function GetCurrentUTC: string;
end;

implementation

constructor TDatabase.Create;
begin
  inherited;

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
      '  ID, MessageID, ConversationID, Content, Links, ' +
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
      Result.Content        := Query.FieldByName('Content'       ).AsString;
      Result.Links          := Query.FieldByName('Links'         ).AsString;
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

procedure TDatabase.Save(Note: TNote);
var
  Query: TFDQuery;
  NowUTC: string;
begin
  if not Assigned(Note) then
    raise Exception.Create('Note is not assigned.');

  NowUTC :=  GetCurrentUTC;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;

    if not FConnection.InTransaction then
      FConnection.StartTransaction;
    try
      if Note.ID = 0 then
      begin
        Note.CreatedAt  := NowUTC;
        Note.ModifiedAt := NowUTC;

        Query.SQL.Text :=
          'INSERT INTO Note ' +
          '(MessageID, ConversationID, Content, Links, CreatedAt, ModifiedAt, IsFavorite, IsDeleted) ' +
          'VALUES ' +
          '(:MessageID, :ConversationID, :Content, :Links, :CreatedAt, :ModifiedAt, :IsFavorite, 0)';

        Query.ParamByName('MessageID'     ).AsString  := Note.MessageID;
        Query.ParamByName('ConversationID').AsString  := Note.ConversationID;
        Query.ParamByName('Content'       ).AsString  := Note.Content;
        Query.ParamByName('Links'         ).AsString  := Note.Links;
        Query.ParamByName('CreatedAt'     ).AsString  := Note.CreatedAt;
        Query.ParamByName('ModifiedAt'    ).AsString  := Note.ModifiedAt;
        Query.ParamByName('IsFavorite'    ).AsInteger := Ord(Note.IsFavorite);

        Query.ExecSQL;

        Note.ID := FConnection.GetLastAutoGenValue('');
      end
      else
      begin
        Note.ModifiedAt := NowUTC;

        Query.SQL.Text :=
          'UPDATE Note SET ' +
          'ConversationID = :ConversationID, ' +
          'Content = :Content, ' +
          'Links = :Links, ' +
          'ModifiedAt = :ModifiedAt, ' +
          'IsFavorite = :IsFavorite ' +
          'WHERE ID = :ID';

        Query.ParamByName('ConversationID').AsString  := Note.ConversationID;
        Query.ParamByName('Content'       ).AsString  := Note.Content;
        Query.ParamByName('Links'         ).AsString  := Note.Links;
        Query.ParamByName('ModifiedAt'    ).AsString  := Note.ModifiedAt;
        Query.ParamByName('IsFavorite'    ).AsInteger := Ord(Note.IsFavorite);
        Query.ParamByName('ID'            ).AsInteger := Note.ID;

        Query.ExecSQL;
      end;

      FConnection.Commit;

    except
      FConnection.Rollback;
      raise;
    end;

  finally
    Query.Free;
  end;
end;

end.
