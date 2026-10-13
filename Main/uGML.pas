unit uGML;

interface

uses
  uDatabase,
  uNote;

type
  TGML = class sealed
  public
    class function TryEnrichMailIdentity(
      ADatabase: TDatabase;
      Note: TNote;
      out ErrorText: string
    ): Boolean; static;
    class function TryRefreshSRLFromGML(
      ADatabase: TDatabase;
      Note: TNote;
      out ErrorText: string
    ): Boolean; static;
    class function TryGetWebLink(
      ADatabase: TDatabase;
      Note: TNote;
      out WebLink: string;
      out ErrorText: string
    ): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uGraphAccounts,
  uGraphAuth,
  uGraphClient,
  uGraphTokenStore;

class function TGML.TryEnrichMailIdentity(
  ADatabase: TDatabase;
  Note: TNote;
  out ErrorText: string
): Boolean;
var
  GraphAccounts: TGraphAccounts;
  Account: TGraphAccount;
  StoredRefreshToken: string;
  Tokens: TGraphTokenResult;
  UserInfo: TGraphUserInfo;
  ImmutableID: string;
  MailboxAddress: string;
begin
  Result := False;
  ErrorText := '';

  if (ADatabase = nil) or (Note = nil) then
  begin
    ErrorText := 'Datenbank oder Mail fehlt.';
    Exit;
  end;

  // GML ist eine zusaetzliche Identitaet. Eine vorhandene ImmutableID bleibt
  // unangetastet; insbesondere wird die SRL-ItemID niemals ersetzt.
  if Note.ImmutableID <> '' then
    Exit(True);

  MailboxAddress := Trim(LowerCase(Note.MailboxAddress));
  if (MailboxAddress = '') or (Note.ItemID = '') then
  begin
    ErrorText := 'MailboxAddress oder ItemID fehlt.';
    Exit;
  end;

  GraphAccounts := TGraphAccounts.Create(ADatabase);
  try
    if not GraphAccounts.TryGet(MailboxAddress, Account) then
    begin
      // Kein interaktiver Dialog aus einem HTTP-Workerthread heraus.
      // Ohne eingerichtetes Graph-Konto bleibt der SRL-Fallback aktiv.
      ErrorText := 'Fuer dieses Konto ist Graph noch nicht eingerichtet.';
      Exit;
    end;

    if Account.State <> gsAvailable then
    begin
      ErrorText := 'Graph ist fuer dieses Konto derzeit nicht verfuegbar.';
      Exit;
    end;

    if not TGraphTokenStore.LoadRefreshToken(
      MailboxAddress, StoredRefreshToken) then
    begin
      GraphAccounts.MarkAuthRequired(
        MailboxAddress, 'Kein gespeicherter Refresh Token.'
      );
      ErrorText := 'Kein gespeicherter Refresh Token.';
      Exit;
    end;

    if not TGraphAuth.RefreshAccessToken(
      StoredRefreshToken, Tokens, ErrorText) then
    begin
      GraphAccounts.MarkAuthRequired(MailboxAddress, ErrorText);
      Exit;
    end;

    if Tokens.RefreshToken <> '' then
      TGraphTokenStore.SaveRefreshToken(
        MailboxAddress, Tokens.RefreshToken
      );

    if not TGraphAuth.GetMe(Tokens.AccessToken, UserInfo, ErrorText) then
    begin
      GraphAccounts.MarkUnavailable(MailboxAddress, ErrorText);
      Exit;
    end;

    if (Account.UserID <> '') and
       not SameText(Account.UserID, UserInfo.ID) then
    begin
      ErrorText := 'Graph Token gehoert zu einem anderen Benutzer.';
      GraphAccounts.MarkDenied(MailboxAddress, ErrorText);
      Exit;
    end;

    if not TGraphClient.TranslateExchangeID(
      Tokens.AccessToken,
      Note.ItemID,
      'ewsId',
      'restImmutableEntryId',
      ImmutableID,
      ErrorText
    ) then
    begin
      // Die ItemID kann z.B. nach einem Verschieben bereits veraltet sein.
      // Das ist kein Grund, Graph fuer das gesamte Konto abzuschalten.
      Exit;
    end;

    Note.ImmutableID := ImmutableID;
    GraphAccounts.MarkAvailable(
      MailboxAddress,
      TGraphAuth.ConfiguredTenantID,
      UserInfo.ID
    );
    Result := True;
  finally
    GraphAccounts.Free;
  end;
end;

class function TGML.TryRefreshSRLFromGML(
  ADatabase: TDatabase;
  Note: TNote;
  out ErrorText: string
): Boolean;
var
  GraphAccounts: TGraphAccounts;
  Account: TGraphAccount;
  StoredRefreshToken: string;
  Tokens: TGraphTokenResult;
  UserInfo: TGraphUserInfo;
  CurrentItemID: string;
  MailboxAddress: string;
