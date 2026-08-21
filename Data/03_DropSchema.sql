-- ACHTUNG: Loescht das gesamte MailNotes-Schema und alle darin enthaltenen Daten.
-- Nur fuer einen bewussten Neustart verwenden.
-- Keine BEGIN-/COMMIT-Anweisungen, da DB Browser selbst eine Transaktion nutzt.

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS AppState;
DROP TABLE IF EXISTS MailLink;
DROP TABLE IF EXISTS NotePerson;
DROP TABLE IF EXISTS Person;
DROP TABLE IF EXISTS NoteTag;
DROP TABLE IF EXISTS Tag;
DROP TABLE IF EXISTS Note;
DROP TABLE IF EXISTS Mail;
DROP TABLE IF EXISTS SchemaInfo;

PRAGMA foreign_keys = ON;
