@echo off

call "%~dp0\..\config.bat"

start "" "%ClientExePath%" -WINDOWED -ResX=600 -ResY=600 -WinX=10 -WinY=50 -ExecCmds="open 127.0.0.1"
start "" "%ClientExePath%" -WINDOWED -ResX=600 -ResY=600 -WinX=620 -WinY=50 -ExecCmds="open 127.0.0.1:7777"