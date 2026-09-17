unit uTrayIcon;

interface

{$IF Defined(MSWINDOWS)}
uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.ActiveX,
  uUpdater,
  uHttpServer,
  uBackupScheduler;

function SetMenuDefaultItem(
  hMenu: HMENU;
  uItem: UINT;
  fByPos: UINT
): BOOL; stdcall; external user32 name 'SetMenuDefaultItem';
{$ELSEIF Defined(MACOS)}
uses
  System.TypInfo,
  Macapi.AppKit,
  Macapi.CocoaTypes,
  Macapi.Foundation,
  Macapi.ObjectiveC,
  uHttpServer,
  uBackupScheduler;
{$ENDIF}

type
{$IF Defined(MACOS)}
  IMailNotesMenuHandler = interface(NSObject)
    ['{B461B6E4-B0A8-47D2-A8DC-536494CEAA3D}']
    procedure showAgentInfo; cdecl;
    procedure revealAgentInFinder; cdecl;
    procedure revealDatabaseInFinder; cdecl;
    procedure revealConfigInFinder; cdecl;
    procedure revealBackupDirectoryInFinder; cdecl;
    procedure changeDatabasePath; cdecl;
    procedure createDatabaseBackup; cdecl;
    procedure changeBackupDirectory; cdecl;
    procedure autoBackupInterval1; cdecl;
    procedure autoBackupInterval2; cdecl;
    procedure autoBackupInterval3; cdecl;
    procedure autoBackupOff; cdecl;
  end;

  TTrayIcon = class;

  TMacMenuHandler = class(TOCLocal)
  private
    FOwner: TTrayIcon;
  protected
    function GetObjectiveCClass: PTypeInfo; override;
  public
    constructor Create(const AOwner: TTrayIcon);
    procedure showAgentInfo; cdecl;
    procedure revealAgentInFinder; cdecl;
    procedure revealDatabaseInFinder; cdecl;
    procedure revealConfigInFinder; cdecl;
    procedure revealBackupDirectoryInFinder; cdecl;
    procedure changeDatabasePath; cdecl;
    procedure createDatabaseBackup; cdecl;
    procedure changeBackupDirectory; cdecl;
    procedure autoBackupInterval1; cdecl;
    procedure autoBackupInterval2; cdecl;
    procedure autoBackupInterval3; cdecl;
    procedure autoBackupOff; cdecl;
  end;
{$ENDIF}

  TTrayState = (
    tsOK,
    tsWarning,
    tsError,
    tsUpdateAvailable
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
    FUpdateAvailable: Boolean;
    FLatestVersion: string;
    FUpdateCheckRunning: Boolean;
    FDownloadedInstallerFile: string;
    FDownloadedVersion: string;
    FUpdatePromptedVersion: string;
    FHttpServer: THttpServer;
    FBackupScheduler: TBackupScheduler;
    FBackupAutoMenu: HMENU;

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
    procedure TestGraphAuthorization;
    procedure TestGraphRefresh;
    procedure StartAutomaticUpdateCheck;
    procedure HandleAutomaticUpdateResult(const ResultPointer: Pointer);
    procedure ApplyUpdateCheckResult(const CheckResult: TUpdateCheckResult);
    procedure UpdateUpdateMenu;
    procedure OpenDataDirectory;
    procedure OpenLogFile;
    procedure ChangeDatabasePath;
    procedure CreateDatabaseBackup;
    procedure ChangeBackupDirectory;
    procedure SetAutoBackupIntervalByIndex(const AIndex: Integer);
    procedure UpdateAutoBackupMenu;
    function SelectBackupDirectory(out ADirectory: string): Boolean;
    function DisplayState: TTrayState;
    function IconResourceID: Integer;
    function StatusText: string;
{$ELSEIF Defined(MACOS)}
    FStatusBar: NSStatusBar;
    FStatusItem: NSStatusItem;
    FPopupMenu: NSMenu;
    FStatusImage: NSImage;
    FMenuHandler: TMacMenuHandler;
    FInfoWindow: NSWindow;
    FHttpServer: THttpServer;
    FDatabaseLink: NSButton;
    FBackupDirectoryLink: NSButton;
    FLastBackupLabel: NSTextField;
    FBackupMenuItem: NSMenuItem;
    FBackupScheduler: TBackupScheduler;
    FBackupAutoMenu: NSMenu;
    FBackupIntervalMenuItems: array[0..MAX_BACKUP_INTERVALS - 1] of NSMenuItem;
    FBackupOffMenuItem: NSMenuItem;

    procedure CreateStatusItem;
    procedure DestroyStatusItem;
    procedure CreateTrayMenu;
    procedure UpdateTrayIcon;
    procedure ShowAgentInfo;
    procedure RevealAgentInFinder;
    procedure RevealDatabaseInFinder;
    procedure RevealConfigInFinder;
    procedure ChangeDatabasePath;
    procedure CreateDatabaseBackup;
    procedure ChangeBackupDirectory;
    procedure SetAutoBackupIntervalByIndex(const AIndex: Integer);
    procedure UpdateAutoBackupMenu;
    function SelectBackupDirectory(out ADirectory: string): Boolean;
    procedure RevealBackupDirectoryInFinder;
    procedure ShowMacMessage(const AMessage, ADetails: string);
    function IconFileName: string;
    function StatusText: string;
{$ENDIF}
  public
{$IF Defined(MSWINDOWS)}
    class procedure RequestRunningInstanceShutdown; static;
{$ENDIF}
{$IF Defined(MSWINDOWS) or Defined(MACOS)}
    constructor Create(AHttpServer: THttpServer);
{$ELSE}
    constructor Create;
{$ENDIF}
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
  Winapi.ShlObj,
  Winapi.CommDlg,
  System.Classes,
  System.StrUtils,
  uTrayIconResources,
  uStatusDialog,
  uGraphAuth,
  uGraphTokenStore,
  uGraphAccounts
{$ELSEIF Defined(MACOS)}
  , Macapi.Helpers,
  Macapi.ObjCRuntime,
  uAppInfo
{$ENDIF}
  ;

{$IF Defined(MSWINDOWS)}

const
  WM_MAILNOTES_TRAY = WM_APP + 117;
  WM_MAILNOTES_UPDATE_RESULT = WM_APP + 118;

  TIMER_AUTO_UPDATE = 2001;
  INITIAL_UPDATE_DELAY_MS = 15000;
  DAILY_UPDATE_INTERVAL_MS = 24 * 60 * 60 * 1000;

  MENU_STATUS = 1000;
  MENU_SHOW_STATUS = 1001;
  MENU_CHECK_UPDATES = 1002;
  MENU_OPEN_DATA = 1003;
  MENU_OPEN_LOG = 1004;
  MENU_CHANGE_DATABASE = 1005;
  MENU_BACKUP_DATABASE = 1006;
  MENU_CHANGE_BACKUP_DIRECTORY = 1007;
  MENU_BACKUP_INTERVAL_1 = 1008;
  MENU_BACKUP_INTERVAL_2 = 1009;
  MENU_BACKUP_INTERVAL_3 = 1010;
  MENU_BACKUP_AUTO_OFF = 1011;
  MENU_EXIT = 1012;
  MENU_TEST_GRAPH_AUTH = 1013;
  MENU_TEST_GRAPH_REFRESH = 1014;

type
  TAutomaticUpdateResult = record
    CheckResult: TUpdateCheckResult;
    InstallerFile: string;
    DownloadError: string;
  end;
  PAutomaticUpdateResult = ^TAutomaticUpdateResult;

constructor TTrayIcon.Create(AHttpServer: THttpServer);
begin
  inherited Create;

  FHttpServer := AHttpServer;
  FBackupScheduler := nil;
  FBackupAutoMenu := 0;
  FState := tsOK;
  FUpdateAvailable := False;
  FLatestVersion := '';
  FUpdateCheckRunning := False;
  FDownloadedInstallerFile := '';
  FDownloadedVersion := '';
  FUpdatePromptedVersion := '';
  FShutdownMessage := RegisterWindowMessage('MailNotesAgent.Shutdown');
  FWindowHandle := AllocateHWnd(WindowMessage);
  CreateTrayMenu;
  AddTrayIcon;
//  FBackupScheduler := TBackupScheduler.Create(FHttpServer);
  FBackupScheduler := TBackupScheduler.Create(FHttpServer);
  FBackupScheduler.Start;

  // Die erste Prüfung erfolgt bewusst leicht verzögert, damit der Agent
  // Die erste Prüfung erfolgt bewusst leicht verzögert, damit der Agent
  // vollständig gestartet ist. Danach wird einmal täglich erneut geprüft.
  SetTimer(FWindowHandle, TIMER_AUTO_UPDATE, INITIAL_UPDATE_DELAY_MS, nil);
end;


destructor TTrayIcon.Destroy;
begin
  if FBackupScheduler <> nil then
  begin
    FBackupScheduler.Stop;
    FBackupScheduler.BackupOnExit;
    FBackupScheduler.Free;
    FBackupScheduler := nil;
  end;

  if FWindowHandle <> 0 then
    KillTimer(FWindowHandle, TIMER_AUTO_UPDATE);

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
    WM_TIMER:
      if Message.WParam = TIMER_AUTO_UPDATE then
      begin
        KillTimer(FWindowHandle, TIMER_AUTO_UPDATE);
        StartAutomaticUpdateCheck;
        SetTimer(
          FWindowHandle,
          TIMER_AUTO_UPDATE,
          DAILY_UPDATE_INTERVAL_MS,
          nil
        );
        Message.Result := 0;
        Exit;
      end;

    WM_MAILNOTES_UPDATE_RESULT:
      begin
        HandleAutomaticUpdateResult(Pointer(Message.WParam));
        Message.Result := 0;
        Exit;
      end;

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
  AppendMenu(FPopupMenu, MF_STRING, MENU_TEST_GRAPH_AUTH, 'Graph-Anmeldung testen ...');
  AppendMenu(FPopupMenu, MF_STRING, MENU_TEST_GRAPH_REFRESH, 'Graph-Refresh testen ...');
  AppendMenu(FPopupMenu, MF_SEPARATOR, 0, nil);
  AppendMenu(FPopupMenu, MF_STRING, MENU_OPEN_DATA, 'Datenordner öffnen');
  AppendMenu(FPopupMenu, MF_STRING, MENU_OPEN_LOG, 'Logdatei öffnen');
  AppendMenu(FPopupMenu, MF_STRING, MENU_CHANGE_DATABASE, 'Datenbankpfad ändern...');
  AppendMenu(FPopupMenu, MF_SEPARATOR, 0, nil);
  AppendMenu(FPopupMenu, MF_STRING, MENU_BACKUP_DATABASE, 'Datenbank sichern ...');
  AppendMenu(FPopupMenu, MF_STRING, MENU_CHANGE_BACKUP_DIRECTORY, 'Backup-Ziel ändern ...');

  FBackupAutoMenu := CreatePopupMenu;
  if FBackupAutoMenu = 0 then
    RaiseLastOSError;
  AppendMenu(FPopupMenu, MF_POPUP, NativeUInt(FBackupAutoMenu), 'Automatisches Backup');
  UpdateAutoBackupMenu;

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
  BackupDirectory: string;
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

  BackupDirectory := TAppPaths.BackupDirectory;
  if (BackupDirectory <> '') and TDirectory.Exists(BackupDirectory) then
    ModifyMenu(
      FPopupMenu, MENU_BACKUP_DATABASE, MF_BYCOMMAND or MF_STRING,
      MENU_BACKUP_DATABASE, 'Datenbank sichern'
    )
  else
    ModifyMenu(
      FPopupMenu, MENU_BACKUP_DATABASE, MF_BYCOMMAND or MF_STRING,
      MENU_BACKUP_DATABASE, 'Datenbank sichern ...'
    );

  UpdateUpdateMenu;
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

    MENU_TEST_GRAPH_AUTH:
      TestGraphAuthorization;

    MENU_TEST_GRAPH_REFRESH:
      TestGraphRefresh;

    MENU_OPEN_DATA:
      OpenDataDirectory;

    MENU_OPEN_LOG:
      OpenLogFile;

    MENU_CHANGE_DATABASE:
      ChangeDatabasePath;

    MENU_BACKUP_DATABASE:
      CreateDatabaseBackup;

    MENU_CHANGE_BACKUP_DIRECTORY:
      ChangeBackupDirectory;

    MENU_BACKUP_INTERVAL_1:
      SetAutoBackupIntervalByIndex(0);

    MENU_BACKUP_INTERVAL_2:
      SetAutoBackupIntervalByIndex(1);

    MENU_BACKUP_INTERVAL_3:
      SetAutoBackupIntervalByIndex(2);

    MENU_BACKUP_AUTO_OFF:
      begin
        TBackupSettings.SetSelectedIntervalHours(0);
        UpdateAutoBackupMenu;
      end;

    MENU_EXIT:
      begin
        RemoveTrayIcon;
        PostQuitMessage(0);
      end;
  end;
end;


procedure TTrayIcon.TestGraphAuthorization;
var
  Verifier: string;
  AuthResult: TGraphAuthorizationResult;
  Tokens: TGraphTokenResult;
  UserInfo: TGraphUserInfo;
  ErrorText: string;
  MailboxAddress: string;
  Details: string;
  StoredRefreshToken: string;
  RefreshTokens: TGraphTokenResult;
  RefreshUserInfo: TGraphUserInfo;
  GraphAccounts: TGraphAccounts;
begin
  try
    if not TGraphAuth.Authorize(Verifier, AuthResult) then
    begin
      Details := 'Graph-Anmeldung fehlgeschlagen.';
      if AuthResult.Error <> '' then
        Details := Details + sLineBreak + sLineBreak + 'Fehler: ' + AuthResult.Error;
      if AuthResult.ErrorDescription <> '' then
        Details := Details + sLineBreak + AuthResult.ErrorDescription;
      MessageBox(FWindowHandle, PChar(Details), 'MailNotes Graph-Test',
        MB_OK or MB_ICONERROR);
      Exit;
    end;

    if not TGraphAuth.ExchangeAuthorizationCode(
      AuthResult.AuthorizationCode, Verifier, Tokens, ErrorText) then
    begin
      MessageBox(FWindowHandle,
        PChar('Token-Austausch fehlgeschlagen:' + sLineBreak + sLineBreak + ErrorText),
        'MailNotes Graph-Test', MB_OK or MB_ICONERROR);
      Exit;
    end;

    if not TGraphAuth.GetMe(Tokens.AccessToken, UserInfo, ErrorText) then
    begin
      MessageBox(FWindowHandle,
        PChar('Graph /me fehlgeschlagen:' + sLineBreak + sLineBreak + ErrorText),
        'MailNotes Graph-Test', MB_OK or MB_ICONERROR);
      Exit;
    end;

    MailboxAddress := UserInfo.Mail;
    if MailboxAddress = '' then
      MailboxAddress := UserInfo.UserPrincipalName;

    if Tokens.RefreshToken = '' then
      raise Exception.Create('Microsoft hat keinen Refresh Token geliefert.');

    TGraphTokenStore.SaveRefreshToken(MailboxAddress, Tokens.RefreshToken);
    if not TGraphTokenStore.LoadRefreshToken(MailboxAddress, StoredRefreshToken) then
      raise Exception.Create('Gespeicherter Refresh Token konnte nicht gelesen werden.');
    if StoredRefreshToken <> Tokens.RefreshToken then
      raise Exception.Create('Gespeicherter Refresh Token stimmt nicht mit dem Original überein.');

    GraphAccounts := TGraphAccounts.Create(FHttpServer.Database);
    try
      GraphAccounts.MarkAvailable(
        MailboxAddress,
        TGraphAuth.ConfiguredTenantID,
        UserInfo.ID
      );
    finally
      GraphAccounts.Free;
    end;

    // Jetzt den gespeicherten Token wirklich benutzen: kein Browser, kein PKCE.
    if not TGraphAuth.RefreshAccessToken(
      StoredRefreshToken, RefreshTokens, ErrorText) then
      raise Exception.Create('Token-Refresh fehlgeschlagen: ' + ErrorText);

    if RefreshTokens.RefreshToken <> '' then
      TGraphTokenStore.SaveRefreshToken(MailboxAddress, RefreshTokens.RefreshToken);

    if not TGraphAuth.GetMe(
      RefreshTokens.AccessToken, RefreshUserInfo, ErrorText) then
      raise Exception.Create('Graph /me nach Token-Refresh fehlgeschlagen: ' + ErrorText);

    if not SameText(RefreshUserInfo.ID, UserInfo.ID) then
      raise Exception.Create('Token-Refresh lieferte einen anderen Graph-Benutzer.');

    GraphAccounts := TGraphAccounts.Create(FHttpServer.Database);
    try
      GraphAccounts.MarkAvailable(
        MailboxAddress,
        TGraphAuth.ConfiguredTenantID,
        RefreshUserInfo.ID
      );
    finally
      GraphAccounts.Free;
    end;

    Details :=
      'Microsoft Graph erfolgreich erreicht.' + sLineBreak + sLineBreak +
      'Name: ' + UserInfo.DisplayName + sLineBreak +
      'Konto: ' + MailboxAddress + sLineBreak +
      'User-ID: ' + UserInfo.ID + sLineBreak +
      'Access Token: erhalten' + sLineBreak +
      'Refresh Token: erhalten' + sLineBreak +
      'Refresh Token sicher gespeichert: ja' + sLineBreak +
      'Refresh ohne Browser: erfolgreich' + sLineBreak +
      'GraphAccount: Available' + sLineBreak +
      'Gültigkeit: ' + IntToStr(Tokens.ExpiresIn) + ' Sekunden';

    MessageBox(FWindowHandle, PChar(Details), 'MailNotes Graph-Test',
      MB_OK or MB_ICONINFORMATION);
  except
    on E: Exception do
      MessageBox(FWindowHandle, PChar('Graph-Test fehlgeschlagen:' + sLineBreak + E.Message),
        'MailNotes Graph-Test', MB_OK or MB_ICONERROR);
  end;
end;


procedure TTrayIcon.TestGraphRefresh;
var
  GraphAccounts: TGraphAccounts;
  Account: TGraphAccount;
  StoredRefreshToken: string;
  Tokens: TGraphTokenResult;
  UserInfo: TGraphUserInfo;
  ErrorText: string;
  MailboxAddress: string;
  Details: string;
begin
  try
    GraphAccounts := TGraphAccounts.Create(FHttpServer.Database);
    try
      if not GraphAccounts.TryGet('gerhard@waldhelm.name', Account) then
        raise Exception.Create('Kein GraphAccount fuer gerhard@waldhelm.name gefunden.');
    finally
      GraphAccounts.Free;
    end;

    MailboxAddress := Account.MailboxAddress;
    if not TGraphTokenStore.LoadRefreshToken(MailboxAddress, StoredRefreshToken) then
      raise Exception.Create('Kein gespeicherter Refresh Token fuer ' + MailboxAddress + ' gefunden.');

    if not TGraphAuth.RefreshAccessToken(StoredRefreshToken, Tokens, ErrorText) then
      raise Exception.Create('Token-Refresh fehlgeschlagen: ' + ErrorText);

    if Tokens.RefreshToken <> '' then
      TGraphTokenStore.SaveRefreshToken(MailboxAddress, Tokens.RefreshToken);

    if not TGraphAuth.GetMe(Tokens.AccessToken, UserInfo, ErrorText) then
      raise Exception.Create('Graph /me nach Token-Refresh fehlgeschlagen: ' + ErrorText);

    if (Account.UserID <> '') and (not SameText(Account.UserID, UserInfo.ID)) then
      raise Exception.Create('Gespeicherter GraphAccount und Refresh Token gehoeren nicht zum selben Benutzer.');

    GraphAccounts := TGraphAccounts.Create(FHttpServer.Database);
    try
      GraphAccounts.MarkAvailable(MailboxAddress, TGraphAuth.ConfiguredTenantID, UserInfo.ID);
    finally
      GraphAccounts.Free;
    end;

    Details :=
      'Persistente Graph-Anmeldung erfolgreich.' + sLineBreak + sLineBreak +
      'Konto: ' + MailboxAddress + sLineBreak +
      'Name: ' + UserInfo.DisplayName + sLineBreak +
      'User-ID: ' + UserInfo.ID + sLineBreak +
      'Refresh Token aus DPAPI-Speicher: ja' + sLineBreak +
      'Browser/PKCE: nicht verwendet' + sLineBreak +
      'Graph /me: erfolgreich' + sLineBreak +
      'GraphAccount: Available' + sLineBreak +
      'Gueltigkeit: ' + IntToStr(Tokens.ExpiresIn) + ' Sekunden';

    MessageBox(FWindowHandle, PChar(Details), 'MailNotes Graph-Refresh-Test',
      MB_OK or MB_ICONINFORMATION);
  except
    on E: Exception do
      MessageBox(FWindowHandle,
        PChar('Graph-Refresh-Test fehlgeschlagen:' + sLineBreak + E.Message),
        'MailNotes Graph-Refresh-Test', MB_OK or MB_ICONERROR);
  end;
end;


procedure TTrayIcon.SetAutoBackupIntervalByIndex(const AIndex: Integer);
var
  Intervals: TBackupIntervals;
  Count: Integer;
begin
  Count := TBackupSettings.LoadIntervals(Intervals);
  if (AIndex < 0) or (AIndex >= Count) then
    Exit;
  TBackupSettings.SetSelectedIntervalHours(Intervals[AIndex]);
  UpdateAutoBackupMenu;
end;

procedure TTrayIcon.UpdateAutoBackupMenu;
const
  MenuIDs: array[0..MAX_BACKUP_INTERVALS - 1] of NativeUInt = (
    MENU_BACKUP_INTERVAL_1,
    MENU_BACKUP_INTERVAL_2,
    MENU_BACKUP_INTERVAL_3
  );
var
  Intervals: TBackupIntervals;
  Count, I, Selected: Integer;
  Flags: UINT;
begin
  if FBackupAutoMenu = 0 then
    Exit;

  while GetMenuItemCount(FBackupAutoMenu) > 0 do
    DeleteMenu(FBackupAutoMenu, 0, MF_BYPOSITION);

  Count := TBackupSettings.LoadIntervals(Intervals);
  Selected := TBackupSettings.SelectedIntervalHours;
  for I := 0 to Count - 1 do
  begin
    Flags := MF_STRING;
    if Selected = Intervals[I] then
      Flags := Flags or MF_CHECKED;
    AppendMenu(FBackupAutoMenu, Flags, MenuIDs[I],
      PChar(TBackupSettings.IntervalCaption(Intervals[I])));
  end;
  AppendMenu(FBackupAutoMenu, MF_SEPARATOR, 0, nil);
  Flags := MF_STRING;
  if Selected = 0 then
    Flags := Flags or MF_CHECKED;
  AppendMenu(FBackupAutoMenu, Flags, MENU_BACKUP_AUTO_OFF, 'Aus');
end;

function TTrayIcon.SelectBackupDirectory(out ADirectory: string): Boolean;
var
  BrowseInfo: TBrowseInfoW;
  ItemIDList: PItemIDList;
  PathBuffer: array[0..MAX_PATH] of WideChar;
begin
  Result := False;
  ADirectory := '';
  FillChar(BrowseInfo, SizeOf(BrowseInfo), 0);
  FillChar(PathBuffer, SizeOf(PathBuffer), 0);
  BrowseInfo.hwndOwner := FWindowHandle;
  BrowseInfo.lpszTitle := 'Backup-Ziel für MailNotes auswählen';
  BrowseInfo.ulFlags := BIF_RETURNONLYFSDIRS or BIF_NEWDIALOGSTYLE;

  ItemIDList := SHBrowseForFolderW(BrowseInfo);
  if ItemIDList = nil then
    Exit;
  try
    if SHGetPathFromIDListW(ItemIDList, PathBuffer) then
    begin
      ADirectory := PathBuffer;
      Result := ADirectory <> '';
    end;
  finally
    CoTaskMemFree(ItemIDList);
  end;
end;

procedure TTrayIcon.ChangeBackupDirectory;
var
  DirectoryName: string;
begin
  if not SelectBackupDirectory(DirectoryName) then
    Exit;

  TAppPaths.SetBackupDirectory(DirectoryName);
  UpdateTrayIcon;
  MessageBoxW(FWindowHandle, PWideChar(DirectoryName),
    'Backup-Ziel gespeichert', MB_OK or MB_ICONINFORMATION);
end;

procedure TTrayIcon.CreateDatabaseBackup;
var
  DirectoryName: string;
  BackupFile: string;
begin
  if FHttpServer = nil then
    Exit;

  DirectoryName := TAppPaths.BackupDirectory;
  if (DirectoryName = '') or not TDirectory.Exists(DirectoryName) then
  begin
    if not SelectBackupDirectory(DirectoryName) then
      Exit;
    TAppPaths.SetBackupDirectory(DirectoryName);
    UpdateTrayIcon;
  end;

  try
    BackupFile := FHttpServer.CreateDatabaseBackup(DirectoryName);
    MessageBoxW(FWindowHandle,
      PWideChar('Backup erfolgreich:' + sLineBreak + sLineBreak + BackupFile),
      'MailNotes Backup', MB_OK or MB_ICONINFORMATION);
  except
    on E: Exception do
      MessageBoxW(FWindowHandle, PWideChar(E.Message), 'Backup fehlgeschlagen',
        MB_OK or MB_ICONERROR);
  end;
end;

procedure TTrayIcon.ChangeDatabasePath;
const
  FILE_BUFFER_CHARS = 32768;
var
  Dialog: TOpenFilenameW;
  FileBuffer: array[0..FILE_BUFFER_CHARS - 1] of WideChar;
  InitialDir: string;
  CurrentFile: string;
  NewPath: string;
  Mode: string;
  InfoText: string;
  Filter: string;
begin
  if FHttpServer = nil then
  begin
    MessageBoxW(
      FWindowHandle,
      'Der HTTP-Server ist nicht verfügbar.',
      'Datenbankpfad kann nicht geändert werden',
      MB_OK or MB_ICONERROR
    );
    Exit;
  end;

  CurrentFile := TAppPaths.DatabaseFile;
  InitialDir := ExtractFilePath(CurrentFile);

  FillChar(FileBuffer, SizeOf(FileBuffer), 0);
  StrPLCopy(FileBuffer, ExtractFileName(CurrentFile), FILE_BUFFER_CHARS - 1);

  // Windows benötigt für die Filterliste eingebettete #0-Zeichen.
  Filter := 'SQLite-Datenbank (*.sqlite)' + #0 + '*.sqlite' + #0 +
            'Alle Dateien (*.*)' + #0 + '*.*' + #0 + #0;

  FillChar(Dialog, SizeOf(Dialog), 0);
  Dialog.lStructSize := SizeOf(Dialog);
  Dialog.hwndOwner := FWindowHandle;
  Dialog.lpstrFilter := PWideChar(Filter);
  Dialog.nFilterIndex := 1;
  Dialog.lpstrFile := @FileBuffer[0];
  Dialog.nMaxFile := FILE_BUFFER_CHARS;
  Dialog.lpstrInitialDir := PWideChar(InitialDir);
  Dialog.lpstrTitle := 'MailNotes-Datenbank auswählen';
  Dialog.lpstrDefExt := 'sqlite';
  Dialog.Flags := OFN_EXPLORER or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY;

  // GetSaveFileName ist hier bewusst gewählt: So kann entweder eine bereits
  // vorhandene Datenbank ausgewählt oder in einem neuen Zielordner eine neue
  // MailNotes.sqlite angegeben werden. Die Datei wird vom Dialog selbst nicht
  // angelegt oder überschrieben.
  if not GetSaveFileNameW(Dialog) then
    Exit;

  NewPath := FileBuffer;
  if Trim(NewPath) = '' then
    Exit;

  try
    NewPath := FHttpServer.ChangeDatabasePath(NewPath, Mode);

    if SameText(Mode, 'adopted') then
      InfoText := 'Die vorhandene Datenbank wurde übernommen.'
    else if SameText(Mode, 'moved') then
      InfoText := 'Die bisherige Datenbank wurde an den neuen Ort kopiert und übernommen.'
    else
      InfoText := 'Der Datenbankpfad ist unverändert.';

    MessageBoxW(
      FWindowHandle,
      PWideChar(InfoText + sLineBreak + sLineBreak + NewPath),
      'Datenbankpfad aktualisiert',
      MB_OK or MB_ICONINFORMATION
    );
  except
    on E: Exception do
      MessageBoxW(
        FWindowHandle,
        PWideChar(E.Message),
        'Datenbankpfad konnte nicht geändert werden',
        MB_OK or MB_ICONERROR
      );
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
  InstallerFile := '';
  SetCursor(LoadCursor(0, IDC_WAIT));
  try
    CheckResult := TMailNotesUpdater.CheckLatest;
  finally
    SetCursor(LoadCursor(0, IDC_ARROW));
  end;

  if CheckResult.Success then
    ApplyUpdateCheckResult(CheckResult);

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

  if (FDownloadedVersion = CheckResult.LatestVersion) and
     (FDownloadedInstallerFile <> '') and
     FileExists(FDownloadedInstallerFile) then
  begin
    InstallerFile := FDownloadedInstallerFile;
  end
  else
  begin
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
  end;

  try
    if InstallerFile = '' then
      InstallerFile := TMailNotesUpdater.DownloadInstaller(
        CheckResult.DownloadUrl,
        CheckResult.AssetName
      );

    Answer := MessageBoxW(
      FWindowHandle,
      PWideChar('Das Setup ist bereit:' + sLineBreak +
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



procedure TTrayIcon.StartAutomaticUpdateCheck;
var
  TargetWindow: HWND;
  UpdateThread: TThread;
begin
  if FUpdateCheckRunning then
    Exit;

  FUpdateCheckRunning := True;
  TargetWindow := FWindowHandle;

  UpdateThread := TThread.CreateAnonymousThread(
    procedure
    var
      ResultPointer: PAutomaticUpdateResult;
    begin
      New(ResultPointer);
      ResultPointer^.CheckResult := TMailNotesUpdater.CheckLatest;
      ResultPointer^.InstallerFile := '';
      ResultPointer^.DownloadError := '';

      // Bei der automatischen Prüfung wird ein gefundenes Update bereits
      // im Hintergrund heruntergeladen. Installiert wird erst nach
      // ausdrücklicher Bestätigung durch den Benutzer.
      if ResultPointer^.CheckResult.Success and
         ResultPointer^.CheckResult.UpdateAvailable then
      begin
        try
          ResultPointer^.InstallerFile := TMailNotesUpdater.DownloadInstaller(
            ResultPointer^.CheckResult.DownloadUrl,
            ResultPointer^.CheckResult.AssetName
          );
        except
          on E: Exception do
            ResultPointer^.DownloadError := E.Message;
        end;
      end;

      if not PostMessage(
        TargetWindow,
        WM_MAILNOTES_UPDATE_RESULT,
        WPARAM(ResultPointer),
        0
      ) then
        Dispose(ResultPointer);
    end
  );
  UpdateThread.FreeOnTerminate := True;
  UpdateThread.Start;
end;


procedure TTrayIcon.HandleAutomaticUpdateResult(
  const ResultPointer: Pointer
);
var
  AutomaticResult: TAutomaticUpdateResult;
  CheckResult: TUpdateCheckResult;
  Answer: Integer;
begin
  FUpdateCheckRunning := False;

  if ResultPointer = nil then
    Exit;

  try
    AutomaticResult := PAutomaticUpdateResult(ResultPointer)^;
  finally
    Dispose(PAutomaticUpdateResult(ResultPointer));
  end;

  CheckResult := AutomaticResult.CheckResult;

  // Netzwerk- und Downloadfehler bleiben bei der automatischen Prüfung
  // bewusst still. Die manuelle Updatesuche zeigt weiterhin eine
  // verständliche Meldung und kann jederzeit erneut angestoßen werden.
  if not CheckResult.Success then
    Exit;

  ApplyUpdateCheckResult(CheckResult);

  if not CheckResult.UpdateAvailable then
    Exit;

  if AutomaticResult.InstallerFile <> '' then
  begin
    FDownloadedInstallerFile := AutomaticResult.InstallerFile;
    FDownloadedVersion := CheckResult.LatestVersion;
  end;

  // Falls der Download fehlgeschlagen ist, bleibt lediglich der bisherige
  // Status "Update verfügbar" bestehen. Es erscheint kein störender Dialog.
  if (FDownloadedInstallerFile = '') or
     (FDownloadedVersion <> CheckResult.LatestVersion) or
     not FileExists(FDownloadedInstallerFile) then
    Exit;

  // Pro Agent-Lauf und Version nur einmal automatisch nachfragen.
  // Lehnt der Benutzer ab, bleibt das Update über das Tray-Menü erreichbar.
  if SameText(FUpdatePromptedVersion, CheckResult.LatestVersion) then
    Exit;

  FUpdatePromptedVersion := CheckResult.LatestVersion;

  Answer := MessageBoxW(
    FWindowHandle,
    PWideChar('MailNotes Agent ' + CheckResult.LatestVersion +
      ' wurde heruntergeladen.' + sLineBreak + sLineBreak +
      'Soll das Update jetzt installiert werden?'),
    'MailNotes Agent',
    MB_YESNO or MB_ICONINFORMATION or MB_DEFBUTTON1
  );

  if Answer = IDYES then
  begin
    if ShellExecuteW(
      FWindowHandle,
      'open',
      PWideChar(FDownloadedInstallerFile),
      nil,
      PWideChar(ExtractFilePath(FDownloadedInstallerFile)),
      SW_SHOWNORMAL
    ) <= 32 then
      MessageBoxW(
        FWindowHandle,
        'Das heruntergeladene Setup konnte nicht gestartet werden.',
        'MailNotes Agent',
        MB_OK or MB_ICONERROR
      );
  end;
end;


procedure TTrayIcon.ApplyUpdateCheckResult(const CheckResult: TUpdateCheckResult);
begin
  FUpdateAvailable := CheckResult.UpdateAvailable;

  if FUpdateAvailable then
    FLatestVersion := CheckResult.LatestVersion
  else
    FLatestVersion := '';

  UpdateTrayIcon;
end;

procedure TTrayIcon.UpdateUpdateMenu;
var
  MenuText: string;
begin
  if FPopupMenu = 0 then
    Exit;

  if FUpdateAvailable then
  begin
    if FLatestVersion <> '' then
      MenuText := 'Update verfügbar (' + FLatestVersion + ')...'
    else
      MenuText := 'Update verfügbar...';

    ModifyMenu(
      FPopupMenu,
      MENU_CHECK_UPDATES,
      MF_BYCOMMAND or MF_STRING,
      MENU_CHECK_UPDATES,
      PChar(MenuText)
    );

    SetMenuDefaultItem(
      FPopupMenu,
      MENU_CHECK_UPDATES,
      0
    );
  end
  else
  begin
    ModifyMenu(
      FPopupMenu,
      MENU_CHECK_UPDATES,
      MF_BYCOMMAND or MF_STRING,
      MENU_CHECK_UPDATES,
      PChar('Nach Updates suchen...')
    );

    SetMenuDefaultItem(
      FPopupMenu,
      UINT(-1),
      0
    );
  end;
end;

function TTrayIcon.DisplayState: TTrayState;
begin
  // Fehler und Warnungen haben Vorrang vor einem verfügbaren Update.
  case FState of
    tsError:
      Exit(tsError);
    tsWarning:
      Exit(tsWarning);
  end;

  if FUpdateAvailable then
    Result := tsUpdateAvailable
  else
    Result := tsOK;
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
  // Das Update-Symbol bleibt in beiden Fällen blau, damit es eindeutig ist.
  USE_MONOCHROME_ICONS = False;
var
  CurrentState: TTrayState;
begin
  CurrentState := DisplayState;

  if CurrentState = tsUpdateAvailable then
    Exit(6);

  if USE_MONOCHROME_ICONS then
  begin
    case CurrentState of
      tsWarning: Result := 4;
      tsError: Result := 5;
    else
      Result := 3;
    end;
  end
  else
  begin
    case CurrentState of
      tsWarning: Result := 1;
      tsError: Result := 2;
    else
      Result := 0;
    end;
  end;
end;

function TTrayIcon.StatusText: string;
begin
  case DisplayState of
    tsWarning:
      Result := 'Warnung';

    tsError:
      Result := 'Fehler';

    tsUpdateAvailable:
      if FLatestVersion <> '' then
        Result := 'Update ' + FLatestVersion + ' verfügbar'
      else
        Result := 'Update verfügbar';
  else
    Result := 'Bereit';
  end;
end;

{$ELSEIF Defined(MACOS)}

constructor TMacMenuHandler.Create(const AOwner: TTrayIcon);
begin
  FOwner := AOwner;
  inherited Create;
end;


function TMacMenuHandler.GetObjectiveCClass: PTypeInfo;
begin
  Result := TypeInfo(IMailNotesMenuHandler);
end;


procedure TMacMenuHandler.showAgentInfo;
begin
  if FOwner <> nil then
    FOwner.ShowAgentInfo;
end;


procedure TMacMenuHandler.revealAgentInFinder;
begin
  if FOwner <> nil then
    FOwner.RevealAgentInFinder;
end;


procedure TMacMenuHandler.revealDatabaseInFinder;
begin
  if FOwner <> nil then
    FOwner.RevealDatabaseInFinder;
end;


procedure TMacMenuHandler.revealConfigInFinder;
begin
  if FOwner <> nil then
    FOwner.RevealConfigInFinder;
end;


procedure TMacMenuHandler.revealBackupDirectoryInFinder;
begin
  if FOwner <> nil then
    FOwner.RevealBackupDirectoryInFinder;
end;


procedure TMacMenuHandler.changeDatabasePath;
begin
  if FOwner <> nil then
    FOwner.ChangeDatabasePath;
end;


procedure TMacMenuHandler.createDatabaseBackup;
begin
  if FOwner <> nil then
    FOwner.CreateDatabaseBackup;
end;


procedure TMacMenuHandler.changeBackupDirectory;
begin
  if FOwner <> nil then
    FOwner.ChangeBackupDirectory;
end;

procedure TMacMenuHandler.autoBackupInterval1;
begin
  if FOwner <> nil then
    FOwner.SetAutoBackupIntervalByIndex(0);
end;

procedure TMacMenuHandler.autoBackupInterval2;
begin
  if FOwner <> nil then
    FOwner.SetAutoBackupIntervalByIndex(1);
end;

procedure TMacMenuHandler.autoBackupInterval3;
begin
  if FOwner <> nil then
    FOwner.SetAutoBackupIntervalByIndex(2);
end;

procedure TMacMenuHandler.autoBackupOff;
begin
  if FOwner <> nil then
  begin
    TBackupSettings.SetSelectedIntervalHours(0);
    FOwner.UpdateAutoBackupMenu;
  end;
end;


constructor TTrayIcon.Create(AHttpServer: THttpServer);
begin
  inherited Create;
  FState := tsOK;
  FStatusBar := nil;
  FStatusItem := nil;
  FPopupMenu := nil;
  FStatusImage := nil;
  FInfoWindow := nil;
  FHttpServer := AHttpServer;
  FDatabaseLink := nil;
  FBackupDirectoryLink := nil;
  FLastBackupLabel := nil;
  FBackupMenuItem := nil;
  FBackupScheduler := nil;
  FBackupAutoMenu := nil;
  FBackupOffMenuItem := nil;
  FBackupIntervalMenuItems[0] := nil;
  FBackupIntervalMenuItems[1] := nil;
  FBackupIntervalMenuItems[2] := nil;
  FMenuHandler := TMacMenuHandler.Create(Self);

  CreateStatusItem;
  FBackupScheduler := TBackupScheduler.Create(FHttpServer);
  FBackupScheduler.Start;
end;


destructor TTrayIcon.Destroy;
begin
  if FBackupScheduler <> nil then
  begin
    FBackupScheduler.Stop;
    FBackupScheduler.BackupOnExit;
    FBackupScheduler.Free;
    FBackupScheduler := nil;
  end;

  if FInfoWindow <> nil then
  begin
    FInfoWindow.close;
    FInfoWindow.release;
    FInfoWindow := nil;
    FDatabaseLink := nil;
    FBackupDirectoryLink := nil;
    FLastBackupLabel := nil;
  end;

  DestroyStatusItem;
  FreeAndNil(FMenuHandler);
  inherited;
end;


procedure TTrayIcon.CreateStatusItem;
begin
  FStatusBar := TNSStatusBar.Wrap(TNSStatusBar.OCClass.systemStatusBar);
  FStatusItem := FStatusBar.statusItemWithLength(NSVariableStatusItemLength);

  if FStatusItem = nil then
    raise Exception.Create('Das macOS-Menüleistenicon konnte nicht angelegt werden.');

  // NSStatusBar hält das Statusitem nicht selbst fest. Ohne retain kann es
  // deshalb wieder aus der Menüleiste verschwinden.
  FStatusItem.retain;
  FStatusItem.setHighlightMode(True);

  CreateTrayMenu;
  FStatusItem.setMenu(FPopupMenu);
  UpdateTrayIcon;
end;


procedure TTrayIcon.DestroyStatusItem;
begin
  if FStatusBar <> nil then
    if FStatusItem <> nil then
      FStatusBar.removeStatusItem(FStatusItem);

  if FStatusImage <> nil then
  begin
    FStatusImage.release;
    FStatusImage := nil;
  end;

  if FPopupMenu <> nil then
  begin
    FBackupMenuItem := nil;
    FBackupAutoMenu := nil;
    FBackupOffMenuItem := nil;
    FBackupIntervalMenuItems[0] := nil;
    FBackupIntervalMenuItems[1] := nil;
    FBackupIntervalMenuItems[2] := nil;
    FPopupMenu.release;
    FPopupMenu := nil;
  end;

  if FStatusItem <> nil then
  begin
    FStatusItem.release;
    FStatusItem := nil;
  end;

  FStatusBar := nil;
end;


procedure TTrayIcon.CreateTrayMenu;
var
  MenuItem: NSMenuItem;
  AutoMenuItem: NSMenuItem;
  BackupDirectory: string;
  BackupCaption: string;
begin
  FPopupMenu := TNSMenu.Wrap(
    TNSMenu.Alloc.initWithTitle(StrToNSStr('MailNotes Agent'))
  );

  MenuItem := TNSMenuItem.Wrap(
    TNSMenuItem.Alloc.initWithTitle(
      StrToNSStr(StatusText),
      nil,
      StrToNSStr('')
    )
  );
  MenuItem.setEnabled(False);
  FPopupMenu.addItem(MenuItem);
  MenuItem.release;

  MenuItem := TNSMenuItem.Wrap(
    TNSMenuItem.Alloc.initWithTitle(
      StrToNSStr('MailNotes Agent …'),
      sel_getUid('showAgentInfo'),
      StrToNSStr('')
    )
  );
  MenuItem.setTarget(FMenuHandler.GetObjectID);
  FPopupMenu.addItem(MenuItem);
  MenuItem.release;

  FPopupMenu.addItem(TNSMenuItem.Wrap(TNSMenuItem.OCClass.separatorItem));

  BackupDirectory := TAppPaths.BackupDirectory;
  if (BackupDirectory <> '') and TDirectory.Exists(BackupDirectory) then
    BackupCaption := 'Datenbank sichern'
  else
    BackupCaption := 'Datenbank sichern …';

  MenuItem := TNSMenuItem.Wrap(
    TNSMenuItem.Alloc.initWithTitle(
      StrToNSStr(BackupCaption),
      sel_getUid('createDatabaseBackup'),
      StrToNSStr('')
    )
  );
  MenuItem.setTarget(FMenuHandler.GetObjectID);
  FBackupMenuItem := MenuItem;
  FPopupMenu.addItem(MenuItem);
  MenuItem.release;

  MenuItem := TNSMenuItem.Wrap(
    TNSMenuItem.Alloc.initWithTitle(
      StrToNSStr('Backup-Ziel ändern …'),
      sel_getUid('changeBackupDirectory'),
      StrToNSStr('')
    )
  );
  MenuItem.setTarget(FMenuHandler.GetObjectID);
  FPopupMenu.addItem(MenuItem);
  MenuItem.release;

  FBackupAutoMenu := TNSMenu.Wrap(TNSMenu.Alloc.initWithTitle(StrToNSStr('Automatisches Backup')));
  AutoMenuItem := TNSMenuItem.Wrap(
    TNSMenuItem.Alloc.initWithTitle(
      StrToNSStr('Automatisches Backup'),
      nil,
      StrToNSStr('')
    )
  );
  AutoMenuItem.setSubmenu(FBackupAutoMenu);
  FPopupMenu.addItem(AutoMenuItem);
  AutoMenuItem.release;
  UpdateAutoBackupMenu;

  FPopupMenu.addItem(TNSMenuItem.Wrap(TNSMenuItem.OCClass.separatorItem));

  MenuItem := TNSMenuItem.Wrap(
    TNSMenuItem.Alloc.initWithTitle(
      StrToNSStr('MailNotes Agent beenden'),
      sel_getUid('terminate:'),
      StrToNSStr('')
    )
  );
  FPopupMenu.addItem(MenuItem);
  MenuItem.release;
end;


procedure TTrayIcon.UpdateTrayIcon;
var
  ImagePath: string;
  NewImage: NSImage;
  StatusMenuItem: NSMenuItem;
  BackupDirectory: string;
begin
  ImagePath := TPath.Combine(
    TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..')),
    TPath.Combine(TPath.Combine('Resources', 'StartUp'), IconFileName)
  );

  NewImage := TNSImage.Wrap(
    TNSImage.Alloc.initWithContentsOfFile(StrToNSStr(ImagePath))
  );

  if NewImage = nil then
    raise Exception.CreateFmt(
      'Das Menüleistenicon wurde nicht gefunden: %s',
      [ImagePath]
    );

  // Die aktuellen SW-Icons sind gerenderte Graustufen-Icons und keine
  // echten macOS-Template-Glyphen. Im Template-Modus würde macOS die
  // komplette Alpha-Silhouette schwarz darstellen ("schwarzer Klotz").
  //
  // Außerdem die logische Bildgröße explizit auf Menüleistenformat setzen,
  // da ein aus .icns geladenes NSImage sonst seine 128x128-Punkt-Größe
  // beibehalten kann.
  NewImage.setSize(NSMakeSize(18, 18));
  NewImage.setTemplate(False);
  FStatusItem.setImage(NewImage);

  if FStatusImage <> nil then
    FStatusImage.release;
  FStatusImage := NewImage;

  if (FPopupMenu <> nil) and (FPopupMenu.numberOfItems > 0) then
  begin
    StatusMenuItem := FPopupMenu.itemAtIndex(0);
    StatusMenuItem.setTitle(StrToNSStr(StatusText));
  end;

  if FBackupMenuItem <> nil then
  begin
    BackupDirectory := TAppPaths.BackupDirectory;
    if (BackupDirectory <> '') and TDirectory.Exists(BackupDirectory) then
      FBackupMenuItem.setTitle(StrToNSStr('Datenbank sichern'))
    else
      FBackupMenuItem.setTitle(StrToNSStr('Datenbank sichern …'));
  end;
end;


function LastBackupDisplayText(const AFileName: string): string;
var
  BackupTime: TDateTime;
begin
  if AFileName = '' then
    Exit('Letztes Backup: noch keines');

  if TFile.Exists(AFileName) then
  begin
    BackupTime := TFile.GetLastWriteTime(AFileName);
    Result := 'Letztes Backup: ' +
      FormatDateTime('dd.mm.yyyy hh:nn', BackupTime) + sLineBreak +
      IncludeTrailingPathDelimiter(ExtractFileDir(AFileName)) + sLineBreak +
      ExtractFileName(AFileName);
  end
  else
    Result := 'Letztes Backup: ' + AFileName;
end;


procedure TTrayIcon.ShowAgentInfo;
var
  ContentView: NSView;
  CaptionLabel: NSTextField;
  VersionLabel: NSTextField;
  AgentLabel: NSTextField;
  DatabaseLabel: NSTextField;
  ConfigLabel: NSTextField;
  ConfigPathLabel: NSButton;
  AgentLink: NSButton;
  ChangeButton: NSButton;
  App: NSApplication;

  function NewLabel(const Text: string; const X, Y, W, H: Single): NSTextField;
  begin
    Result := TNSTextField.Wrap(
      TNSTextField.Alloc.initWithFrame(MakeNSRect(X, Y, W, H))
    );
    Result.setStringValue(StrToNSStr(Text));
    Result.setEditable(False);
    Result.setSelectable(False);
    Result.setBezeled(False);
    Result.setDrawsBackground(False);
  end;

  function NewLink(
    const Text: string;
    const SelectorName: PAnsiChar;
    const X, Y, W, H: Single
  ): NSButton;
  begin
    Result := TNSButton.Wrap(
      TNSButton.Alloc.initWithFrame(MakeNSRect(X, Y, W, H))
    );
    Result.setTitle(StrToNSStr(Text));
    Result.setBordered(False);
    Result.setFocusRingType(NSFocusRingTypeNone);
    Result.setAlignment(NSLeftTextAlignment);
    Result.setTarget(FMenuHandler.GetObjectID);
    Result.setAction(sel_getUid(SelectorName));
  end;

  function NewButton(
    const Text: string;
    const SelectorName: PAnsiChar;
    const X, Y, W, H: Single
  ): NSButton;
  begin
    Result := TNSButton.Wrap(
      TNSButton.Alloc.initWithFrame(MakeNSRect(X, Y, W, H))
    );
    Result.setTitle(StrToNSStr(Text));
    Result.setBezelStyle(NSRoundedBezelStyle);
    Result.setFocusRingType(NSFocusRingTypeNone);
    Result.setTarget(FMenuHandler.GetObjectID);
    Result.setAction(sel_getUid(SelectorName));
  end;

begin
  if FInfoWindow = nil then
  begin
    FInfoWindow := TNSWindow.Wrap(
      TNSWindow.Alloc.initWithContentRect(
        MakeNSRect(0, 0, 620, 394),
        NSTitledWindowMask or NSClosableWindowMask,
        NSBackingStoreBuffered,
        False
      )
    );

    FInfoWindow.setTitle(StrToNSStr('MailNotes Agent'));
    FInfoWindow.setReleasedWhenClosed(False);
    FInfoWindow.center;

    ContentView := TNSView.Wrap(FInfoWindow.contentView);

    CaptionLabel := NewLabel('MailNotes Agent', 24, 348, 570, 24);
    CaptionLabel.setFont(TNSFont.Wrap(TNSFont.OCClass.boldSystemFontOfSize(16)));
    ContentView.addSubview(CaptionLabel);
    CaptionLabel.release;

    VersionLabel := NewLabel('Version: ' + TAppInfo.Version, 24, 320, 570, 20);
    ContentView.addSubview(VersionLabel);
    VersionLabel.release;

    AgentLabel := NewLabel('Agent:', 24, 280, 570, 18);
    ContentView.addSubview(AgentLabel);
    AgentLabel.release;

    AgentLink := NewLink(
      TAppPaths.AgentFile,
      'revealAgentInFinder',
      20, 253, 580, 26
    );
    ContentView.addSubview(AgentLink);
    AgentLink.release;

    DatabaseLabel := NewLabel('Datenbank:', 24, 218, 570, 18);
    ContentView.addSubview(DatabaseLabel);
    DatabaseLabel.release;

    FDatabaseLink := NewLink(
      TAppPaths.DatabaseFile,
      'revealDatabaseInFinder',
      20, 191, 430, 26
    );
    ContentView.addSubview(FDatabaseLink);
    FDatabaseLink.release;

    ChangeButton := NewButton(
      'Pfad ändern …',
      'changeDatabasePath',
      465, 191, 130, 26
    );
    ContentView.addSubview(ChangeButton);
    ChangeButton.release;

    ConfigLabel := NewLabel('Konfiguration:', 24, 154, 570, 18);
    ContentView.addSubview(ConfigLabel);
    ConfigLabel.release;

    ConfigPathLabel := NewLink(
      TAppPaths.ConfigFile,
      'revealConfigInFinder',
      20, 127, 580, 26
    );
    ContentView.addSubview(ConfigPathLabel);
    ConfigPathLabel.release;

    DatabaseLabel := NewLabel('Backup-Ziel:', 24, 90, 570, 18);
    ContentView.addSubview(DatabaseLabel);
    DatabaseLabel.release;

    FBackupDirectoryLink := NewLink(
      TAppPaths.BackupDirectory,
      'revealBackupDirectoryInFinder',
      20, 63, 430, 26
    );
    ContentView.addSubview(FBackupDirectoryLink);
    FBackupDirectoryLink.release;

    ChangeButton := NewButton(
      'Ziel ändern …',
      'changeBackupDirectory',
      465, 63, 130, 26
    );
    ContentView.addSubview(ChangeButton);
    ChangeButton.release;

    FLastBackupLabel := NewLabel('', 24, 4, 570, 54);
    ContentView.addSubview(FLastBackupLabel);
    FLastBackupLabel.release;
  end;

  if FDatabaseLink <> nil then
    FDatabaseLink.setTitle(StrToNSStr(TAppPaths.DatabaseFile));

  if FBackupDirectoryLink <> nil then
  begin
    if TAppPaths.BackupDirectory = '' then
      FBackupDirectoryLink.setTitle(StrToNSStr('(noch nicht festgelegt)'))
    else
      FBackupDirectoryLink.setTitle(StrToNSStr(TAppPaths.BackupDirectory));
  end;

  if FLastBackupLabel <> nil then
    FLastBackupLabel.setStringValue(StrToNSStr(
      LastBackupDisplayText(TAppPaths.LastSuccessfulBackup)));

  App := TNSApplication.Wrap(TNSApplication.OCClass.sharedApplication);
  App.activateIgnoringOtherApps(True);
  FInfoWindow.makeKeyAndOrderFront(nil);
end;


procedure TTrayIcon.RevealAgentInFinder;
var
  Workspace: NSWorkspace;
begin
  Workspace := TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace);
  Workspace.selectFile(
    StrToNSStr(TAppPaths.AgentFile),
    StrToNSStr('')
  );
end;


procedure TTrayIcon.RevealDatabaseInFinder;
var
  Workspace: NSWorkspace;
begin
  TAppPaths.EnsureDataDirectory;
  Workspace := TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace);

  if TFile.Exists(TAppPaths.DatabaseFile) then
    Workspace.selectFile(
      StrToNSStr(TAppPaths.DatabaseFile),
      StrToNSStr('')
    )
  else
    Workspace.openFile(StrToNSStr(TAppPaths.DataDirectory));
end;


procedure TTrayIcon.RevealConfigInFinder;
var
  Workspace: NSWorkspace;
begin
  TAppPaths.EnsureDataDirectory;
  Workspace := TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace);

  if TFile.Exists(TAppPaths.ConfigFile) then
    Workspace.selectFile(
      StrToNSStr(TAppPaths.ConfigFile),
      StrToNSStr('')
    )
  else
    Workspace.openFile(StrToNSStr(TAppPaths.DataDirectory));
