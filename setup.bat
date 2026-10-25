:: Copyright LifeEXE. All Rights Reserved.
@echo off

if not exist "%~dp0..\devops_data" mkdir "%~dp0..\devops_data"

call :copyIfMissing "%~dp0setup\config.template" "%~dp0..\devops_data\config.bat"
call :copyIfMissing "%~dp0setup\clean_intermediate_files.template" "%~dp0..\devops_data\clean_intermediate_files.bat"
call :copyIfMissing "%~dp0setup\format_all_files.template" "%~dp0..\devops_data\format_all_files.bat"
call :copyIfMissing "%~dp0setup\generate_project_files.template" "%~dp0..\devops_data\generate_project_files.bat"
call :copyIfMissing "%~dp0setup\run_tests.template" "%~dp0..\devops_data\run_tests.bat"
call :copyIfMissing "%~dp0setup\generate_docs.template" "%~dp0..\devops_data\generate_docs.bat"
call :copyIfMissing "%~dp0setup\package_game.template" "%~dp0..\devops_data\package_game.bat"
call :copyIfMissing "%~dp0setup\update_submodules.template" "%~dp0..\devops_data\update_submodules.bat"
call :copyIfMissing "%~dp0setup\README.template" "%~dp0..\devops_data\README.md"
call :copyIfMissing "%~dp0setup\.clang-format.template" "%~dp0..\devops_data\.clang-format"
call :copyIfMissing "%~dp0setup\.gitignore.template" "%~dp0..\devops_data\.gitignore"
call :copyIfMissing "%~dp0setup\LICENSE.template" "%~dp0..\devops_data\LICENSE.md"
call :copyIfMissing "%~dp0setup\Doxyfile.template" "%~dp0..\devops_data\Doxyfile"

echo All files were copied to "%~dp0..\devops_data"
pause
goto:EOF

:: existing files (e.g. a configured config.bat) are kept
:copyIfMissing
if exist "%~2" (
    echo Skipped, already exists: %~2
) else (
    copy "%~1" "%~2"
)
exit /b
