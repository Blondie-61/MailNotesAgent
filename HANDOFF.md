# Übergabe – Bilder in Notizen

Stand 11. November 2026

## Umsetzungsstand

- Der Windows-Agent speichert PNG und JPEG als SQLite-BLOBs in `NoteImages`. Der Fremdschlüssel verweist auf `Note.ID`. HTTP-Aufrufe verwenden `mailNotesId` und eine pro Bild vom Client erzeugte UUID.
- Der Notiztext referenziert Bilder mit `![Alternativtext](mailnotes-image:<uuid>)`. `TDatabase.Save` speichert Notiz, Revision und neue Bilder in einer Transaktion. Fehlende Bildreferenzen oder fehlerhafte Uploads rollen den Save zurück. Bilder, die ein erfolgreicher JSON-Save aus dem Inhalt entfernt, werden aus der Datenbank gelöscht.
- Die Migration 6 → 7 legt `NoteImages` und `Note.Revision` an und erhöht die Schemaversion im selben Commit. Die mitgelieferte Vorlage steht auf Schema 7. Beim Öffnen nach einem Restore migriert der Agent auch eine Datenbank aus Schema 6.
- Der Agent meldet die Fähigkeit über `capabilities.noteImages`. Das aktuelle Add-in-Bundle enthält Capability-Abfrage, Bild-Paste und Konfliktbehandlung. Einfügen und erneutes Öffnen mit Bild sind vom Anwender in Outlook bestätigt. Der Speicherkonflikt ist bisher isoliert geprüft.

Quellcode und Schema finden sich in [uHttpServer.pas](Main/uHttpServer.pas), [uDatabase.pas](Main/uDatabase.pas) und [01_CreateSchema.sql](Data/01_CreateSchema.sql).

## Add-in-Deployment unter Windows und macOS

Am 11. November 2026 wurde das aktive Mac-Quellprojekt über die Freigabe
`Z:\MailNotes` einbezogen. `Z:\MailNotes-Git` ist eine weitere Kopie.
Die Änderungen am Buildablauf liegen im aktiven Projekt unter
`scripts/deploy-addin.js`, `scripts/addin-package.cjs`,
`webpack.config.js`, `BuildProduction.sh` und `README-PRODUCTION.txt`.

### Gemeinsames Buildpaket

- Webpack erzeugt mit `output.clean` einen vollständigen Production-Build.
  Das Postbuild erstellt `addin-build.json` mit Dateiliste, SHA-256 pro Datei
  und einer aus dieser Liste abgeleiteten Build-ID. Eine fehlgeschlagene
  Webpack-Ausführung löst das npm-Postbuild nicht aus.
- Das gemeinsame Modul `Setup/addin-package.cjs` prüft Pflichtdateien,
  lokale HTML-Referenzen, Dateiinventar und Prüfsummen. Das entsprechende
  Modul im Mac-Quellprojekt ist identisch. Finder-/Git-Metadaten werden
  beim Export ausgelassen. Einzelne HTML-, JS- oder CSS-Dateien nachträglich
  zu kopieren führt zu einem ungültigen Paket.
- Der Import kopiert zuerst in einen benachbarten Staging-Ordner, prüft
  diesen und tauscht anschließend den ganzen Ordner aus. Bei einem
  Umschaltfehler wird das bisherige Paket wiederhergestellt. Vorhandene
  Staging-/Rollback-Ordner nach einem Prozessabbruch müssen geprüft werden.

### Windows

Das fertige Paket wird vom Mac-Quellprojekt vollständig importiert.

```powershell
node Setup/addin-package.cjs deploy Z:/MailNotes/dist Resources/Addin
node Setup/addin-package.cjs validate Resources/Addin
Setup/BuildSetup.cmd
```

Alternativ importiert `Setup/BuildSetup.cmd Z:/MailNotes/dist` das Paket vor
der Setup-Erstellung. Node.js wird auf dem Buildrechner benötigt.

