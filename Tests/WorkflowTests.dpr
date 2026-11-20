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
        Check(DB.CountDueNotes = 0, 'Completed WVL is inactive');
        Check(DB.CountReminders = 0, 'Completed WVL excluded from active count');
        DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
        Check(Notifications = 1, 'Completed WVL must not notify');
        N.CompletedUTC := '';
        DB.Save(N, N.Revision, nil);
        DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
        Check(Notifications = 1, 'Reopening same notified WVL must not duplicate');
        N.CompletedUTC := '2026-11-17T07:00:00Z';
        DB.Save(N, N.Revision, nil);
        N.ReminderUTC := '1999-01-01T10:00:00Z';
        DB.Save(N, N.Revision, nil);
        DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
        Check(Notifications = 1, 'New reminder stays inactive while completed');
        Conflict := False;
        try DB.Save(Stale, Stale.Revision, nil);
        except on E: ENoteImageConflict do Conflict := True; end;
        Check(Conflict, 'Stale save must be rejected');
        N.CompletedUTC := '';
        DB.Save(N, N.Revision, nil);
      finally Stale.Free; N.Free; end;
      Check(DB.CountDueNotes = 1, 'Reopened note is due');
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      Check(Notifications = 2, 'Completion toggle must not rearm notification');
      N := DB.FindByMailNotesID(ID);
      try
        var RevisionBefore := N.Revision;
        DB.AddFileLinks(ID, N.ID, [TPath.Combine(Folder, 'Prüfung #1.pdf'), TPath.Combine(Folder, 'Prüfung #1.pdf')], 'Windows');
        Check(Length(DB.FileLinks(ID)) = 1, 'Duplicate file link suppressed');
        Check(DB.FileLinks(ID)[0].Path.EndsWith('Prüfung #1.pdf'), 'Unicode path roundtrip');
        Stale := DB.FindByMailNotesID(ID);
        try Check(Stale.Revision = RevisionBefore, 'File links do not invalidate text autosave'); finally Stale.Free; end;
        Conflict := False;
        try DB.AddFileLinks(ID, N.ID + 1, [TPath.Combine(Folder, 'wrong.pdf')], 'Windows');
        except on E: Exception do Conflict := True; end;
        Check(Conflict and (Length(DB.FileLinks(ID)) = 1), 'Wrong originating note must not receive links');
        DB.DeleteFileLink('another-mail', DB.FileLinks(ID)[0].ID);
        Check(Length(DB.FileLinks(ID)) = 1, 'Delete is scoped to originating note');
      finally N.Free; end;
      BackupFile := DB.CreateBackup(TPath.Combine(Folder, 'Backup'), 0);
      N := DB.FindByMailNotesID(ID);
      try
        N.ReminderUTC := '2099-01-01T10:00:00Z';
        DB.Save(N, N.Revision, nil);
      finally N.Free; end;
      Check(DB.CountDueNotes = 0, 'Future reminder not due');
      Check(DB.CountReminders = 1, 'Future reminder must remain counted');
      DB.RestoreBackup(BackupFile);
      Check(DB.CountDueNotes = 1, 'Restore keeps reminder');
      Check(Length(DB.FileLinks(ID)) = 1, 'Restore keeps file links');
      DB.NotifyDueReminders(procedure(Count: Integer) begin Inc(Notifications, Count); end);
      Check(Notifications = 2, 'Restore keeps notification state');
      N := DB.FindByMailNotesID(ID);
      try
        N.ReminderUTC := '';
        DB.Save(N, N.Revision, nil);
      finally N.Free; end;
      Check(DB.CountDueNotes = 0, 'Removed reminder not due');
      DB.DeleteFileLink(ID, DB.FileLinks(ID)[0].ID);
      Check(Length(DB.FileLinks(ID)) = 0, 'Remove file link');
      N := DB.FindByMailNotesID(ID);
      try DB.AddFileLinks(ID, N.ID, [TPath.Combine(Folder, 'delete-note-test.txt')], 'Windows'); finally N.Free; end;
      Check(DB.DeleteNote(ID, ''), 'Delete file-only note');
      Check(Length(DB.FileLinks(ID)) = 0, 'Deleted note hides file links');
      N := TNote.Create('<workflow-test@example.invalid>');
      try N.MailNotesID := ID; N.Content := 'New note'; DB.Save(N, 0, nil); finally N.Free; end;
      Check(Length(DB.FileLinks(ID)) = 0, 'New note must not revive deleted file links');
      Writeln('PASS file links, migration, save/load, due state, restart, completion toggle, conflict, notification deduplication and restore');
    finally DB.Free; end;
  except
    on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
