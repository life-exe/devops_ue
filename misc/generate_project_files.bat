:: Copyright LifeEXE. All Rights Reserved.
@echo off

set EnginePath=%~1
set VersionSelector=%~2
set ProjectPath=%CD%\%~3

"%VersionSelector%" -switchversionsilent "%ProjectPath%" "%EnginePath%"
