@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"
if not exist "%TEMP%\MailNotesWorkflowTests" mkdir "%TEMP%\MailNotesWorkflowTests"
dcc64 -Q -B "-U%BDS%\lib\win64\release;..\Main" "-E%TEMP%\MailNotesWorkflowTests" "-N0%TEMP%\MailNotesWorkflowTests" WorkflowTests.dpr > "%TEMP%\mailnotes-workflow-tests-build.log" 2>&1
if errorlevel 1 (type "%TEMP%\mailnotes-workflow-tests-build.log" & exit /b 1)
"%TEMP%\MailNotesWorkflowTests\WorkflowTests.exe" "%~dp0Fixtures\Schema6.sqlite"
if errorlevel 1 exit /b 1
"%TEMP%\MailNotesWorkflowTests\WorkflowTests.exe" "%~dp0Fixtures\Schema7.sqlite"
