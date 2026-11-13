# MailNotes 1.2.2.1

Release-Vorbereitung vom 13. November 2026. Dieser Stand ist ein Freigabekandidat.

## Änderungen

- PNG- und JPEG-Bilder aus der Zwischenablage in Notizen einfügen. Die Bilder liegen als SQLite-BLOBs in derselben Datenbank und werden mitgesichert.
- Markdown-Vorschau mit Formatierungsleiste, Links und kombinierten Fett-/Kursivformatierungen.
- Kompakter Kopf, breites Suchfeld, eigene Filterzeile und platzsparende Mailinformationen.
- Lesbare Suchvorschauen mit Bildhinweis statt interner Bildreferenzen.
- Ein Diagnosebereich, gesteuert über den INI-Eintrag [Debug] Enabled. Bei fehlendem Eintrag oder Enabled=0 bleibt die Diagnose aus.
- Vollständige Add-in-Pakete mit Dateiliste und SHA-256-Prüfung. Wechselnde CSS-Namen werden übernommen. PAServer-Altdateien werden beim Installieren des manifestierten Pakets ausgelassen.
- Setup und Delphi-Deployment prüfen das Paket mit PowerShell. Node.js wird für den optionalen Paketimport benötigt.

## Datenbank und Versionen

Der Agent migriert Schema 6 beim Öffnen auf Schema 7. Die Migration ergänzt NoteImages und Notizrevisionen. Bilddaten und Notiztext werden in derselben Transaktion gespeichert. Der bestehende Formular-Speicherpfad akzeptiert Textänderungen, solange vorhandene Bildreferenzen erhalten bleiben.

Das Add-in aktiviert Bilder nur bei capabilities.noteImages. Bei einem Speicherkonflikt hält es den lokalen Entwurf und neue Bilder innerhalb des geöffneten Taskpanes vor. Vor dem Update eine Datenbanksicherung erstellen.

Windows-Agent, Installer und Add-in tragen 1.2.2.1. Der dreiteilige macOS-Bundle-Build lautet 1.2.2, die angezeigte Agent-Version 1.2.2.1.

## Bestätigte Prüfungen

- Der Anwender hat Bild-Paste, Anzeige nach erneutem Öffnen, Formatierung und Diagnose-Sichtbarkeit auf Mac und Windows bestätigt.
- Restore mit Bild wurde auf dem Windows-Testsystem bestätigt.
- Bildentfernung mit Speichern und erneutem Öffnen sowie der Konflikt mit erhaltenem Entwurf und Bild sind in Outlook bestätigt. Dafür wurden Hauptfenster und separates Mailfenster verwendet.
- Der neu gebaute macOS-Agent startete nach der PAServer-Korrektur ohne Bereitstellungswarnung.
- Isolierte Agent-Tests für atomaren Save, Rollback, Migration und Restore stehen in HANDOFF.md.
- Am 13. November waren TypeScript-Prüfung, nativer Produktionsbuild, docs-Export und Paketprüfung erfolgreich.
- dist, docs, installiertes Mac-Add-in und Resources/AddIn haben dieselbe geprüfte Build-ID.
- Windows-Agent und Installer wurden auf Datei- und Produktversion 1.2.2.1 geprüft.
- BuildSetup.cmd hat am 13. November das Setup mit dem aktuellen Paket erfolgreich erzeugt.

## Bekannter ungeklärter Fehler

Die Markdown-Vorschau wurde nach erneutem Auswählen zeitweise falsch gezeichnet, obwohl der Rohtext vollständig blieb. Die Entkopplung vom versteckten Editor allein behob den gemeldeten Fehler nicht. Er war zuletzt auf beiden Plattformen nicht reproduzierbar. Eine bestätigte Ursache und abschließende Korrektur fehlen.

Bei erneutem Auftreten vor einem Outlook-Neustart die Diagnose mit Enabled=1 aktivieren und das Protokoll sichern. Die zusätzliche Renderdiagnose protokolliert Fingerabdrücke und Strukturzahlen ohne Notiztext.

## Vor Veröffentlichung offen

- Den am 13. November neu erzeugten Installer auf dem Test-PC installieren bzw. aktualisieren und bei wieder verfügbarem Outlook prüfen. Das vorherige Setup wurde grundsätzlich erfolgreich getestet.
- Den endgültigen macOS-Auslieferungsstand mit diesem Paket über Delphi/PAServer erzeugen und Manifest, Start sowie Installerablauf prüfen. Der frühere erfolgreiche Starttest gilt für den damaligen Stand.
- Über die Freigabe trotz des dokumentierten sporadischen Vorschaufehlers entscheiden.
- Anschließend Release-Tags, Push und Veröffentlichung durchführen.

## Paketidentität

Add-in-Build-ID 632dce351ae14b240148fb72265dec1549b98d8072c03b796f3a5acfb6f875d6.

Die vollständigen Paketprüfsummen stehen in Resources/AddIn/addin-build.json.
Die folgenden Prüfsummen beziehen sich auf die am 13. November erzeugten lokalen Dateien.

- MailNotesAgent-Setup-1.2.2.1.exe SHA-256 3005187302b7938e82d1e3ab7da2d311240a26040e280d872b0a9011ec5150bd
- MailNotesAgent.exe SHA-256 2e08725a1c5331b124aefe30f4cb691e1b3bc722798deaae201eff7469d01376
- addin-build.json SHA-256 06da0958c911d5ba139d827aa22900881ff0f3d099302958693ad21303abc31c
