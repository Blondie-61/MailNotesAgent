program WorkflowHttpTests;
{$APPTYPE CONSOLE}
uses Winapi.Windows, System.SysUtils, System.IOUtils, System.Classes,
  System.JSON, System.Generics.Collections, IdHTTP, uDatabase, uNote, uHttpServer;

procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

var DB: TDatabase; Server: THttpServer; Client: TIdHTTP;
  Body: TStringStream; Response, ID, Folder: string; Obj: TJSONObject;
begin
  try
    Folder := TPath.Combine(TPath.GetTempPath, 'MailNotesWorkflowHttp-' + TGUID.NewGuid.ToString);
    TDirectory.CreateDirectory(TPath.Combine(Folder, 'MailNotes'));
    SetEnvironmentVariable('LOCALAPPDATA', PChar(Folder));
    TFile.Copy(ParamStr(1), TPath.Combine(Folder, 'MailNotes\MailNotes.sqlite'));
    DB := TDatabase.Create;
    try
      DB.Open;
      Server := THttpServer.Create(DB);
      Client := TIdHTTP.Create(nil);
      try
        Server.Start;
        Client.Request.ContentType := 'application/json';
        Body := TStringStream.Create('{"messageId":"<workflow-http@example.invalid>","content":"HTTP workflow","links":"[]","expectedRevision":0,"reminderUtc":"2000-01-01T10:00:00.000Z","completedUtc":"","imageUploads":[]}', TEncoding.UTF8);
        try Response := Client.Post('http://127.0.0.1:48571/note', Body); finally Body.Free; end;
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          ID := Obj.GetValue<string>('mailNotesId');
          Check(Obj.GetValue<Integer>('revision') = 1, 'Initial revision');
        finally Obj.Free; end;
        Response := Client.Get('http://127.0.0.1:48571/note?mailNotesId=' + ID);
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<string>('reminderUtc').StartsWith('2000-01-01T10:00:00'), 'Reminder roundtrip');
          Check(Obj.GetValue<string>('completedUtc') = '', 'Open state');
        finally Obj.Free; end;
        Response := Client.Get('http://127.0.0.1:48571/search?q=&due=1');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(Obj.GetValue<Integer>('count') = 1, 'Due search'); finally Obj.Free; end;
        Body := TStringStream.Create('{"mailNotesId":"' + ID + '","content":"HTTP workflow","links":"[]","expectedRevision":1,"completedUtc":"2026-11-16T10:00:00Z","imageUploads":[]}', TEncoding.UTF8);
        try Response := Client.Post('http://127.0.0.1:48571/note', Body); finally Body.Free; end;
        Response := Client.Get('http://127.0.0.1:48571/reminders/count');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<Integer>('count') = 1, 'Completed reminder remains counted');
          Check(Obj.GetValue<Integer>('dueCount') = 1, 'Completed reminder remains due');
        finally Obj.Free; end;
        Body := TStringStream.Create('{"mailNotesId":"' + ID + '","content":"HTTP workflow","links":"[]","expectedRevision":2,"reminderUtc":"2099-01-01T10:00:00Z","imageUploads":[]}', TEncoding.UTF8);
        try Response := Client.Post('http://127.0.0.1:48571/note', Body); finally Body.Free; end;
        Response := Client.Get('http://127.0.0.1:48571/reminders/count');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<Integer>('count') = 1, 'Future reminder remains counted');
          Check(Obj.GetValue<Integer>('dueCount') = 0, 'Future reminder is not due');
        finally Obj.Free; end;
        Response := Client.Get('http://127.0.0.1:48571/search?q=&reminders=1');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(Obj.GetValue<Integer>('count') = 1, 'Reminder filter includes future and completed'); finally Obj.Free; end;
        Body := TStringStream.Create('{"mailNotesId":"' + ID + '","content":"HTTP workflow","links":"[]","expectedRevision":3,"reminderUtc":"invalid","imageUploads":[]}', TEncoding.UTF8);
        try
          try
            Client.Post('http://127.0.0.1:48571/note', Body);
            raise Exception.Create('Invalid date accepted');
          except on E: EIdHTTPProtocolException do Check(E.ErrorCode=400, 'Invalid date status'); end;
        finally Body.Free; end;
        Response := Client.Get('http://127.0.0.1:48571/note?mailNotesId=' + ID);
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<Integer>('revision') = 3, 'Invalid request changed revision');
          Check(Obj.GetValue<string>('reminderUtc').StartsWith('2099-01-01T10:00:00'), 'Invalid request changed reminder');
          Check(Obj.GetValue<string>('completedUtc') <> '', 'Reminder edit changed completion');
        finally Obj.Free; end;
        Writeln('PASS HTTP first save, roundtrip, due search, completion, preserved reminder, invalid date and atomic revision');
      finally Client.Free; Server.Free; end;
    finally DB.Free; end;
  except on E: Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message); Halt(1); end; end;
end.
