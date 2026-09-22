unit uRuntimeConfig;

interface

type
  TRuntimeConfig = class sealed
  public
    class function HttpPort: Integer; static;
    class function HttpBindAddress: string; static;
    class function UseHttps: Boolean; static;
    class function EnableLogging: Boolean; static;
    class function ServeAddinFiles: Boolean; static;
    class function IsAllowedCorsOrigin(const AOrigin: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

class function TRuntimeConfig.HttpPort: Integer;
begin
  Result := 48571;
end;

class function TRuntimeConfig.HttpBindAddress: string;
begin
{$IFDEF DEBUG}
  // Entwicklung: Agent aus der Windows-VM auch vom Mac-Devserver erreichbar.
  Result := '';
{$ELSE}
  // Produktion: ausschließlich lokaler Rechner.
  Result := '127.0.0.1';
{$ENDIF}
end;

class function TRuntimeConfig.UseHttps: Boolean;
begin
{$IF (Defined(MSWINDOWS) or Defined(MACOS)) and not Defined(DEBUG)}
  // Im produktiven Betrieb wird das Outlook-Add-in direkt vom Agent
  // über HTTPS auf localhost:48571 geladen.
  Result := True;
{$ELSE}
  // Entwicklung bleibt wie bisher: webpack HTTPS -> Agent HTTP.
  Result := False;
{$ENDIF}
end;

class function TRuntimeConfig.ServeAddinFiles: Boolean;
begin
  Result := UseHttps;
end;

class function TRuntimeConfig.EnableLogging: Boolean;
begin
  Result := True;
end;

class function TRuntimeConfig.IsAllowedCorsOrigin(const AOrigin: string): Boolean;
var
  Origin: string;
begin
  Origin := Trim(AOrigin);
  if Origin = '' then
    Exit(False);

{$IF Defined(DEBUG) or Defined(MACOS)}
  // Development sowie der aktuelle macOS-Release-Betrieb:
  // Das Outlook-Add-in läuft auf dem lokalen webpack-HTTPS-Server,
  // der Agent selbst auf http://127.0.0.1:48571.
  if SameText(Origin, 'https://localhost:3000') then
    Exit(True);
  if SameText(Origin, 'https://127.0.0.1:3000') then
    Exit(True);
{$ENDIF}

  // Im Produktionsbetrieb sind Taskpane und API same-origin
  // (https://localhost:48571). CORS ist dort nicht erforderlich.
  Result := False;
end;

end.
