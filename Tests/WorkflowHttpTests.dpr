program WorkflowHttpTests;
{$APPTYPE CONSOLE}
uses Winapi.Windows, System.SysUtils, System.IOUtils, System.Classes,
  System.JSON, System.Generics.Collections, uAppPaths, uRuntimeConfig, IdHTTP, uDatabase, uNote, uHttpServer;

procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

var DB: TDatabase; Server: THttpServer; Client: TIdHTTP;
  Body: TStringStream; Response, ID, Folder, Stage: string; Obj: TJSONObject;
begin
  try
    Folder := TPath.Combine(TPath.GetTempPath, 'MailNotesWorkflowHttp-' + TGUID.NewGuid.ToString);
    TDirectory.CreateDirectory(TPath.Combine(Folder, 'MailNotes'));
    SetEnvironmentVariable('LOCALAPPDATA', PChar(Folder));
    TFile.Copy(ParamStr(1), TPath.Combine(Folder, 'MailNotes\MailNotes.sqlite'));
    TFile.WriteAllText(TPath.Combine(Folder, 'MailNotes\mailnotes.ini'), '[Debug]' + sLineBreak + 'Enabled=1' + sLineBreak + 'LogLevel=3');
    Writeln('HTTP test folder: ', Folder);
    Writeln('HTTP config: ', TAppPaths.ConfigFile);
    Check(TRuntimeConfig.HttpPort = 48580, 'Dedicated HTTP test port required');
    Check(TAppPaths.DatabaseFile.StartsWith(Folder + PathDelim), 'Dedicated HTTP test data required');
    DB := TDatabase.Create;
    try
      DB.Open;
      Server := THttpServer.Create(DB);
      Client := TIdHTTP.Create(nil);
      try
        Writeln('HTTP test HTTPS=', TRuntimeConfig.UseHttps, ' port=', TRuntimeConfig.HttpPort);
        Server.Start;
        Client.Request.ContentType := 'application/json';
        Body := TStringStream.Create('{"messageId":"<workflow-http@example.invalid>","content":"HTTP workflow","links":"[]","expectedRevision":0,"reminderUtc":"2000-01-01T10:00:00.000Z","completedUtc":"","imageUploads":[]}', TEncoding.UTF8);
        Stage := 'POST at test line 30';
        try Response := Client.Post('http://127.0.0.1:48580/note', Body); finally Body.Free; end;
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          ID := Obj.GetValue<string>('mailNotesId');
          Check(Obj.GetValue<Integer>('revision') = 1, 'Initial revision');
        finally Obj.Free; end;
        Stage := 'File link API';
        var FilePath := TPath.Combine(Folder, 'datei-test.txt');
        TFile.WriteAllText(FilePath, 'File link test');
        var LinkNote := DB.FindByMailNotesID(ID);
        try DB.AddFileLinks(ID, LinkNote.ID, [FilePath], 'Windows'); finally LinkNote.Free; end;
        var FileID := DB.FileLinks(ID)[0].ID;
        var Rejected := False;
        try Client.Get('http://127.0.0.1:48580/filelinks?mailNotesId=' + ID);
        except on E: Exception do Rejected := Client.ResponseCode = 403; end;
        Check(Rejected, 'File link API requires explicit custom header');
        Client.Request.CustomHeaders.Values['X-MailNotes-FileLinks'] := '1';
        Client.Request.CustomHeaders.Values['Origin'] := 'http://127.0.0.1:48580';
        Response := Client.Get('http://127.0.0.1:48580/filelinks?mailNotesId=' + ID);
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(Obj.GetValue<TJSONArray>('files').Count = 1, 'List stored file link'); finally Obj.Free; end;
        Response := Client.Get('http://127.0.0.1:48580/filelinks/check?mailNotesId=' + ID + '&linkId=' + FileID);
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(Obj.GetValue<Boolean>('available'), 'Existing file is available'); finally Obj.Free; end;
        TFile.Delete(FilePath);
        Response := Client.Get('http://127.0.0.1:48580/filelinks/check?mailNotesId=' + ID + '&linkId=' + FileID);
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(not Obj.GetValue<Boolean>('available'), 'Removed file is unavailable'); finally Obj.Free; end;
        Check(Length(DB.FileLinks(ID)) = 1, 'Missing file link is retained');
        Client.Request.CustomHeaders.Values['Origin'] := 'https://unrelated.invalid';
        Rejected := False;
        try Client.Get('http://127.0.0.1:48580/filelinks?mailNotesId=' + ID);
        except on E: Exception do Rejected := Client.ResponseCode = 403; end;
        Check(Rejected, 'Unrelated origin rejected');
        Client.Request.CustomHeaders.Values['Origin'] := '';
        Client.Request.CustomHeaders.Values['X-MailNotes-FileLinks'] := '';
        Stage := 'GET at test line 36';
        Response := Client.Get('http://127.0.0.1:48580/note?mailNotesId=' + ID);
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<string>('reminderUtc').StartsWith('2000-01-01T10:00:00'), 'Reminder roundtrip');
          Check(Obj.GetValue<string>('completedUtc') = '', 'Open state');
        finally Obj.Free; end;
        Stage := 'GET at test line 42';
        Response := Client.Get('http://127.0.0.1:48580/search?q=&due=1');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(Obj.GetValue<Integer>('count') = 1, 'Due search'); finally Obj.Free; end;
        Stage := 'GET at test line 45';
        Response := Client.Get('http://127.0.0.1:48580/search?q=&reminders=1&reminderState=due');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(Obj.GetValue<Integer>('count') = 1, 'Due menu state'); finally Obj.Free; end;
        Body := TStringStream.Create('{"mailNotesId":"' + ID + '","content":"HTTP workflow","links":"[]","expectedRevision":1,"completedUtc":"2026-11-16T10:00:00Z","imageUploads":[]}', TEncoding.UTF8);
        Stage := 'POST at test line 49';
        try Response := Client.Post('http://127.0.0.1:48580/note', Body); finally Body.Free; end;
        Stage := 'GET at test line 50';
        Response := Client.Get('http://127.0.0.1:48580/reminders/count');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<Integer>('count') = 0, 'Completed reminder excluded from active count');
          Check(Obj.GetValue<Integer>('dueCount') = 0, 'Completed reminder not active due');
        finally Obj.Free; end;
        Body := TStringStream.Create('{"mailNotesId":"' + ID + '","content":"HTTP workflow","links":"[]","expectedRevision":2,"reminderUtc":"2099-01-01T10:00:00Z","imageUploads":[]}', TEncoding.UTF8);
        Stage := 'POST at test line 57';
        try Response := Client.Post('http://127.0.0.1:48580/note', Body); finally Body.Free; end;
        Stage := 'GET at test line 58';
        Response := Client.Get('http://127.0.0.1:48580/reminders/count');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<Integer>('count') = 0, 'Future reminder on completed note inactive');
          Check(Obj.GetValue<Integer>('dueCount') = 0, 'Future reminder is not due');
        finally Obj.Free; end;
        Stage := 'GET at test line 64';
        Response := Client.Get('http://127.0.0.1:48580/search?q=&reminders=1');
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try Check(Obj.GetValue<Integer>('count') = 0, 'Reminder filter excludes completed'); finally Obj.Free; end;
        for var State in TArray<string>.Create('active', 'future', 'due', 'completed') do
        begin
          Stage := 'GET at test line 69';
          Response := Client.Get('http://127.0.0.1:48580/search?q=&reminders=1&reminderState=' + State);
          Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
          try
            var Expected := 0;
            if State = 'completed' then Expected := 1;
            Check(Obj.GetValue<Integer>('count') = Expected, 'Completed menu state ' + State);
          finally Obj.Free; end;
        end;
        Body := TStringStream.Create('{"mailNotesId":"' + ID + '","content":"HTTP workflow","links":"[]","expectedRevision":3,"reminderUtc":"invalid","imageUploads":[]}', TEncoding.UTF8);
        try
          try
            Stage := 'POST at test line 80';
            Client.Post('http://127.0.0.1:48580/note', Body);
            raise Exception.Create('Invalid date accepted');
          except on E: EIdHTTPProtocolException do Check(E.ErrorCode=400, 'Invalid date status'); end;
        finally Body.Free; end;
        Stage := 'GET at test line 84';
        Response := Client.Get('http://127.0.0.1:48580/note?mailNotesId=' + ID);
        Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
        try
          Check(Obj.GetValue<Integer>('revision') = 3, 'Invalid request changed revision');
          Check(Obj.GetValue<string>('reminderUtc').StartsWith('2099-01-01T10:00:00'), 'Invalid request changed reminder');
          Check(Obj.GetValue<string>('completedUtc') <> '', 'Reminder edit changed completion');
        finally Obj.Free; end;
        Body := TStringStream.Create('{"mailNotesId":"' + ID + '","content":"HTTP workflow #Shared @Anna","links":"[]","expectedRevision":3,"completedUtc":"","imageUploads":[]}', TEncoding.UTF8);
        Stage := 'POST at test line 92';
        try Response := Client.Post('http://127.0.0.1:48580/note', Body); finally Body.Free; end;
        Check(DB.CountReminders = 1, 'Reopened future WVL counted');
        Check(DB.CountDueNotes = 0, 'Future WVL not due');
        Check(DB.SetFavorite(ID, '', True), 'Favorite setup');
        var N := TNote.Create('<favorite-only@example.invalid>');
        try
          N.Content := 'Favorite only #Shared @Anna';
          N.IsFavorite := True;
          DB.Save(N, 0, nil);
        finally N.Free; end;
        N := TNote.Create('<reminder-only@example.invalid>');
        try
          N.Content := 'Reminder only #Other @Otherperson';
          N.ReminderUTC := '2099-01-01T10:00:00Z';
          DB.Save(N, 0, nil);
        finally N.Free; end;
        for var TestCase in TArray<string>.Create('favorite=1', 'reminders=1', 'favorite=1&reminders=1',
          'favorite=1&reminders=1&tags=shared&persons=anna') do
        begin
          Stage := 'GET at test line 111';
          Response := Client.Get('http://127.0.0.1:48580/search?q=&' + TestCase);
          Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
          try
            var Expected := 1;
            if (TestCase = 'favorite=1') or (TestCase = 'reminders=1') then Expected := 2;
            Check(Obj.GetValue<Integer>('count') = Expected, 'AND filter ' + TestCase);
          finally Obj.Free; end;
        end;
        for var State in TArray<string>.Create('active', 'future', 'due', 'completed') do
        begin
          Stage := 'GET at test line 121';
          Response := Client.Get('http://127.0.0.1:48580/search?q=&favorite=1&reminders=1&reminderState=' + State);
          Obj := TJSONObject.ParseJSONValue(Response) as TJSONObject;
          try
            var Expected := 0;
            if (State = 'active') or (State = 'future') then Expected := 1;
            Check(Obj.GetValue<Integer>('count') = Expected, 'Menu state with favorite AND ' + State);
          finally Obj.Free; end;
        end;
        Writeln('PASS HTTP first save, roundtrip, due search, completion, preserved reminder, invalid date and atomic revision');
      finally Client.Free; Server.Free; end;
    finally DB.Free; end;
  except on E: Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message, ' [', Stage, ']'); if TFile.Exists(TPath.Combine(TAppPaths.DataDirectory, 'Logs\MailNotesAgent-Diagnostic.log')) then Writeln(TFile.ReadAllText(TPath.Combine(TAppPaths.DataDirectory, 'Logs\MailNotesAgent-Diagnostic.log'))); Halt(1); end; end;
end.
