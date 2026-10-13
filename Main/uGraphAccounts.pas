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
    function OfferSetupOnce(const MailboxAddress: string): Boolean;
  end;

implementation

uses
  System.DateUtils,
  uGraphAuth,
  uGraphTokenStore
{$IF Defined(MSWINDOWS)}
  , Winapi.Windows
{$ENDIF}
  ;

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


function TGraphAccounts.OfferSetupOnce(const MailboxAddress: string): Boolean;
var
  NormalizedMailbox: string;
  Existing: TGraphAccount;
{$IF Defined(MSWINDOWS)}
  Verifier: string;
  AuthResult: TGraphAuthorizationResult;
  Tokens: TGraphTokenResult;
  UserInfo: TGraphUserInfo;
  ErrorText: string;
  SignedInMailbox: string;
{$ENDIF}
begin
  Result := False;
  NormalizedMailbox := Trim(LowerCase(MailboxAddress));
  if NormalizedMailbox = '' then
    Exit;

  // Nur anbieten, wenn fuer dieses Konto noch nie eine Entscheidung gespeichert
  // wurde. Damit erscheint die Frage exakt einmal pro Konto und Installation.
  if TryGet(NormalizedMailbox, Existing) then
    Exit(Existing.State = gsAvailable);

{$IF Defined(MSWINDOWS)}
  // Bereits VOR dem Dialog persistent markieren. Auch "Nein", Abbruch, Timeout
  // oder ein fehlgeschlagener Login fuehren daher nicht zu einer Frageschleife.
  MarkDenied(NormalizedMailbox, 'Graph-Einrichtung wurde bereits angeboten.');

  if MessageBoxW(
    0,
    PWideChar(
      'Microsoft Graph ist f' + WideChar($00FC) + 'r dieses Postfach noch nicht eingerichtet.' +
      sLineBreak + sLineBreak +
      'Jetzt einmalig f' + WideChar($00FC) + 'r ' + NormalizedMailbox + ' einrichten?'
    ),
    'MailNotes - Microsoft Graph',
    MB_YESNO or MB_ICONQUESTION or MB_DEFBUTTON1
  ) <> IDYES then
    Exit;

  if not TGraphAuth.Authorize(Verifier, AuthResult) then
    Exit;

  if not TGraphAuth.ExchangeAuthorizationCode(
    AuthResult.AuthorizationCode, Verifier, Tokens, ErrorText) then
    Exit;

  if not TGraphAuth.GetMe(Tokens.AccessToken, UserInfo, ErrorText) then
    Exit;

  SignedInMailbox := Trim(LowerCase(UserInfo.Mail));
  if SignedInMailbox = '' then
    SignedInMailbox := Trim(LowerCase(UserInfo.UserPrincipalName));

  // Verhindert, dass versehentlich ein anderes Microsoft-Konto dem Zielpostfach
  // zugeordnet wird. Erneute bewusste Anmeldung bleibt ueber das Tray moeglich.
  if not SameText(SignedInMailbox, NormalizedMailbox) then
  begin
    MarkDenied(
      NormalizedMailbox,
      'Bei Graph wurde ein anderes Konto angemeldet: ' + SignedInMailbox
    );
    MessageBoxW(
      0,
      PWideChar(
        'Angemeldet wurde ' + SignedInMailbox + ',' + sLineBreak +
        'ben' + WideChar($00F6) + 'tigt wird aber ' + NormalizedMailbox + '.' +
        sLineBreak + sLineBreak +
        'Bitte die Graph-Anmeldung bei Bedarf ' + WideChar($00FC) +
        'ber das Tray-Men' + WideChar($00FC) + ' erneut starten.'
      ),
      'MailNotes - Microsoft Graph',
      MB_OK or MB_ICONWARNING
    );
    Exit;
  end;

  if Tokens.RefreshToken = '' then
    Exit;

  TGraphTokenStore.SaveRefreshToken(NormalizedMailbox, Tokens.RefreshToken);
  MarkAvailable(
    NormalizedMailbox,
    TGraphAuth.ConfiguredTenantID,
    UserInfo.ID
  );
  Result := True;

  MessageBoxW(
    0,
    PWideChar(
      'Microsoft Graph ist jetzt f' + WideChar($00FC) + 'r ' +
      NormalizedMailbox + ' eingerichtet.'
    ),
    'MailNotes - Microsoft Graph',
    MB_OK or MB_ICONINFORMATION
  );
{$ENDIF}
end;

end.
