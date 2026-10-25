:: Copyright LifeEXE. All Rights Reserved.
@echo off

set EnginePath=%~1
set VersionSelector=%~2

rem project file: absolute path, relative to the current dir, or relative to the project root
set ProjectPath=%~f3
if not exist "%ProjectPath%" set ProjectPath=%~dp0..\..\%~3
if not exist "%ProjectPath%" (
    echo Project file not found: %~3
    exit /b 1
)

set BuildBatPath=%EnginePath%\Engine\Build\BatchFiles\Build.bat
if exist "%BuildBatPath%" (
    call "%BuildBatPath%" -projectfiles -project="%ProjectPath%" -game -progress
    exit /b
)

rem fallback for engines without batch files
if exist "%VersionSelector%" (
    "%VersionSelector%" -switchversionsilent "%ProjectPath%" "%EnginePath%"
    exit /b
)

echo Neither "%BuildBatPath%" nor "%VersionSelector%" was found, check EnginePath and VersionSelector in devops_data\config.bat
exit /b 1
