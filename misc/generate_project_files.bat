@echo off

set EnginePath=%~1
set UBTRelativePath=%~2
set VersionSelector=%~3
set ProjectPath=%CD%\%~4

"%VersionSelector%" -switchversionsilent "%ProjectPath%" "%EnginePath%"

rem Calling UBT is a temporary fix for 5.0EA project generation, could be removed later
rem UBT flags for build from sources: -game -engine
"%EnginePath%\%UBTRelativePath%" -projectfiles -progress -project="%ProjectPath%"
