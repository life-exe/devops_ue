:: Copyright LifeEXE. All Rights Reserved.
:: Installs devops_ue skills for Claude Code for the current user (%USERPROFILE%\.claude\skills)
:: so they are available in any folder, e.g. ue-create-project before a project exists.
@echo off
setlocal

set "SkillsSrc=%~dp0"
set "SkillsDst=%USERPROFILE%\.claude\skills"
for %%I in ("%~dp0..") do set "DevopsRoot=%%~fI"

if not exist "%SkillsDst%" mkdir "%SkillsDst%"

for /d %%S in ("%SkillsSrc%*") do (
    if exist "%%S\SKILL.md" (
        echo Installing %%~nxS
        robocopy "%%S" "%SkillsDst%\%%~nxS" /E /NFL /NDL /NJH /NJS /NP >nul
        rem remember where devops_ue lives - the skill scripts need setup.bat and templates from it
        >"%SkillsDst%\%%~nxS\devops_source.txt" echo %DevopsRoot%
    )
)

echo Skills installed to "%SkillsDst%"
pause
