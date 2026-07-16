unit uRepairQueue;

interface

type
  TRepairQueueItem = class
  public
    ID: Integer;
    MailNotesID: string;
    OldItemID: string;
    MessageID: string;
    Subject: string;
    SenderName: string;
    SenderAddress: string;
    MailDate: string;
    Reason: string;
    CreatedAt: string;
    ModifiedAt: string;
    RetryCount: Integer;
    Status: Integer;
  end;

const
  REPAIR_STATUS_PENDING = 0;
  REPAIR_STATUS_SEARCHING = 1;
  REPAIR_STATUS_REPAIRED = 2;
  REPAIR_STATUS_SKIPPED = 3;

implementation

end.
