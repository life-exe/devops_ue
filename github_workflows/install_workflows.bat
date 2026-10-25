:: Copyright LifeEXE. All Rights Reserved.
@echo off

robocopy "%~dp0workflows" "%~dp0..\..\.github\workflows"
if %ERRORLEVEL% LSS 8 exit /b 0