end;


function TTrayIcon.IconFileName: string;
begin
  case FState of
    tsWarning:
      Result := 'MN-WARN-SW.icns';

    tsError:
      Result := 'MN-ERR-SW.icns';
  else
    Result := 'MN-OK-SW.icns';
  end;
end;


procedure TTrayIcon.ShowMacMessage(const AMessage, ADetails: string);
var
  Alert: NSAlert;
begin
  Alert := TNSAlert.Wrap(TNSAlert.Alloc.init);
  try
    Alert.setMessageText(StrToNSStr(AMessage));
    if ADetails <> '' then
      Alert.setInformativeText(StrToNSStr(ADetails));
    Alert.addButtonWithTitle(StrToNSStr('OK'));
    Alert.runModal;
  finally
    Alert.release;
  end;
end;


procedure TTrayIcon.SetAutoBackupIntervalByIndex(const AIndex: Integer);
var
  Intervals: TBackupIntervals;
  Count: Integer;
begin
  Count := TBackupSettings.LoadIntervals(Intervals);
  if (AIndex < 0) or (AIndex >= Count) then
    Exit;
  TBackupSettings.SetSelectedIntervalHours(Intervals[AIndex]);
  UpdateAutoBackupMenu;
end;

procedure TTrayIcon.UpdateAutoBackupMenu;
var
  Intervals: TBackupIntervals;
  Count, I, Selected: Integer;
  MenuItem: NSMenuItem;
  Selector: SEL;
