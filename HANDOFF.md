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

## PAServer-Altdateien am 11. November

Nach erneutem Deployment verblieben das alte Stylesheet und sechs alte Bilddateien im PAServer-App-Bundle. Alle manifestierten Dateien waren vorhanden und ihre SHA-256-Prüfsummen korrekt. Der wiederholte strenge Inventarvergleich des Quellbundles verhinderte den Start der Add-in-Bereitstellung.

TAddinDeploy toleriert nun ausschließlich im Quellbundle zusätzliche Dateien. Es validiert weiterhin alle manifestierten Dateien und kopiert nur diese plus addin-build.json in das Staging-Verzeichnis. Staging- und Zielprüfung bleiben streng. Das aktuelle Bundle wurde nach Sicherung der sieben Altdateien bereinigt und vom Node-Paketprüfer erfolgreich validiert.

Offen: die geänderte Delphi-Unit kompilieren und auf macOS starten. Danach bei zusätzlich im Quellbundle abgelegtem altem CSS prüfen, dass nur das aktuelle Paket installiert wird. Eine geänderte oder fehlende manifestierte Datei muss weiterhin zur Ablehnung führen.

## Versionsabgleich 1.2.2.1

Installer MyAppVersion sowie Add-in-Konfiguration und Manifest stehen auf 1.2.2.1. Das Add-in wurde erfolgreich nativ gebaut, installiert und vollständig nach Resources/AddIn exportiert. Mac-Commit 474fad5. Der Anwender hat Bildentfernung mit Speichern und erneutem Öffnen sowie den Konfliktfall in zwei Taskpanes (Hauptfenster und separates Mailfenster) erfolgreich getestet. Diese beiden Outlook-Tests sind damit bestanden.

Delphi-Versionsfelder wurden hier nicht geändert. Win64/Release zeigt FileVersion und ProductVersion 1.2.2.1. OSXARM64/Release zeigt CFBundleShortVersionString 1.2.2.1, aber numerisch noch VerInfo_Build=2. Vor Release in der IDE prüfen und abgleichen. Installer neu kompilieren und Update auf dem Windows-Test-PC ausführen.

## BuildSetup ohne Node.js

BuildSetup ohne Parameter und Setup/Addin.Deploy.targets verwenden jetzt den vorhandenen PowerShell-Pruefer. Der optionale Node-Import prueft Node im PATH und meldet eine konkrete Voraussetzung. Der PowerShell-Pruefer ignoriert SMB/Finder-Metadaten wie der Node-Pruefer und der Installer-Export.

In der laufenden Windows-VM wurde VerifyAddin.ps1 gegen Resources/AddIn erfolgreich ausgefuehrt. Der vollstaendige BuildSetup-Durchlauf erzeugte Output/MailNotesAgent-Setup-1.2.2.1.exe erfolgreich. Der erste Durchlauf scheiterte beim Inno-Ressourcenupdate mit EndUpdateResource (110); ein erneuter Durchlauf gelang. Die Ursache des einmaligen Dateizugriffsfehlers ist nicht geklaert. Installation und Update dieses Setups auf dem Test-PC bleiben offen.

## Erneutes Laden von Markdown-Notizen am 12. November

Mac-Commit ffc1ca9 entkoppelt die Vorschau beim Laden vom innerText des versteckten Editors. Der vom Agenten gelieferte Klartext wird direkt an Hervorhebung und Vorschau übergeben. Vor dem Ausblenden wird der Editor auf denselben Klartext normalisiert. In lokaler Mac-Testdatenbank und HTTP-Antwort war der Originaltext vollständig. Ein isolierter DOM-Test prüft dreifaches Laden und Editor/Vorschau-Wechsel. TypeScript, sieben Markdown-Fälle und Produktionsbuild sind bestanden. Das vollständige Paket ist nach Resources/AddIn übernommen und gegen das Mac-Paket geprüft. Der tatsächliche Outlook-Test auf Mac und Windows steht aus.

## Renderdiagnose am 12. November

Der Anwender bestätigt den Fehler trotz aktuellem ffc1ca9-Build; der Rohtext bleibt vollständig. Die versteckte-Editor-Korrektur hat den Fehler damit nicht behoben. Das Diagnosepaket ergänzt bei aktiviertem Debug textfreie Quell-, DOM- und Text-Fingerabdrücke sowie Strukturzahlen unmittelbar nach Rendern und im folgenden Frame. Ein Vergleich der korrekten ersten und falschen späteren Vorschau steht aus. TypeScript und Build erfolgreich. Diagnosepaket vollständig importiert.

