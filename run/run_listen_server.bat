:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

start "" "%GameExePath%" ?listen -WINDOWED -ResX=600 -ResY=600 -WinX=1230 -WinY=50