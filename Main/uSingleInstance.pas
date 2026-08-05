unit uSingleInstance;

interface

type
  TSingleInstanceGuard = class
  private
{$IF Defined(MSWINDOWS)}
    FMutexHandle: THandle;
{$ENDIF}
    FAcquired: Boolean;
  public
    constructor Create(const InstanceName: string);
    destructor Destroy; override;

    property Acquired: Boolean read FAcquired;
  end;

implementation

uses
  System.SysUtils
{$IF Defined(MSWINDOWS)}
  , Winapi.Windows
{$ENDIF}
  ;

constructor TSingleInstanceGuard.Create(const InstanceName: string);
{$IF Defined(MSWINDOWS)}
var
  MutexName: string;
{$ENDIF}
begin
  inherited Create;

{$IF Defined(MSWINDOWS)}
  MutexName := 'Local\' + InstanceName;
  FMutexHandle := CreateMutex(nil, True, PChar(MutexName));

  if FMutexHandle = 0 then
    RaiseLastOSError;

  FAcquired := GetLastError <> ERROR_ALREADY_EXISTS;
{$ELSE}
  // Der plattformspezifische Schutz für macOS folgt mit dem LaunchAgent.
  FAcquired := True;
{$ENDIF}
end;


destructor TSingleInstanceGuard.Destroy;
begin
{$IF Defined(MSWINDOWS)}
  if FMutexHandle <> 0 then
  begin
    if FAcquired then
      ReleaseMutex(FMutexHandle);

    CloseHandle(FMutexHandle);
    FMutexHandle := 0;
  end;
{$ENDIF}

  inherited;
end;

end.
