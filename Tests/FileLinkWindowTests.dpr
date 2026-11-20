program FileLinkWindowTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.Classes, uFileLinkWindow
{$IF Defined(MACOS)}
  , Macapi.AppKit, Macapi.Foundation
{$ENDIF}
;
var Window: TFileLinkWindow; Token, MailID, State, Folder, A,B,C: string;
  NoteID: Integer; Generation: Int64; Paths, Batch: TArray<string>;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
procedure Pump(const Seconds: Double);
begin
{$IF Defined(MACOS)}
  TNSRunLoop.Wrap(TNSRunLoop.OCClass.currentRunLoop).runUntilDate(
    TNSDate.Wrap(TNSDate.OCClass.dateWithTimeIntervalSinceNow(Seconds)));
{$ENDIF}
end;
begin
  try
    Folder := TPath.Combine(TPath.GetTempPath,'MailNotes-file-window-'+TGUID.NewGuid.ToString);
    TDirectory.CreateDirectory(TPath.Combine(Folder,'Rechnungen'));
    TDirectory.CreateDirectory(TPath.Combine(Folder,'Verträge'));
    A:=TPath.Combine(Folder,'Rechnungen/Rechnung November.pdf');
    B:=TPath.Combine(Folder,'Verträge/Vertrag – Entwurf.txt');
    C:=TPath.Combine(Folder,'Besprechung.md');
    TFile.WriteAllText(A,'Test'); TFile.WriteAllText(B,'Test'); TFile.WriteAllText(C,'Test');
    Window := TFileLinkWindow.Create;
    try
      Token := Window.BeginSelection('original-mail','WG: Unterlagen zum Projekt',123,7,[A]);
      Pump(0.1);
      Check(Length(Window.DisplayFiles)=1,'Existing file must be shown');
      Window.Accept([A,B,B]);
      State:=Window.Snapshot(Token,MailID,NoteID,Generation,Paths);
      Check((State='ready') and (MailID='original-mail') and (NoteID=123) and
        (Generation=7) and (Length(Paths)=1),'Anchored selection and duplicate handling');
      Batch:=Copy(Paths);
      Window.Accept([C]);
      Window.Finish(Token,Batch);
      State:=Window.Snapshot(Token,MailID,NoteID,Generation,Paths);
      Check((State='ready') and (Length(Paths)=1) and (Paths[0]=C),'Drop during save must remain pending');
      Check(Window.Revision=1,'First saved batch revision');
      Window.Finish(Token,Paths);
      Check(Window.Snapshot(Token,MailID,NoteID,Generation,Paths)='waiting','Window must remain open after save');
      Check(Window.Revision=2,'Second saved batch revision');
      Check((Length(Window.DisplayFiles)=3) and Window.DisplayFiles[2].Saved,'Saved file list');
      Check(Window.BeginSelection('original-mail','Same mail',123,7)=Token,'Reopen must preserve session');
      Pump(0.1);
      if FindCmdLineSwitch('preview',True) then Pump(25);
      Window.Cancel;
      Check(Window.Snapshot(Token,MailID,NoteID,Generation,Paths)='done','User-controlled close');
      Token:=Window.BeginSelection('second-mail','Test Abschluss mit ausstehenden Dateien',124,7);
      Window.Accept([B]);
      Window.Snapshot(Token,MailID,NoteID,Generation,Paths); Batch:=Copy(Paths);
      Window.Cancel;
      Check(Window.Snapshot(Token,MailID,NoteID,Generation,Paths)='ready','Close must not discard pending files');
      Window.Finish(Token,Batch);
      Check(Window.Snapshot(Token,MailID,NoteID,Generation,Paths)='done','Finish pending save after close');
      Token:=Window.BeginSelection('third-mail','Test Speicherfehler',125,7);
      Window.Accept([C]); Window.Fail(Token,'Testfehler');
      Check((Window.Feedback='Testfehler') and
        (Window.Snapshot(Token,MailID,NoteID,Generation,Paths)='error'),'Visible save failure');
      Window.Cancel; Pump(0.1);
      Writeln('PASS existing files, multiple folders, duplicate handling, overlapping batches, retained window, revision updates, close with pending files and save errors');
    finally Window.Free; TDirectory.Delete(Folder,True); end;
  except on E: Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
