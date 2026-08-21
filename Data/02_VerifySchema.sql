-- ==========================================================
-- MailNotes - Pruefung des finalen neuen Schemas
-- ==========================================================

PRAGMA foreign_keys = ON;

-- SQLite-Version
SELECT sqlite_version() AS SQLiteVersion;

-- Fremdschluesselstatus: 1 = ON, 0 = OFF
PRAGMA foreign_keys;

-- Schemaversion
SELECT SchemaVersion, CreatedUTC
FROM SchemaInfo;

-- Vorhandene Tabellen
SELECT name
FROM sqlite_master
WHERE type = 'table'
  AND name NOT LIKE 'sqlite_%'
ORDER BY name;

-- Vorhandene Indizes
SELECT name, tbl_name
FROM sqlite_master
WHERE type = 'index'
  AND name NOT LIKE 'sqlite_%'
ORDER BY tbl_name, name;

-- Tabellenstrukturen
PRAGMA table_info(Mail);
PRAGMA table_info(Note);
PRAGMA table_info(Tag);
PRAGMA table_info(NoteTag);
PRAGMA table_info(Person);
PRAGMA table_info(NotePerson);
PRAGMA table_info(MailLink);
PRAGMA table_info(AppState);
PRAGMA table_info(SHLRepairQueue);

-- Fremdschluesseldefinitionen
PRAGMA foreign_key_list(Note);
PRAGMA foreign_key_list(NoteTag);
PRAGMA foreign_key_list(NotePerson);
PRAGMA foreign_key_list(MailLink);

-- Initialer Anwendungszustand
SELECT Key, Value, ModifiedUTC
FROM AppState
ORDER BY Key;

-- Datenbankintegritaet: muss "ok" liefern
PRAGMA integrity_check;

-- Fremdschluesselpruefung: darf keine Zeilen liefern
PRAGMA foreign_key_check;
