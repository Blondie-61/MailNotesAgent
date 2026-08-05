unit uStatusDialog;

interface

{$IF Defined(MSWINDOWS)}
uses
  Winapi.Windows;

procedure ShowMailNotesStatusDialog(const Owner: HWND);
{$ENDIF}

implementation

{$IF Defined(MSWINDOWS)}

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Winapi.Messages,
  Winapi.ShellAPI,
  uAppPaths,
  uAppInfo,
  uTrayIconResources,
  uStatusLogo;

const
  STATUS_WINDOW_CLASS = 'MailNotesAgent.StatusWindow';

  ID_OPEN_AGENT = 2001;
  ID_OPEN_ADDIN = 2002;
  ID_OPEN_DATA = 2003;
  ID_COPY_INFO = 2004;
  ID_CLOSE = 2005;

  ID_STATUS_AUTOSTART = 2101;
  ID_STATUS_HTTP = 2102;
  ID_STATUS_SQLITE = 2103;

  // Farbpalette des Statusdialogs
  COLOR_BACKGROUND = $00FCF9F7; // #F7F9FC
  COLOR_PANEL      = $00FFFFFF; // #FFFFFF
  COLOR_BORDER     = $00E7DED9; // #D9DEE7
  COLOR_TEXT       = $00271811; // #111827
  COLOR_SECONDARY  = $00706055; // #556070
  COLOR_OK         = $002A7A13; // #137A2A

  WINDOW_WIDTH = 820;
  WINDOW_HEIGHT = 520;

var
  StatusWindow: HWND;
  FontNormal: HFONT;
  FontTitle: HFONT;
  FontSubtitle: HFONT;
  FontSection: HFONT;
  FontVersion: HFONT;
  BackgroundBrush: HBRUSH;
  PanelBrush: HBRUSH;
  AppIconLarge: HICON;
  AppIconSmall: HICON;

function CreateUiFont(const SizePt, Weight: Integer): HFONT;
var
  DC: HDC;
  Height: Integer;
begin
  DC := GetDC(0);
  try
    Height := -MulDiv(SizePt, GetDeviceCaps(DC, LOGPIXELSY), 72);
  finally
    ReleaseDC(0, DC);
  end;

  Result := CreateFontW(
    Height,
    0,
    0,
    0,
    Weight,
    0,
    0,
    0,
    DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS,
    CLIP_DEFAULT_PRECIS,
    CLEARTYPE_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE,
    'Segoe UI'
  );
end;

procedure EnsureFonts;
begin
  if FontNormal = 0 then
    FontNormal := CreateUiFont(9, FW_NORMAL);
  if FontTitle = 0 then
    FontTitle := CreateUiFont(18, FW_SEMIBOLD);
  if FontSubtitle = 0 then
    FontSubtitle := CreateUiFont(10, FW_NORMAL);
  if FontSection = 0 then
    FontSection := CreateUiFont(10, FW_SEMIBOLD);
  if FontVersion = 0 then
    FontVersion := CreateUiFont(17, FW_SEMIBOLD);
end;

procedure SetControlFont(const ControlHandle: HWND; const FontHandle: HFONT = 0);
begin
  if FontHandle <> 0 then
    SendMessage(ControlHandle, WM_SETFONT, WPARAM(FontHandle), LPARAM(1))
  else
    SendMessage(ControlHandle, WM_SETFONT, WPARAM(FontNormal), LPARAM(1));
end;

function AddStatic(
  const Parent: HWND;
  const Text: string;
  X, Y, W, H: Integer;
  Style: DWORD = SS_LEFT;
  const FontHandle: HFONT = 0;
  ControlID: Integer = 0
): HWND;
begin
  Result := CreateWindowExW(
    0,
    'STATIC',
    PWideChar(Text),
    WS_CHILD or WS_VISIBLE or Style,
    X, Y, W, H,
    Parent,
    HMENU(ControlID),
    HInstance,
    nil
  );
  SetControlFont(Result, FontHandle);
end;

function AddButton(
  const Parent: HWND;
  const Text: string;
  ID, X, Y, W, H: Integer;
  DefaultButton: Boolean = False
): HWND;
var
  ButtonStyle: DWORD;
