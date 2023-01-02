@echo off

call "%~dp0\..\config.bat"

start "" "%GameExePath%" ?listen -WINDOWED -ResX=600 -ResY=600 -WinX=1230 -WinY=50