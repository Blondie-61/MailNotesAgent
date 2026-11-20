# Isolated Mac HTTPS stress harness

Build with Tests/BuildMacHttpStress.cmd in the Delphi VM. This builds a separate executable into Tests/MacHttpStressBuild and does not deploy or launch the agent. It needs the same SDK and OpenSSL library installation as the main project.

The executable uses port 48579 and requires one data-directory argument beginning with /private/tmp/MailNotesAgent-Stress-. It never uses the normal MailNotes data path. Initialize that directory with Data/01_CreateSchema.sql and an isolated TLS directory (localhost-cert.pem and localhost-key.pem). Copy the agent's runtime dylibs beside the test executable. System reminders are deliberately not delivered; the scheduler callback is empty.

The server exits when a file named stop appears in its data directory, or after 180 seconds. Its shutdown markers identify whether the scheduler, server or database teardown fails. Retain the matching .map and executable for address resolution. Initial testpath/port mismatch must fail before sending any HTTP requests.

Reproduction and after-fix evidence for 18 November 2026 are stored on the Mac under Documents/Codex/2026-11-18/MailNotes-Absturz. The original overnight failure still requires an overnight regression run.
