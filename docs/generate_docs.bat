:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

pushd "%ProjectRoot%"
rmdir /s /q "%ProjectRoot%\Documentation"
doxygen "%ProjectRoot%\devops_data\Doxyfile"
start "" "%ProjectRoot%\Documentation\html\index.html"
popd
