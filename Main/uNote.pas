unit uNote;

interface

type
  TNote = class
  public
    ID: Integer;
    MessageID: string;
    ConversationID: string;
    Content: string;
    CreatedAt: string;
    ModifiedAt: string;
    IsFavorite: Boolean;

    constructor Create; overload;
    constructor Create(const AMessageID: string); overload;
  end;

implementation

constructor TNote.Create;
begin
  inherited Create;
  IsFavorite := False;
end;

constructor TNote.Create(const AMessageID: string);
begin
  Create;
  MessageID := AMessageID;
end;

end.
