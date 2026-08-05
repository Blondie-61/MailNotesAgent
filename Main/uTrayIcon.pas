unit uTrayIcon;

interface

{$IF Defined(MSWINDOWS)}
uses
  Winapi.Windows,
  Winapi.Messages;
{$ENDIF}

type
  TTrayState = (
    tsOK,
    tsWarning,
    tsError
  );

  TTrayIcon = class
  private
    FState: TTrayState;
{$IF Defined(MSWINDOWS)}
    FWindowHandle: HWND;
    FPopupMenu: HMENU;
    FIconHandle: HICON;
    FIconAdded: Boolean;
    FShutdownMessage: UINT;

    procedure WindowMessage(var Message: TMessage);
    procedure CreateTrayMenu;
    procedure DestroyTrayMenu;
    procedure AddTrayIcon;
    procedure RemoveTrayIcon;
    procedure UpdateTrayIcon;
    procedure ShowTrayMenu;
    procedure ExecuteMenuCommand(const CommandID: NativeUInt);
    procedure ShowStatusDialog;
    procedure CheckForUpdates;
    procedure OpenDataDirectory;
    procedure OpenLogFile;
    function IconResourceID: Integer;
    function StatusText: string;
{$ENDIF}
  public
{$IF Defined(MSWINDOWS)}
    class procedure RequestRunningInstanceShutdown; static;
{$ENDIF}
    constructor Create;
    destructor Destroy; override;

    procedure SetState(const State: TTrayState);
    procedure Run;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  uAppPaths
{$IF Defined(MSWINDOWS)}
  , Winapi.ShellAPI,
  System.Classes,
  uTrayIconResources,
  uStatusDialog,
  uUpdater
{$ENDIF}
  ;

{$IF Defined(MSWINDOWS)}

const
  WM_MAILNOTES_TRAY = WM_APP + 117;

  MENU_STATUS = 1000;
  MENU_SHOW_STATUS = 1001;
  MENU_CHECK_UPDATES = 1002;
  MENU_OPEN_DATA = 1003;
  MENU_OPEN_LOG = 1004;
  MENU_EXIT = 1005;

constructor TTrayIcon.Create;
begin
  inherited Create;

  FState := tsOK;
  FShutdownMessage := RegisterWindowMessage('MailNotesAgent.Shutdown');
  FWindowHandle := AllocateHWnd(WindowMessage);
  CreateTrayMenu;
  AddTrayIcon;
end;


destructor TTrayIcon.Destroy;
begin
  RemoveTrayIcon;
  DestroyTrayMenu;

  if FWindowHandle <> 0 then
  begin
    DeallocateHWnd(FWindowHandle);
    FWindowHandle := 0;
  end;

  inherited;
end;


procedure TTrayIcon.SetState(const State: TTrayState);
begin
  if FState = State then
  begin
    UpdateTrayIcon;
    Exit;
  end;

  FState := State;
  UpdateTrayIcon;
end;


procedure TTrayIcon.Run;
var
  Message: TMsg;
begin
  while GetMessage(Message, 0, 0, 0) do
  begin
    TranslateMessage(Message);
    DispatchMessage(Message);
  end;
end;


class procedure TTrayIcon.RequestRunningInstanceShutdown;
var
  ShutdownMessage: UINT;
begin
  ShutdownMessage := RegisterWindowMessage('MailNotesAgent.Shutdown');
  if ShutdownMessage <> 0 then
    PostMessage(HWND_BROADCAST, ShutdownMessage, 0, 0);
end;


procedure TTrayIcon.WindowMessage(var Message: TMessage);
begin
  if (FShutdownMessage <> 0) and (Message.Msg = FShutdownMessage) then
  begin
    RemoveTrayIcon;
    PostQuitMessage(0);
    Message.Result := 0;
    Exit;
  end;

  case Message.Msg of
    WM_MAILNOTES_TRAY:
      case Message.LParam of
        WM_LBUTTONDBLCLK,
        WM_RBUTTONUP,
        WM_CONTEXTMENU:
          ShowTrayMenu;
      end;

    WM_COMMAND:
      ExecuteMenuCommand(LoWord(Message.WParam));

    WM_DESTROY:
      PostQuitMessage(0);
  else
    Message.Result := DefWindowProc(FWindowHandle, Message.Msg, Message.WParam, Message.LParam);
  end;
end;


procedure TTrayIcon.CreateTrayMenu;
begin
  FPopupMenu := CreatePopupMenu;

  if FPopupMenu = 0 then
    RaiseLastOSError;

  AppendMenu(FPopupMenu, MF_STRING or MF_GRAYED, MENU_STATUS, PChar(StatusText));
  AppendMenu(FPopupMenu, MF_STRING, MENU_SHOW_STATUS, 'Statusinformationen...');
  AppendMenu(FPopupMenu, MF_STRING, MENU_CHECK_UPDATES, 'Nach Updates suchen...');
  AppendMenu(FPopupMenu, MF_SEPARATOR, 0, nil);
  AppendMenu(FPopupMenu, MF_STRING, MENU_OPEN_DATA, 'Datenordner öffnen');
  AppendMenu(FPopupMenu, MF_STRING, MENU_OPEN_LOG, 'Logdatei öffnen');
  AppendMenu(FPopupMenu, MF_SEPARATOR, 0, nil);
  AppendMenu(FPopupMenu, MF_STRING, MENU_EXIT, 'MailNotes Agent beenden');
