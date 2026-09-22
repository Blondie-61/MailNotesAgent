unit uGraphTokenStore;

interface

uses
  System.SysUtils;

type
  TGraphTokenStore = class sealed
  private
    class function TokenFileName(const MailboxAddress: string): string; static;
  public
    class procedure SaveRefreshToken(
      const MailboxAddress, RefreshToken: string
    ); static;
    class function LoadRefreshToken(
      const MailboxAddress: string;
      out RefreshToken: string
    ): Boolean; static;
    class procedure DeleteRefreshToken(
      const MailboxAddress: string
    ); static;
  end;

implementation

uses
  System.Classes,
  System.Hash,
  System.IOUtils,
  System.NetEncoding,
  uAppPaths
{$IF Defined(MSWINDOWS)}
  , Winapi.Windows
{$ELSEIF Defined(MACOS)}
  , Macapi.CoreFoundation
{$ENDIF}
  ;

{$IF Defined(MSWINDOWS)}
type
  PDataBlob = ^TDataBlob;
  TDataBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;

function CryptProtectData(
  pDataIn: PDataBlob;
  szDataDescr: LPCWSTR;
  pOptionalEntropy: PDataBlob;
  pvReserved: Pointer;
  pPromptStruct: Pointer;
  dwFlags: DWORD;
  pDataOut: PDataBlob
): BOOL; stdcall; external 'crypt32.dll';

function CryptUnprotectData(
  pDataIn: PDataBlob;
  ppszDataDescr: PLPWSTR;
  pOptionalEntropy: PDataBlob;
  pvReserved: Pointer;
  pPromptStruct: Pointer;
  dwFlags: DWORD;
  pDataOut: PDataBlob
): BOOL; stdcall; external 'crypt32.dll';

const
  CRYPTPROTECT_UI_FORBIDDEN = $00000001;
{$ENDIF}

{$IF Defined(MACOS)}
type
  OSStatus = Integer;
  SecKeychainItemRef = Pointer;
  PSecKeychainItemRef = ^SecKeychainItemRef;

const
  errSecSuccess = 0;
  errSecItemNotFound = -25300;
  GraphKeychainService = 'MailNotes Microsoft Graph';

function SecKeychainAddGenericPassword(
  keychain: Pointer;
  serviceNameLength: UInt32;
  serviceName: Pointer;
  accountNameLength: UInt32;
  accountName: Pointer;
  passwordLength: UInt32;
  passwordData: Pointer;
  itemRef: PSecKeychainItemRef
): OSStatus; cdecl; external '/System/Library/Frameworks/Security.framework/Security';

function SecKeychainFindGenericPassword(
  keychainOrArray: Pointer;
  serviceNameLength: UInt32;
  serviceName: Pointer;
  accountNameLength: UInt32;
  accountName: Pointer;
  passwordLength: PUInt32;
  passwordData: PPointer;
  itemRef: PSecKeychainItemRef
): OSStatus; cdecl; external '/System/Library/Frameworks/Security.framework/Security';

function SecKeychainItemModifyAttributesAndData(
  itemRef: SecKeychainItemRef;
  attrList: Pointer;
  length: UInt32;
  data: Pointer
): OSStatus; cdecl; external '/System/Library/Frameworks/Security.framework/Security';

function SecKeychainItemDelete(
  itemRef: SecKeychainItemRef
): OSStatus; cdecl; external '/System/Library/Frameworks/Security.framework/Security';

function SecKeychainItemFreeContent(
  attrList: Pointer;
  data: Pointer
): OSStatus; cdecl; external '/System/Library/Frameworks/Security.framework/Security';

procedure RaiseKeychainError(const Operation: string; const Status: OSStatus);
begin
  raise Exception.CreateFmt(
    'macOS Keychain: %s fehlgeschlagen (OSStatus %d).',
    [Operation, Status]
  );
end;
{$ENDIF}

class function TGraphTokenStore.TokenFileName(
  const MailboxAddress: string
): string;
var
  Key: string;
begin
  Key := THashSHA2.GetHashString(
    Trim(LowerCase(MailboxAddress)),
    THashSHA2.TSHA2Version.SHA256
  );
  Result := TPath.Combine(
    TPath.Combine(TAppPaths.DataDirectory, 'GraphTokens'),
    Key + '.dat'
  );
