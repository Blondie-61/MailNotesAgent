unit uVersion;

interface

uses
  System.SysUtils;

type
  TMailNotesVersion = record
  private
    FMajor: Cardinal;
    FMinor: Cardinal;
    FRelease: Cardinal;
    FBuild: Cardinal;
  public
    class function Parse(const AValue: string): TMailNotesVersion; static;
    class function TryParse(const AValue: string;
      out AVersion: TMailNotesVersion): Boolean; static;
    function CompareTo(const AOther: TMailNotesVersion): Integer;
    function ToString: string;
    property Major: Cardinal read FMajor;
    property Minor: Cardinal read FMinor;
    property Release: Cardinal read FRelease;
    property Build: Cardinal read FBuild;
  end;

implementation

function NormalizeVersionText(const AValue: string): string;
var
  S: string;
  I: Integer;
begin
  S := Trim(AValue);
  if (S <> '') and CharInSet(S[1], ['v', 'V']) then
    Delete(S, 1, 1);

  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['0'..'9', '.']) then
    begin
      SetLength(S, I - 1);
      Break;
    end;

  Result := S;
end;

class function TMailNotesVersion.TryParse(const AValue: string;
  out AVersion: TMailNotesVersion): Boolean;
var
  Parts: TArray<string>;
  Values: array[0..3] of Cardinal;
  I: Integer;
  Number: UInt64;
  S: string;
begin
  AVersion := Default(TMailNotesVersion);
  FillChar(Values, SizeOf(Values), 0);

  S := NormalizeVersionText(AValue);
  if S = '' then
    Exit(False);

  Parts := S.Split(['.']);
  if (Length(Parts) < 1) or (Length(Parts) > 4) then
    Exit(False);

  for I := 0 to High(Parts) do
  begin
    if (Parts[I] = '') or not TryStrToUInt64(Parts[I], Number) or
       (Number > High(Cardinal)) then
      Exit(False);
    Values[I] := Cardinal(Number);
  end;

  AVersion.FMajor := Values[0];
  AVersion.FMinor := Values[1];
  AVersion.FRelease := Values[2];
  AVersion.FBuild := Values[3];
  Result := True;
end;

class function TMailNotesVersion.Parse(
  const AValue: string): TMailNotesVersion;
begin
  if not TryParse(AValue, Result) then
    raise EConvertError.CreateFmt('Ungültige Versionsnummer: %s', [AValue]);
end;

function TMailNotesVersion.CompareTo(
  const AOther: TMailNotesVersion): Integer;
begin
  if FMajor < AOther.FMajor then Exit(-1);
  if FMajor > AOther.FMajor then Exit(1);
  if FMinor < AOther.FMinor then Exit(-1);
  if FMinor > AOther.FMinor then Exit(1);
  if FRelease < AOther.FRelease then Exit(-1);
  if FRelease > AOther.FRelease then Exit(1);
  if FBuild < AOther.FBuild then Exit(-1);
  if FBuild > AOther.FBuild then Exit(1);
  Result := 0;
end;

function TMailNotesVersion.ToString: string;
begin
  Result := Format('%d.%d.%d.%d', [FMajor, FMinor, FRelease, FBuild]);
end;

end.
