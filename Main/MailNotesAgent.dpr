program MailNotesAgent;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uDatabase in 'uDatabase.pas',
  uNote in 'uNote.pas',
  uHttpServer in 'uHttpServer.pas';

var
  Database: TDatabase;

const
  DEBUG = True;

procedure Log(const S: string);
begin
  if DEBUG then
    Writeln(S);
end;

begin
  Database := TDatabase.Create;
  try

    Write('Opening database........');
    Database.Open;
    Writeln('OK');

    Write('Finding note............');

    var Note := Database.FindByMessageID('<TEST>');
    try
      if Assigned(Note) then
      begin
        Writeln('OK');
        Writeln('Content: ', Note.Content);
      end
      else
      begin
        Writeln('FAILED');
      end;
    finally
      Note.Free;
    end;

    Write('Saving note.............');

    Note := Database.FindByMessageID('<SELFTEST>');

    if not Assigned(Note) then
    begin
      Note := TNote.Create;
      Note.MessageID      := '<SELFTEST>';
      Note.ConversationID := '<SELFTEST>';
    end;

    try
      Note.Content := 'Selftest ' +
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);

      Note.IsFavorite := False;

      Database.Save(Note);

      Writeln('OK');

      Write('Starting HTTP server...');
      var HttpServer := THttpServer.Create(Database);
      try
        HttpServer.Start;
        Writeln('OK');
        Writeln('Listening on http://127.0.0.1:48571');

        Writeln;
        Writeln('Press ENTER to exit...');
        Readln;
      finally
        HttpServer.Free;
      end;

    finally
      Note.Free;
    end;

  finally
    Database.Free;
end;

end.

