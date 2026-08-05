unit uAppInfo;

interface

uses
  System.SysUtils;

type
  TAppInfo = class sealed
  private
    class function NormalizeVersion(const AVersion: string): string; static;
  public
    class function Version: string; static;
    class function PlatformName: string; static;
    class function CompareVersions(const AVersion1, AVersion2: string): Integer; static;
  end;

implementation

{$IF Defined(MSWINDOWS)}
uses
  Winapi.Windows;
{$ENDIF}

class function TAppInfo.NormalizeVersion(const AVersion: string): string;
var
  S: string;
  I: Integer;
begin
  S := Trim(AVersion);
  if (S <> '') and CharInSet(S[1], ['v', 'V']) then
    Delete(S, 1, 1);

  // Anhänge wie "-beta" oder "+build" werden für den numerischen
  // Vier-Komponenten-Vergleich abgeschnitten.
  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['0'..'9', '.']) then
    begin
      SetLength(S, I - 1);
      Break;
    end;

  Result := S;
end;

class function TAppInfo.Version: string;
begin
  // Diese vier Komponenten sind die verbindliche Produkt-/Updateversion.
  // Der Versionsvergleich berücksichtigt alle vier Werte vollständig.
  Result := '1.0.0.0';
end;

class function TAppInfo.PlatformName: string;
begin
{$IF Defined(MSWINDOWS)}
  Result := 'Windows';
{$ELSEIF Defined(MACOS)}
  Result := 'macOS';
{$ELSE}
  Result := 'Unbekannt';
{$ENDIF}
end;

class function TAppInfo.CompareVersions(
  const AVersion1, AVersion2: string
): Integer;
var
  Parts1: TArray<string>;
  Parts2: TArray<string>;
  Values1: array[0..3] of UInt64;
  Values2: array[0..3] of UInt64;
  I: Integer;
  V: UInt64;
begin
  Parts1 := NormalizeVersion(AVersion1).Split(['.']);
  Parts2 := NormalizeVersion(AVersion2).Split(['.']);
  FillChar(Values1, SizeOf(Values1), 0);
  FillChar(Values2, SizeOf(Values2), 0);

  for I := 0 to 3 do
  begin
    if (I < Length(Parts1)) and TryStrToUInt64(Parts1[I], V) then
      Values1[I] := V;
    if (I < Length(Parts2)) and TryStrToUInt64(Parts2[I], V) then
      Values2[I] := V;
  end;

  for I := 0 to 3 do
  begin
    if Values1[I] < Values2[I] then
      Exit(-1);
    if Values1[I] > Values2[I] then
      Exit(1);
  end;

  Result := 0;
end;

end.
