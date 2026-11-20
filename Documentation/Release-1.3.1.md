# MailNotes 1.3.1 – privater Teststand

Windows-Agent und Setup: **1.3.1.0** · macOS Apple Silicon: **1.3.1** · Add-in: **1.3.1.0**

Dieser Release bleibt ein unveröffentlichter GitHub-Entwurf. Die Praxistests sind noch nicht abgeschlossen.

## Neu seit 1.2.2

- Wiedervorlagen mit Datum und Uhrzeit, Fälligkeitsanzeige und Systemmitteilungen.
- Notizen mit Erledigt-Zeitpunkt; erneutes Anklicken öffnet sie wieder.
- Kompaktes WVL-Auswahlmenü mit Zustandsfarben und kombinierbaren Suchfiltern.
- Dateiverknüpfungen über ein natives Ablagefenster: mehrere Dateien aus verschiedenen Ordnern per Drag-and-drop oder Dateiauswahl hinzufügen.
- Das Fenster bleibt bis „Fertig“ geöffnet und zeigt Dateinamen, Ordner sowie den bestätigten Speicherstatus. Bereits vorhandene Verknüpfungen werden mit angezeigt.
- Dateiverknüpfungen werden beim Aufrufen geprüft. Nicht erreichbare Dateien bleiben gespeichert und werden dezent markiert.
- Schlankere Oberfläche und einheitliche Verknüpfungssymbole.

## Korrekturen

- Verlorene erste Klicks nach Aktivierung/Anpinnen des Taskpanes werden aufgefangen.
- Enter speichert den Wiedervorlage-Dialog; Dialoge warten auf bestätigte Speicherung.
- macOS-TLS-Verbindungen verwenden getrennte Verbindungsobjekte. Der anschließende Dauerlauf war erfolgreich; daraus folgt noch keine Garantie für alle Langzeitfälle.
- Add-in-Pakete werden vollständig mit Dateiinventar und Prüfsummen bereitgestellt.

## Hinweise zum Test

- Vor dem Update eine Datenbanksicherung erstellen. Der Agent migriert ältere Datenbanken auf **Schema 9**.
- Dateiverknüpfungen enthalten nur Pfade. Die Dateien selbst werden weder kopiert noch Teil des Datenbankbackups. Entfernen einer Verknüpfung löscht die Datei nicht.
- Verschieben oder Umbenennen wird nicht automatisch nachverfolgt. Pfade der jeweils anderen Plattform werden als dort nicht verfügbar behandelt.
- Mac-DMG: nur Apple Silicon, lokal ad hoc signiert und nicht notarisiert. Automatischer Start bleibt bei der Standardinstallation ausgeschaltet.
- Windows-Setup: Autostart und Add-in-Einrichtung sind auswählbare Aufgaben.
- Der Agent und das Taskpane müssen beide aktualisiert werden. Agent und Outlook anschließend neu starten.

## Prüfung

Bereits bestanden: Windows-/Mac-Builds, Datenbankmigration und Backup/Restore mit Schema 6/7/8, Dateilink-API, native Fenstertests, Browserprüfungen zu Mailwechseln, mehreren Ablagen, Speicherbestätigungen und Dateinamen sowie TypeScript/Produktionsbuild. Der erste echte Finder-Drop wurde vom Anwender bestätigt.

Noch offen: vollständiger Windows-Outlook-Praxistest aller neuen Funktionen, mehrfache reale Ablagen im überarbeiteten Fenster auf beiden Plattformen sowie Installation/Update der hier angehängten Pakete auf den Testsystemen.
