unit uGraphAccounts;

interface

uses
  System.SysUtils,
  uDatabase;

type
  TGraphState = (
    gsUnknown = 0,
    gsAvailable = 1,
    gsAuthRequired = 2,
    gsDenied = 3,
    gsUnavailable = 4
  );

  TGraphAccount = record
    MailboxAddress: string;
    TenantID: string;
    UserID: string;
    State: TGraphState;
    LastCheckedUTC: string;
    LastSuccessUTC: string;
    LastError: string;
  end;

  TGraphAccounts = class
  private
    FDatabase: TDatabase;
    function UTCNow: string;
    procedure SaveState(
      const MailboxAddress, TenantID, UserID: string;
      const State: TGraphState;
      const LastSuccessUTC, LastError: string
    );
  public
    constructor Create(ADatabase: TDatabase);

    function TryGet(const MailboxAddress: string; out Account: TGraphAccount): Boolean;
    procedure MarkAvailable(
      const MailboxAddress, TenantID, UserID: string
    );
    procedure MarkAuthRequired(const MailboxAddress, ErrorText: string);
    procedure MarkDenied(const MailboxAddress, ErrorText: string);
    procedure MarkUnavailable(const MailboxAddress, ErrorText: string);
  end;

implementation

uses
  System.DateUtils;

constructor TGraphAccounts.Create(ADatabase: TDatabase);
begin
  inherited Create;
  if ADatabase = nil then
    raise EArgumentNilException.Create('ADatabase');
  FDatabase := ADatabase;
end;

function TGraphAccounts.UTCNow: string;
begin
  Result := FormatDateTime(
    'yyyy-mm-dd"T"hh:nn:ss"Z"',
    TTimeZone.Local.ToUniversalTime(Now)
  );
end;

function TGraphAccounts.TryGet(
  const MailboxAddress: string;
  out Account: TGraphAccount
): Boolean;
var
  StateValue: Integer;
begin
  Account := Default(TGraphAccount);
  Account.MailboxAddress := Trim(LowerCase(MailboxAddress));

  Result := FDatabase.LoadGraphAccount(
    Account.MailboxAddress,
    Account.TenantID,
    Account.UserID,
    StateValue,
    Account.LastCheckedUTC,
    Account.LastSuccessUTC,
    Account.LastError
  );

  if Result and (StateValue >= Ord(Low(TGraphState))) and
    (StateValue <= Ord(High(TGraphState))) then
    Account.State := TGraphState(StateValue)
  else
    Account.State := gsUnknown;
end;

procedure TGraphAccounts.SaveState(
  const MailboxAddress, TenantID, UserID: string;
  const State: TGraphState;
  const LastSuccessUTC, LastError: string
);
begin
  FDatabase.UpsertGraphAccount(
    MailboxAddress,
    TenantID,
    UserID,
    Ord(State),
    UTCNow,
    LastSuccessUTC,
    LastError
  );
end;

procedure TGraphAccounts.MarkAvailable(
  const MailboxAddress, TenantID, UserID: string
);
var
  Timestamp: string;
begin
  Timestamp := UTCNow;
  FDatabase.UpsertGraphAccount(
    MailboxAddress,
    TenantID,
    UserID,
    Ord(gsAvailable),
    Timestamp,
    Timestamp,
    ''
  );
end;

procedure TGraphAccounts.MarkAuthRequired(
  const MailboxAddress, ErrorText: string
);
begin
  SaveState(MailboxAddress, '', '', gsAuthRequired, '', ErrorText);
end;

procedure TGraphAccounts.MarkDenied(
  const MailboxAddress, ErrorText: string
);
begin
  SaveState(MailboxAddress, '', '', gsDenied, '', ErrorText);
end;

procedure TGraphAccounts.MarkUnavailable(
  const MailboxAddress, ErrorText: string
);
begin
  SaveState(MailboxAddress, '', '', gsUnavailable, '', ErrorText);
end;

end.
