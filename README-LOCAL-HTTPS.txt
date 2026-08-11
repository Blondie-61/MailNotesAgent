MailNotes - lokales HTTPS (Production)
======================================

Debug:
  Webpack: https://localhost:3000
  Agent:   http://<VM-IP>:48571

Release:
  Taskpane + API gemeinsam über:
  https://localhost:48571

Damit entfallen im Produktivbetrieb GitHub-Pages -> Loopback-Fetch sowie CORS/LNA.

Setup:
  - installiert den Add-in-Build nach C:\Program Files\MailNotes\Addin
  - erzeugt beim ersten Setup ein individuelles localhost-Zertifikat
  - vertraut diesem Zertifikat in LocalMachine\Root
  - exportiert Zertifikat/Key nach C:\ProgramData\MailNotes\TLS
  - startet anschließend den Agent

WICHTIG:
  Für HTTPS wird MWASoftware/IndySecOpenSSL projektlokal verwendet.
Vor dem ersten Win64-Build einmal PrepareIndySecOpenSSL.cmd ausführen.
Für die Laufzeit werden OpenSSL-3-Win64-DLLs benötigt (Setup\OpenSSL).
