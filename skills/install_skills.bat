:: Copyright LifeEXE. All Rights Reserved.
:: Installs devops_ue skills for AI coding agents (Claude Code, Codex, OpenCode, Antigravity).
::   install_skills.bat                          - asks where and for which agent
::   install_skills.bat global|project           - Claude Code (as before)
::   install_skills.bat global|project <agent>   - agent: claude | codex | opencode | antigravity | all
::
:: Folders (project = <project>\..., global = %USERPROFILE%\...):
::   claude                 .claude\skills
::   codex, opencode        .agents\skills   (the shared "agents" folder; OpenCode also reads .claude\skills)
::   antigravity            .agents\skills   (+ global: .gemini\antigravity\skills)
::   all                    all of the above
:: project: the folder that holds devops_ue, only this project, can be committed.
:: global: any folder, needed to create a project from scratch.
@echo off
setlocal

set "SkillsSrc=%~dp0"
for %%I in ("%~dp0..") do set "DevopsRoot=%%~fI"
for %%I in ("%~dp0..\..") do set "ProjectRoot=%%~fI"

set "Mode=%~1"
set "Agent=%~2"

if "%Mode%"=="" goto :ask_mode
if /i "%Mode%"=="global" goto :mode_ok
if /i "%Mode%"=="project" goto :mode_ok
echo Unknown mode "%Mode%": use global or project
exit /b 1

:ask_mode
echo Where to install the skills?
echo   [G] Global  - %USERPROFILE% (available in every folder)
echo   [P] Project - %ProjectRoot% (only this project, can be committed)
choice /c GP /n /m "Choose G or P: "
if errorlevel 2 (set "Mode=project") else (set "Mode=global")
set "Interactive=1"

:mode_ok
if not "%Agent%"=="" goto :agent_ok
if not "%Interactive%"=="1" (
    set "Agent=claude"
    goto :agent_ok
)
echo For which agent?
echo   [C] Claude Code         (.claude\skills)
echo   [X] Codex / OpenCode / Antigravity  (.agents\skills)
echo   [A] All
choice /c CXA /n /m "Choose C, X or A: "
if errorlevel 3 (set "Agent=all") else if errorlevel 2 (set "Agent=codex") else (set "Agent=claude")

:agent_ok
set "DoClaude=0"
set "DoAgents=0"
set "DoGemini=0"
if /i "%Agent%"=="claude"      set "DoClaude=1"
if /i "%Agent%"=="codex"       set "DoAgents=1"
if /i "%Agent%"=="opencode"    set "DoAgents=1"
if /i "%Agent%"=="antigravity" set "DoAgents=1" & set "DoGemini=1"
if /i "%Agent%"=="all"         set "DoClaude=1" & set "DoAgents=1" & set "DoGemini=1"
if "%DoClaude%%DoAgents%%DoGemini%"=="000" (
    echo Unknown agent "%Agent%": use claude, codex, opencode, antigravity or all
    exit /b 1
)

if /i "%Mode%"=="global" (
    set "Base=%USERPROFILE%"
    set "WriteSource=1"
) else (
    set "Base=%ProjectRoot%"
    rem project skills find devops_ue next to .claude / .agents by themselves - no absolute path, the folder stays portable
    set "WriteSource=0"
    set "DoGemini=0"
)

if "%DoClaude%"=="1" call :install_to "%Base%\.claude\skills"
if "%DoAgents%"=="1" call :install_to "%Base%\.agents\skills"
if "%DoGemini%"=="1" call :install_to "%USERPROFILE%\.gemini\antigravity\skills"

rem verify: every installed copy (user and project) must match devops_ue\skills
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check_skills.ps1" -ProjectDir "%ProjectRoot%"

echo Restart your agent (Claude Code / Codex / OpenCode / Antigravity) to pick the skills up.
if "%Interactive%"=="1" pause
exit /b 0

:install_to
set "SkillsDst=%~1"
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
exit /b 0
