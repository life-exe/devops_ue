:: Copyright LifeEXE. All Rights Reserved.
@echo off
setlocal

rem Load configuration if available
if exist "%~dp0..\..\devops_data\config.bat" (
    call "%~dp0..\..\devops_data\config.bat"
)

rem Fallbacks if not set in config
if not defined Configuration set Configuration=Shipping
if "%~1" neq "" set Configuration=%~1
if not defined Platform set Platform=Wasm
if not defined ArchivePath (
    if defined ProjectRoot (
        set "ArchivePath=%ProjectRoot%\Build"
    ) else (
        set "ArchivePath=%~dp0..\..\Build"
    )
)

if not defined RunUATPath (
    if defined EnginePath (
        set "RunUATPath=%EnginePath%\Engine\Build\BatchFiles\RunUAT.bat"
    ) else (
        set "RunUATPath=C:\Program Files\Epic Games\UE_5.9\Engine\Build\BatchFiles\RunUAT.bat"
    )
)

rem Ensure WASM_EMSDK_ROOT is defined
if not defined WASM_EMSDK_ROOT (
    if exist "C:\emsdk" (
        set "WASM_EMSDK_ROOT=C:\emsdk"
    ) else (
        echo [ERROR] WASM_EMSDK_ROOT is not set and C:\emsdk does not exist.
        echo Run setup\setup_emsdk.bat first to install Emscripten 6.0.10.
        exit /b 1
    )
)

echo =======================================================
echo Packaging for Wasm (Web) [%Configuration%]
echo Project: %ProjectPath%
echo Archive: %ArchivePath%\Wasm
echo =======================================================

"%RunUATPath%" BuildCookRun ^
  -project="%ProjectPath%" ^
  -platform=Wasm ^
  -clientconfig="%Configuration%" ^
  -archivedirectory="%ArchivePath%\Wasm" ^
  -build -cook -stage -pak -iostore -package -archive -allmaps ^
  -unattended -utf8output ^
  -AdditionalCookerOptions="-unattended -nopause -nosplash -nullrhi"

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Packaging failed with exit code %ERRORLEVEL%!
    exit /b %ERRORLEVEL%
)

echo [SUCCESS] Web package completed in: %ArchivePath%\Wasm
exit /b 0
