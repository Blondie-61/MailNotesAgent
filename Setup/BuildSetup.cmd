@echo off
setlocal
cd /d "%~dp0"

if not exist "..\Main\Win64\Release\MailNotesAgent.exe" (
  echo FEHLER: ..\Main\Win64\Release\MailNotesAgent.exe fehlt.
  echo Bitte den Agent zuerst in Delphi fuer Win64 / Release neu erstellen.
  pause
  exit /b 1
)

if not exist "..\Data\MailNotes.sqlite" (
  echo FEHLER: ..\Data\MailNotes.sqlite fehlt.
  pause
  exit /b 2
)

if not exist "..\Resources\Windows\MN-OK-ALL.ico" (
  echo FEHLER: ..\Resources\Windows\MN-OK-ALL.ico fehlt.
  pause
  exit /b 3
)

if not exist "..\Resources\AddIn\taskpane.html" (
  echo FEHLER: ..\Resources\AddIn\taskpane.html fehlt.
  echo Bitte zuerst den Production-Build des Outlook-Add-ins nach Resources\AddIn kopieren.
  pause
  exit /b 4
)

if not exist "..\Resources\AddIn\manifest.xml" (
  echo FEHLER: ..\Resources\AddIn\manifest.xml fehlt.
  echo Bitte zuerst den kompletten Production-Build des Outlook-Add-ins nach Resources\AddIn kopieren.
  pause
  exit /b 7
)

if not exist "RemoveLocalCertificate.ps1" (
  echo FEHLER: Setup\RemoveLocalCertificate.ps1 fehlt.
  pause
  exit /b 8
)

if not exist "OpenSSL\libssl-3-x64.dll" (
  echo FEHLER: Setup\OpenSSL\libssl-3-x64.dll fehlt.
  echo OpenSSL-3-Win64-DLLs fuer IndySecOpenSSL bereitstellen.
  pause
  exit /b 5
)

if not exist "OpenSSL\libcrypto-3-x64.dll" (
  echo FEHLER: Setup\OpenSSL\libcrypto-3-x64.dll fehlt.
  echo OpenSSL-3-Win64-DLLs fuer IndySecOpenSSL bereitstellen.
  pause
  exit /b 6
)

set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"

if not exist "%ISCC%" (
  echo FEHLER: Inno Setup 6 wurde nicht gefunden.
  echo Erwartet wurde ISCC.exe unter Program Files.
  pause
  exit /b 4
)

"%ISCC%" "MailNotesAgent.iss"
if errorlevel 1 (
  echo.
  echo Setup-Erstellung fehlgeschlagen.
  pause
  exit /b 5
)

echo.
echo Fertig. Setup liegt in: %~dp0Output\
pause
