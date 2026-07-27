program MailNotesAgent;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uDatabase in 'uDatabase.pas',
  uNote in 'uNote.pas',
  uLinkBuffer in 'uLinkBuffer.pas',
  uRepairQueue in 'uRepairQueue.pas',
  uHttpServer in 'uHttpServer.pas',
  FireDAC.UI.Intf,
  FireDAC.ConsoleUI.Wait;

var
  Database: TDatabase;
  HttpServer: THttpServer;
  Note: TNote;

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

    Write('Saving note.............');

    Note := Database.FindByMessageID('<SELFTEST>');

    if not Assigned(Note) then
    begin
      Note := TNote.Create;
      Note.MessageID      := '<SELFTEST>';
      Note.ConversationID := '<SELFTEST>';
      Note.Subject        := 'MailNotesAgent Selftest';
      Note.SenderName     := 'MailNotesAgent';
      Note.MailDate       := '';
      Note.ItemID         := '';
    end;

    try
      Note.Content :=
        'Selftest ' +
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);

      Note.IsFavorite := False;

      Database.Save(Note);

      Writeln('OK');
    finally
      Note.Free;
    end;

    Write('Finding note............');

    Note := Database.FindByMessageID('<SELFTEST>');
    try
      if Assigned(Note) then
      begin
        Writeln('OK');
        Log('Content: ' + Note.Content);
      end
      else
        Writeln('FAILED');
    finally
      Note.Free;
    end;

    Write('Starting HTTP server...');

    HttpServer := THttpServer.Create(Database);
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
    Database.Free;
  end;

end.
