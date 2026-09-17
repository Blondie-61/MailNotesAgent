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
{$ELSE}
begin
  RefreshToken := '';
  Result := False;
end;
{$ENDIF}

class procedure TGraphTokenStore.DeleteRefreshToken(
  const MailboxAddress: string
);
var
  FileName: string;
begin
  FileName := TokenFileName(MailboxAddress);
  if TFile.Exists(FileName) then
    TFile.Delete(FileName);
end;

end.