begin
  if FBackupAutoMenu = nil then
    Exit;

  FBackupAutoMenu.removeAllItems;
  FBackupIntervalMenuItems[0] := nil;
  FBackupIntervalMenuItems[1] := nil;
  FBackupIntervalMenuItems[2] := nil;
  FBackupOffMenuItem := nil;

  Count := TBackupSettings.LoadIntervals(Intervals);
  Selected := TBackupSettings.SelectedIntervalHours;
  for I := 0 to Count - 1 do
  begin
    case I of
      0: Selector := sel_getUid('autoBackupInterval1');
      1: Selector := sel_getUid('autoBackupInterval2');
    else
      Selector := sel_getUid('autoBackupInterval3');
    end;

    MenuItem := TNSMenuItem.Wrap(
      TNSMenuItem.Alloc.initWithTitle(
        StrToNSStr(TBackupSettings.IntervalCaption(Intervals[I])),
        Selector,
        StrToNSStr('')
      )
    );
    MenuItem.setTarget(FMenuHandler.GetObjectID);
    if Selected = Intervals[I] then
      MenuItem.setState(1)
    else
      MenuItem.setState(0);
    FBackupIntervalMenuItems[I] := MenuItem;
    FBackupAutoMenu.addItem(MenuItem);
    MenuItem.release;
  end;

  FBackupAutoMenu.addItem(TNSMenuItem.Wrap(TNSMenuItem.OCClass.separatorItem));
  MenuItem := TNSMenuItem.Wrap(
    TNSMenuItem.Alloc.initWithTitle(
      StrToNSStr('Aus'),
      sel_getUid('autoBackupOff'),
      StrToNSStr('')
    )
  );
  MenuItem.setTarget(FMenuHandler.GetObjectID);
  if Selected = 0 then
    MenuItem.setState(1)
  else
    MenuItem.setState(0);
  FBackupOffMenuItem := MenuItem;
  FBackupAutoMenu.addItem(MenuItem);
  MenuItem.release;