## Release-Vorbereitung am 13. November

Release-Notizen und offene Freigabepunkte stehen in Documentation/Release-1.2.2.1.md. Der Vorschaufehler ist auf beiden Plattformen aktuell nicht reproduzierbar, bleibt aber ungeklärt. Native TypeScript-/Production-Prüfung, docs-Export und Paketgleichheit sind bestanden. Paket-Build-ID 632dce351ae14b240148fb72265dec1549b98d8072c03b796f3a5acfb6f875d6. BuildSetup hat das aktuelle Setup erfolgreich neu erzeugt. Prüfsummen liegen in Setup/Output/SHA256-1.2.2.1.txt und den Release-Notizen. Die zuvor in der Delphi-IDE gesetzten Versionswerte werden im Git-Stand gesichert. Finaler Windows-Update-Test dieses Artefakts und macOS-Auslieferungspaket bleiben vor Freigabe offen. Outlook war heute nicht verfügbar.

## Erstes macOS-DMG am 13. November

Resources/MacOS/BuildDmg.sh erstellt ein Apple-Silicon-DMG aus App-Bundle, geprüftem Add-in-Paket und leerer Schema-7-Vorlage. Aufruf mit bash und drei Argumenten: App-Bundle, Add-in-Ordner, Ausgabe.dmg. Enthalten sind Installieren.command, InstallAgentMac.sh, LaunchAgent-Vorlage, Anleitung und vollständige Datei-Prüfsummen. Das zusammengestellte Bundle ist lokal ad hoc signiert, das DMG nicht notarisiert. Es ist für einen lokalen Test vorgesehen.

InstallAgentMac.sh prüft die App-Signatur vor Änderungen, erkennt einen manuell belegten Port und prüft nach dem Start sowohl Version als auch ausführbaren Pfad. Bei fehlgeschlagenem App-Austausch oder Start werden App und LaunchAgent-Datei sowie ein zuvor geladener Autostart wiederhergestellt. Neue TLS-Zertifikate werden bei Bedarf weiterhin mit Benutzerfreigabe eingerichtet. Die App-Rollbacktests ersetzen keinen echten Zertifikats-/Schlüsselbundtest.

Build, hdiutil-Prüfung, schreibgeschütztes Mounten, vollständige SHA-256-Dateiprüfung, codesign --verify --deep --strict und Paketprüfung sind bestanden. Vier isolierte Shell-Tests bestanden: Erstinstallation, fehlgeschlagener Upgrade-Start mit Wiederherstellung, fehlgeschlagene Erstinstallation und belegter Port. App-Kopie und Signaturprüfung echt; TLS, launchctl und curl simuliert. Reale Installation/Autostart/TLS/Outlook stehen aus.

Datei MailNotesAgent-1.2.2.1-macOS-arm64.dmg, SHA-256 a3c5372a2c44e68379d1304e6ac8ca33e0e56717f087bb1a39afce78c1b4c754. Ausgabe im Codex-outputs-Ordner dieses Chats.

## macOS-Testphase ohne Autostart

Auf Wunsch des Anwenders wurde der aktive LaunchAgent auf dem Mac entladen und seine plist außerhalb von Library/LaunchAgents gesichert. Der laufende Agent wurde dabei beendet. InstallAgentMac.sh installiert standardmäßig ohne LaunchAgent und ohne automatischen Start. Ein vorhandener LaunchAgent wird beim Test-Update entfernt. Optional bleibt --autostart verfügbar. Das neue DMG trägt den Zusatz -Test. Zwei zusätzliche isolierte Tests bestätigen Standardinstallation ohne Autostart und Entfernung des bisherigen Dienstes beim Update. Die bisherigen vier Tests mit explizitem --autostart bleiben erfolgreich.

## Wiedervorlage und Erledigt – Entwicklungsstand vom 16. November

Die neue Funktion liegt als eigener Entwicklungsstand vor. Der bestehende Release bleibt vom nächsten Versionsentscheid getrennt.