end;

class procedure TGraphTokenStore.SaveRefreshToken(
  const MailboxAddress, RefreshToken: string
);
{$IF Defined(MSWINDOWS)}
var
  PlainBytes: TBytes;
  InputBlob: TDataBlob;
  OutputBlob: TDataBlob;
  EncryptedBytes: TBytes;
  FileName: string;
begin
  if Trim(MailboxAddress) = '' then
    raise EArgumentException.Create('MailboxAddress darf nicht leer sein.');
  if RefreshToken = '' then
    raise EArgumentException.Create('RefreshToken darf nicht leer sein.');

  PlainBytes := TEncoding.UTF8.GetBytes(RefreshToken);
  InputBlob.cbData := Length(PlainBytes);
  if Length(PlainBytes) > 0 then
    InputBlob.pbData := @PlainBytes[0]
  else
    InputBlob.pbData := nil;

  OutputBlob.cbData := 0;
  OutputBlob.pbData := nil;

  if not CryptProtectData(
    @InputBlob,
    'MailNotes Microsoft Graph Refresh Token',
    nil,
    nil,
    nil,
    CRYPTPROTECT_UI_FORBIDDEN,
    @OutputBlob
  ) then
    RaiseLastOSError;

  try
    SetLength(EncryptedBytes, OutputBlob.cbData);
    if OutputBlob.cbData > 0 then
      Move(OutputBlob.pbData^, EncryptedBytes[0], OutputBlob.cbData);

    FileName := TokenFileName(MailboxAddress);
    TDirectory.CreateDirectory(ExtractFilePath(FileName));
    TFile.WriteAllBytes(FileName, EncryptedBytes);
  finally
    if OutputBlob.pbData <> nil then
      LocalFree(HLOCAL(OutputBlob.pbData));
  end;
end;
{$ELSEIF Defined(MACOS)}
var
  ServiceUTF8: UTF8String;
  AccountUTF8: UTF8String;
  TokenUTF8: UTF8String;
  ItemRef: SecKeychainItemRef;
  Status: OSStatus;
begin
  if Trim(MailboxAddress) = '' then
    raise EArgumentException.Create('MailboxAddress darf nicht leer sein.');
  if RefreshToken = '' then
    raise EArgumentException.Create('RefreshToken darf nicht leer sein.');

  ServiceUTF8 := UTF8String(GraphKeychainService);
  AccountUTF8 := UTF8String(Trim(LowerCase(MailboxAddress)));
  TokenUTF8 := UTF8String(RefreshToken);
  ItemRef := nil;

  Status := SecKeychainFindGenericPassword(
    nil,
    Length(ServiceUTF8), PAnsiChar(ServiceUTF8),
    Length(AccountUTF8), PAnsiChar(AccountUTF8),
    nil, nil, @ItemRef
  );

  if Status = errSecSuccess then
  begin
    try
      Status := SecKeychainItemModifyAttributesAndData(
        ItemRef, nil, Length(TokenUTF8), PAnsiChar(TokenUTF8)
      );
      if Status <> errSecSuccess then
        RaiseKeychainError('Refresh Token aktualisieren', Status);
    finally
      if ItemRef <> nil then
        CFRelease(ItemRef);
    end;
    Exit;
  end;

  if Status <> errSecItemNotFound then
    RaiseKeychainError('Refresh Token suchen', Status);

  Status := SecKeychainAddGenericPassword(
    nil,
    Length(ServiceUTF8), PAnsiChar(ServiceUTF8),
    Length(AccountUTF8), PAnsiChar(AccountUTF8),
    Length(TokenUTF8), PAnsiChar(TokenUTF8),
    nil
  );
  if Status <> errSecSuccess then
    RaiseKeychainError('Refresh Token speichern', Status);
end;
{$ELSE}
begin
  raise ENotSupportedException.Create(
    'Sichere Graph-Tokenablage ist auf dieser Plattform noch nicht implementiert.'
  );
end;
{$ENDIF}

class function TGraphTokenStore.LoadRefreshToken(
  const MailboxAddress: string;
  out RefreshToken: string
): Boolean;
{$IF Defined(MSWINDOWS)}
var
  EncryptedBytes: TBytes;
  InputBlob: TDataBlob;
  OutputBlob: TDataBlob;
  FileName: string;
  PlainBytes: TBytes;