begin
  if DefaultButton then
    ButtonStyle := BS_DEFPUSHBUTTON
  else
    ButtonStyle := BS_PUSHBUTTON;

  Result := CreateWindowExW(
    0,
    'BUTTON',
    PWideChar(Text),
    WS_CHILD or WS_VISIBLE or WS_TABSTOP or ButtonStyle,
    X, Y, W, H,
    Parent,
    HMENU(ID),
    HInstance,
    nil
  );
  SetControlFont(Result);
end;

procedure AddSeparator(const Parent: HWND; X, Y, W: Integer);
begin
  CreateWindowExW(
    0,
    'STATIC',
    nil,
    WS_CHILD or WS_VISIBLE or SS_ETCHEDHORZ,
    X, Y, W, 2,
    Parent,
    0,
    HInstance,
    nil
  );
end;

function IsAutostartEnabled: Boolean;
var
  Key: HKEY;
  ValueType: DWORD;
  ValueSize: DWORD;
begin
  Result := False;
  if RegOpenKeyExW(
    HKEY_CURRENT_USER,
    'Software\Microsoft\Windows\CurrentVersion\Run',
    0,
    KEY_QUERY_VALUE,
    Key
  ) <> ERROR_SUCCESS then
    Exit;

  try
    ValueType := 0;
    ValueSize := 0;
    Result := RegQueryValueExW(
      Key,
      'MailNotesAgent',
      nil,
      @ValueType,
      nil,
      @ValueSize
    ) = ERROR_SUCCESS;
  finally
    RegCloseKey(Key);
  end;
end;

function AddinStatusText: string;
begin
  if TDirectory.Exists(TAppPaths.AddinDirectory) then
    Result := 'Installiert'
  else
    Result := 'Noch nicht installiert';
end;

function DatabaseStatusText: string;
begin
  if TFile.Exists(TAppPaths.DatabaseFile) then
    Result := 'OK'
  else
    Result := 'Nicht vorhanden';
end;

function AutostartStatusText: string;
begin
  if IsAutostartEnabled then
    Result := 'Aktiv'
  else
    Result := 'Nicht aktiv';
end;

function StatusInformationText: string;
begin
  Result :=
    'MailNotes Agent' + sLineBreak +
    'Version: ' + TAppInfo.Version + sLineBreak +
    'Plattform: ' + TAppInfo.PlatformName + ' (x64)' + sLineBreak +
    'HTTP-Server: Port 48571 – OK' + sLineBreak +
    'SQLite: ' + DatabaseStatusText + sLineBreak +
    'Autostart: ' + AutostartStatusText + sLineBreak + sLineBreak +
    'Agent: ' + TAppPaths.AgentFile + sLineBreak +
    'Outlook-Add-in: ' + TAppPaths.AddinDirectory +
      ' (' + AddinStatusText + ')' + sLineBreak +
    'Datenbank: ' + TAppPaths.DatabaseFile;
end;

procedure CopyTextToClipboard(const Owner: HWND; const Text: string);
var
  MemoryHandle: HGLOBAL;
  MemoryPointer: Pointer;
  ByteCount: NativeUInt;
begin
  if not OpenClipboard(Owner) then
    RaiseLastOSError;
  try
    EmptyClipboard;
    ByteCount := (Length(Text) + 1) * SizeOf(Char);
    MemoryHandle := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, ByteCount);
    if MemoryHandle = 0 then
      RaiseLastOSError;

    MemoryPointer := GlobalLock(MemoryHandle);
    if MemoryPointer = nil then
    begin
      GlobalFree(MemoryHandle);
      RaiseLastOSError;
    end;

    try
      Move(PChar(Text)^, MemoryPointer^, ByteCount);
    finally
      GlobalUnlock(MemoryHandle);
    end;

    if SetClipboardData(CF_UNICODETEXT, MemoryHandle) = 0 then
    begin
      GlobalFree(MemoryHandle);
      RaiseLastOSError;
    end;
  finally
    CloseClipboard;
  end;
end;

procedure OpenExistingDirectory(
  const Owner: HWND;
  const DirectoryName, Description: string
);
begin
  if TDirectory.Exists(DirectoryName) then
    ShellExecuteW(Owner, 'open', PWideChar(DirectoryName), nil, nil, SW_SHOWNORMAL)
  else
    MessageBoxW(
      Owner,
      PWideChar(
        Description + ' ist noch nicht vorhanden.' +
        sLineBreak + sLineBreak + DirectoryName
      ),
      'MailNotes Agent',
      MB_OK or MB_ICONINFORMATION
    );
end;