In der Notiz stehen die Aktionen ↺ und ✓ links neben dem Favoritenherz. Nur benutzte Werte erscheinen in kleiner Schrift über dem Text. Aktionsknopf und Eintrag öffnen dieselbe Datumsauswahl bzw. schalten Erledigt/Offen. Fällige offene Termine haben eine dezente Akzentfarbe. Ein kleiner WVL-Filter mit Zähler zeigt alle gesetzten Wiedervorlagen und lässt sich mit Text, Tags, Personen und Favoriten kombinieren. Fälligkeit wird getrennt durch eine dezente rote Akzentfarbe angezeigt. Der Erledigt-Status ist unabhängig.

Schema 8 ergänzt Note.ReminderUTC, CompletedUTC und ReminderNotifiedUTC. Migrationen von 6 und 7 sowie die leere Vorlage und das SQL-Neuschema sind geprüft. Die Werte werden in derselben Save-Transaktion samt Revision gespeichert. Fehlende JSON-Felder bleiben bei vorhandenen Notizen erhalten. Alte Formularclients bewahren die Felder ebenfalls.

GET /version meldet capabilities.noteWorkflow=true. GET /note enthält reminderUtc und completedUtc als UTC-ISO-Zeit oder leere Zeichenfolge. POST /note akzeptiert diese optionalen Felder auf dem JSON-Pfad mit expectedRevision. Ungültige Zeitangaben führen zu 400 ohne Änderung. GET /reminders/count liefert count für alle gesetzten WVL und dueCount für deren fälligen Anteil. GET /search?reminders=1 zeigt alle gesetzten WVL mit Zeitangabe; GET /search?due=1 bleibt für ausschließlich fällige WVL verfügbar. Beide schließen gelöschte Notizen aus und sind unabhängig von CompletedUTC.

Ein eigener Scheduler prüft nach zehn Sekunden und dann alle 30 Sekunden. Windows verwendet die native Tray-Benachrichtigung, macOS NSUserNotificationCenter. Mehrere gleichzeitig fällige Notizen werden in einer kurzen Systemmeldung zusammengefasst. Der Erledigt-Status beeinflusst weder WVL, Zähler, Fälligkeit noch Benachrichtigungsstatus. Eine Terminänderung reaktiviert die Systemmeldung. Das Umschalten von Erledigt/Offen reaktiviert sie nicht. ReminderNotifiedUTC verhindert wiederholte Meldungen nach einem Agent-Neustart. Die Markierung erfolgt nach dem Aufruf der Benachrichtigungsfunktion in einer Datenbanktransaktion unter der bestehenden Serversperre. Eine Betriebssystem-Unterdrückung durch Fokus-/Mitteilungseinstellungen kann dabei nicht als fehlgeschlagene Zustellung erkannt werden.

Bestanden sind Win64- und OSXARM64-Release-Kompilierung, TypeScript, Production-Build und Paketprüfung. Tests/RunWorkflowTests.cmd prüft echte Agent-Units mit isolierten Schema-6-/Schema-7-Datenbanken, Save/Load, Revisionen, Erledigen/Öffnen, Neustart, einmalige Erinnerung, Fehler beim Benachrichtigungsaufruf sowie Backup/Restore. Tests/RunWorkflowHttpTests.cmd prüft HTTP-Speichern, geladene UTC-Werte, Fälligkeitssuche, Teilupdates und ungültige Termine mit unveränderter Revision. Der HTTP-Test benötigt einen freien Port 48571 und nutzt den Debug-HTTP-Server nur für die Dauer des isolierten Tests.

Ein isolierter Chromium-Test mit tatsächlichem HTML, CSS und den UI-Funktionen prüft beide Klickwege, Datumsauswahl, Entfernen, Erledigt-Umschalter, Akzentfarbe und ausgeblendete Leerwerte sowie das Ausblenden bei altem Agenten. Der neue Agent ist noch nicht als laufende Produktionsinstanz gestartet. Reale Systembenachrichtigungen und die Darstellung in Outlook auf beiden Plattformen sind noch zu prüfen. Dafür zuerst eine Datenbanksicherung erstellen und den neuen Agenten bereitstellen/starten. Das Add-in ist auf dem Mac installiert und vollständig nach Resources/AddIn exportiert; bei altem Agenten bleiben die neuen Aktionen verborgen.


## WVL-Abschluss am 17. November

Nach Wiederherstellung der VM-Verbindung sind die gestern unterbrochenen Builds und die vollständige Paketübernahme abgeschlossen.

