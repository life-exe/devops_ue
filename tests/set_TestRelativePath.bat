:: Copyright LifeEXE. All Rights Reserved.

@echo off

rem This script is designed to be called from create_spec_file.bat and create_test_file.bat
rem It sets TestRelativePath (relative path for saving the test files)

set TestRelativePath=%RelativePathToTests%
echo In what directory do you want to create the test file(s)? The target directory relative to [Source\%ProjectPureName%] is currently "%TestRelativePath%".
echo Please note that OpenCppCoverage will exclude tests from the following path: [%ExcludedPathForTestReport%*]. 
:change_TestRelativePath
set /p ChangeDirChoice= "Do you want to change the target directory? [Y/N or (E)xit] :"
set RETURNED_VALUE=
if /i "%ChangeDirChoice%"=="Y" (
	set /p TestRelativePath= "Enter the new relative to [Source\%ProjectPureName%] directory (use \ symbol for subdirs) :"
) else if /i "%ChangeDirChoice%"=="e" (
	set RETURNED_VALUE=EXIT
) else if /i "%ChangeDirChoice%"=="n" (
	 rem Just continue with the current TestRelativePath
) else (
    echo Invalid ChangeDirChoice. Please enter Y, N or E.
	goto change_TestRelativePath
)
