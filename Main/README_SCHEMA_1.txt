MailNotesAgent - Anpassung an Datenbankschema 1
================================================

Geaendert:
- MailNotesID ist die zentrale interne Mail-Identitaet.
- Mail-Metadaten liegen in der Tabelle Mail.
- Note verweist ueber MailNotesID auf Mail.
- MailLink verbindet SourceMailNotesID und TargetMailNotesID.
- Der interne Linkbuffer wird als AppState['ActiveLinkBuffer'] gespeichert.

Kompatibilitaet:
- Das aktuelle Taskpane darf weiterhin messageId verwenden.
- Der Agent erzeugt bei der ersten Speicherung automatisch eine MailNotesID.
- /resolve akzeptiert sowohl alte mailnotes:<InternetMessageID>-Links als auch
  neue mailnotes:<MailNotesID>-Links.
- GET /linkbuffer liefert vorerst weiterhin messageId und zusaetzlich mailNotesId.

Noch nicht enthalten:
- Postfachweite Suche und eigentliche SHL-Reparatur.
- Speicherung der MailNotesID als Outlook-Custom-Property.

Vorgehen:
1. Das finale Schema muss in MailNotes.sqlite vorhanden sein.
2. Die vier Delphi-Dateien im Main-Ordner ersetzen.
3. Projekt neu kompilieren.
4. Agent starten und danach das bestehende Taskpane testen.
