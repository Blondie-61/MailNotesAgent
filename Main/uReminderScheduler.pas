unit uReminderScheduler;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs, uHttpServer;

type
  TReminderScheduler = class(TThread)
  private
    FServer: THttpServer;
    FNotify: TProc<Integer>;
    FStopEvent: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AServer: THttpServer; const ANotify: TProc<Integer>);
    destructor Destroy; override;
    procedure Stop;
  end;

implementation

uses uDiagnostics;

constructor TReminderScheduler.Create(AServer: THttpServer; const ANotify: TProc<Integer>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FServer := AServer;
  FNotify := ANotify;
  FStopEvent := TEvent.Create(nil, True, False, '');
end;

procedure TReminderScheduler.Stop;
begin
  Terminate;
  if Assigned(FStopEvent) then FStopEvent.SetEvent;
  if not Suspended then WaitFor;
end;

destructor TReminderScheduler.Destroy;
begin
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TReminderScheduler.Execute;
begin
  if FStopEvent.WaitFor(10000) = wrSignaled then Exit;
  while not Terminated do
  begin
    try
      FServer.NotifyDueReminders(FNotify);
    except
      on E: Exception do TMNDiagnostics.Error('Reminder', E.Message);
    end;
    if FStopEvent.WaitFor(30000) = wrSignaled then Exit;
  end;
end;

end.
