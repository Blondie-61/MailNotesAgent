-- MailNotes - finales neues Datenbankschema ab Version 0
-- SQLite
-- WICHTIG: Dieses Skript ist fuer eine LEERE Datenbank gedacht.
-- Keine BEGIN-/COMMIT-Anweisungen, da DB Browser selbst eine Transaktion nutzt.

PRAGMA foreign_keys = ON;

CREATE TABLE SchemaInfo
(
    SchemaVersion INTEGER NOT NULL,
    CreatedUTC    TEXT    NOT NULL
);

INSERT INTO SchemaInfo (SchemaVersion, CreatedUTC)
VALUES (5, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));

-- Fachliche Identitaet einer E-Mail in MailNotes.
-- MailNotesID bleibt stabil; Outlook-IDs duerfen sich beim Verschieben aendern.
CREATE TABLE Mail
(
    MailNotesID       TEXT NOT NULL PRIMARY KEY,

    -- Technische Outlook-/Exchange-Kennungen
    ItemID            TEXT,
    ImmutableID       TEXT,
    InternetMessageID TEXT,
    ConversationID    TEXT,
    MailboxAddress    TEXT,

    -- Fingerabdruck / Anzeigeinformationen fuer SHL
    Subject           TEXT,
    SenderName        TEXT,
    SenderAddress     TEXT,
    ReceivedUTC       TEXT,

    -- Resolver-/Pflegeinformationen
    CreatedUTC        TEXT    NOT NULL,
    ModifiedUTC       TEXT    NOT NULL,
    LastResolvedUTC   TEXT,
    ResolveState      INTEGER NOT NULL DEFAULT 0,

    CHECK (length(MailNotesID) > 0),
    CHECK (ResolveState IN (0, 1, 2))
);

-- ResolveState:
-- 0 = unbekannt / noch nicht geprueft
-- 1 = erfolgreich aufgeloest
-- 2 = derzeit nicht aufloesbar

CREATE INDEX IX_Mail_ItemID
    ON Mail(ItemID);

CREATE INDEX IX_Mail_ImmutableID
    ON Mail(ImmutableID);

CREATE INDEX IX_Mail_InternetMessageID
    ON Mail(InternetMessageID);

CREATE INDEX IX_Mail_ConversationID
    ON Mail(ConversationID);

CREATE INDEX IX_Mail_Fingerprint
    ON Mail(SenderAddress, ReceivedUTC, Subject);

-- Aktuell genau eine Notiz pro Mail.
-- Spaeter kann UNIQUE(MailNotesID) entfallen, falls mehrere Notizen pro Mail kommen.
CREATE TABLE Note
(
    ID          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    MailNotesID TEXT    NOT NULL UNIQUE,

    Content     TEXT    NOT NULL DEFAULT '',
    Links       TEXT    NOT NULL DEFAULT '[]',

    CreatedUTC  TEXT    NOT NULL,
    ModifiedUTC TEXT    NOT NULL,

    IsFavorite  INTEGER NOT NULL DEFAULT 0,
    IsDeleted   INTEGER NOT NULL DEFAULT 0,
    DeletedUTC  TEXT,

    FOREIGN KEY (MailNotesID)
        REFERENCES Mail(MailNotesID)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CHECK (IsFavorite IN (0, 1)),
    CHECK (IsDeleted IN (0, 1))
);

CREATE INDEX IX_Note_ModifiedUTC
    ON Note(ModifiedUTC);

CREATE INDEX IX_Note_IsFavorite
    ON Note(IsFavorite)
    WHERE IsFavorite = 1 AND IsDeleted = 0;


-- Aus dem Notiztext automatisch erkannte #Tags.
-- NormalizedName dient dem gross-/kleinschreibungsunabhaengigen Vergleich.
CREATE TABLE Tag
(
    ID             INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    Name           TEXT    NOT NULL,
    NormalizedName TEXT    NOT NULL UNIQUE,

    CHECK (length(Name) > 0),
    CHECK (length(NormalizedName) > 0)
);

CREATE INDEX IX_Tag_Name
    ON Tag(Name COLLATE NOCASE);

