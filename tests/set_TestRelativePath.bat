:: Copyright LifeEXE. All Rights Reserved.

@echo off

rem This script is designed to be called from create_spec_file.bat and create_test_file.bat
rem It sets TestRelativePath (relative path for saving the test files) and ModuleName (equals to ProjectPureName or TestsModuleName depending on where test files are created)

set ModuleName=%ProjectPureName%
set UseTestsModule=FALSE

if [%TestsModuleName%]==[] goto :endOfTestsModule

:askWhatModule

rem Suggest creating tests files in the tests module if it is defined
:: ModuleName can be ProjectPureName or TestsModuleName
set RETURNED_VALUE=
echo.
echo TestsModuleName is defined in config.bat: [%TestsModuleName%]. 
set /p "UserChoice=Where do you want to create test file(s)? [M - in the tests (M)odule, P - inside your UE game (P)roject, E - Exit] :" 
if /i "%UserChoice%"=="M" (
	:: Creating test files in the Tests Module
	set ModuleName=%TestsModuleName%
	set UseTestsModule=TRUE
) else if /i "%UserChoice%"=="P" (
	rem Just continue with defaults
) else if /i "%UserChoice%"=="E" (
	set RETURNED_VALUE=EXIT
	goto :EOF
) else (
	echo Invalid UserChoice. Please enter M, P or E.
	goto :askWhatModule
)
:endOfTestsModule

rem Create test files
set TestRelativePath=%RelativePathToTests%
echo.
echo Defining the directory where you want to create the test file(s)...
echo The target directory relative to [Source\%ModuleName%] is currently "%TestRelativePath%".
echo Please note that OpenCppCoverage will exclude tests from the following path(s):
echo - [%ExcludedPathForTestReport%*]
if /i "%UseTestsModule%"=="TRUE" (
	echo - [%SourceCodePath%\%TestsModuleName%*]
)
:change_TestRelativePath
set RETURNED_VALUE=
set /p "ChangeDirChoice=Do you want to change the target directory? [Y/N or (E)xit] :"
if /i "%ChangeDirChoice%"=="Y" (
	set /p "TestRelativePath=Enter the new relative to [Source\%ModuleName%] directory (use \ symbol for subdirs) :"
) else if /i "%ChangeDirChoice%"=="E" (
	set RETURNED_VALUE=EXIT
	goto :EOF
) else if /i "%ChangeDirChoice%"=="N" (
	 rem Just continue with the current TestRelativePath
) else (
    echo Invalid ChangeDirChoice. Please enter Y, N or E.
	goto :change_TestRelativePath
)