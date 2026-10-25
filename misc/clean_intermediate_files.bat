:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

if not defined ProjectRoot (
    echo ProjectRoot is not set, check devops_data\config.bat
    exit /b 1
)

pushd "%ProjectRoot%" || exit /b 1
FOR %%f in (%dirsToRemove%) do (
    if exist "%%f" rmdir /s /q "%%f"
)

FOR %%f in (%filesToRemove%) do (
    if exist "%%f" del /q "%%f"
)

rem plugins with sources only: precompiled plugins can't rebuild their binaries
FOR /D %%p in ("Plugins\*") do (
    if exist "%%p\Source" (
        if exist "%%p\Intermediate" rmdir /s /q "%%p\Intermediate"
        if exist "%%p\Binaries" rmdir /s /q "%%p\Binaries"
    )
)
popd
