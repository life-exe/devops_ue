:: Copyright LifeEXE. All Rights Reserved.
@echo off
setlocal

rem Check if WASM_EMSDK_ROOT is already defined
if defined WASM_EMSDK_ROOT (
    echo WASM_EMSDK_ROOT is already set to: %WASM_EMSDK_ROOT%
    exit /b 0
)

set TARGET_DIR=C:\emsdk
if exist "%TARGET_DIR%\emsdk.bat" (
    echo Found existing emsdk at %TARGET_DIR%
) else (
    echo Cloning emsdk to %TARGET_DIR%...
    git clone https://github.com/emscripten-core/emsdk.git "%TARGET_DIR%"
    rem "if errorlevel" is evaluated at run time, %ERRORLEVEL% inside ( ) would be expanded before git runs
    if errorlevel 1 (
        echo [ERROR] Failed to clone emsdk!
        exit /b 1
    )
)

cd /d "%TARGET_DIR%"
echo Installing Emscripten 6.0.10 (required by Unreal Engine Wasm platform)...
call emsdk.bat install 6.0.10
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to install Emscripten 6.0.10!
    exit /b 1
)

echo Activating Emscripten 6.0.10...
call emsdk.bat activate 6.0.10
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to activate Emscripten 6.0.10!
    exit /b 1
)

echo Setting WASM_EMSDK_ROOT environment variable...
setx WASM_EMSDK_ROOT "%TARGET_DIR%"
set "WASM_EMSDK_ROOT=%TARGET_DIR%"

echo [SUCCESS] Emscripten 6.0.10 successfully configured!
exit /b 0