begin
  Result := False;
  ErrorText := '';

  if (ADatabase = nil) or (Note = nil) then
  begin
    ErrorText := 'Datenbank oder Mail fehlt.';
    Exit;
  end;

  MailboxAddress := Trim(LowerCase(Note.MailboxAddress));
  if (MailboxAddress = '') or (Note.ImmutableID = '') then
  begin
    ErrorText := 'MailboxAddress oder ImmutableID fehlt.';
    Exit;
  end;

  GraphAccounts := TGraphAccounts.Create(ADatabase);
  try
    if not GraphAccounts.TryGet(MailboxAddress, Account) then
    begin
      // Kein interaktiver Dialog aus einem HTTP-Workerthread heraus.
      // Ohne eingerichtetes Graph-Konto bleibt der SRL-Fallback aktiv.
      ErrorText := 'Fuer dieses Konto ist Graph noch nicht eingerichtet.';
      Exit;
    end;

    if Account.State <> gsAvailable then
    begin
      ErrorText := 'Graph ist fuer dieses Konto derzeit nicht verfuegbar.';
      Exit;
    end;

    if not TGraphTokenStore.LoadRefreshToken(
      MailboxAddress, StoredRefreshToken) then
    begin
      GraphAccounts.MarkAuthRequired(
        MailboxAddress, 'Kein gespeicherter Refresh Token.'
      );
      ErrorText := 'Kein gespeicherter Refresh Token.';
      Exit;
    end;

    if not TGraphAuth.RefreshAccessToken(
      StoredRefreshToken, Tokens, ErrorText) then
    begin
      GraphAccounts.MarkAuthRequired(MailboxAddress, ErrorText);
      Exit;
    end;

    if Tokens.RefreshToken <> '' then
      TGraphTokenStore.SaveRefreshToken(
        MailboxAddress, Tokens.RefreshToken
      );

    if not TGraphAuth.GetMe(Tokens.AccessToken, UserInfo, ErrorText) then
    begin
      GraphAccounts.MarkUnavailable(MailboxAddress, ErrorText);
      Exit;
    end;

    if (Account.UserID <> '') and
       not SameText(Account.UserID, UserInfo.ID) then
    begin
      ErrorText := 'Graph Token gehoert zu einem anderen Benutzer.';
      GraphAccounts.MarkDenied(MailboxAddress, ErrorText);
      Exit;
    end;

    if not TGraphClient.TranslateExchangeID(
      Tokens.AccessToken,
      Note.ImmutableID,
      'restImmutableEntryId',
      'ewsId',
      CurrentItemID,
      ErrorText
    ) then
      Exit;

    if CurrentItemID = '' then
    begin
      ErrorText := 'Graph hat keine aktuelle EWS-ID geliefert.';
      Exit;
    end;

    // GML repariert nur die SRL. Die ImmutableID bleibt unveraendert erhalten.
    Note.ItemID := CurrentItemID;
    ADatabase.RefreshMailIdentity(Note);

    GraphAccounts.MarkAvailable(
      MailboxAddress,
      TGraphAuth.ConfiguredTenantID,
      UserInfo.ID
    );
    Result := True;
  finally
    GraphAccounts.Free;
  end;
end;

class function TGML.TryGetWebLink(
  ADatabase: TDatabase;
  Note: TNote;
  out WebLink: string;
  out ErrorText: string
): Boolean;
var
  GraphAccounts: TGraphAccounts;
  Account: TGraphAccount;
  StoredRefreshToken: string;
  Tokens: TGraphTokenResult;
  UserInfo: TGraphUserInfo;
  Mail: TGraphMailInfo;
  MailboxAddress: string;
begin
  Result := False;
  WebLink := '';
  ErrorText := '';

  if (ADatabase = nil) or (Note = nil) then
  begin
    ErrorText := 'Datenbank oder Mail fehlt.';
    Exit;
  end;

  MailboxAddress := Trim(LowerCase(Note.MailboxAddress));
  if (MailboxAddress = '') or (Note.ImmutableID = '') then
  begin
    ErrorText := 'MailboxAddress oder ImmutableID fehlt.';
    Exit;
  end;

  GraphAccounts := TGraphAccounts.Create(ADatabase);
  try
    if not GraphAccounts.TryGet(MailboxAddress, Account) then
    begin
      // Kein interaktiver Dialog aus einem HTTP-Workerthread heraus.
      // Ohne eingerichtetes Graph-Konto bleibt der SRL-Fallback aktiv.
      ErrorText := 'Fuer dieses Konto ist Graph noch nicht eingerichtet.';
      Exit;
    end;

    if Account.State <> gsAvailable then
    begin
      ErrorText := 'Graph ist fuer dieses Konto derzeit nicht verfuegbar.';
      Exit;
    end;

    if not TGraphTokenStore.LoadRefreshToken(
      MailboxAddress, StoredRefreshToken) then
    begin
      GraphAccounts.MarkAuthRequired(
        MailboxAddress, 'Kein gespeicherter Refresh Token.'
      );
      ErrorText := 'Kein gespeicherter Refresh Token.';
      Exit;
    end;

    if not TGraphAuth.RefreshAccessToken(
      StoredRefreshToken, Tokens, ErrorText) then
    begin
      GraphAccounts.MarkAuthRequired(MailboxAddress, ErrorText);
      Exit;
    end;

    if Tokens.RefreshToken <> '' then
      TGraphTokenStore.SaveRefreshToken(
        MailboxAddress, Tokens.RefreshToken
      );

    if not TGraphAuth.GetMe(Tokens.AccessToken, UserInfo, ErrorText) then
    begin
      GraphAccounts.MarkUnavailable(MailboxAddress, ErrorText);
      Exit;
    end;

    if (Account.UserID <> '') and
       not SameText(Account.UserID, UserInfo.ID) then
    begin
      ErrorText := 'Graph Token gehoert zu einem anderen Benutzer.';
      GraphAccounts.MarkDenied(MailboxAddress, ErrorText);
      Exit;
    end;

    if not TGraphClient.GetMailByImmutableID(
      Tokens.AccessToken, Note.ImmutableID, Mail, ErrorText) then
      Exit;

    WebLink := Mail.WebLink;
    if WebLink = '' then
    begin
      ErrorText := 'Graph hat keinen WebLink geliefert.';
      Exit;
    end;

    GraphAccounts.MarkAvailable(
      MailboxAddress,
      TGraphAuth.ConfiguredTenantID,
      UserInfo.ID
    );
    Result := True;
  finally
    GraphAccounts.Free;
  end;
end;

end.
