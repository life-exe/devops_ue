:: Copyright LifeEXE. All Rights Reserved.
@echo off
setlocal

rem Load configuration if available
if exist "%~dp0..\..\devops_data\config.bat" (
    call "%~dp0..\..\devops_data\config.bat"
)

set "Port=%~1"
if "%Port%"=="" set "Port=8000"

rem Search for Wasm build directory
set "WasmDir="
if defined ArchivePath (
    if exist "%ArchivePath%\Wasm\Wasm" set "WasmDir=%ArchivePath%\Wasm\Wasm"
    if not defined WasmDir if exist "%ArchivePath%\Wasm" set "WasmDir=%ArchivePath%\Wasm"
)

if not defined WasmDir (
    if defined ProjectRoot (
        if exist "%ProjectRoot%\Build\Wasm\Wasm" set "WasmDir=%ProjectRoot%\Build\Wasm\Wasm"
        if not defined WasmDir if exist "%ProjectRoot%\Builds\Wasm\Wasm" set "WasmDir=%ProjectRoot%\Builds\Wasm\Wasm"
        if not defined WasmDir if exist "%ProjectRoot%\Builds\Wasm" set "WasmDir=%ProjectRoot%\Builds\Wasm"
    )
)

if not defined WasmDir (
    if exist "%~dp0..\..\Build\Wasm\Wasm" set "WasmDir=%~dp0..\..\Build\Wasm\Wasm"
    if not defined WasmDir if exist "%~dp0..\..\Builds\Wasm" set "WasmDir=%~dp0..\..\Builds\Wasm"
)

if not defined WasmDir (
    echo [ERROR] Could not find packaged Wasm build folder!
    echo Please run package\package_wasm.bat first.
    exit /b 1
)

rem Check if engine generated launcher exists next to Wasm folder
for %%D in ("%WasmDir%\..") do set "ParentDir=%%~fD"
for %%F in ("%ParentDir%\Play_*.bat") do (
    if exist "%%~fF" (
        echo Running engine generated launcher: %%~nxF
        cd /d "%ParentDir%"
        call "%%~fF"
        exit /b %ERRORLEVEL%
    )
)

rem Fallback: run serve.py using engine Python
set "PythonExe="
if defined EnginePath (
    if exist "%EnginePath%\Engine\Binaries\ThirdParty\Python3\Win64\python.exe" (
        set "PythonExe=%EnginePath%\Engine\Binaries\ThirdParty\Python3\Win64\python.exe"
    )
)
if not defined PythonExe set "PythonExe=python"

set "ServePy="
if defined EnginePath (
    if exist "%EnginePath%\Engine\Platforms\Wasm\Build\Tools\web\serve.py" (
        set "ServePy=%EnginePath%\Engine\Platforms\Wasm\Build\Tools\web\serve.py"
    )
)
if not defined ServePy if exist "%ParentDir%\serve.py" set "ServePy=%ParentDir%\serve.py"

if not defined ServePy (
    echo [ERROR] Could not locate serve.py!
    exit /b 1
)

echo Starting Wasm web server on port %Port%...
echo Serving: %WasmDir%
"%PythonExe%" "%ServePy%" --root "%WasmDir%" --port %Port% --open index.html
exit /b %ERRORLEVEL%