Das Windows-Setup liefert nach `Addin.staging`, prüft die SHA-256-Dateiliste
mit `Setup/VerifyAddin.ps1` und aktiviert den Ordner erst danach. Die vorige
Installation bleibt als `Addin.rollback` bis zum nächsten Update erhalten.
Der Installer benötigt zur Prüfung Windows PowerShell, keine Node-Laufzeit.

### macOS

`npm run build` im aktiven Add-in-Quellprojekt erstellt das Paket und
installiert es unter macOS über denselben Staging-/Rollback-Ablauf nach
`~/Library/Application Support/MailNotes/Addin`.
`BuildProduction.sh` übernimmt außerdem das vollständige Paket nach
`docs`. Ein nachträgliches Ändern des Manifests nach dem Build entfällt.

Optional exportiert Postbuild dasselbe Paket in den durch
`MAILNOTES_AGENT_ADDIN` angegebenen Agent-Ordner `Resources/Addin`.
Ohne diesen Wert erfolgt der Import ins Agent-Projekt über den obigen
Windows-Befehl.

Die festen Add-in-Dateilisten und CSS-Hashes wurden aus den Delphi-Projekt-
und Deploymentdateien entfernt. `Setup/Addin.Deploy.targets` bindet für
OSXARM64/Release rekursiv alle Paketdateien ein und prüft das Paket vor
Release-Build und Deploymentberechnung. Damit werden auch neue CSS-Namen
und zusätzliche Assets automatisch ins App-Bundle übernommen.

`TAddinDeploy.EnsureInstalled` prüft unter macOS das Buildmanifest im
App-Bundle und die kopierte Staging-Version vor dem Ordnerwechsel.
Auch zusätzliche Altdateien im Ziel lösen einen vollständigen Austausch
aus. `InstallAgentMac.sh` übernimmt das App-Bundle zunächst in einen
Staging-Ordner und behält das vorige Bundle bis zur erfolgreichen
Startprüfung als Rollback.

### Ausgeführte Deploymenttests am 11. November 2026

- Production-Webpack-Build gegen die Quellen unter `Z:\MailNotes` mit
  Windows-Node erfolgreich. Das Postbuild wurde anschließend separat
  ausgeführt und der komplette Build ins Agent-Projekt importiert.
  Wegen der Git-Eigentümerprüfung auf der Freigabe enthält dieser
  Testbuild den Git-Commitwert `unbekannt`.
- Das importierte Paket enthält 13 Nutzdateien plus Buildmanifest.
  Node-Prüfung, Windows-PowerShell-Prüfung und der mit Delphi 37 für
  Win64 kompilierte Paketprüfer akzeptieren es.
- Ein vermischtes JavaScript wurde von allen drei Prüfern abgewiesen.
  Fehlende Dateien und eine HTML-Referenz auf eine fehlende CSS-Datei
  wurden abgewiesen. Das bisherige Zielpaket blieb gültig.
- Ein Fixture mit geändertem CSS-Dateinamen wurde vollständig übernommen,
  einschließlich angepasstem HTML. Die vorige CSS-Datei wurde entfernt.
- Ein injizierter Fehler beim Umbenennen des Staging-Ordners stellte
  den vorherigen Zielordner wieder her.
- MSBuild-Auswertung für OSXARM64/Release enthält alle 14 Paketdateien
  mit korrekten Zielpfaden, einschließlich des aktuellen CSS-Namens.
  Der MSBuild-Validierungsschritt läuft erfolgreich.
- Win64-Release-Kompilierung und Inno-Setup-Kompilierung erfolgreich.
  Die Setup-Datei wurde erzeugt, der Installer wurde nicht ausgeführt.
- `bash -n` für `InstallAgentMac.sh` und `BuildProduction.sh` erfolgreich.

### Offene Deploymenttests unter Windows

- Das erzeugte Setup auf einem Testsystem installieren und aktualisieren.
  Den tatsächlichen Ordnerwechsel und das Verhalten bei Dateisperren prüfen.
