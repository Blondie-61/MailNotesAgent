MailNotes Agent – Windows-Setup 0.2
==================================

Produktversion des Agents: 1.0.0.1
Version des Installers:    0.2

Erstellen des Installers
-------------------------

1. In Delphi „Release“ und „Windows 64-Bit“ wählen.
2. MailNotesAgent neu erstellen.
3. Prüfen, dass Main\Win64\Release\MailNotesAgent.exe vorhanden ist.
4. Inno Setup 6 installieren.
5. Setup\BuildSetup.cmd ausführen.

Das fertige Setup wird erzeugt unter:

    Setup\Output\MailNotesAgent-Setup-0.2.exe

Installation
------------

Installationsordner:

    C:\Program Files\MailNotes\Agent

Installiert werden:

    MailNotesAgent.exe
    Data\MailNotes.sqlite

Die SQLite-Datei im Programmordner ist nur die Vorlage für den ersten Start.
Die persönliche Datenbank bleibt unter:

    %LOCALAPPDATA%\MailNotes\MailNotes.sqlite

Optionen im Installer
---------------------

- Autostart mit Windows: standardmäßig aktiviert
- Desktop-Symbol: standardmäßig deaktiviert
- Startmenü-Eintrag: wird immer angelegt
- Agent nach der Installation starten: auswählbar auf der Abschlussseite

Update und Deinstallation
-------------------------

Vor einem Update oder einer Deinstallation wird ein laufender Agent zunächst
sauber mit „MailNotesAgent.exe /shutdown“ beendet. Falls eine ältere Version
diesen Schalter nicht kennt, verwendet das Setup als Rückfall taskkill.

Bei der Deinstallation bleiben die persönlichen Daten standardmäßig erhalten.
Am Ende wird ausdrücklich gefragt, ob der Ordner unter %LOCALAPPDATA%\MailNotes
zusätzlich gelöscht werden soll. Die sichere Standardauswahl ist „Nein“.

Build Windows Setup

Voraussetzungen
---------------
- Delphi 11/13 Win64 Release Build
- Inno Setup 6.x

Erzeugen
--------
BuildSetup.cmd

Ausgabe
-------
Setup\Output\MailNotesAgent-Setup-x.x.x.x.exe