end;


procedure TTrayIcon.DestroyTrayMenu;
begin
  if FPopupMenu <> 0 then
  begin
    DestroyMenu(FPopupMenu);
    FPopupMenu := 0;
  end;
end;


procedure TTrayIcon.AddTrayIcon;
var
  NotifyData: TNotifyIconData;
begin
  if FIconAdded then
    Exit;

  FillChar(NotifyData, SizeOf(NotifyData), 0);
  NotifyData.cbSize := SizeOf(NotifyData);
  NotifyData.Wnd := FWindowHandle;
  NotifyData.uID := 1;
  NotifyData.uFlags := NIF_MESSAGE or NIF_TIP;
  NotifyData.uCallbackMessage := WM_MAILNOTES_TRAY;
  StrPLCopy(NotifyData.szTip, 'MailNotes Agent', Length(NotifyData.szTip) - 1);

  if not Shell_NotifyIcon(NIM_ADD, @NotifyData) then
    RaiseLastOSError;

  FIconAdded := True;
  UpdateTrayIcon;
end;


procedure TTrayIcon.RemoveTrayIcon;
var
  NotifyData: TNotifyIconData;
begin
  if FIconAdded then
  begin
    FillChar(NotifyData, SizeOf(NotifyData), 0);
    NotifyData.cbSize := SizeOf(NotifyData);
    NotifyData.Wnd := FWindowHandle;
    NotifyData.uID := 1;
    Shell_NotifyIcon(NIM_DELETE, @NotifyData);
    FIconAdded := False;
  end;

  if FIconHandle <> 0 then
  begin
    DestroyIcon(FIconHandle);
    FIconHandle := 0;
  end;
end;


procedure TTrayIcon.UpdateTrayIcon;
var
  NewIcon: HICON;
  OldIcon: HICON;
  NotifyData: TNotifyIconData;
begin
  NewIcon := CreateMailNotesIcon(IconResourceID);

  // CopyIcon liefert auch für das Fallback ein eigenes Handle. Dadurch kann
  // FIconHandle beim nächsten Wechsel immer gefahrlos freigegeben werden.
  if NewIcon = 0 then
    NewIcon := CopyIcon(LoadIcon(0, IDI_APPLICATION));

  FillChar(NotifyData, SizeOf(NotifyData), 0);
  NotifyData.cbSize := SizeOf(NotifyData);
  NotifyData.Wnd := FWindowHandle;
  NotifyData.uID := 1;
  NotifyData.uFlags := NIF_ICON or NIF_TIP;
  NotifyData.hIcon := NewIcon;

  StrPLCopy(
    NotifyData.szTip,
    PChar('MailNotes Agent - ' + StatusText),
    Length(NotifyData.szTip) - 1
  );

  if FIconAdded then
    Shell_NotifyIcon(NIM_MODIFY, @NotifyData);

  OldIcon := FIconHandle;
  FIconHandle := NewIcon;

  if OldIcon <> 0 then
    DestroyIcon(OldIcon);

  ModifyMenu(
    FPopupMenu,
    MENU_STATUS,
    MF_BYCOMMAND or MF_STRING or MF_GRAYED,
    MENU_STATUS,
    PChar(StatusText)
  );
end;


procedure TTrayIcon.ShowTrayMenu;
var
  CursorPosition: TPoint;
begin
  GetCursorPos(CursorPosition);
  SetForegroundWindow(FWindowHandle);

  TrackPopupMenu(
    FPopupMenu,
    TPM_RIGHTBUTTON or TPM_BOTTOMALIGN or TPM_LEFTALIGN,
    CursorPosition.X,
    CursorPosition.Y,
    0,
    FWindowHandle,
    nil
  );

  PostMessage(FWindowHandle, WM_NULL, 0, 0);
end;


procedure TTrayIcon.ExecuteMenuCommand(const CommandID: NativeUInt);
begin
  case CommandID of
    MENU_SHOW_STATUS:
      ShowStatusDialog;

    MENU_CHECK_UPDATES:
      CheckForUpdates;

    MENU_OPEN_DATA:
      OpenDataDirectory;

    MENU_OPEN_LOG:
      OpenLogFile;

    MENU_EXIT:
      begin
        RemoveTrayIcon;
        PostQuitMessage(0);
      end;
  end;
end;


procedure TTrayIcon.ShowStatusDialog;
begin
  ShowMailNotesStatusDialog(FWindowHandle);
end;


