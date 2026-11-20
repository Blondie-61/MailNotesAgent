unit uFileLinkWindow;

interface

uses System.SysUtils, System.Classes,
{$IF Defined(MSWINDOWS)}
  Winapi.Windows, Winapi.Messages,
{$ELSEIF Defined(MACOS)}
  System.TypInfo, Macapi.ObjectiveC, Macapi.AppKit, Macapi.Foundation, Macapi.CocoaTypes,
{$ENDIF}
  System.SyncObjs;

type
  TFileLinkDisplay = record
    Path: string;
    Saved: Boolean;
  end;

  TFileLinkWindow = class;
{$IF Defined(MACOS)}
  IFileLinkSymbolsClass = interface(NSImageClass)
    ['{61425140-D03F-41BF-BFEB-419382E8E32F}']
    function imageWithSystemSymbolName(symbolName: NSString; accessibilityDescription: NSString): Pointer; cdecl;
  end;
  TFileLinkSymbols = class(TOCGenericImport<IFileLinkSymbolsClass, NSImage>) end;
  IFileLinkImageView = interface(NSImageView)
    ['{DA6F3ABF-FC7B-40AB-9216-85AF3CE6CC1D}']
    procedure setContentTintColor(color: NSColor); cdecl;
  end;
  TFileLinkImageView = class(TOCGenericImport<NSImageViewClass, IFileLinkImageView>) end;

  IMailNotesFileDropView = interface(NSView)
    ['{69749A5B-C2CF-4A50-ACEC-E436582D20F9}']
    procedure showFiles; cdecl;
    procedure refreshFiles; cdecl;
    procedure drawRect(dirtyRect: NSRect); cdecl;
    procedure draggingExited(sender: Pointer); cdecl;
    procedure chooseFiles; cdecl;
    procedure cancelFiles; cdecl;

    function draggingEntered(sender: Pointer): NSUInteger; cdecl;
    function prepareForDragOperation(sender: Pointer): Boolean; cdecl;
    function performDragOperation(sender: Pointer): Boolean; cdecl;
  end;
  TMacFileWindow = class(TOCLocal, NSWindowDelegate)
  private
    FOwner: TFileLinkWindow;
    FWindow: NSWindow;
    FView: NSView;
    FCaption, FSummary, FFeedback: NSTextField;
    FDocument: NSView;
    FDragging: Boolean;
  protected
    function GetObjectiveCClass: PTypeInfo; override;
  public
    constructor Create(Owner: TFileLinkWindow);
    destructor Destroy; override;
    function windowShouldClose(Sender: Pointer): Boolean; cdecl;
    procedure windowWillClose(notification: NSNotification); cdecl;
    procedure windowDidBecomeKey(notification: NSNotification); cdecl;
    procedure windowDidResignKey(notification: NSNotification); cdecl;
    procedure windowDidResize(notification: NSNotification); cdecl;
    procedure windowDidMove(notification: NSNotification); cdecl;
    procedure windowDidMiniaturize(notification: NSNotification); cdecl;
    procedure windowDidDeminiaturize(notification: NSNotification); cdecl;
    procedure windowDidEnterFullScreen(notification: NSNotification); cdecl;
    procedure windowDidExitFullScreen(notification: NSNotification); cdecl;
    procedure windowDidChangeBackingProperties(notification: NSNotification); cdecl;
    procedure QueueShow;
    procedure QueueRefresh;
    procedure showFiles; cdecl;
    procedure refreshFiles; cdecl;
    procedure drawRect(dirtyRect: NSRect); cdecl;
    procedure draggingExited(sender: Pointer); cdecl;
    procedure chooseFiles; cdecl;
    procedure cancelFiles; cdecl;

    function draggingEntered(sender: Pointer): NSUInteger; cdecl;
    function prepareForDragOperation(sender: Pointer): Boolean; cdecl;
    function performDragOperation(sender: Pointer): Boolean; cdecl;
  end;
{$ENDIF}

  // HTTP workers only exchange immutable snapshots under FLock. Native windows
  // and panels are created, shown and destroyed on the application's main thread.
  TFileLinkWindow = class
  private
    FLock: TObject;
    FToken, FMailID, FSubject, FState: string;
    FNoteID: Integer;
    FGeneration: Int64;
    FExpires: TDateTime;
    FPaths, FSavedPaths: TArray<string>;
    FClosed: Boolean;
    FRevision: Integer;
    FFeedback: string;
{$IF Defined(MSWINDOWS)}
    FHandle, FCaption, FSummary, FList, FFeedbackLabel: HWND;
    FFont, FTitleFont, FSmallFont: HFONT;
    FBackground: HBRUSH;
    procedure UpdateFileList;
    procedure PaintWindow;
    procedure ChooseFiles;
{$ELSEIF Defined(MACOS)}
    FMac: TMacFileWindow;
{$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;
    function BeginSelection(const MailID, Subject: string; NoteID: Integer;
      Generation: Int64; const ExistingPaths: TArray<string> = nil): string;
    function Snapshot(const Token: string; out MailID: string; out NoteID: Integer;
      out Generation: Int64; out Paths: TArray<string>): string;
    procedure Finish(const Token: string; const CommittedPaths: TArray<string>);
    procedure Fail(const Token, ErrorText: string);
    function Revision: Integer;
    function DisplayFiles: TArray<TFileLinkDisplay>;
    function Feedback: string;
    procedure Refresh;
    function Accept(const Paths: TArray<string>): Boolean;
    procedure Cancel;
    function Caption: string;
{$IF Defined(MSWINDOWS)}
    procedure WindowMessage(var Message: TMessage);
{$ENDIF}
  end;

implementation

uses System.IOUtils, System.DateUtils,
{$IF Defined(MSWINDOWS)}
  Winapi.ShellAPI, Winapi.CommDlg, Winapi.CommCtrl,
{$ELSEIF Defined(MACOS)}
  Macapi.Helpers, Macapi.ObjCRuntime,
{$ENDIF}
  System.Generics.Collections;

{$IF Defined(MSWINDOWS)}
const SHOW_FILES = WM_USER + 171; REFRESH_FILES = WM_USER + 172;
{$ENDIF}

{$IF Defined(MACOS)}
function FilePoint(X,Y: CGFloat): NSPoint;
begin Result.x:=X; Result.y:=Y; end;
function FileSize(W,H: CGFloat): NSSize;
begin Result.width:=W; Result.height:=H; end;
{$ENDIF}

function SameFilePath(const A,B: string): Boolean;
begin
{$IF Defined(MSWINDOWS)}
  Result := SameText(A,B);
{$ELSE}
  Result := A=B;
{$ENDIF}
end;
function FileNameOnly(const Path: string): string;
var Normal: string;
begin Normal:=StringReplace(Path,'\','/',[rfReplaceAll]); Result:=Copy(Normal,LastDelimiter('/',Normal)+1,MaxInt); end;
function FileFolder(const Path: string): string;
begin Result:=Copy(Path,1,Length(Path)-Length(FileNameOnly(Path))); end;

constructor TFileLinkWindow.Create;
begin
  inherited;
  FLock := TObject.Create;
{$IF Defined(MSWINDOWS)}
  InitCommonControls;
  FHandle := AllocateHWnd(WindowMessage);
  SetWindowLongPtr(FHandle, GWL_STYLE, WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU);
  SetWindowLongPtr(FHandle, GWL_EXSTYLE, WS_EX_APPWINDOW);
  SetWindowText(FHandle, 'MailNotes');
  SetWindowPos(FHandle, 0, (GetSystemMetrics(SM_CXSCREEN)-660) div 2,
    (GetSystemMetrics(SM_CYSCREEN)-650) div 2, 660, 650, SWP_NOZORDER or SWP_FRAMECHANGED);
  FFont := CreateFont(-15, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, 0, 'Segoe UI');
  FTitleFont := CreateFont(-23, 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, 0, 'Segoe UI');
  FSmallFont := CreateFont(-12, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, 0, 'Segoe UI');
  FBackground := CreateSolidBrush(RGB(246, 248, 250));
  var LabelHandle := CreateWindow('STATIC', 'Dateien verknüpfen', WS_CHILD or WS_VISIBLE,
    28, 22, 580, 32, FHandle, 0, HInstance, nil);
  SendMessage(LabelHandle, WM_SETFONT, FTitleFont, 1);
  FCaption := CreateWindow('STATIC', '', WS_CHILD or WS_VISIBLE,
    28, 62, 580, 42, FHandle, 0, HInstance, nil);
  SendMessage(FCaption, WM_SETFONT, FSmallFont, 1);
  LabelHandle := CreateWindow('STATIC', 'Dateien hierher ziehen', WS_CHILD or WS_VISIBLE or SS_CENTER,
    48, 174, 540, 26, FHandle, 0, HInstance, nil);
  SendMessage(LabelHandle, WM_SETFONT, FFont, 1);
  var Button := CreateWindow('BUTTON', 'Dateien auswählen …', WS_CHILD or WS_VISIBLE or WS_TABSTOP,
    218, 215, 200, 32, FHandle, HMENU(1), HInstance, nil);
  SendMessage(Button, WM_SETFONT, FFont, 1);
  FSummary := CreateWindow('STATIC', 'Noch keine Dateien', WS_CHILD or WS_VISIBLE,
    28, 286, 580, 24, FHandle, 0, HInstance, nil);
  SendMessage(FSummary, WM_SETFONT, FFont, 1);
  FList := CreateWindow(WC_LISTVIEW, '', WS_CHILD or WS_VISIBLE or LVS_REPORT or LVS_SINGLESEL,
    28, 320, 584, 210, FHandle, 0, HInstance, nil);
  SendMessage(FList, WM_SETFONT, FSmallFont, 1);
  ListView_SetExtendedListViewStyle(FList, LVS_EX_FULLROWSELECT or LVS_EX_DOUBLEBUFFER);
  ListView_SetBkColor(FList, RGB(255,255,255));
  var Column: TLVColumn;
  FillChar(Column, SizeOf(Column), 0); Column.mask := LVCF_TEXT or LVCF_WIDTH;
  Column.pszText := 'Datei'; Column.cx := 200; ListView_InsertColumn(FList, 0, Column);
  Column.pszText := 'Ordner'; Column.cx := 270; ListView_InsertColumn(FList, 1, Column);
  Column.pszText := 'Status'; Column.cx := 105; ListView_InsertColumn(FList, 2, Column);
  FFeedbackLabel := CreateWindow('STATIC', '', WS_CHILD or WS_VISIBLE,
    28, 540, 580, 22, FHandle, 0, HInstance, nil);
  SendMessage(FFeedbackLabel, WM_SETFONT, FSmallFont, 1);
  LabelHandle := CreateWindow('STATIC', 'Die Dateien bleiben an ihrem Platz.', WS_CHILD or WS_VISIBLE,
    28, 582, 420, 22, FHandle, 0, HInstance, nil);
  SendMessage(LabelHandle, WM_SETFONT, FSmallFont, 1);
  Button := CreateWindow('BUTTON', 'Fertig', WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_DEFPUSHBUTTON,
    512, 572, 100, 32, FHandle, HMENU(2), HInstance, nil);
  SendMessage(Button, WM_SETFONT, FFont, 1);
  DragAcceptFiles(FHandle, True);
{$ELSEIF Defined(MACOS)}
  TNSApplication.OCClass.sharedApplication;
  FMac := TMacFileWindow.Create(Self);
{$ENDIF}
end;

destructor TFileLinkWindow.Destroy;
begin
{$IF Defined(MSWINDOWS)}
  DragAcceptFiles(FHandle, False);
  DeallocateHWnd(FHandle);
  DeleteObject(FFont); DeleteObject(FTitleFont); DeleteObject(FSmallFont); DeleteObject(FBackground);
{$ELSEIF Defined(MACOS)}
  FMac.Free;
{$ENDIF}
  FLock.Free;
  inherited;
end;

function TFileLinkWindow.BeginSelection(const MailID, Subject: string;
  NoteID: Integer; Generation: Int64; const ExistingPaths: TArray<string>): string;
begin
  TMonitor.Enter(FLock);
  try
    if ((FState = 'waiting') or (FState = 'ready')) and (Now < FExpires) then begin
      if (FMailID <> MailID) or (FNoteID <> NoteID) or (FGeneration <> Generation) then
        raise Exception.Create('Das Dateifenster gehört noch zu einer anderen Mail. Bitte dort zuerst Fertig wählen.');
    end else begin
      FToken := TGUID.NewGuid.ToString;
      FMailID := MailID; FNoteID := NoteID; FGeneration := Generation;
      FSubject := Subject; FState := 'waiting'; FPaths := nil;
      FSavedPaths := Copy(ExistingPaths); FClosed := False; FRevision := 0;
      FFeedback := '';
    end;
    FExpires := IncHour(Now, 24);
    Result := FToken;
  finally TMonitor.Exit(FLock); end;
{$IF Defined(MSWINDOWS)}
  PostMessage(FHandle, SHOW_FILES, 0, 0);
{$ELSEIF Defined(MACOS)}
  FMac.QueueShow;
{$ENDIF}
end;

function TFileLinkWindow.Snapshot(const Token: string; out MailID: string;
  out NoteID: Integer; out Generation: Int64; out Paths: TArray<string>): string;
begin
  TMonitor.Enter(FLock);
  try
    if (Token = '') or (Token <> FToken) then Exit('unknown');
    MailID := FMailID; NoteID := FNoteID; Generation := FGeneration;
    Paths := Copy(FPaths); Result := FState;
  finally TMonitor.Exit(FLock); end;
end;

function TFileLinkWindow.Caption: string;
begin
  TMonitor.Enter(FLock);
  try Result := FSubject; finally TMonitor.Exit(FLock); end;
end;

function TFileLinkWindow.Revision: Integer;
begin
  TMonitor.Enter(FLock);
  try Result := FRevision; finally TMonitor.Exit(FLock); end;
end;

function TFileLinkWindow.Feedback: string;
begin
  TMonitor.Enter(FLock);
  try Result := FFeedback; finally TMonitor.Exit(FLock); end;
end;

function TFileLinkWindow.DisplayFiles: TArray<TFileLinkDisplay>;
var I, J: Integer;
begin
  TMonitor.Enter(FLock);
  try
    SetLength(Result, Length(FSavedPaths) + Length(FPaths));
    for I := 0 to High(FSavedPaths) do begin Result[I].Path := FSavedPaths[I]; Result[I].Saved := True; end;
    J := Length(FSavedPaths);
    for I := 0 to High(FPaths) do begin Result[J + I].Path := FPaths[I]; Result[J + I].Saved := False; end;
  finally TMonitor.Exit(FLock); end;
end;

procedure TFileLinkWindow.Finish(const Token: string; const CommittedPaths: TArray<string>);
var Pending, Saved: TList<string>; P: string;
begin
  Pending := TList<string>.Create; Saved := TList<string>.Create;
  try
    TMonitor.Enter(FLock);
    try
      if FToken <> Token then Exit;
      Saved.AddRange(FSavedPaths); Pending.AddRange(FPaths);
      // A second drop may arrive while the previous snapshot is being saved.
      // Acknowledge only those paths, never clear the entire pending queue.
      for P in CommittedPaths do begin
        Pending.Remove(P);
        if not Saved.Contains(P) then Saved.Add(P);
      end;
      FSavedPaths := Saved.ToArray; FPaths := Pending.ToArray;
      Inc(FRevision); FFeedback := '';
      if Length(FPaths) > 0 then FState := 'ready'
      else if FClosed then FState := 'done' else FState := 'waiting';
    finally TMonitor.Exit(FLock); end;
  finally Saved.Free; Pending.Free; end;
  Refresh;
end;

procedure TFileLinkWindow.Fail(const Token, ErrorText: string);
begin
  TMonitor.Enter(FLock);
  try
    if FToken <> Token then Exit;
    FState := 'error'; FFeedback := ErrorText;
  finally TMonitor.Exit(FLock); end;
  Refresh;
end;

function TFileLinkWindow.Accept(const Paths: TArray<string>): Boolean;
var L: TList<string>; P: string; Added, Valid: Integer;
begin
  Result := False; Added := 0; Valid := 0;
  L := TList<string>.Create;
  try
    for P in Paths do
      if (P <> '') and TPath.IsPathRooted(P) and TFile.Exists(P) and
         not L.Contains(P) and (L.Count < 100) then L.Add(P);
    TMonitor.Enter(FLock);
    try
      if FClosed or not ((FState = 'waiting') or (FState = 'ready')) then Exit;
      Valid := L.Count;
      for P in L do begin
        var Exists := False;
        for var Known in FSavedPaths do
          if SameFilePath(Known, P) then begin Exists := True; Break; end;
        if not Exists then for var Known in FPaths do
          if SameFilePath(Known, P) then begin Exists := True; Break; end;
        if not Exists then begin
          SetLength(FPaths, Length(FPaths) + 1); FPaths[High(FPaths)] := P; Inc(Added);
        end;
      end;
      if Added > 0 then begin FState := 'ready'; FFeedback := ''; end
      else if Valid > 0 then FFeedback := 'Diese Dateien sind bereits erfasst.'
      else FFeedback := 'Bitte Dateien auswählen – keine Ordner.';
      Result := Valid > 0;
    finally TMonitor.Exit(FLock); end;
  finally L.Free; end;
  Refresh;
end;

procedure TFileLinkWindow.Cancel;
begin
  TMonitor.Enter(FLock);
  try
    FClosed := True;
    if (FState = 'waiting') or (FState = 'error') then FState := 'done';
  finally TMonitor.Exit(FLock); end;
end;

procedure TFileLinkWindow.Refresh;
begin
{$IF Defined(MSWINDOWS)}
  PostMessage(FHandle, REFRESH_FILES, 0, 0);
{$ELSEIF Defined(MACOS)}
  FMac.QueueRefresh;
{$ENDIF}
end;

{$IF Defined(MSWINDOWS)}
procedure TFileLinkWindow.UpdateFileList;
var Rows: TArray<TFileLinkDisplay>; Item: TLVItem; I: Integer; Name, Folder, Status: string;
begin
  Rows := DisplayFiles;
  SendMessage(FList, WM_SETREDRAW, 0, 0);
  try
    ListView_DeleteAllItems(FList);
    for I := 0 to High(Rows) do begin
      Name := FileNameOnly(Rows[I].Path); Folder := FileFolder(Rows[I].Path);
      if Rows[I].Saved then Status := 'Verknüpft' else Status := 'Wird verknüpft …';
      FillChar(Item, SizeOf(Item), 0); Item.mask := LVIF_TEXT;
      Item.iItem := I; Item.pszText := PChar(Name); ListView_InsertItem(FList, Item);
      ListView_SetItemText(FList, I, 1, PChar(Folder));
      ListView_SetItemText(FList, I, 2, PChar(Status));
    end;
  finally SendMessage(FList, WM_SETREDRAW, 1, 0); InvalidateRect(FList, nil, True); end;
  SetWindowText(FSummary, PChar(IntToStr(Length(Rows)) + ' Dateien erfasst'));
  SetWindowText(FFeedbackLabel, PChar(Feedback));
end;

procedure TFileLinkWindow.PaintWindow;
var PS: TPaintStruct; DC: HDC; R: TRect; Pen, OldPen: HPEN; Brush, OldBrush: HBRUSH;
begin
  DC := BeginPaint(FHandle, PS);
  try
    GetClientRect(FHandle, R); FillRect(DC, R, FBackground);
    Pen := CreatePen(PS_DASH, 1, RGB(175,184,193)); OldPen := SelectObject(DC, Pen);
    Brush := CreateSolidBrush(RGB(255,255,255)); OldBrush := SelectObject(DC, Brush);
    RoundRect(DC, 28, 110, 612, 268, 14, 14);
    SelectObject(DC, OldPen); DeleteObject(Pen);
    Pen := CreatePen(PS_SOLID, 2, RGB(87,96,106)); SelectObject(DC, Pen);
    MoveToEx(DC, 320, 153, nil); LineTo(DC, 320, 127);
    MoveToEx(DC, 312, 135, nil); LineTo(DC, 320, 127); LineTo(DC, 328, 135);
    MoveToEx(DC, 306, 145, nil); LineTo(DC, 306, 157); LineTo(DC, 334, 157); LineTo(DC, 334, 145);
    SelectObject(DC, OldPen); DeleteObject(Pen); SelectObject(DC, OldBrush); DeleteObject(Brush);
  finally EndPaint(FHandle, PS); end;
end;

procedure TFileLinkWindow.WindowMessage(var Message: TMessage);
var Drop: HDROP; Count, I: Integer; Paths: TArray<string>; Buffer: TArray<Char>;
begin
  case Message.Msg of
    SHOW_FILES:
      begin SetWindowText(FCaption, PChar(Caption)); UpdateFileList; ShowWindow(FHandle, SW_SHOWNORMAL);
        SetForegroundWindow(FHandle); Message.Result := 0; Exit; end;
    REFRESH_FILES:
      begin UpdateFileList; Message.Result := 0; Exit; end;
    WM_ERASEBKGND:
      begin Message.Result := 1; Exit; end;
    WM_PAINT:
      begin PaintWindow; Message.Result := 0; Exit; end;
    WM_CTLCOLORSTATIC:
      begin SetBkMode(HDC(Message.WParam),TRANSPARENT); SetTextColor(HDC(Message.WParam),RGB(87,96,106));
        Message.Result:=LRESULT(FBackground); Exit; end;
    WM_CLOSE:
      begin Cancel; ShowWindow(FHandle, SW_HIDE); Message.Result := 0; Exit; end;
    WM_COMMAND:
      begin
        if LoWord(Message.WParam) = 1 then ChooseFiles
        else if LoWord(Message.WParam) = 2 then begin Cancel; ShowWindow(FHandle, SW_HIDE); end;
        Message.Result := 0; Exit;
      end;
    WM_DROPFILES:
      begin
        Drop := HDROP(Message.WParam);
        try
          Count := DragQueryFile(Drop, $FFFFFFFF, nil, 0);
          if Count > 100 then Count := 100;
          SetLength(Paths, Count);
          for I := 0 to Count - 1 do begin
            SetLength(Buffer, DragQueryFile(Drop, I, nil, 0) + 1);
            DragQueryFile(Drop, I, @Buffer[0], Length(Buffer)); Paths[I] := PChar(@Buffer[0]);
          end;
          Accept(Paths);
        finally DragFinish(Drop); end;
        Message.Result := 0; Exit;
      end;
  end;
  Message.Result := DefWindowProc(FHandle, Message.Msg, Message.WParam, Message.LParam);
end;

procedure TFileLinkWindow.ChooseFiles;
var Dialog: TOpenFilename; Buffer: TArray<Char>; Parts: TList<string>;
  P: PChar; Paths: TArray<string>; I: Integer;
begin
  SetLength(Buffer, 65536); FillChar(Dialog, SizeOf(Dialog), 0);
  Dialog.lStructSize := SizeOf(Dialog); Dialog.hwndOwner := FHandle;
  Dialog.lpstrFile := @Buffer[0]; Dialog.nMaxFile := Length(Buffer);
  Dialog.lpstrTitle := 'Dateien verknüpfen';
  Dialog.Flags := OFN_EXPLORER or OFN_ALLOWMULTISELECT or OFN_FILEMUSTEXIST or OFN_NOCHANGEDIR;
  if not GetOpenFileName(Dialog) then Exit;
  Parts := TList<string>.Create;
  try
    P := @Buffer[0];
    while P^ <> #0 do begin Parts.Add(P); Inc(P, Length(P) + 1); end;
    if Parts.Count = 1 then Paths := [Parts[0]] else begin
      SetLength(Paths, Parts.Count - 1);
      for I := 1 to Parts.Count - 1 do Paths[I - 1] := TPath.Combine(Parts[0], Parts[I]);
    end;
    Accept(Paths);
  finally Parts.Free; end;
end;
{$ELSEIF Defined(MACOS)}
function TMacFileWindow.GetObjectiveCClass: PTypeInfo;
begin Result := TypeInfo(IMailNotesFileDropView); end;

constructor TMacFileWindow.Create(Owner: TFileLinkWindow);
var LabelView: NSTextField; Button: NSButton; Types: NSArray;
  TypeIDs: array[0..1] of Pointer;
  function LabelAt(const Text: string; X, Y, W, H, Size: Single; Bold: Boolean = False): NSTextField;
  begin
    Result := TNSTextField.Wrap(TNSTextField.Alloc.initWithFrame(MakeNSRect(X,Y,W,H)));
    Result.setStringValue(StrToNSStr(Text)); Result.setEditable(False); Result.setSelectable(False);
    Result.setBezeled(False); Result.setDrawsBackground(False);
    if Bold then Result.setFont(TNSFont.Wrap(TNSFont.OCClass.boldSystemFontOfSize(Size)))
    else Result.setFont(TNSFont.Wrap(TNSFont.OCClass.systemFontOfSize(Size)));
    Result.setTextColor(TNSColor.Wrap(TNSColor.OCClass.colorWithCalibratedRed(0.14,0.16,0.18,1)));
    FView.addSubview(Result); Result.release;
  end;
begin
  FOwner := Owner; inherited Create;
  UpdateObjectID(NSView(Super).initWithFrame(MakeNSRect(0,0,640,600)));
  FView := TNSView.Wrap(GetObjectID);
  FWindow := TNSWindow.Wrap(TNSWindow.Alloc.initWithContentRect(MakeNSRect(0,0,640,600),
    NSTitledWindowMask or NSClosableWindowMask, NSBackingStoreBuffered, False));
  FWindow.setContentView(FView); FWindow.setDelegate(Self); FWindow.setReleasedWhenClosed(False);
  FWindow.setTitle(StrToNSStr('MailNotes'));
  LabelAt('Dateien verknüpfen',24,540,592,34,23,True);
  FCaption := LabelAt('',24,497,592,34,12);
  FCaption.setTextColor(TNSColor.Wrap(TNSColor.OCClass.secondaryLabelColor));
  LabelView := LabelAt('Dateien hierher ziehen',120,390,400,28,17,True);
  LabelView.setAlignment(NSCenterTextAlignment);
  Button := TNSButton.Wrap(TNSButton.Alloc.initWithFrame(MakeNSRect(216,343,208,32)));
  Button.setTitle(StrToNSStr('Dateien auswählen …')); Button.setBezelStyle(NSRoundedBezelStyle);
  Button.setFont(TNSFont.Wrap(TNSFont.OCClass.systemFontOfSize(13)));
  Button.setTarget(GetObjectID); Button.setAction(sel_getUid('chooseFiles'));
  FView.addSubview(Button); Button.release;
  FSummary := LabelAt('Noch keine Dateien',24,283,592,24,13,True);
  var Scroll := TNSScrollView.Wrap(TNSScrollView.Alloc.initWithFrame(MakeNSRect(24,82,592,190)));
  Scroll.setHasVerticalScroller(True); Scroll.setHasHorizontalScroller(False);
  Scroll.setAutohidesScrollers(True); Scroll.setBorderType(NSNoBorder);
  Scroll.setDrawsBackground(True); Scroll.setBackgroundColor(TNSColor.Wrap(TNSColor.OCClass.whiteColor));
  FDocument := TNSView.Wrap(TNSView.Alloc.initWithFrame(MakeNSRect(0,0,576,190)));
  Scroll.setDocumentView(FDocument); FDocument.release;
  FView.addSubview(Scroll); Scroll.release;
  FFeedback := LabelAt('',24,54,592,22,11);
  FFeedback.setTextColor(TNSColor.Wrap(TNSColor.OCClass.secondaryLabelColor));
  LabelView := LabelAt('Die Dateien bleiben an ihrem Platz.',24,20,460,22,11);
  LabelView.setTextColor(TNSColor.Wrap(TNSColor.OCClass.secondaryLabelColor));
  Button := TNSButton.Wrap(TNSButton.Alloc.initWithFrame(MakeNSRect(520,16,96,32)));
  Button.setTitle(StrToNSStr('Fertig')); Button.setBezelStyle(NSRoundedBezelStyle);
  Button.setKeyEquivalent(StrToNSStr(#13));
  Button.setTarget(GetObjectID); Button.setAction(sel_getUid('cancelFiles'));
  FView.addSubview(Button); Button.release;
  TypeIDs[0] := (NSFilenamesPboardType as ILocalObject).GetObjectID;
  TypeIDs[1] := (StrToNSStr('public.file-url') as ILocalObject).GetObjectID;
  Types := TNSArray.Wrap(TNSArray.OCClass.arrayWithObjects(@TypeIDs[0],2));
  FView.registerForDraggedTypes(Types);
end;

destructor TMacFileWindow.Destroy;
begin
  FWindow.setDelegate(nil); FWindow.orderOut(nil); FView.unregisterDraggedTypes;
  FWindow.release; FWindow := nil; FView := nil;
  inherited;
end;

procedure TMacFileWindow.QueueShow;
begin
  FView.performSelectorOnMainThread(sel_getUid('showFiles'), nil, False);
end;
procedure TMacFileWindow.showFiles;
begin
  FCaption.setStringValue(StrToNSStr(FOwner.Caption)); refreshFiles; FWindow.center;
  TNSApplication.Wrap(TNSApplication.OCClass.sharedApplication).activateIgnoringOtherApps(True);
  FWindow.makeKeyAndOrderFront(nil);
end;
procedure TMacFileWindow.QueueRefresh;
begin FView.performSelectorOnMainThread(sel_getUid('refreshFiles'),nil,False); end;

procedure TMacFileWindow.refreshFiles;
var Rows: TArray<TFileLinkDisplay>; Child: NSView; LabelView: NSTextField;
  Height, Y: Single; I: Integer;
  procedure RowLabel(const Text: string; X,Y,W,H,Size: Single; Secondary: Boolean);
  begin
    LabelView := TNSTextField.Wrap(TNSTextField.Alloc.initWithFrame(MakeNSRect(X,Y,W,H)));
    LabelView.setStringValue(StrToNSStr(Text)); LabelView.setEditable(False); LabelView.setSelectable(False);
    LabelView.setBezeled(False); LabelView.setDrawsBackground(False);
    LabelView.setFont(TNSFont.Wrap(TNSFont.OCClass.systemFontOfSize(Size)));
    if Secondary then LabelView.setTextColor(TNSColor.Wrap(TNSColor.OCClass.secondaryLabelColor));
    LabelView.setToolTip(StrToNSStr(Text));
    FDocument.addSubview(LabelView); LabelView.release;
  end;
begin
  Rows := FOwner.DisplayFiles;
  while FDocument.subviews.count > 0 do begin
    Child := TNSView.Wrap(FDocument.subviews.objectAtIndex(0)); Child.removeFromSuperview;
  end;
  Height := Length(Rows) * 56;
  if Height < 190 then Height := 190;
  FDocument.setFrameSize(FileSize(576,Height));
  for I := 0 to High(Rows) do begin
    Y := Height - (I+1)*56;
    var Icon := TNSImageView.Wrap(TNSImageView.Alloc.initWithFrame(MakeNSRect(13,Y+21,20,20)));
    Icon.setImage(TNSImage.Wrap(TFileLinkSymbols.OCClass.imageWithSystemSymbolName(
      StrToNSStr('link'),StrToNSStr('Dateiverknüpfung'))));
    TFileLinkImageView.Wrap((Icon as ILocalObject).GetObjectID).setContentTintColor(
      TNSColor.Wrap(TNSColor.OCClass.secondaryLabelColor));
    FDocument.addSubview(Icon); Icon.release;
    RowLabel(FileNameOnly(Rows[I].Path),44,Y+28,376,20,13,False);
    RowLabel(FileFolder(Rows[I].Path),44,Y+8,490,18,11,True);
    if Rows[I].Saved then RowLabel('✓ Verknüpft',432,Y+28,136,20,11,True)
    else RowLabel('Wird verknüpft …',432,Y+28,136,20,11,True);
    var Line := TNSBox.Wrap(TNSBox.Alloc.initWithFrame(MakeNSRect(12,Y,548,1)));
    Line.setBoxType(NSBoxSeparator); FDocument.addSubview(Line); Line.release;
  end;
  if Length(Rows)=0 then RowLabel('Noch keine Dateien – ziehe die ersten hierher.',16,80,540,24,12,True);
  FSummary.setStringValue(StrToNSStr(IntToStr(Length(Rows))+' Dateien erfasst'));
  FFeedback.setStringValue(StrToNSStr(FOwner.Feedback));
end;

procedure TMacFileWindow.drawRect(dirtyRect: NSRect);
var Path: NSBezierPath; Dash: array[0..1] of CGFloat;
begin
  TNSColor.Wrap(TNSColor.OCClass.colorWithCalibratedRed(0.965,0.973,0.98,1)).setFill;
  TNSBezierPath.Wrap(TNSBezierPath.OCClass.bezierPathWithRect(MakeNSRect(0,0,640,600))).fill;
  if FDragging then
    TNSColor.Wrap(TNSColor.OCClass.colorWithCalibratedRed(0.94,0.97,1,1)).setFill
  else TNSColor.Wrap(TNSColor.OCClass.whiteColor).setFill;
  Path := TNSBezierPath.Wrap(TNSBezierPath.OCClass.bezierPathWithRoundedRect(MakeNSRect(24,324,592,160),10,10));
  Path.fill;
  if FDragging then
    TNSColor.Wrap(TNSColor.OCClass.colorWithCalibratedRed(0.035,0.41,0.85,1)).setStroke
  else TNSColor.Wrap(TNSColor.OCClass.colorWithCalibratedRed(0.69,0.72,0.76,1)).setStroke;
  Dash[0]:=5; Dash[1]:=4; Path.setLineDash(@Dash[0],2,0); Path.setLineWidth(1); Path.stroke;
  TNSColor.Wrap(TNSColor.OCClass.colorWithCalibratedRed(0.34,0.38,0.42,1)).setStroke;
  Path:=TNSBezierPath.Wrap(TNSBezierPath.OCClass.bezierPath); Path.setLineWidth(1.8);
  Path.moveToPoint(FilePoint(320,432)); Path.lineToPoint(FilePoint(320,459));
  Path.moveToPoint(FilePoint(312,451)); Path.lineToPoint(FilePoint(320,459)); Path.lineToPoint(FilePoint(328,451));
  Path.moveToPoint(FilePoint(305,440)); Path.lineToPoint(FilePoint(305,429));
  Path.lineToPoint(FilePoint(335,429)); Path.lineToPoint(FilePoint(335,440)); Path.stroke;
end;

procedure TMacFileWindow.draggingExited(sender: Pointer);
begin FDragging:=False; FView.setNeedsDisplay(True); end;

procedure TMacFileWindow.chooseFiles;
var Panel: NSOpenPanel; URLs: NSArray; I: Integer; Paths: TArray<string>;
begin
  Panel := TNSOpenPanel.Wrap(TNSOpenPanel.OCClass.openPanel);
  Panel.setTitle(StrToNSStr('Dateien verknüpfen')); Panel.setCanChooseFiles(True);
  Panel.setCanChooseDirectories(False); Panel.setAllowsMultipleSelection(True);
  Panel.setPrompt(StrToNSStr('Verknüpfen'));
  if Panel.runModal <> 1 then Exit;
  URLs := Panel.URLs; SetLength(Paths, URLs.count);
  for I := 0 to High(Paths) do Paths[I] := NSStrToStr(TNSURL.Wrap(URLs.objectAtIndex(I)).path);
  FOwner.Accept(Paths);
end;
procedure TMacFileWindow.cancelFiles;
begin FOwner.Cancel; FWindow.orderOut(nil); end;
function TMacFileWindow.windowShouldClose(Sender: Pointer): Boolean;
begin Result := True; end;
procedure TMacFileWindow.windowWillClose(notification: NSNotification);
begin FOwner.Cancel; end;
procedure TMacFileWindow.windowDidBecomeKey(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidResignKey(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidResize(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidMove(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidMiniaturize(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidDeminiaturize(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidEnterFullScreen(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidExitFullScreen(notification: NSNotification);
begin end;
procedure TMacFileWindow.windowDidChangeBackingProperties(notification: NSNotification);
begin end;

function TMacFileWindow.draggingEntered(sender: Pointer): NSUInteger;
begin FDragging:=True; FView.setNeedsDisplay(True); Result := NSDragOperationLink; end;
function TMacFileWindow.prepareForDragOperation(sender: Pointer): Boolean;
begin Result := True; end;
function TMacFileWindow.performDragOperation(sender: Pointer): Boolean;
var Board: NSPasteboard; PathsObj, Classes: NSArray; I: Integer; Paths: TArray<string>;
  URL: NSURL;
begin
  Result := False;
  Board := TNSDraggingInfo.Wrap(sender).draggingPasteboard;
  Classes := TNSArray.Wrap(TNSArray.OCClass.arrayWithObject(objc_getClass('NSURL')));
  PathsObj := Board.readObjectsForClasses(Classes, nil);
  if (PathsObj <> nil) and (PathsObj.count > 0) then begin
    SetLength(Paths, PathsObj.count);
    for I := 0 to High(Paths) do begin
      URL := TNSURL.Wrap(PathsObj.objectAtIndex(I));
      if URL.isFileURL then Paths[I] := NSStrToStr(URL.path);
    end;
  end else begin
    PathsObj := TNSArray.Wrap(Board.propertyListForType(NSFilenamesPboardType));
    if PathsObj = nil then Exit;
    SetLength(Paths, PathsObj.count);
    for I := 0 to High(Paths) do Paths[I] := NSStrToStr(TNSString.Wrap(PathsObj.objectAtIndex(I)));
  end;
  FDragging:=False; FView.setNeedsDisplay(True); Result := FOwner.Accept(Paths);
end;
{$ENDIF}
end.