end;

function TTrayIcon.SelectBackupDirectory(out ADirectory: string): Boolean;
var
  Panel: NSOpenPanel;
  SelectedURL: NSURL;
begin
  Result := False;
  ADirectory := '';

  Panel := TNSOpenPanel.Wrap(TNSOpenPanel.OCClass.openPanel);
  Panel.setTitle(StrToNSStr('Backup-Ziel für MailNotes auswählen'));
  Panel.setPrompt(StrToNSStr('Auswählen'));
  Panel.setCanChooseDirectories(True);
  Panel.setCanChooseFiles(False);
  Panel.setAllowsMultipleSelection(False);
  Panel.setCanCreateDirectories(True);

  if Panel.runModal <> 1 then
    Exit;

  SelectedURL := Panel.URL;
  if SelectedURL = nil then
    Exit;

  ADirectory := NSStrToStr(SelectedURL.path);
  Result := ADirectory <> '';
end;

procedure TTrayIcon.RevealBackupDirectoryInFinder;
var
  Workspace: NSWorkspace;
  DirectoryName: string;
begin
  DirectoryName := TAppPaths.BackupDirectory;
  if DirectoryName = '' then
    Exit;

  Workspace := TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace);
  Workspace.openFile(StrToNSStr(DirectoryName));