procedure TTrayIcon.CheckForUpdates;
var
  CheckResult: TUpdateCheckResult;
  InstallerFile: string;
  Answer: Integer;
begin
  SetCursor(LoadCursor(0, IDC_WAIT));
  try
    CheckResult := TMailNotesUpdater.CheckLatest;
  finally
    SetCursor(LoadCursor(0, IDC_ARROW));
  end;

  if not CheckResult.Success then
  begin
    MessageBoxW(
      FWindowHandle,
      PWideChar('Die Updatesuche ist fehlgeschlagen.' + sLineBreak +
        sLineBreak + CheckResult.ErrorMessage),
      'MailNotes Agent',
      MB_OK or MB_ICONERROR
    );
    Exit;
  end;

  if not CheckResult.UpdateAvailable then
  begin
    MessageBoxW(
      FWindowHandle,
      PWideChar('MailNotes Agent ist aktuell.' + sLineBreak + sLineBreak +
        'Installierte Version: ' + CheckResult.CurrentVersion + sLineBreak +
        'Aktuelle Version: ' + CheckResult.LatestVersion),
      'MailNotes Agent',
      MB_OK or MB_ICONINFORMATION
    );
    Exit;
  end;

  Answer := MessageBoxW(
    FWindowHandle,
    PWideChar('Eine neue Version ist verfügbar.' + sLineBreak + sLineBreak +
      'Installiert: ' + CheckResult.CurrentVersion + sLineBreak +
      'Verfügbar: ' + CheckResult.LatestVersion + sLineBreak + sLineBreak +
      'Soll das Setup jetzt heruntergeladen werden?'),
    'MailNotes Agent',
    MB_YESNO or MB_ICONINFORMATION or MB_DEFBUTTON1
  );

  if Answer <> IDYES then
    Exit;

  try
    InstallerFile := TMailNotesUpdater.DownloadInstaller(
      CheckResult.DownloadUrl,
      CheckResult.AssetName
    );

    Answer := MessageBoxW(
      FWindowHandle,
      PWideChar('Das Setup wurde heruntergeladen:' + sLineBreak +
        InstallerFile + sLineBreak + sLineBreak +
        'Soll es jetzt gestartet werden?'),
      'MailNotes Agent',
      MB_YESNO or MB_ICONINFORMATION or MB_DEFBUTTON1
    );

    if Answer = IDYES then
      if ShellExecuteW(
        FWindowHandle,
        'open',
        PWideChar(InstallerFile),
        nil,
        PWideChar(ExtractFilePath(InstallerFile)),
        SW_SHOWNORMAL
      ) <= 32 then
        RaiseLastOSError;
  except
    on E: Exception do
      MessageBoxW(
        FWindowHandle,
        PWideChar('Das Update konnte nicht heruntergeladen oder gestartet werden.' +
          sLineBreak + sLineBreak + E.Message),
        'MailNotes Agent',
        MB_OK or MB_ICONERROR
      );
  end;
end;


procedure TTrayIcon.OpenDataDirectory;
begin
  TAppPaths.EnsureDataDirectory;
  ShellExecute(
    0,
    'open',
    PChar(TAppPaths.DataDirectory),
    nil,
    nil,
    SW_SHOWNORMAL
  );
end;


procedure TTrayIcon.OpenLogFile;
begin
  if TFile.Exists(TAppPaths.LogFile) then
  begin
    ShellExecute(
      0,
      'open',
      PChar(TAppPaths.LogFile),
      nil,
      nil,
      SW_SHOWNORMAL
    );
  end
  else
  begin
    MessageBox(
      FWindowHandle,
      'Die Logdatei wurde noch nicht angelegt.',
      'MailNotes Agent',
      MB_OK or MB_ICONINFORMATION
    );
  end;
end;


function TTrayIcon.IconResourceID: Integer;
const
  // False = farbige Statussymbole, True = Schwarzweiß-Symbole.
  USE_MONOCHROME_ICONS = False;
begin
  if USE_MONOCHROME_ICONS then
  begin
    case FState of
      tsWarning: Result := 4;
      tsError: Result := 5;
    else
      Result := 3;
    end;
  end
  else
  begin
    case FState of
      tsWarning: Result := 1;
      tsError: Result := 2;
    else
      Result := 0;
    end;
  end;
end;


function TTrayIcon.StatusText: string;
begin
  case FState of
    tsWarning:
      Result := 'Warnung';

    tsError:
      Result := 'Fehler';
  else
    Result := 'Bereit';
  end;
end;

{$ELSE}

constructor TTrayIcon.Create;
begin
  inherited Create;
  FState := tsOK;
end;


destructor TTrayIcon.Destroy;
begin
  inherited;
end;


procedure TTrayIcon.SetState(const State: TTrayState);
begin
  FState := State;
end;


procedure TTrayIcon.Run;
begin
  Writeln('MailNotes Agent läuft. Zum Beenden Eingabetaste drücken.');
  Readln;
end;

{$ENDIF}

end.
