unit uNote;

interface

type
  TNote = class
  public
    ID: Integer;
    MailNotesID: string;

    ItemID: string;
    ImmutableID: string;
    MessageID: string;
    ConversationID: string;
    MailboxAddress: string;

    Content: string;
    Links: string;

    CreatedAt: string;
    ModifiedAt: string;

    IsFavorite: Boolean;
    IsDeleted: Boolean;
    DeletedAt: string;

    Subject: string;
    SenderName: string;
    SenderAddress: string;
    MailDate: string;

    SearchSnippet: string;
    SearchRank: Double;

    // Nur für die Backlink-API: exakt gespeicherter Link in der Quellnotiz.
    BacklinkLink: string;

    constructor Create; overload;
    constructor Create(const AMessageID: string); overload;
  end;

implementation

constructor TNote.Create;
begin
  inherited Create;

  IsFavorite := False;
  IsDeleted := False;
  Links := '[]';
end;

constructor TNote.Create(const AMessageID: string);
begin
  Create;
  MessageID := AMessageID;
end;

end.