Verbindliche Regel: Eine gesetzte Wiedervorlage zählt sofort, auch mit einem zukünftigen Termin. Beim Eintritt der Fälligkeit bleibt der Gesamtzähler gleich und erhält eine dezente rote Akzentfarbe. Verschieben in die Zukunft entfernt die Fälligkeitsfarbe, aber nicht die WVL aus dem Zähler. Entfernen der WVL reduziert den Zähler. Vergangene WVL werden nicht automatisch gelöscht. CompletedUTC ist davon vollständig unabhängig.

Die Agent-Schnittstelle liefert Gesamtzahl und Fälligkeiten getrennt. Der WVL-Filter zeigt alle gesetzten Termine, einschließlich der WVL erledigter Notizen. In der Ergebnisliste steht der Termin klein unter den Maildaten. Ein reguläres Umschalten Erledigt/Offen beeinflusst keine Systemmeldung; ein neu gesetzter Termin kann erneut melden.

Bestanden am 17. November: echte Datenbanktests für Migration von Schema 6 und 7, Save/Load, unabhängigen Erledigt-Status, neue Benachrichtigung trotz erledigter Notiz, keine erneute Meldung allein durch Erledigt-Umschalten, Backup/Restore und Konfliktschutz. HTTP-Tests bestätigen count=1 und dueCount=0 bei zukünftiger WVL sowie das Auffinden derselben auch bei gesetztem CompletedUTC. Der isolierte Zählertest bestätigt 1 neutral → 1 akzentuiert → 1 neutral → 0 und ignoriert veraltete Antworten.

Win64/Release und OSXARM64/Release sind erfolgreich kompiliert. Das vollständige Add-in-Paket wurde in Resources/AddIn übernommen und byteweise über seine Build-ID mit dem Mac-Paket abgeglichen. Source-Commit des Add-ins ist 6136cb4. Live-Agent und Outlook wurden für diesen Abschluss nicht neu gestartet. Für den Praxistest den neuen Agenten über Delphi bereitstellen und starten und danach das Taskpane neu laden. Die neue Zählweise benötigt diese Agent-Aktualisierung; ein reines Add-in-Update reicht hier nicht.


## 17. November 2026 – WVL-Auswahlmenü und erledigte Notizen

Diese Regeln ersetzen die frühere vollständige Unabhängigkeit von WVL und Erledigt:
- Eine erledigte Notiz behält ihren WVL-Termin, dieser ist aber grau/inaktiv. Sie zählt nicht zu offenen WVL und löst keine Systemmeldung aus. Wiederöffnen aktiviert den erhaltenen Termin wieder; die bereits bestätigte Meldung desselben Termins wird nicht wiederholt.
- Der einzelne WVL-Filterknopf öffnet eine Auswahl: Ohne WVL-Filter, Alle offenen WVL, Zukünftig, Fällig, Erledigt mit WVL. Der Zähler bleibt die Gesamtzahl offener WVL. Die aktuelle Auswahl steht klein unter den Filterknöpfen.
- Farben: zukünftige WVL grün, fällige rot, erledigte grau. Filterauswahl nutzt eine neutrale hinterlegte Fläche statt eines blauen Rahmens.
- GET /search?reminders=1&reminderState=active|future|due|completed kombiniert den Zustand weiterhin mit Text, Favoriten, Tags und Personen per AND. Ohne reminderState bleibt reminders=1 die offene Gesamtmenge.
- Eine leere Schnittmenge zeigt ausdrücklich „Keine Treffer für diese Auswahl.“. Der zunächst gemeldete AND-Fehler wurde vom Anwender zurückgenommen.

Ausgeführt: Datenbanktests einschließlich Restore aus Schema 6 und 7; HTTP-Tests der Zustände und ihrer Kombination mit Favoriten/Tags/Personen; TypeScript-Prüfung; isolierter Browser-Test von Menüauswahl, WVL-Aktionen und Erledigen/Wiederöffnen; Release-Kompilierung für Win64 und OSXARM64.
Offen: Prüfung der neuen Menübedienung und nativer Systemmeldungen in Outlook unter macOS und Windows mit neu gestartetem Agenten.


## 17. November 2026 – Version 1.3.0 vorbereitet

Versionsquellen für Agent, Setup, Delphi-Konfigurationen und Outlook-Manifest auf 1.3.0.0 angehoben. Beide macOS-Bundle-Versionsfelder lauten 1.3.0; npm-Paket 1.3.0. Historische Release-Notizen und vorhandene Release-Artefakte behalten ihre ursprünglichen Versionen. Die ausführlichen Windows-Praxistests stehen noch aus; Checkliste: Documentation/Release-1.3.0.md. Kein Release veröffentlicht.


