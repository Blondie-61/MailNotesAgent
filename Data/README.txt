MailNotes - finales neues Datenbankschema
=========================================

Dieses Schema ist fuer einen vollstaendigen Neustart mit einer leeren
SQLite-Datenbank gedacht. Alte Daten werden nicht migriert.

Dateien
-------
01_CreateSchema.sql
    Legt SchemaInfo, Mail, Note, MailLink und AppState an.

02_VerifySchema.sql
    Prueft Tabellen, Indizes, Fremdschluessel und Integritaet.

03_DropSchema.sql
    Loescht das komplette neue Schema. Nur bewusst verwenden.

Reihenfolge
-----------
1. Alte MailNotes.sqlite sichern.
2. Eine neue, leere MailNotes.sqlite anlegen.
3. 01_CreateSchema.sql ausfuehren.
4. 02_VerifySchema.sql ausfuehren.

Architektur
-----------
Mail.MailNotesID ist die dauerhafte fachliche Identitaet einer E-Mail.
Outlook-IDs sind nur technische Zugriffsdaten und duerfen sich aendern.

Note und MailLink referenzieren ausschliesslich MailNotesID.
Dadurch muss beim Verschieben einer Mail nur der Datensatz in Mail
aktualisiert werden; bestehende Verknuepfungen bleiben unveraendert.

AppState ersetzt die spezielle LinkBuffer-Tabelle. Der interne
MailLink-Zwischenspeicher wird so abgelegt:

    Key   = ActiveLinkBuffer
    Value = <MailNotesID>

Der Datensatz wird beim Erstellen des Schemas bereits mit NULL angelegt.
Spaeter kann AppState auch andere persistente Programmeinstellungen oder
Zustaende aufnehmen.

Wichtig
-------
Der derzeitige Delphi-Agent muss vor Verwendung dieser neuen Datenbank
an das neue Schema angepasst werden.
