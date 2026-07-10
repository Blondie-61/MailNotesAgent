unit uNote;

interface

type
  TNote = class
  public
    ID: Integer;
    MessageID: string;
    ConversationID: string;
    Content: string;
    Links: string;

    CreatedAt: string;
    ModifiedAt: string;

    IsFavorite: Boolean;
    IsDeleted: Boolean;
    DeletedAt: string;

    Subject: string;
    SenderName: string;
    MailDate: string;

    constructor Create; overload;
    constructor Create(const AMessageID: string); overload;
  end;

implementation

constructor TNote.Create;
begin
  inherited Create;

  IsFavorite := False;
  IsDeleted := False;
end;

constructor TNote.Create(const AMessageID: string);
begin
  Create;
  MessageID := AMessageID;
end;

end.
