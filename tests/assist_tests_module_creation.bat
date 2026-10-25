:: Copyright LifeEXE. All Rights Reserved.

@echo off

rem This script facilitates the creation of a UE module for your game tests.
rem Additionally, it prompts the user to assign TestsModuleName variable in config.bat, using the name of this module.
rem This variable streamlines the process of creating new test files within the designated module and enables the exclusion of this module from the OpenCppCoverage report.

set "ConfigBatFullPath=%~dp0..\..\devops_data\config.bat"
call "%ConfigBatFullPath%"

:begin
set /p NewModuleName= "Enter the name of module for tests you want to create :"
if [%NewModuleName%]==[] goto:begin

rem .build.cs / .h / .cpp file names
set ModuleBuildFileName=%NewModuleName%.Build.cs
set ModuleCppFileName=%NewModuleName%.cpp
set ModuleHFileName=%NewModuleName%.h

rem Full paths to .build.cs / .h / .cpp files to create
set ModuleAbsoluteDir=%SourceCodePath%\%NewModuleName%
set ModuleBuildFilePath=%ModuleAbsoluteDir%\%ModuleBuildFileName%
set ModuleCppFilePath=%ModuleAbsoluteDir%\%ModuleCppFileName%
set ModuleHFilePath=%ModuleAbsoluteDir%\%ModuleHFileName%

rem Confirmation info
echo.
echo =========== Files to be created: ===========
echo %ModuleBuildFilePath%
echo %ModuleCppFilePath%
echo %ModuleHFilePath%
if exist "%ModuleAbsoluteDir%" (
	echo.
    echo Directory "%ModuleAbsoluteDir%" already exists. If it contains the files listed above, they will be overwritten.
)

:: Find out if we need to add TestsModuleName to config.bat
set bStringFound=FALSE
set "SetTestsModuleNameString=set TestsModuleName="
call :findStringInFile "%SetTestsModuleNameString%" , "%ConfigBatFullPath%"
set TestsModuleNameExisitsInConfig=FALSE
if "%bStringFound%"=="TRUE" (
    set TestsModuleNameExisitsInConfig=TRUE
)

:: Find out if TestsModuleName exists in config.bat and if we need to define or re-define it
set TestsModuleNameToBeChanged=FALSE
if "%TestsModuleNameExisitsInConfig%"=="TRUE" if [%TestsModuleName%]==[] goto :setTestsModuleNameToBeChanged
if "%TestsModuleNameExisitsInConfig%"=="TRUE" if not "%TestsModuleName%"=="%NewModuleName%" goto :setTestsModuleNameToBeChanged
goto :afterSetTestsModuleNameToBeChanged
:setTestsModuleNameToBeChanged
set TestsModuleNameToBeChanged=TRUE
:afterSetTestsModuleNameToBeChanged

:: Don't print TestsModuleName info block if it's empty
if "%TestsModuleNameExisitsInConfig%"=="TRUE" if "%TestsModuleNameToBeChanged%"=="FALSE" goto :endOfConfirmationInfo

echo =========== TestsModuleName: ===========
if "%TestsModuleNameToBeChanged%"=="TRUE" (
	echo TestsModuleName is currently defined in config.bat as %TestsModuleName%. 
	echo It will be re-defined as %NewModuleName%.
)

if "%TestsModuleNameExisitsInConfig%"=="FALSE" (
    echo TestsModuleName is not found in config.bat. It will be added and defined as %NewModuleName%. 
)

:endOfConfirmationInfo
echo ======================================
echo.

set /p UserConfirmed= "Confirm? [Y/N or (E)xit] :" 
if /i "%UserConfirmed%"=="N" goto :begin
if /i "%UserConfirmed%"=="E" goto :EOF

rem Create dir for the module
if not exist "%ModuleAbsoluteDir%" mkdir "%ModuleAbsoluteDir%"

rem Full paths .build.cs / .h / .cpp template files
set ModuleBuildTemplateFilePath=%ProjectRoot%\devops_ue\tests\templates\tests_module\TestsModule.Build.cs.template
set ModuleCppTemplateFilePath=%ProjectRoot%\devops_ue\tests\templates\tests_module\TestsModule.cpp.template
set ModuleHTemplateFilePath=%ProjectRoot%\devops_ue\tests\templates\tests_module\TestsModule.h.template