- In Outlook nach einem Update HTML, JavaScript und CSS aus dem installierten
  Paket laden und die Bild- und Diagnosefunktionen prüfen.

### Offene Deploymenttests unter macOS

- `npm run build` und `BuildProduction.sh` nativ auf dem Mac ausführen.
  Postbuild, docs-Export und optionalen Agent-Export prüfen.
- Das OSXARM64-Deployment über PAServer tatsächlich ausführen und das
  Dateiinventar im App-Bundle mit `addin-build.json` vergleichen.
- `InstallAgentMac.sh` auf dem Mac ausführen, den Agent-Neustart und
  die Übernahme vom Bundle ins Benutzerverzeichnis prüfen.
- Fehlende/veränderte Bundle-Dateien und Dateisperren beim Ordnerwechsel
  auf macOS prüfen. In Outlook das aktualisierte Add-in neu laden.

## HTTP-Vertrag

### GET /version

Beispielantwort mit Installationspfaden.

```json
{
  "name": "MailNotesAgent",
  "capabilities": { "noteImages": true },
  "debugEnabled": false,
  "version": "1.2.2.0",
  "platform": "Windows",
  "port": 48571,
  "agentPath": "C:\\Program Files\\MailNotes\\MailNotesAgent.exe",
  "addinPath": "C:\\Program Files\\MailNotes\\Addin",
  "databasePath": "C:\\Users\\Beispiel\\AppData\\Local\\MailNotes\\MailNotes.sqlite"
}
```

Das Add-in aktiviert die Bildfunktion nur bei `capabilities.noteImages === true`.

Windows und macOS lesen für `debugEnabled` denselben INI-Wert `[Debug] Enabled` wie das Agent-Diagnoselog. `Enabled=1` ergibt den JSON-Boolean `true`. `Enabled=0` und eine fehlende Einstellung ergeben `false`. Das Add-in fragt den Wert beim Öffnen des Taskpanes ab und aktiviert seinen einzigen Diagnosebereich und die Messungen nur bei booleschem `true`. Bei einem fehlenden Feld oder Abruffehler bleibt die Diagnose aus. Nach einer INI-Änderung das Taskpane neu laden.

### POST /note

Erster Save mit `Content-Type: application/json`. Der Client sendet `expectedRevision: 0` und kann die Mail zunächst per `messageId` identifizieren.

```json
{
  "messageId": "<bild-test@example.test>",
  "expectedRevision": 0,
  "content": "Beleg\n![Beleg](mailnotes-image:11111111-1111-4111-8111-111111111111)",
  "links": "[]",
  "imageUploads": [
    {
      "imageId": "11111111-1111-4111-8111-111111111111",
      "mediaType": "image/png",
      "dataBase64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK2kAAAAASUVORK5CYII="
    }
  ]
}
```

Antwort nach dem Commit mit `200 OK`.

```json
{
  "saved": true,
  "revision": 1,
  "id": 43,
  "mailNotesId": "461d9629-c49d-46b9-a963-bf3920007b0b",
  "gmlActive": false
}
```

### GET /note

Beispiel für `GET /note?mailNotesId=461d9629-c49d-46b9-a963-bf3920007b0b`.

```json
{
  "found": true,
  "revision": 1,
  "images": [
    {
      "imageId": "11111111-1111-4111-8111-111111111111",
      "mediaType": "image/png"
    }
  ],
  "mailNotesId": "461d9629-c49d-46b9-a963-bf3920007b0b",
  "gmlActive": false,
  "content": "Beleg\n![Beleg](mailnotes-image:11111111-1111-4111-8111-111111111111)",
  "links": "[]",
  "createdAt": "2026-11-09T10:39:02Z",
  "modifiedAt": "2026-11-09T10:39:02Z",
  "isFavorite": false
}
```

Eine fehlende aktive Notiz liefert `found: false` und `revision: 0`. Falls die Mail bereits bekannt ist, kann die Antwort zusätzlich `mailNotesId` enthalten.

