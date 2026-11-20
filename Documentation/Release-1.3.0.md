# MailNotes 1.3.0 – Vorbereitung

Stand: 17. November 2026. Noch nicht für die Veröffentlichung freigegeben.

Versionen: Windows-Agent und Setup 1.3.0.0; macOS CFBundleVersion und CFBundleShortVersionString 1.3.0; Outlook-Manifest 1.3.0.0 (vierstellig), npm-Paket 1.3.0.

Neue Funktionen: Wiedervorlagen mit Datum/Uhrzeit, dezente Fälligkeitshinweise im Add-in und Systemmitteilungen; Erledigen/Wiederöffnen mit Zeitstempel; WVL-Auswahlmenü und Zustandsfarben. Erledigte WVL bleiben gespeichert, sind aber inaktiv. Das Terminfenster wartet auf eine erfolgreiche Speicherbestätigung.

## Noch offene Windows-Praxistests

- Neue und bestehende Notiz: WVL setzen, ändern und entfernen, anschließend erneut öffnen und nach Agent-/Outlook-Neustart prüfen.
- Zukunft zählt sofort; bei Fälligkeit bleibt der Zähler gleich und wird rot. Hinweis im Add-in und Windows-Systemmeldung prüfen.
- Mehrere WVL: einzelne ändern/entfernen; Zähler und Liste kontrollieren. Neuer Termin löst wieder eine Meldung aus; gleicher Termin wird nicht mehrfach gemeldet.
- Erledigen/Wiederöffnen: Zeitstempel, inaktive graue WVL, Zähler, Benachrichtigungen und Wiederaktivierung des erhaltenen Termins.
- Menüoptionen und AND-Verknüpfung mit Text, Favoriten, Tags und Personen; leere Trefferliste.
- Speicherfehler/Konflikt: Terminfenster bleibt offen, Fehlermeldung und erfolgreicher erneuter Versuch.
- Backup/Restore aus Schema 6, 7 und 8; danach WVL/Erledigt, Bilder und Formatierungen prüfen.
- Installation/Update des Windows-Setups, vollständiges Add-in-Paket und Versionsanzeigen prüfen.

## Bekannter offener Punkt

macOS zeigt unter Mitteilungen auf dem Entwicklungsrechner weiterhin ein Platzhalter-Icon, obwohl App-Ressource und Registrierung korrigiert sind. Sichtbare Aktualisierung steht noch aus.