end;

procedure TTrayIcon.ChangeBackupDirectory;
var
  DirectoryName: string;
begin
  if not SelectBackupDirectory(DirectoryName) then
    Exit;

  TAppPaths.SetBackupDirectory(DirectoryName);
  UpdateTrayIcon;
  if FBackupDirectoryLink <> nil then
    FBackupDirectoryLink.setTitle(StrToNSStr(DirectoryName));
  ShowMacMessage('Backup-Ziel gespeichert', DirectoryName);
end;

procedure TTrayIcon.CreateDatabaseBackup;
var
  DirectoryName: string;
  BackupFile: string;
begin
  if FHttpServer = nil then
  begin
    ShowMacMessage('Backup fehlgeschlagen', 'Der HTTP-Server ist nicht verfügbar.');
    Exit;
  end;

  DirectoryName := TAppPaths.BackupDirectory;
  if (DirectoryName = '') or not TDirectory.Exists(DirectoryName) then
  begin
    if not SelectBackupDirectory(DirectoryName) then
      Exit;
    TAppPaths.SetBackupDirectory(DirectoryName);
    UpdateTrayIcon;
  end;

  try
    BackupFile := FHttpServer.CreateDatabaseBackup(DirectoryName);
    if FBackupDirectoryLink <> nil then
      FBackupDirectoryLink.setTitle(StrToNSStr(DirectoryName));
    if FLastBackupLabel <> nil then
      FLastBackupLabel.setStringValue(StrToNSStr(
        LastBackupDisplayText(BackupFile)));
    ShowMacMessage('Backup erfolgreich', BackupFile);
  except
    on E: Exception do
      ShowMacMessage('Backup fehlgeschlagen', E.Message);
  end;