procedure AddPathRow(
  const WindowHandle: HWND;
  const Caption, PathText, StatusText: string;
  ButtonID, Y: Integer
);
begin
  AddStatic(WindowHandle, Caption, 68, Y, 155, 24, SS_LEFT, FontSection);
  AddStatic(WindowHandle, PathText, 225, Y, 405, 36, SS_LEFT or SS_NOPREFIX);
  AddButton(WindowHandle, 'Ordner öffnen', ButtonID, 650, Y - 3, 125, 30);

  if StatusText <> '' then
    AddStatic(WindowHandle, StatusText, 225, Y + 25, 405, 20, SS_LEFT);
end;

function LoadMailNotesAppIcon(const Width, Height: Integer): HICON;
begin
  // Delphi bindet das in den Projektoptionen gewählte Symbol unter
  // dem Ressourcennamen "Icon_1" ein. "MAINICON" existiert hier nicht.
  Result := HICON(LoadImageW(
    HInstance,
    'Icon_1',
    IMAGE_ICON,
    Width,
    Height,
    LR_DEFAULTCOLOR
  ));

  // Fallback für ältere Projektstände mit numerischer Icon-ID.
  if Result = 0 then
    Result := HICON(LoadImageW(
      HInstance,
      MakeIntResource(1),
      IMAGE_ICON,
      Width,
      Height,
      LR_DEFAULTCOLOR
    ));

  // Letzter Fallback: das bereits im Quellcode eingebettete MailNotes-Icon.
  if Result = 0 then
    Result := CreateMailNotesIcon(0);
end;

procedure DrawStatusLogo(const DC: HDC; const X, Y, Size: Integer);
var
  Stream: TMemoryStream;
  PNG: TPngImage;
  Canvas: TCanvas;
begin
  Stream := TMemoryStream.Create;
  PNG := TPngImage.Create;
  Canvas := TCanvas.Create;
  try
    Stream.WriteBuffer(MailNotesStatusLogoData[0], Length(MailNotesStatusLogoData));
    Stream.Position := 0;
    PNG.LoadFromStream(Stream);

    Canvas.Handle := DC;
    try
      PNG.Draw(Canvas, Rect(X, Y, X + Size, Y + Size));
    finally
      Canvas.Handle := 0;
    end;
  finally
    Canvas.Free;
    PNG.Free;
    Stream.Free;
  end;
end;

procedure CreateStatusControls(const WindowHandle: HWND);
begin
  EnsureFonts;

  AddStatic(WindowHandle, 'MailNotes Agent', 112, 22, 390, 38, SS_LEFT, FontTitle);
  AddStatic(WindowHandle, 'Statusinformationen und Pfade', 113, 62, 390, 24, SS_LEFT, FontSubtitle);

  AddStatic(WindowHandle, TAppInfo.Version, 630, 22, 145, 38, SS_RIGHT, FontVersion);
  AddStatic(WindowHandle, TAppInfo.PlatformName + ' (x64)', 600, 62, 175, 24, SS_RIGHT, FontSubtitle);

  AddStatic(WindowHandle, 'Version', 56, 132, 130, 22);
  AddStatic(WindowHandle, TAppInfo.Version, 205, 132, 160, 22);

  AddStatic(WindowHandle, 'Plattform', 56, 171, 130, 22);
  AddStatic(WindowHandle, TAppInfo.PlatformName + ' (x64)', 205, 171, 160, 22);

  AddStatic(WindowHandle, 'Autostart', 56, 210, 130, 22);
  AddStatic(WindowHandle, AutostartStatusText, 205, 210, 160, 22, SS_LEFT, 0, ID_STATUS_AUTOSTART);

  AddStatic(WindowHandle, 'HTTP-Server', 420, 132, 130, 22);
  AddStatic(WindowHandle, 'Port 48571 – OK', 560, 132, 175, 22, SS_LEFT, 0, ID_STATUS_HTTP);

  AddStatic(WindowHandle, 'SQLite', 420, 171, 130, 22);
  AddStatic(WindowHandle, DatabaseStatusText, 560, 171, 175, 22, SS_LEFT, 0, ID_STATUS_SQLITE);

  AddPathRow(
    WindowHandle,
    'Agent (Programm)',
    TAppPaths.AgentFile,
    '',
    ID_OPEN_AGENT,
    321
  );

  AddPathRow(
    WindowHandle,
    'Outlook-Add-in',
    TAppPaths.AddinDirectory,
    AddinStatusText,
    ID_OPEN_ADDIN,
    371
  );

  AddPathRow(
    WindowHandle,
    'Datenbank',
    TAppPaths.DatabaseFile,
    '',
    ID_OPEN_DATA,
    431
  );

  AddStatic(
    WindowHandle,
    'Diese Informationen können bei der Diagnose und im Support hilfreich sein.',
    30, 492, 405, 24,
    SS_LEFT
  );

  AddButton(WindowHandle, 'In Zwischenablage kopieren', ID_COPY_INFO, 460, 486, 205, 32);
  AddButton(WindowHandle, 'Schließen', ID_CLOSE, 675, 486, 100, 32, True);
