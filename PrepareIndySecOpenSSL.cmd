@echo off
setlocal
cd /d "%~dp0"

set "TARGET=ThirdParty\IndySecOpenSSL"
set "REPO=https://github.com/MWASoftware/IndySecOpenSSL.git"

where git >nul 2>&1
if errorlevel 1 (
  echo FEHLER: git wurde nicht gefunden.
  echo Bitte Git for Windows installieren bzw. git in PATH aufnehmen.
  pause
  exit /b 1
)

if exist "%TARGET%\src\IdSecOpenSSL.pas" (
  echo IndySecOpenSSL ist bereits vorbereitet:
  echo   %TARGET%
  exit /b 0
)

if exist "%TARGET%" rmdir /s /q "%TARGET%"

echo Klone IndySecOpenSSL projektlokal...
git clone --depth 1 https://github.com/MWASoftware/IndySecOpenSSL.git "%TARGET%"
if errorlevel 1 (
  echo.
  echo FEHLER: IndySecOpenSSL konnte nicht geklont werden.
  pause
  exit /b 2
)

if not exist "%TARGET%\src\IdSecOpenSSL.pas" (
  echo.
  echo FEHLER: IdSecOpenSSL.pas wurde nicht gefunden.
  pause
  exit /b 3
)

echo.
echo Fertig. Delphi selbst wurde NICHT veraendert.
exit /b 0