end;

procedure TTrayIcon.ChangeDatabasePath;
var
  Panel: NSOpenPanel;
  SelectedURL: NSURL;
  SelectedPath: string;
  NewPath: string;
  Mode: string;
  InfoText: string;
begin
  if FHttpServer = nil then
  begin
    ShowMacMessage(
      'Datenbankpfad kann nicht geändert werden.',
      'Der HTTP-Server ist nicht verfügbar.'
    );
    Exit;
  end;

  Panel := TNSOpenPanel.Wrap(TNSOpenPanel.OCClass.openPanel);
  Panel.setTitle(StrToNSStr('MailNotes-Datenbank auswählen'));
  Panel.setMessage(StrToNSStr(
    'Wähle einen Ordner für MailNotes.sqlite oder eine vorhandene SQLite-Datenbank aus.'
  ));
  Panel.setPrompt(StrToNSStr('Auswählen'));
  Panel.setCanChooseDirectories(True);
  Panel.setCanChooseFiles(True);
  Panel.setAllowsMultipleSelection(False);
  Panel.setCanCreateDirectories(True);

  // NSModalResponseOK hat unter macOS den Wert 1. Die numerische Prüfung
  // vermeidet Abhängigkeiten von unterschiedlich benannten Delphi-SDK-Konstanten.
  if Panel.runModal <> 1 then
    Exit;

  SelectedURL := Panel.URL;
  if SelectedURL = nil then
    Exit;

  SelectedPath := NSStrToStr(SelectedURL.path);
  if SelectedPath = '' then
    Exit;

  try
    NewPath := FHttpServer.ChangeDatabasePath(SelectedPath, Mode);

    if FDatabaseLink <> nil then
      FDatabaseLink.setTitle(StrToNSStr(NewPath));

    if SameText(Mode, 'adopted') then
      InfoText := 'Die vorhandene Datenbank wurde übernommen.'
    else if SameText(Mode, 'moved') then
      InfoText := 'Die bisherige Datenbank wurde an den neuen Ort kopiert und übernommen.'
    else
      InfoText := 'Der Datenbankpfad ist unverändert.';

    ShowMacMessage(
      'Datenbankpfad aktualisiert',
      InfoText + sLineBreak + sLineBreak + NewPath
    );
  except
    on E: Exception do
      ShowMacMessage(
        'Datenbankpfad konnte nicht geändert werden.',
        E.Message
      );
  end;
end;


function TTrayIcon.StatusText: string;
begin
  case FState of
    tsWarning:
      Result := 'Status: Warnung';

    tsError:
      Result := 'Status: Fehler';

    tsUpdateAvailable:
      Result := 'Status: Update verfügbar';
  else
    Result := 'Status: Bereit';
  end;
end;


procedure TTrayIcon.SetState(const State: TTrayState);
begin
  FState := State;
  UpdateTrayIcon;
end;


procedure TTrayIcon.Run;
begin
  TNSApplication.Wrap(TNSApplication.OCClass.sharedApplication).run;
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
end;

{$ENDIF}

end.
