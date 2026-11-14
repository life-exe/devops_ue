:: Copyright LifeEXE. All Rights Reserved.
:: Installs devops_ue skills for Claude Code.
::   install_skills.bat           - asks where to install
::   install_skills.bat global    - %USERPROFILE%\.claude\skills (any folder, needed to create a project from scratch)
::   install_skills.bat project   - <project>\.claude\skills (the folder that holds devops_ue, only this project)
@echo off
setlocal

set "SkillsSrc=%~dp0"
for %%I in ("%~dp0..") do set "DevopsRoot=%%~fI"
for %%I in ("%~dp0..\..") do set "ProjectRoot=%%~fI"

set "Mode=%~1"
if /i "%Mode%"=="global" goto :mode_global
if /i "%Mode%"=="project" goto :mode_project

echo Where to install the skills?
echo   [G] Global  - %USERPROFILE%\.claude\skills (available in every folder)
echo   [P] Project - %ProjectRoot%\.claude\skills (only this project, can be committed)
choice /c GP /n /m "Choose G or P: "
if errorlevel 2 goto :mode_project

:mode_global
set "SkillsDst=%USERPROFILE%\.claude\skills"
set "WriteSource=1"
goto :install

:mode_project
set "SkillsDst=%ProjectRoot%\.claude\skills"
rem project skills find devops_ue next to .claude by themselves - no absolute path, the folder stays portable
set "WriteSource=0"

:install
if not exist "%SkillsDst%" mkdir "%SkillsDst%"

for /d %%S in ("%SkillsSrc%*") do (
    if exist "%%S\SKILL.md" (
        echo Installing %%~nxS
        robocopy "%%S" "%SkillsDst%\%%~nxS" /MIR /XD __pycache__ /NFL /NDL /NJH /NJS /NP >nul
        rem global skills remember where devops_ue lives - the scripts need setup.bat and templates from it
        if "%WriteSource%"=="1" (
            >"%SkillsDst%\%%~nxS\devops_source.txt" echo %DevopsRoot%
        ) else (
            if exist "%SkillsDst%\%%~nxS\devops_source.txt" del /q "%SkillsDst%\%%~nxS\devops_source.txt"
        )
    )
)

echo Skills installed to "%SkillsDst%"

rem verify: every installed copy (user and project) must match devops_ue\skills
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check_skills.ps1" -ProjectDir "%ProjectRoot%"

echo Restart Claude Code to pick them up.
if "%~1"=="" pause