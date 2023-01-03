:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

rem remove previous data folder
set TestsDir=%~dp0
set TestsDataDir=%~dp0data
rmdir /s /q "%TestsDataDir%"

rem copy automation content
robocopy "%UEAutomationContentPath%" "%TestsDataDir%" /E

rem install bower
call npm install -g bower

rem install bower packages
pushd "%TestsDir%"
cd "%TestsDataDir%"
call bower install "%TestsDataDir%\bower.json"
popd

rem install simple server
call npm install http-server bower -g
