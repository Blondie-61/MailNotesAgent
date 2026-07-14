unit uLinkBuffer;

interface

type
  TLinkBuffer = class
  public
    MailNotesID: string;

    MessageID: string;
    ItemID: string;
    ImmutableID: string;
    ConversationID: string;
    MailboxAddress: string;

    Subject: string;
    SenderName: string;
    SenderAddress: string;
    MailDate: string;

    CreatedAt: string;
    ModifiedAt: string;
  end;

implementation

end.