## 18. November 2026 – TLS-Lebensdauer korrigiert; Mac-Backup vorübergehend lokal

Der Mac-Absturz vom 18.11. um 07:20 wurde untersucht. Ein isolierter Lasttest reproduzierte eine Zugriffsverletzung in TComponent.RemoveFreeNotifications beim Stoppen des HTTP-Servers. Die TLS-Komponente teilte einen fIOHandler zwischen Listenern und registrierte Verbindungshandler am gemeinsamen Server für unsynchronisierte FreeNotifications.

Die Korrektur liegt in Compatibility/IndySecOpenSSL/IdSecOpenSSL.pas. Diese Unit hat in den Projektpfaden Vorrang; die übrige Bibliothek und Header kommen weiterhin aus C:\Delphi-Projekte\Komponenten\IndySecOpenSSL\src. Die globale Installation und die ignorierte ältere ThirdParty-Kopie wurden nicht verändert. Mac-Release-Builds erzeugen nun eine separate Adresskarte. Fehler vor der eigentlichen HTTP-Verarbeitung werden zusätzlich protokolliert, normale Graceful-Disconnects ausgenommen.

Ausgeführt: Release-Builds Win64 und OSXARM64; Datenbank-/Restoretests aus Schema 6 und 7; HTTP-Workflowtests einschließlich WVL-Menüzuständen und AND-Filtern. Der HTTP-Test verwendet nun Port 48580 nur mit MAILNOTES_HTTP_TEST, prüft seinen eigenen Datenpfad und eine sprachunabhängige Portbelegung. Zuvor übersah die Suche nach LISTENING den deutschen Status ABHÖREN und kollidierte mit dem automatisch gestarteten Windows-Agenten. Produktionsport bleibt 48571.

Nach TLS-Korrektur: 22.985 + 22.125 + 44.270 = 89.380 isolierte Mac-HTTPS-Anfragen, keine Clientfehler, jeweils sauberer Shutdown; erster Lauf gemischt IPv4/IPv6. Diese Tests belegen den reproduzierten Fehler, ersetzen aber keinen nächtlichen Dauerlauf für den ursprünglichen Absturz.

Der korrigierte Mac-Agent 1.3.0.0 ist bereitgestellt und gestartet. Mac-Bundle 1.3.0, UUID 72F11C10-C6DD-3049-88C3-E5A98AAB8E43. HTTPS mit TLS 1.2 und 1.3 und WVL-Abfrage wurden direkt an diesem Agenten geprüft. Die vorige App liegt als MailNotesAgent.app.before-tls-fix-20261118 neben der PAServer-App. Autostart bleibt aus; kein neuer Installer/Release veröffentlicht.

Zusatzbefund: Der erste Start blockierte beim direkten SQLite-Backup ins pCloud-Ziel, während FDatabaseLock gehalten wurde. Nach ausdrücklicher Zustimmung des Anwenders wurde nur Backup.Directory in der Mac-INI vorübergehend nach /Users/gerd/Library/Application Support/MailNotes/Backups umgestellt. Erstes automatisches Backup erstellt und geprüft: integrity_check=ok, 117 Notizen. HTTP/WVL antworten danach weiter. Die vorherige INI ist gesichert; bestehende pCloud-Backups bleiben erhalten. Neue Sicherungen liegen bis zur Klärung nur lokal.

Offen: Dauerlauf über Nacht; ausführliche Windows-Praxistests; pCloud-Verfügbarkeit/Rückumstellung. Ein späterer Backup-Umbau sollte zunächst lokal sichern und erst außerhalb der DB-Sperre ins externe Ziel veröffentlichen. Vollständige Diagnoseartefakte: /Users/gerd/Documents/Codex/2026-11-18/MailNotes-Absturz/Befund.md.

Eine durch den unterbrochenen SMB-Schreibzugriff leere Projektdatei wurde vor dem Patch aus der unmittelbar zuvor erstellten Sicherung wiederhergestellt und als XML geprüft. Für weitere IDE-Builds das extern geänderte Projekt neu laden, damit die Compatibility-Unit sicher verwendet wird.


### WVL-Filteranzeige kompakter (18.11.)

