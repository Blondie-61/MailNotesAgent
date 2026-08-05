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
echo Fertig: %~dp0Output\MailNotesAgent-Setup-0.2.exe
pause