### Bildabruf und weitere Saves

- `GET /note/image?mailNotesId=…&imageId=…` liefert rohe Bildbytes mit `image/png` oder `image/jpeg`. Fehlende Bilder, Bilder anderer Notizen und Bilder gelöschter Notizen liefern `404`.
- Ein Autosave für eine bestehende Notiz sendet `mailNotesId` und die zuletzt gelesene oder bestätigte Revision als `expectedRevision`. `imageUploads` enthält nur neue Bilder. Der Inhalt enthält alle Referenzen, die bestehen bleiben sollen. Der Client übernimmt die Revision aus jeder erfolgreichen Save-Antwort.
- Bei veralteter Revision liefert der Agent `409` mit `{"error":"revision_conflict"}`. Das Add-in soll den lokalen Entwurf samt ausstehenden Bildern behalten.
- Der alte Formularpfad akzeptiert Textänderungen mit derselben Menge an Bild-IDs. Eine geänderte Menge ergibt `409` mit `{"error":"image_references_changed"}`. Ein erfolgreicher Formular-Save und ein Soft Delete erhöhen jeweils die Revision. Beim Soft Delete entfernt der Agent Bildreferenzen und BLOBs in derselben Transaktion.
- Fehlerhafte Uploads ergeben `400`, Größenüberschreitungen `413` und nicht unterstützte Bildformate `415`. Die Limits betragen 5 MiB pro dekodiertem Bild und 24 MiB pro JSON-Request. Die Formatprüfung prüft die Bildsignaturen.

## Ausgeführte Tests

Die Laufzeittests verwendeten ein isoliertes Win64-Testprogramm mit den Agent-Units und separaten SQLite-Dateien.

| Test | Ergebnis |
| --- | --- |
| Win64-Release-Kompilierung | Mit Delphi 37 erfolgreich. |
| Erster Save mit Bild | PNG und JPEG per HTTP gespeichert und bytegleich abgerufen. Der erste Save lieferte Revision 1. |
| Fehlerhafter Upload | Der zweite Upload im selben Request lieferte 400. Das zuvor geschriebene BLOB wurde zurückgerollt. Inhalt und Revision blieben auf dem vorherigen Stand. Ein fehlgeschlagener erster Save hinterließ auch keine Mail-Zeile. |
| Formularpfad und Soft Delete | Textänderung mit erhaltenen Bildreferenzen akzeptiert. Entfernen einer Referenz per Formular ergab 409. Nach Soft Delete ergab der Bildabruf 404 und ein verspäteter Autosave 409. |
| Restore aus Schema 6 | Auf Schema 7 migriert. Notiz-ID und Text blieben erhalten, die Bildtabelle war leer. Ein absichtlich ausgelöster Migrationsfehler stellte die ursprüngliche Live-Datenbank wieder her. |
| Restore aus Schema 7 | Ein vom Agent erzeugtes Backup stellte Notiz, Revision und PNG wieder her. Der Bildabruf war bytegleich. |
| SQLite-Prüfungen | Bei beiden erfolgreichen Restores ergab `integrity_check` den Wert `ok`. `foreign_key_check` lieferte keine Fehlerzeilen. |
| Diagnosevertrag unter Windows | HTTP 200 für `Enabled=0 → 1 → 0` in derselben isolierten Win64-Instanz. Die JSON-Booleans waren `false → true → false`. Bei `LogLevel=2` wuchs das HTTP-Diagnoselog nur bei `Enabled=1`. |
| Diagnose im Add-in-Bundle | JavaScript-Syntaxprüfung und isolierter Node-Test mit gemockter Browserumgebung bestanden. Nur boolesches `true` aktivierte Diagnosebereich, Event-Listener, Timer, Observer und Zeitmessung. |

## Offene Windows- und Outlook-Tests