-- n:m-Zuordnung zwischen Notizen und Tags.
CREATE TABLE NoteTag
(
    NoteID INTEGER NOT NULL,
    TagID  INTEGER NOT NULL,

    PRIMARY KEY (NoteID, TagID),

    FOREIGN KEY (NoteID)
        REFERENCES Note(ID)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    FOREIGN KEY (TagID)
        REFERENCES Tag(ID)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE INDEX IX_NoteTag_TagID
    ON NoteTag(TagID);

-- Aus dem Notiztext automatisch erkannte @Personen.
-- Ein Personentag beginnt am Zeilenanfang oder nach Leerzeichen/Tab und reicht bis Zeilenende/EOF.
CREATE TABLE Person
(
    ID             INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    Name           TEXT    NOT NULL,
    NormalizedName TEXT    NOT NULL UNIQUE,

    CHECK (length(Name) > 0),
    CHECK (length(NormalizedName) > 0)
);

CREATE INDEX IX_Person_Name
    ON Person(Name COLLATE NOCASE);

CREATE TABLE NotePerson
(
    NoteID   INTEGER NOT NULL,
    PersonID INTEGER NOT NULL,

    PRIMARY KEY (NoteID, PersonID),

    FOREIGN KEY (NoteID)
        REFERENCES Note(ID)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    FOREIGN KEY (PersonID)
        REFERENCES Person(ID)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE INDEX IX_NotePerson_PersonID
    ON NotePerson(PersonID);

-- Gerichtete Verknuepfung von einer Mail zu einer anderen Mail.
CREATE TABLE MailLink
(
    ID                INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    SourceMailNotesID TEXT    NOT NULL,
    TargetMailNotesID TEXT    NOT NULL,
    CreatedUTC        TEXT    NOT NULL,
    IsFavorite        INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (SourceMailNotesID)
        REFERENCES Mail(MailNotesID)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    FOREIGN KEY (TargetMailNotesID)
        REFERENCES Mail(MailNotesID)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    UNIQUE (SourceMailNotesID, TargetMailNotesID),
    CHECK (SourceMailNotesID <> TargetMailNotesID),
    CHECK (IsFavorite IN (0, 1))
);

CREATE INDEX IX_MailLink_Source
    ON MailLink(SourceMailNotesID);

CREATE INDEX IX_MailLink_Target
    ON MailLink(TargetMailNotesID);

CREATE INDEX IX_MailLink_IsFavorite
    ON MailLink(IsFavorite)
    WHERE IsFavorite = 1;

-- Allgemeiner persistenter Anwendungszustand.
-- Beispiel fuer den internen MailLink-Zwischenspeicher:
-- Key = 'ActiveLinkBuffer', Value = <MailNotesID>
-- Ein NULL-Wert bedeutet: Zustand ist vorhanden, aber aktuell leer.
CREATE TABLE AppState
(
    Key         TEXT NOT NULL PRIMARY KEY,
    Value       TEXT,
    ModifiedUTC TEXT NOT NULL,

    CHECK (length(Key) > 0)
);

-- Der Schluessel wird von Anfang an angelegt und ist zunaechst leer.
INSERT INTO AppState (Key, Value, ModifiedUTC)
VALUES ('ActiveLinkBuffer', NULL, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));


-- Warteschlange fuer nicht mehr erreichbare gespeicherte Outlook-IDs.
CREATE TABLE SHLRepairQueue
(
    ID                INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    MailNotesID       TEXT    NOT NULL UNIQUE,
    OldItemID         TEXT,
    InternetMessageID TEXT,
    Subject           TEXT,
    SenderName        TEXT,
    SenderAddress     TEXT,
    ReceivedUTC       TEXT,
    Reason            TEXT    NOT NULL,
    CreatedUTC        TEXT    NOT NULL,
    ModifiedUTC       TEXT    NOT NULL,
    RetryCount        INTEGER NOT NULL DEFAULT 0,
    Status            INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (MailNotesID)
        REFERENCES Mail(MailNotesID)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CHECK (Status IN (0, 1, 2, 3))
);

CREATE INDEX IX_SHLRepairQueue_Status
    ON SHLRepairQueue(Status, CreatedUTC);


-- Volltextindex fuer Notiztext und Mail-Metadaten.
CREATE VIRTUAL TABLE MailNoteSearch USING fts5
(
    MailNotesID UNINDEXED,
    Content,
    Subject,
    SenderName,
    SenderAddress,
    tokenize = 'unicode61 remove_diacritics 2'
);
