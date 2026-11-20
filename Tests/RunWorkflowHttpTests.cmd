@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"
netstat -ano -p tcp | findstr /R /C:":48580 .*:0 " >nul
if not errorlevel 1 (echo Testport 48580 belegt & exit /b 2)
if not exist "%TEMP%\MailNotesWorkflowTests" mkdir "%TEMP%\MailNotesWorkflowTests"
dcc64 -Q -B -DDEBUG;MAILNOTES_HTTP_TEST "-NSSystem;Winapi;Vcl;Data;System.Win;Xml;Soap" "-IC:\Delphi-Projekte\Komponenten\IndySecOpenSSL\src;C:\Delphi-Projekte\Komponenten\IndySecOpenSSL\src\opensslHdrs" "-U%BDS%\lib\win64\release;..\Main;..\Compatibility\IndySecOpenSSL;C:\Delphi-Projekte\Komponenten\IndySecOpenSSL\src;C:\Delphi-Projekte\Komponenten\IndySecOpenSSL\src\opensslHdrs" "-E%TEMP%\MailNotesWorkflowTests" "-N0%TEMP%\MailNotesWorkflowTests" WorkflowHttpTests.dpr > "%TEMP%\mailnotes-workflow-http-tests-build.log" 2>&1
if errorlevel 1 (findstr /i "Fehler Schwerwiegend Error" "%TEMP%\mailnotes-workflow-http-tests-build.log" & exit /b 1)
"%TEMP%\MailNotesWorkflowTests\WorkflowHttpTests.exe" "%~dp0Fixtures\Schema7.sqlite"
