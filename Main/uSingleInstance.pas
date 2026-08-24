unit uSingleInstance;

interface

type
  TSingleInstanceGuard = class
  private
{$IF Defined(MSWINDOWS)}
    FMutexHandle: THandle;
{$ELSEIF Defined(MACOS)}
    FLockFd: Integer;
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
{$ELSEIF Defined(MACOS)}
  , System.IOUtils
  , Posix.Base
  , Posix.Fcntl
  , Posix.SysStat
  , Posix.Unistd
{$ENDIF}
  ;

{$IF Defined(MACOS)}
const
  LOCK_EX = 2;
  LOCK_NB = 4;
  LOCK_UN = 8;

function flock(fd, operation: Integer): Integer; cdecl;
  external libc name _PU + 'flock';
{$ENDIF}

constructor TSingleInstanceGuard.Create(const InstanceName: string);
{$IF Defined(MSWINDOWS)}
var
  MutexName: string;
{$ELSEIF Defined(MACOS)}
var
  LockFileName: string;
  LockFileNameUtf8: UTF8String;
{$ENDIF}
begin
  inherited Create;

  FAcquired := False;

{$IF Defined(MSWINDOWS)}
  MutexName := 'Local\' + InstanceName;
  FMutexHandle := CreateMutex(nil, True, PChar(MutexName));

  if FMutexHandle = 0 then
    RaiseLastOSError;

  FAcquired := GetLastError <> ERROR_ALREADY_EXISTS;
{$ELSEIF Defined(MACOS)}
  FLockFd := -1;
  LockFileName := TPath.Combine(TPath.GetTempPath, InstanceName + '.lock');
  LockFileNameUtf8 := UTF8String(LockFileName);

  // Unter POSIX einen echten Dateideskriptor verwenden.
  // System.SysUtils.FileCreate liefert hier keinen verlässlichen fd für flock.
  FLockFd := Posix.Fcntl.open(
    PAnsiChar(LockFileNameUtf8),
    O_RDWR or O_CREAT,
    S_IRUSR or S_IWUSR
  );

  if FLockFd < 0 then
    RaiseLastOSError;

  if flock(FLockFd, LOCK_EX or LOCK_NB) = 0 then
    FAcquired := True
  else
  begin
    FileClose(FLockFd);
    FLockFd := -1;
  end;
{$ELSE}
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
{$ELSEIF Defined(MACOS)}
  if FLockFd >= 0 then
  begin
    if FAcquired then
      flock(FLockFd, LOCK_UN);

    FileClose(FLockFd);
    FLockFd := -1;
  end;
{$ENDIF}

  inherited;
end;

end.
