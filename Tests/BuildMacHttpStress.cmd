@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0..\Main"
msbuild MailNotesAgent.dproj /t:Build /p:Config=Release /p:Platform=OSXARM64 /p:MainSource=..\Tests\MacHttpStress\MacHttpStress.dpr /p:DCC_MapFile=3 /p:DCC_ExeOutput=..\Tests\MacHttpStressBuild /p:DCC_DcuOutput=..\Tests\MacHttpStressBuild /v:minimal
