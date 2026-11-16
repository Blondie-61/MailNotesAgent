program WorkflowTests;
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, System.SysUtils, System.IOUtils, uDatabase, uNote;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then raise Exception.Create(Message);
end;

var
  DB: TDatabase;
  N, Stale: TNote;
  Folder, ID, BackupFile: string;
  Notifications: Integer;
  Conflict: Boolean;
begin
  try
    Folder := TPath.Combine(TPath.GetTempPath, 'MailNotesWorkflow-' + TGUID.NewGuid.ToString);
    TDirectory.CreateDirectory(TPath.Combine(Folder, 'MailNotes'));
    SetEnvironmentVariable('LOCALAPPDATA', PChar(Folder));
    TFile.Copy(ParamStr(1), TPath.Combine(Folder, 'MailNotes\MailNotes.sqlite'));
    DB := TDatabase.Create;
    try
      DB.Open;
      Check(DB.CountDueNotes = 0, 'Migration with no reminder');
      N := TNote.Create('<workflow-test@example.invalid>');
      try
        N.Content := 'Workflow test';
        N.ReminderUTC := '2000-01-01T10:00:00Z';
        DB.Save(N, 0, nil);
        ID := N.MailNotesID;
        Check(N.Revision = 1, 'First save revision');
      finally
        N.Free;
      end;
      Check(DB.CountDueNotes = 1, 'Past reminder must be due');
      Notifications := 0;
      try
        DB.NotifyDueReminders(procedure(Count: Integer) begin raise Exception.Create('Simulated delivery failure'); end);
      except on E: Exception do Check(E.Message = 'Simulated delivery failure', 'Unexpected delivery error'); end;
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      Check(Notifications = 1, 'Only one notification for the same date');
      DB.Close;
      DB.Open;
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      Check(Notifications = 1, 'No duplicate after restart');
      N := DB.FindByMailNotesID(ID);
      try
        Check(N.ReminderUTC = '2000-01-01T10:00:00Z', 'Reminder roundtrip');
        N.Content := 'Changed text';
        DB.Save(N, N.Revision, nil);
      finally N.Free; end;
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      Check(Notifications = 1, 'Text edit must not resend notification');
      N := DB.FindByMailNotesID(ID);
      Stale := DB.FindByMailNotesID(ID);
      try
        N.CompletedUTC := '2026-11-16T10:00:00Z';
        DB.Save(N, N.Revision, nil);
        Check(DB.CountDueNotes = 0, 'Completed note is not due');
        Conflict := False;
        try DB.Save(Stale, Stale.Revision, nil);
        except on E: ENoteImageConflict do Conflict := True; end;
        Check(Conflict, 'Stale save must be rejected');
        N.CompletedUTC := '';
        DB.Save(N, N.Revision, nil);
      finally Stale.Free; N.Free; end;
      Check(DB.CountDueNotes = 1, 'Reopened note is due');
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      Check(Notifications = 2, 'Reopening rearms notification');
      BackupFile := DB.CreateBackup(TPath.Combine(Folder, 'Backup'), 0);
      N := DB.FindByMailNotesID(ID);
      try
        N.ReminderUTC := '2099-01-01T10:00:00Z';
        DB.Save(N, N.Revision, nil);
      finally N.Free; end;
      Check(DB.CountDueNotes = 0, 'Future reminder not due');
      DB.RestoreBackup(BackupFile);
      Check(DB.CountDueNotes = 1, 'Restore keeps reminder');
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      Check(Notifications = 2, 'Restore keeps notification state');
      N := DB.FindByMailNotesID(ID);
      try
        N.ReminderUTC := '';
        DB.Save(N, N.Revision, nil);
      finally N.Free; end;
      Check(DB.CountDueNotes = 0, 'Removed reminder not due');
      Writeln('PASS migration, save/load, due state, restart, completion toggle, conflict, notification deduplication and restore');
    finally DB.Free; end;
  except
    on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