Der Filterknopf folgt der gewählten Ansicht: Zukünftig grüner Pfeil, Fällig roter Pfeil, Erledigt grauer Haken, sonst grauer Pfeil. Der globale Zähler bleibt unverändert; ohne Auswahl kann seine Zahl weiterhin fällige WVL rot signalisieren. Bei aktivem WVL-Filter entfällt die zusätzliche Fälligkeitszeile; ohne WVL-Filter ist sie auf „↺ N fällig“ verkürzt. Leere Auswahl: „Keine Treffer.“. TypeScript, Production-Build und isolierte DOM/CSS-Prüfung bestanden. Pakete auf Mac, VM und im Mac-App-Bundle identisch aktualisiert.


### Erster Klick auf WVL während des Ladens (18.11.)

Das Add-in merkt den Dialogwunsch beim Laden für die konkrete Mail vor und öffnet ihn nach der vollständigen Datenübernahme. Der WVL-Aktionsknopf kann während eines laufenden gültigen Ladevorgangs geklickt werden; doppelte Klicks öffnen nur einen Dialog. Andere Mail bzw. Ladefehler öffnen keinen veralteten Dialog. Wiederholtes Laden derselben Mail erhält den vorgemerkten Wunsch. Die Diagnose protokolliert „reminder dialog requested“ mit dem Ladezustand, ohne Mailinhalt/ID. Ein isolierter Browser-Test mit den echten Lade- und Dialogfunktionen sowie verzögertem Abruf bestand. Outlook-Praxistest des vom Anwender beschriebenen ersten Klicks noch offen.


### Enter im WVL-Dialog / Klickdiagnose (18.11.)

Speichern ist nun der Submit-Button eines Formulars. Enter im Datum-/Zeitfeld übernimmt den Termin; native Segmente werden vor Submit per Blur bestätigt. Validierung, Schutz vor doppeltem Speichern und Warten auf Speicherbestätigung bleiben erhalten. Abbrechen/Entfernen sind weiterhin type=button. Browser-Prüfungen zu gültigem/ungültigem Datum, Mehrfach-Enter, IME, Abbrechen sowie verzögertem Laden bestanden.

Der erste Klick in Outlook wurde vom Anwender weiterhin als fehlerhaft gemeldet und ist offen. Die bisherige Zusatzdiagnose war durch ENABLE_LOGGING=false ebenfalls abgeschaltet. Inhaltsfreie Workflow-Diagnosen dürfen nun gezielt bei aktivem INI-Debug-Schalter protokolliert werden, ohne das allgemeine Produktionslogging einzuschalten. Pointerdown/Click auf WVL-Aktion/-Eintrag sowie Dialoganforderung und erfolgreiches Öffnen werden erfasst. Der Schaltertest (Debug ein/aus bei Produktionslogging aus) bestand. Der nächste Outlook-Praxistest muss die tatsächlichen Ereignisse liefern.


### Verlorener erster Aktivierungsklick (18.11.)

Die reale Klickdiagnose zeigt am 18.11. um 11:48:56 nur pointerdown auf note-reminder-entry, loading=false, disabled=false, focused=false. Erst der zweite Versuch um 11:49:00 liefert pointerdown und click bei focused=true; der Dialog öffnet danach. Der Anwender berichtet denselben Effekt am WVL-Filter direkt nach dem Anpinnen. Die vorherige Lade-Vormerkung adressierte diesen Fokusfall nicht.

Neu: src/taskpane/focusClickRecovery.ts im Add-in. Nur ein primärer Mausdruck in der zunächst unfokussierten Taskpane wird beobachtet. Nach pointerup/mouseup bekommt der normale click Vorrang; nur wenn er fehlt, wird die Knopfaktion ergänzt. Ein verspäteter nativer Klick derselben Aktivierung wird unterdrückt, neue physische Klicks und Tastaturklicks bleiben eigenständig. Ziehen, pointercancel, deaktivierte/entfernte Knöpfe lösen keine Ersatzaktion aus. WVL-/Filterdiagnose erfasst jetzt auch pointerup/mouseup.

Prüfung: npm run test:focus-click (isolierter Chrome, MAILNOTES_TEST_CHROME optional) bestanden, ebenso TypeScript und Production-Build. Der Test ist im Projekt unter scripts/test-focus-click-recovery.cjs gespeichert. Mac-Livepaket, VM-Ressourcen und signiertes Mac-App-Paket aktualisiert. Outlook vollständig neu starten, damit die neuen Handler installiert werden. Native Outlook-Praxisprüfung nach dem Neustart steht noch aus.