end;

procedure CenterWindow(const WindowHandle, Owner: HWND);
var
  WindowRect: TRect;
  OwnerRect: TRect;
  X: Integer;
  Y: Integer;
begin
  GetWindowRect(WindowHandle, WindowRect);
  if (Owner <> 0) and IsWindowVisible(Owner) then
    GetWindowRect(Owner, OwnerRect)
  else
    SystemParametersInfoW(SPI_GETWORKAREA, 0, @OwnerRect, 0);

  X := OwnerRect.Left +
    ((OwnerRect.Right - OwnerRect.Left) -
    (WindowRect.Right - WindowRect.Left)) div 2;
  Y := OwnerRect.Top +
    ((OwnerRect.Bottom - OwnerRect.Top) -
    (WindowRect.Bottom - WindowRect.Top)) div 2;

  SetWindowPos(
    WindowHandle,
    0,
    X,
    Y,
    0,
    0,
    SWP_NOSIZE or SWP_NOZORDER
  );
end;

function StatusWindowProc(
  WindowHandle: HWND;
  Msg: UINT;
  WParam: WPARAM;
  LParam: LPARAM
): LRESULT; stdcall;
var
  PaintStruct: TPaintStruct;
  DC: HDC;
  ClientRect: TRect;
  OldPen: HPEN;
  OldBrush: HBRUSH;
  BorderPen: HPEN;
begin
  case Msg of
    WM_ERASEBKGND:
      begin
        Result := 1;
        Exit;
      end;

    WM_PAINT:
      begin
        DC := BeginPaint(WindowHandle, PaintStruct);
        try
          GetClientRect(WindowHandle, ClientRect);
          FillRect(DC, ClientRect, BackgroundBrush);
          DrawStatusLogo(DC, 30, 18, 72);

          BorderPen := CreatePen(PS_SOLID, 1, COLOR_BORDER);
          OldPen := SelectObject(DC, BorderPen);
          OldBrush := SelectObject(DC, PanelBrush);
          try
            RoundRect(DC, 24, 104, 776, 282, 10, 10);
            RoundRect(DC, 24, 298, 776, 468, 10, 10);
          finally
            SelectObject(DC, OldBrush);
            SelectObject(DC, OldPen);
            DeleteObject(BorderPen);
          end;
        finally
          EndPaint(WindowHandle, PaintStruct);
        end;
        Result := 0;
        Exit;
      end;

    WM_CTLCOLORSTATIC:
      begin
        SetBkMode(HDC(WParam), TRANSPARENT);
        case GetDlgCtrlID(HWND(LParam)) of
          ID_STATUS_AUTOSTART,
          ID_STATUS_HTTP,
          ID_STATUS_SQLITE:
            SetTextColor(HDC(WParam), COLOR_OK);
        else
          SetTextColor(HDC(WParam), COLOR_TEXT);
        end;
        Result := LRESULT(GetStockObject(NULL_BRUSH));
        Exit;
      end;

    WM_CTLCOLORBTN:
      begin
        SetBkColor(HDC(WParam), COLOR_BACKGROUND);
        Result := LRESULT(BackgroundBrush);
        Exit;
      end;

    WM_CREATE:
      begin
        CreateStatusControls(WindowHandle);
        Result := 0;
        Exit;
      end;

    WM_COMMAND:
      begin
        case LoWord(WParam) of
          ID_OPEN_AGENT:
            OpenExistingDirectory(
              WindowHandle,
              TAppPaths.ExecutableDirectory,
              'Der Agent-Ordner'
            );

          ID_OPEN_ADDIN:
            OpenExistingDirectory(
              WindowHandle,
              TAppPaths.AddinDirectory,
              'Der Outlook-Add-in-Ordner'
            );

          ID_OPEN_DATA:
            begin
              TAppPaths.EnsureDataDirectory;
              OpenExistingDirectory(
                WindowHandle,
                TAppPaths.DataDirectory,
                'Der Datenordner'
              );
            end;

          ID_COPY_INFO:
            begin
              try
                CopyTextToClipboard(WindowHandle, StatusInformationText);
              except
                on E: Exception do
                  MessageBoxW(
                    WindowHandle,
                    PWideChar('Die Informationen konnten nicht kopiert werden:' +
                      sLineBreak + E.Message),
                    'MailNotes Agent',
                    MB_OK or MB_ICONERROR
                  );
              end;
            end;

          ID_CLOSE:
            DestroyWindow(WindowHandle);
        end;

        Result := 0;
        Exit;
      end;

    WM_CLOSE:
      begin
        DestroyWindow(WindowHandle);
        Result := 0;
        Exit;
      end;

    WM_DESTROY:
      begin
        StatusWindow := 0;
        Result := 0;
        Exit;
      end;
  end;

  Result := DefWindowProcW(WindowHandle, Msg, WParam, LParam);
