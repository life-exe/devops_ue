:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

rem remove previous data folder
set TestsDir=%~dp0
set TestsDataDir=%~dp0data
if exist "%TestsDataDir%" rmdir /s /q "%TestsDataDir%"

rem copy automation content
robocopy "%UEAutomationContentPath%" "%TestsDataDir%" /E

rem install simple server and bower (if bower.json exists in UE Automation Content)
call npm install -g http-server bower

if exist "%TestsDataDir%\bower.json" (
    pushd "%TestsDataDir%"
    call bower install
    popd
)
exit /b 0
