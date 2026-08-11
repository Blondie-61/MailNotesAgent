MailNotes Agent – Debug / Production
====================================

Eine Codebasis. Der Modus wird automatisch durch Delphis DEBUG-Symbol gewählt.

Zentrale Einstellungen:
  Main\uRuntimeConfig.pas

Debug-Build
-----------
- HTTP-Server bindet wie bisher an alle Interfaces.
- Damit ist der Agent in der Windows-VM vom Mac-dev-server erreichbar.
- Development-CORS-Origins localhost:3000 sind zugelassen.

Release/Production-Build
------------------------
- HTTP-Server bindet nur an 127.0.0.1.
- Nur die Production-Origin des Outlook-Add-ins wird per CORS zugelassen.

Es gibt keine zweite Produktionskopie des Quellcodes.
