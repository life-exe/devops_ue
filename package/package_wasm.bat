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

rem Maps: the project's MapsToCook (Config\DefaultGame.ini) when it lists any, else every map (-allmaps).
rem -allmaps also cooks the demo levels of marketplace packs and their heavy content
set "CookMapsArg=-allmaps"
for %%I in ("%ProjectPath%") do set "ProjectConfigGame=%%~dpIConfig\DefaultGame.ini"
if exist "%ProjectConfigGame%" (
    findstr /b /c:"+MapsToCook=" "%ProjectConfigGame%" >nul && set "CookMapsArg="
)
if defined CookMapsArg (set "CookMapsInfo=all maps") else (set "CookMapsInfo=MapsToCook from DefaultGame.ini")

echo =======================================================
echo Packaging for Wasm (Web) [%Configuration%]
echo Maps: %CookMapsInfo%
echo Project: %ProjectPath%
echo Archive: %ArchivePath%\Wasm
echo =======================================================

rem "call": without it cmd never returns from RunUAT.bat and nothing below runs
call "%RunUATPath%" BuildCookRun ^
  -project="%ProjectPath%" ^
  -platform=Wasm ^
  -clientconfig="%Configuration%" ^
  -archivedirectory="%ArchivePath%\Wasm" ^
  -build -cook -stage -pak -iostore -package -archive %CookMapsArg% ^
  -unattended -utf8output ^
  -AdditionalCookerOptions="-unattended -nopause -nosplash -nullrhi"

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Packaging failed with exit code %ERRORLEVEL%!
    exit /b %ERRORLEVEL%
)

rem the engine leaves FileOpenOrder\ (open-order logs with build machine paths) in the public site folder;
rem the game doesn't use it and it fails the release scan (check_stage.py) - keep it next to Wasm-Debug
call :moveFileOpenOrder "%ArchivePath%\Wasm\Wasm"
call :moveFileOpenOrder "%ArchivePath%\Wasm"

rem project page additions (OpenGraph tags, og image): devops_data\web\head.html and devops_data\web\public\
if exist "%~dp0..\..\devops_data\web" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0web_page_extras.ps1" -Stage "%ArchivePath%\Wasm" -ExtrasDir "%~dp0..\..\devops_data\web"
    if errorlevel 1 (
        echo [ERROR] Adding devops_data\web to the page failed!
        exit /b 1
    )
)

echo [SUCCESS] Web package completed in: %ArchivePath%\Wasm
exit /b 0

:moveFileOpenOrder
if not exist "%~1\index.html" exit /b 0
if not exist "%~1\FileOpenOrder" exit /b 0
for %%P in ("%~1\..") do set "FileOpenOrderDst=%%~fP\Wasm-FileOpenOrder"
if exist "%FileOpenOrderDst%" rmdir /s /q "%FileOpenOrderDst%"
move "%~1\FileOpenOrder" "%FileOpenOrderDst%" >nul
echo FileOpenOrder moved out of the public folder to %FileOpenOrderDst%
exit /b 0