- Neuer Installer mit vollständiger Paketprüfung: Installation und Update auf Windows-Test-PC prüfen. Bildabruf und Restore mit Bild wurden vom Anwender mit dem vorherigen installierten Agenten bereits bestätigt.
- Separate Laufzeittests für beide Formate PNG und JPEG dokumentieren. Bild-Paste und Anzeige nach erneutem Öffnen wurden grundsätzlich auf Mac und Windows bestätigt.
- In Outlook einen Revisionskonflikt auslösen und prüfen, dass der lokale Entwurf einschließlich noch nicht hochgeladener Bilder erhalten bleibt.

- Diagnose-Sichtbarkeit wurde vom Anwender für beide Plattformen bestätigt. Abschalten sämtlicher Messungen ist im isolierten Test geprüft.

## Offene macOS-Tests

- Numerischen Vergleich des macOS-Agent-Diagnoselogs bei Enabled=0 und 1 gesondert dokumentieren.
- Sichtbarkeit des einzigen Diagnosebereichs bei Enabled=0 und Enabled=1 ist vom Anwender auf macOS bestätigt.

Bei Änderungen am HTTP-Vertrag die Beispiele, Feldbeschreibungen und Statuscodes in dieser Datei zusammen mit der Implementierung aktualisieren. Neue Testergebnisse mit Testumgebung und Ergebnis unter den ausgeführten Tests festhalten und den entsprechenden offenen Eintrag aktualisieren.

## Ergänzung vom 11. November – Rollback und Suchvorschau

Das Node-Deployment akzeptiert den vom macOS-Agenten regulär aufbewahrten .rollback-Ordner. Es prüft das neue Staging-Paket und das Live-Paket, bevor es die alte Sicherung ablöst. Ein Staging-Rest blockiert weiterhin. Bei beschädigtem Live-Paket bleibt die Rollback-Sicherung erhalten. Diese Fälle wurden mit temporären Paketen geprüft. Das gemeinsame Node-Modul wurde in beiden Repositories synchronisiert.

Der native Mac-Production-Build samt Postbuild und Installation ist erfolgreich. Das vollständige neue Paket wurde nach Resources/Addin importiert. Enthalten sind die Korrektur verschachtelter Fett-/Kursivmarker und lesbare Suchvorschauen ohne interne Bild-IDs. Outlook-Laufzeittest dieser Änderungen steht aus.

## Release-Abgleich am 11. November 2026

Das aktuelle vollständige Add-in-Paket wurde vom Mac nach Resources/AddIn übernommen. Es enthält das vom Anwender bestätigte kompakte Layout, die lesbare Suchvorschau und die korrigierte Verschachtelung von Fett/Kursiv. Die Mac-Commits sind 566c1be (Deployment) und c43e966 (Bilder, Editor und Layout). Der native Production-Build mit Installation und Paketprüfung ist erfolgreich. TypeScript tsc --noEmit und git diff --check sind erfolgreich. Ein überholter Diagnoseaufruf beim Backlink-Löschen mit undefinierten Variablen wurde entfernt. Die Unicode-Buchstabenerkennung nutzt denselben Ausdruck über RegExp, passend zum Compilerziel.

Isolierte Clienttests mit simulierten Agent-Antworten bestätigen: 409 erhält Notiztext und ausstehendes Bild, weitere Autosaves bleiben blockiert, der Entwurf wird beim Mailwechsel aufgehoben. Nach Entfernen einer Bildreferenz werden Inhalt ohne Referenz und keine zugehörigen Uploads gesendet. Sieben verschachtelte Markdown-Fälle sind bestanden. Die tatsächlichen Outlook-Tests für Bildentfernung nach erneutem Öffnen und Revisionskonflikt stehen weiterhin aus. Die SQLite-/HTTP-Server-Tests aus der vorigen Übergabe bleiben davon getrennt.

Noch vor Freigabe: aktuelles Paket unter Windows ansehen, neue Installer-Installation und Update testen, tatsächliche Outlook-Sonderfälle prüfen. Delphi-Versionsnummern weiterhin in der IDE setzen.
