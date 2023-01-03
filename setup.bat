:: Copyright LifeEXE. All Rights Reserved.
@echo off

mkdir "%~dp0..\devops_data"

copy "%~dp0setup\config.template" "%~dp0..\devops_data\config.bat"
copy "%~dp0setup\clean_intermediate_files.template" "%~dp0..\devops_data\clean_intermediate_files.bat"
copy "%~dp0setup\format_all_files.template" "%~dp0..\devops_data\format_all_files.bat"
copy "%~dp0setup\generate_project_files.template" "%~dp0..\devops_data\generate_project_files.bat"
copy "%~dp0setup\run_tests.template" "%~dp0..\devops_data\run_tests.bat"
copy "%~dp0setup\generate_docs.template" "%~dp0..\devops_data\generate_docs.bat"
copy "%~dp0setup\package_game.template" "%~dp0..\devops_data\package_game.bat"
copy "%~dp0setup\update_submodules.template" "%~dp0..\devops_data\update_submodules.bat"
copy "%~dp0setup\README.template" "%~dp0..\devops_data\README.md"
copy "%~dp0setup\.clang-format.template" "%~dp0..\devops_data\.clang-format"
copy "%~dp0setup\.gitignore.template" "%~dp0..\devops_data\.gitignore"
copy "%~dp0setup\LICENSE.template" "%~dp0..\devops_data\LICENSE.md"
copy "%~dp0setup\Doxyfile.template" "%~dp0..\devops_data\Doxyfile"

echo All files were copied to "%~dp0..\devops_data"
pause