begin
  RefreshToken := '';
  FileName := TokenFileName(MailboxAddress);
  if not TFile.Exists(FileName) then
    Exit(False);

  EncryptedBytes := TFile.ReadAllBytes(FileName);
  if Length(EncryptedBytes) = 0 then
    Exit(False);

  InputBlob.cbData := Length(EncryptedBytes);
  InputBlob.pbData := @EncryptedBytes[0];
  OutputBlob.cbData := 0;
  OutputBlob.pbData := nil;

  if not CryptUnprotectData(
    @InputBlob,
    nil,
    nil,
    nil,
    nil,
    CRYPTPROTECT_UI_FORBIDDEN,
    @OutputBlob
  ) then
    RaiseLastOSError;

  try
    SetLength(PlainBytes, OutputBlob.cbData);
    if OutputBlob.cbData > 0 then
      Move(OutputBlob.pbData^, PlainBytes[0], OutputBlob.cbData);
    RefreshToken := TEncoding.UTF8.GetString(PlainBytes);
    Result := RefreshToken <> '';
  finally
    if OutputBlob.pbData <> nil then
      LocalFree(HLOCAL(OutputBlob.pbData));
  end;
end;
{$ELSEIF Defined(MACOS)}
var
  ServiceUTF8: UTF8String;
  AccountUTF8: UTF8String;
  PasswordLength: UInt32;
  PasswordData: Pointer;
  Status: OSStatus;
  TokenBytes: TBytes;
begin
  RefreshToken := '';
  ServiceUTF8 := UTF8String(GraphKeychainService);
  AccountUTF8 := UTF8String(Trim(LowerCase(MailboxAddress)));
  PasswordLength := 0;
  PasswordData := nil;

  Status := SecKeychainFindGenericPassword(
    nil,
    Length(ServiceUTF8), PAnsiChar(ServiceUTF8),
    Length(AccountUTF8), PAnsiChar(AccountUTF8),
    @PasswordLength, @PasswordData, nil
  );

  if Status = errSecItemNotFound then
    Exit(False);
  if Status <> errSecSuccess then
    RaiseKeychainError('Refresh Token lesen', Status);

  try
    SetLength(TokenBytes, PasswordLength);
    if PasswordLength > 0 then
      Move(PasswordData^, TokenBytes[0], PasswordLength);
    RefreshToken := TEncoding.UTF8.GetString(TokenBytes);
    Result := RefreshToken <> '';
  finally
    if PasswordData <> nil then
      SecKeychainItemFreeContent(nil, PasswordData);
  end;
end;
{$ELSE}
begin
  RefreshToken := '';
  Result := False;
end;
{$ENDIF}

class procedure TGraphTokenStore.DeleteRefreshToken(
  const MailboxAddress: string
);
{$IF Defined(MSWINDOWS)}
var
  FileName: string;
begin
  FileName := TokenFileName(MailboxAddress);
  if TFile.Exists(FileName) then
    TFile.Delete(FileName);
end;
{$ELSEIF Defined(MACOS)}
var
  ServiceUTF8: UTF8String;
  AccountUTF8: UTF8String;
  ItemRef: SecKeychainItemRef;
  Status: OSStatus;
begin
  ServiceUTF8 := UTF8String(GraphKeychainService);
  AccountUTF8 := UTF8String(Trim(LowerCase(MailboxAddress)));
  ItemRef := nil;

  Status := SecKeychainFindGenericPassword(
    nil,
    Length(ServiceUTF8), PAnsiChar(ServiceUTF8),
    Length(AccountUTF8), PAnsiChar(AccountUTF8),
    nil, nil, @ItemRef
  );

  if Status = errSecItemNotFound then
    Exit;
  if Status <> errSecSuccess then
    RaiseKeychainError('Refresh Token suchen', Status);

  try
    Status := SecKeychainItemDelete(ItemRef);
    if Status <> errSecSuccess then
      RaiseKeychainError('Refresh Token loeschen', Status);
  finally
    if ItemRef <> nil then
      CFRelease(ItemRef);
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

end.