end;

procedure RegisterStatusWindowClass;
var
  WindowClass: WNDCLASSEXW;
begin
  FillChar(WindowClass, SizeOf(WindowClass), 0);
  WindowClass.cbSize := SizeOf(WindowClass);

  if GetClassInfoExW(HInstance, STATUS_WINDOW_CLASS, WindowClass) then
    Exit;

  WindowClass.style := CS_HREDRAW or CS_VREDRAW;
  WindowClass.lpfnWndProc := @StatusWindowProc;
  WindowClass.hInstance := HInstance;
  if AppIconSmall = 0 then
    AppIconSmall := LoadMailNotesAppIcon(32, 32);
  WindowClass.hIcon := AppIconSmall;
  WindowClass.hCursor := LoadCursorW(0, IDC_ARROW);
  if BackgroundBrush = 0 then
    BackgroundBrush := CreateSolidBrush(COLOR_BACKGROUND);
  if PanelBrush = 0 then
    PanelBrush := CreateSolidBrush(COLOR_PANEL);
  WindowClass.hbrBackground := BackgroundBrush;
  WindowClass.lpszClassName := STATUS_WINDOW_CLASS;
  WindowClass.hIconSm := WindowClass.hIcon;

  if RegisterClassExW(WindowClass) = 0 then
    RaiseLastOSError;
end;

procedure ShowMailNotesStatusDialog(const Owner: HWND);
var
  Msg: TMsg;
  MessageResult: Integer;
  OwnerEnabled: Boolean;
begin
  if StatusWindow <> 0 then
  begin
    ShowWindow(StatusWindow, SW_RESTORE);
    SetForegroundWindow(StatusWindow);
    Exit;
  end;

  RegisterStatusWindowClass;
  EnsureFonts;

  StatusWindow := CreateWindowExW(
    WS_EX_DLGMODALFRAME,
    STATUS_WINDOW_CLASS,
    'MailNotes Agent – Status',
    WS_CAPTION or WS_SYSMENU,
    CW_USEDEFAULT,
    CW_USEDEFAULT,
    WINDOW_WIDTH,
    WINDOW_HEIGHT + 42,
    Owner,
    0,
    HInstance,
    nil
  );

  if StatusWindow = 0 then
    RaiseLastOSError;

  SendMessageW(StatusWindow, WM_SETICON, ICON_BIG, LPARAM(AppIconLarge));
  SendMessageW(StatusWindow, WM_SETICON, ICON_SMALL, LPARAM(AppIconSmall));

  CenterWindow(StatusWindow, Owner);
  ShowWindow(StatusWindow, SW_SHOW);
  UpdateWindow(StatusWindow);

  OwnerEnabled := (Owner <> 0) and IsWindowEnabled(Owner);
  if OwnerEnabled then
    EnableWindow(Owner, False);
  try
    while IsWindow(StatusWindow) do
    begin
      MessageResult := Integer(GetMessageW(Msg, 0, 0, 0));
      if MessageResult <= 0 then
        Break;

      if not IsDialogMessageW(StatusWindow, Msg) then
      begin
        TranslateMessage(Msg);
        DispatchMessageW(Msg);
      end;
    end;
  finally
    if OwnerEnabled then
    begin
      EnableWindow(Owner, True);
      SetForegroundWindow(Owner);
    end;
  end;
end;

{$ENDIF}

end.