rem Remove old module files if exist
set TmpEchoLine=Deleting module files if exist
echo %TmpEchoLine%...
del /q "%ModuleBuildFilePath%"
del /q "%ModuleCppFilePath%"
del /q "%ModuleHFilePath%"
echo %TmpEchoLine%: Complete

rem create actual files
set TmpEchoLine=Creating module files from templates
echo %TmpEchoLine%...
call :createTemplate "%ModuleBuildTemplateFilePath%" , "%ModuleBuildFilePath%"
call :createTemplate "%ModuleCppTemplateFilePath%" , "%ModuleCppFilePath%"
call :createTemplate "%ModuleHTemplateFilePath%" , "%ModuleHFilePath%"
echo %TmpEchoLine%: Complete

rem Dealing with TestsModuleName in config.bat
set TmpEchoLine=Setting TestsModuleName in config.bat
echo %TmpEchoLine%...
:: Add TestsModuleName (with undefined value) to config.bat
if "%TestsModuleNameExisitsInConfig%"=="FALSE" (
    echo. >> "%ConfigBatFullPath%"
    echo. >> "%ConfigBatFullPath%"
    echo %SetTestsModuleNameString% >> "%ConfigBatFullPath%"
)
:: Define or re-define TestsModuleName in config.bat
set before=%SetTestsModuleNameString%
set after=%SetTestsModuleNameString%%NewModuleName%
:: If you need config.bat to be in UTF8, then there is problem with BOM. 
:: The problem is that PowerShell versions up to 5.1 including PowerShell Core 6.x (used by default in Windows 10 versions up to 1909) save files in UTF8 adding BOM. Becuase of this we need to delete BOM, otherwise files saved by powerwhell become binary. And config.bat should not contain BOM to be read without erorrs.
:: However, if you don't need config.bat to be saved in UTF8, it can be saved in ANSCII. To do it, comment out or remove "UTF8 version" block, and uncomment the ASCII version below (it works for all versions of powershell).
:: ASCII version of the powershell comand below works fine: 
:: powershell -Command "(gc '%ConfigBatFullPath%') -replace '^%before%.*', '%after%' | Out-File -encoding ASCII '%ConfigBatFullPath%'"
:: UTF8 version
powershell -Command "(gc '%ConfigBatFullPath%') -replace '^%before%.*', '%after%' | Out-File -encoding UTF8 '%ConfigBatFullPath%'"
call :normalizePath "%ConfigBatFullPath%"
set ConfigBatNormalizedFullPath=%RETVAL%
call :removeBOM "%ConfigBatNormalizedFullPath%"
:: end of UTF8 version
echo %TmpEchoLine%: Complete

rem Clang-format
set TmpEchoLine=Clang format
echo %TmpEchoLine%...
call "%~dp0..\misc\format_all_files.bat"
echo %TmpEchoLine%: Complete

goto :EOF

:: ========== FUNCTIONS ==========

rem Function to create .build.cs / .h / .cpp from template
:createTemplate
set TemplateName=%~1
set FileToWriteIn=%~2
for /f "usebackq tokens=*" %%a in ("%TemplateName%") do (
    if %%a == NEW_LINE (
        echo.>>"%FileToWriteIn%"
    ) else (
        call echo %%a>>"%FileToWriteIn%"
    )
)
exit /b

rem Function to find out if a line exists in a a file. Sets bStringFound=TRUE if found
:findStringInFile
set bStringFound=FALSE
set InSearchString=%~1
set InFilePath=%~2
rem Loop through each line of the file
for /f "usebackq tokens=*" %%a in ("%InFilePath%") do (
    rem Check if the line starts with the specified string
    echo %%a | findstr /b /c:"%InSearchString%" >nul
    if not errorlevel 1 (
        set bStringFound=TRUE
    )
)
exit /b

rem Call the Python script to remove BOM
:removeBOM
python ..\service\remove_bom.py "%~1"
:: Check if Python script execution was successful
if %errorlevel% neq 0 (
    echo ERROR in [remove_bom.py]: Error occurred during conversion. You may need to convert the config.bat file manually into UTF8.
	pause
) else (
    echo [remove_bom.py]: Conversion completed successfully.
)
exit /b

rem Path normalization: e.g. it can turn path representation from "dir1\dir2\..\dir3" into "dir1\dir3"
:normalizePath
set RETVAL=%~f1
exit /b
