# Copyright LifeEXE. All Rights Reserved.
# Sets up an Unreal Engine 5.9+ project for the web (Wasm: WebAssembly + WebGPU):
# emscripten SDK, .uproject plugin rules, Wasm project settings, C++ module for Blueprint-only projects,
# devops_ue web scripts, engine web skills, SDK verification, optional editor build and packaging.
#
#   web_setup.ps1 -ProjectPath C:\Projects\MyGame -StartMode Click
#   web_setup.ps1 -ProjectPath C:\Projects\MyGame -CheckOnly
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [string]$EnginePath = '',
    [string]$EmsdkDir = 'C:\emsdk',
    [switch]$SkipEmsdk,
    [switch]$InstallPlaywright,
    [string]$PageTitle = '',
    [ValidateSet('', 'Auto', 'Click')][string]$StartMode = '',
    [ValidateSet('', 'Warn', 'Block', 'Allow')][string]$MobileDevices = '',
    [switch]$ForwardOnly,
    [switch]$InjectIsolationHeaders,
    [string[]]$WebSetting = @(),
    [switch]$KeepAIAssistant,
    # Blueprint-only projects: add a C++ module (required by Wasm in UE 5.9 Preview)
    [switch]$AddCppModule,
    [switch]$SkipEngineSkills,
    [switch]$SkipVerify,
    [switch]$BuildEditor,
    [ValidateSet('', 'Development', 'Shipping', 'Test')][string]$Package = '',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Warnings = New-Object System.Collections.ArrayList
$Status = [ordered]@{}

function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Add-Warning([string]$Text) { [void]$Warnings.Add($Text); Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}
function Invoke-Exe([string]$FilePath, [string]$Arguments) {
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    $p.WaitForExit()
    return $p.ExitCode
}
function Invoke-Bat([string]$BatPath, [string]$Arguments = '') {
    return Invoke-Exe $env:ComSpec "/d /s /c `"`"$BatPath`" $Arguments < nul`""
}

function Get-IniLines([string]$Path) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) { $lines.AddRange([string[]]([IO.File]::ReadAllLines($Path))) }
    return , $lines
}
function Find-IniSection($Lines, [string]$Section) {
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i].Trim() -eq "[$Section]") { $start = $i; break } }
    if ($start -lt 0) { return @(-1, -1) }
    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) { if ($Lines[$i].Trim() -match '^\[.+\]$') { $end = $i; break } }
    return @($start, $end)
}
function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    $lines = Get-IniLines $Path
    $range = Find-IniSection $lines $Section
    if ($range[0] -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
        $lines.Add("[$Section]"); $lines.Add("$Key=$Value")
    }
    else {
        $done = $false
        for ($i = $range[0] + 1; $i -lt $range[1]; $i++) {
            if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $lines[$i] = "$Key=$Value"; $done = $true; break }
        }
        if (-not $done) {
            $at = $range[1]; while ($at -gt $range[0] + 1 -and $lines[$at - 1].Trim() -eq '') { $at-- }
            $lines.Insert($at, "$Key=$Value")
        }
    }
    [IO.File]::WriteAllLines($Path, $lines, $Utf8NoBom)
}
function Add-IniLine([string]$Path, [string]$Section, [string]$Line) {
    $lines = Get-IniLines $Path
    if ($lines -contains $Line) { return }
    $range = Find-IniSection $lines $Section
    if ($range[0] -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
        $lines.Add("[$Section]"); $lines.Add($Line)
    }
    else {
        $at = $range[1]; while ($at -gt $range[0] + 1 -and $lines[$at - 1].Trim() -eq '') { $at-- }
        $lines.Insert($at, $Line)
    }
    [IO.File]::WriteAllLines($Path, $lines, $Utf8NoBom)
}
function Get-IniValue([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    foreach ($l in [IO.File]::ReadAllLines($Path)) { if ($l -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*)$") { return $Matches[1].Trim() } }
    return ''
}

function Resolve-EngineFromAssociation([string]$Association) {
    if (-not $Association) { return '' }
    foreach ($root in 'HKLM:\SOFTWARE\EpicGames\Unreal Engine', 'HKLM:\SOFTWARE\WOW6432Node\EpicGames\Unreal Engine') {
        $key = Join-Path $root $Association
        if (Test-Path $key) { $dir = (Get-ItemProperty $key).InstalledDirectory; if ($dir -and (Test-Path -LiteralPath $dir)) { return $dir } }
    }
    $builds = 'HKCU:\Software\Epic Games\Unreal Engine\Builds'
    if (Test-Path $builds) {
        $v = (Get-ItemProperty $builds).$Association
        if ($v -and (Test-Path -LiteralPath $v)) { return $v }
    }
    # folder scan from the sibling ue-create-project skill
    $common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
    if (Test-Path -LiteralPath $common) {
        . $common
        $match = Get-UnrealEngines | Where-Object { $_.MajorMinor -eq $Association -or $_.Association -eq $Association } | Select-Object -First 1
        if ($match) { return $match.Path }
    }
    return ''
}

function Get-EmsdkVersion([string]$Dir) {
    if (-not $Dir) { return '' }
    $file = Join-Path $Dir 'upstream\emscripten\emscripten-version.txt'
    if (-not (Test-Path -LiteralPath $file)) { return '' }
    return (Read-Text $file).Trim().Trim('"')
}
function Test-Emsdk([string]$Dir, [string]$Version) {
    if ((Get-EmsdkVersion $Dir) -ne $Version) { return $false }
    $emDir = Join-Path $Dir 'upstream\emscripten'
    foreach ($launcher in 'em++.exe', 'em++.bat', 'em++.py', 'em++') { if (Test-Path -LiteralPath (Join-Path $emDir $launcher)) { return $true } }
    return $false
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project and engine'

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
if ($ProjectPath -like '*.uproject') { $UProjectPath = $ProjectPath; $ProjectRoot = Split-Path -Parent $ProjectPath }
else {
    $ProjectRoot = $ProjectPath
    $found = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File)
    if ($found.Count -ne 1) { throw "Expected exactly one .uproject in $ProjectRoot (found $($found.Count)). Pass -ProjectPath <file.uproject>." }
    $UProjectPath = $found[0].FullName
}
$ProjectName = [IO.Path]::GetFileNameWithoutExtension($UProjectPath)
$uproject = Read-Text $UProjectPath | ConvertFrom-Json
$configBat = Join-Path $ProjectRoot 'devops_data\config.bat'

if (-not $EnginePath -and (Test-Path -LiteralPath $configBat)) {
    $EnginePath = ((Read-Text $configBat) -split "`r?`n" | Where-Object { $_ -match '^set EnginePath=(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
    if ($EnginePath -and -not (Test-Path -LiteralPath (Join-Path $EnginePath 'Engine'))) { $EnginePath = '' }
}
if (-not $EnginePath) { $EnginePath = Resolve-EngineFromAssociation $uproject.EngineAssociation }
if (-not $EnginePath) { throw "Engine not found for association '$($uproject.EngineAssociation)'. Pass -EnginePath." }
$EnginePath = (Resolve-Path -LiteralPath $EnginePath).Path.TrimEnd('\')

$buildVersion = Read-Text (Join-Path $EnginePath 'Engine\Build\Build.version') | ConvertFrom-Json
$engineVersion = [version]"$($buildVersion.MajorVersion).$($buildVersion.MinorVersion)"
$WasmPlatform = Join-Path $EnginePath 'Engine\Platforms\Wasm'
if ($engineVersion -lt [version]'5.9') { throw "Web (Wasm) needs Unreal Engine 5.9+, engine is $engineVersion ($EnginePath)" }
if (-not (Test-Path -LiteralPath $WasmPlatform)) { throw "Engine has no Wasm platform: $WasmPlatform is missing (install the web libraries / use a source build with Engine\Platforms\Wasm)" }

$sdkJson = Read-Text (Join-Path $WasmPlatform 'Config\Wasm_SDK.json') | ConvertFrom-Json
$EmsdkVersion = $sdkJson.MainVersion
$EnginePython = Join-Path $EnginePath 'Engine\Binaries\ThirdParty\Python3\Win64\python.exe'

$isCpp = (Test-Path -LiteralPath (Join-Path $ProjectRoot 'Source')) -and ($uproject.PSObject.Properties['Modules'] -and @($uproject.Modules).Count -gt 0)
Write-Host "Project: $UProjectPath ($(if ($isCpp) { 'C++' } else { 'Blueprint-only' }))"
Write-Host "Engine : $EnginePath ($($buildVersion.MajorVersion).$($buildVersion.MinorVersion).$($buildVersion.PatchVersion))"
Write-Host "emsdk  : required $EmsdkVersion"

# ---------------------------------------------------------------------------------------------
Write-Step "Emscripten SDK $EmsdkVersion"

$wasmRoot = $env:WASM_EMSDK_ROOT
if (-not $wasmRoot) { $wasmRoot = [Environment]::GetEnvironmentVariable('WASM_EMSDK_ROOT', 'User') }
$emsdkVar = $env:EMSDK
if (-not $emsdkVar) { $emsdkVar = [Environment]::GetEnvironmentVariable('EMSDK', 'User') }

$emsdkOk = $false
if ($wasmRoot) {
    if (Test-Emsdk $wasmRoot $EmsdkVersion) { $emsdkOk = $true; Write-Host "  WASM_EMSDK_ROOT=$wasmRoot (ok)" }
    else { Write-Host "  WASM_EMSDK_ROOT=$wasmRoot has emscripten '$(Get-EmsdkVersion $wasmRoot)', need $EmsdkVersion" }
}
elseif ($emsdkVar) {
    if (Test-Emsdk $emsdkVar $EmsdkVersion) { $emsdkOk = $true; $wasmRoot = $emsdkVar; Write-Host "  EMSDK=$emsdkVar (ok)" }
    else { Add-Warning "Stale EMSDK=$emsdkVar (emscripten '$(Get-EmsdkVersion $emsdkVar)'): the engine would use it. WASM_EMSDK_ROOT will override it." }
}
elseif ($env:UE_SDKS_ROOT -and (Test-Path -LiteralPath (Join-Path $env:UE_SDKS_ROOT "HostWin64\Wasm\$EmsdkVersion"))) {
    $emsdkOk = $true; Write-Host "  AutoSDK: $env:UE_SDKS_ROOT\HostWin64\Wasm\$EmsdkVersion (WASM_EMSDK_ROOT/EMSDK must stay unset)"
}

if (-not $emsdkOk -and (Test-Emsdk $EmsdkDir $EmsdkVersion)) {
    $wasmRoot = $EmsdkDir; $emsdkOk = $true; Write-Host "  found $EmsdkDir (ok)"
    if (-not $CheckOnly) { [Environment]::SetEnvironmentVariable('WASM_EMSDK_ROOT', $EmsdkDir, 'User'); Write-Host "  WASM_EMSDK_ROOT=$EmsdkDir (user env)" }
}

if (-not $emsdkOk -and -not $CheckOnly -and -not $SkipEmsdk) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required to install emsdk' }
    if (-not (Test-Path -LiteralPath (Join-Path $EmsdkDir 'emsdk.bat'))) {
        Write-Host "  cloning emsdk to $EmsdkDir"
        git clone https://github.com/emscripten-core/emsdk.git $EmsdkDir
        if ($LASTEXITCODE -ne 0) { throw 'git clone emsdk failed' }
    }
    Write-Host "  emsdk install/activate $EmsdkVersion (downloads ~1 GB)"
    $code = Invoke-Exe $env:ComSpec "/d /s /c `"cd /d `"$EmsdkDir`" && emsdk.bat install $EmsdkVersion && emsdk.bat activate $EmsdkVersion < nul`""
    if ($code -ne 0 -or -not (Test-Emsdk $EmsdkDir $EmsdkVersion)) { throw "emsdk install $EmsdkVersion failed (code $code)" }
    [Environment]::SetEnvironmentVariable('WASM_EMSDK_ROOT', $EmsdkDir, 'User')
    $wasmRoot = $EmsdkDir; $emsdkOk = $true
    Write-Host "  installed, WASM_EMSDK_ROOT=$EmsdkDir (user env)"
}
if ($wasmRoot -and $emsdkOk) { $env:WASM_EMSDK_ROOT = $wasmRoot }
$Status['emsdk'] = if ($emsdkOk) { "ok ($wasmRoot)" } else { 'missing' }
if (-not $emsdkOk) { Add-Warning "emscripten $EmsdkVersion is not installed (run without -SkipEmsdk/-CheckOnly or devops_ue\setup\setup_emsdk.bat)" }

# ---------------------------------------------------------------------------------------------
if ($InstallPlaywright -and -not $CheckOnly) {
    Write-Step 'Playwright for the browser test harness (engine Python)'
    $req = Join-Path $WasmPlatform 'Build\Tools\web\requirements.txt'
    $code = Invoke-Exe $EnginePython "-m pip install -r `"$req`""
    if ($code -ne 0) { Add-Warning "pip install playwright failed (code $code)" }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Blueprint-only check'

if ($isCpp) { Write-Host '  C++ project (ok)'; $Status['cpp'] = 'ok' }
elseif (-not $AddCppModule) {
    $Status['cpp'] = 'Blueprint-only: Wasm packaging is blocked'
    Add-Warning 'Blueprint-only project: UE 5.9 Wasm needs a C++ module. Re-run with -AddCppModule (or Tools > New C++ Class in the editor).'
}
elseif (-not $CheckOnly) {
    $copyright = Get-IniValue (Join-Path $ProjectRoot 'Config\DefaultGame.ini') 'CopyrightNotice'
    if (-not $copyright -and (Test-Path -LiteralPath $configBat)) {
        $line = (Read-Text $configBat) -split "`r?`n" | Where-Object { $_ -match '^set COPYRIGHT_LINE=//\s*(.+)$' } | ForEach-Object { $Matches[1] } | Select-Object -First 1
        if ($line -and $line -notmatch 'My game copyright') { $copyright = $line }
    }
    if (-not $copyright) { $copyright = "Copyright $ProjectName. All Rights Reserved." }
    $copyrightLine = "// $copyright"

    $blankSource = Join-Path $EnginePath 'Templates\TP_Blank\Source'
    if (-not (Test-Path -LiteralPath $blankSource)) { throw "C++ template not found: $blankSource" }
    foreach ($file in Get-ChildItem -LiteralPath $blankSource -Recurse -File) {
        $rel = $file.FullName.Substring($blankSource.Length + 1) -replace 'TP_Blank', $ProjectName
        $text = (Read-Text $file.FullName).Replace('TP_BLANK', $ProjectName.ToUpperInvariant()) -replace 'TP_Blank', $ProjectName
        $text = [regex]::Replace($text, '^\s*//[^\r\n]*Copyright[^\r\n]*', $copyrightLine.Replace('$', '$$'))
        $dest = Join-Path $ProjectRoot "Source\$rel"
        if (-not (Test-Path -LiteralPath $dest)) { Write-Text $dest $text; Write-Host "  created Source\$rel" }
    }
    $api = "$($ProjectName.ToUpperInvariant())_API"
    $gmH = Join-Path $ProjectRoot "Source\$ProjectName\${ProjectName}GameMode.h"
    if (-not (Test-Path -LiteralPath $gmH)) {
        Write-Text $gmH "$copyrightLine`r`n`r`n#pragma once`r`n`r`n#include `"CoreMinimal.h`"`r`n#include `"GameFramework/GameModeBase.h`"`r`n#include `"${ProjectName}GameMode.generated.h`"`r`n`r`nUCLASS()`r`nclass $api A${ProjectName}GameMode : public AGameModeBase`r`n{`r`n    GENERATED_BODY()`r`n};`r`n"
        Write-Text (Join-Path $ProjectRoot "Source\$ProjectName\${ProjectName}GameMode.cpp") "$copyrightLine`r`n`r`n#include `"${ProjectName}GameMode.h`"`r`n"
        Write-Host "  created A${ProjectName}GameMode (the project keeps its current default game mode)"
    }
    & $EnginePython -I (Join-Path $PSScriptRoot 'uproject_web_ready.py') $UProjectPath --add-module $ProjectName $(if ($KeepAIAssistant) { '--keep-ai-assistant' })
    $isCpp = $true
    $Status['cpp'] = "C++ module $ProjectName added"
    $BuildEditor = $true  # the editor can't open the project until the module is built
}

# ---------------------------------------------------------------------------------------------
Write-Step '.uproject plugin rules'
if ($CheckOnly) {
    $names = @(); if ($uproject.PSObject.Properties['Plugins']) { $names = @($uproject.Plugins) }
    foreach ($p in 'OnlineSubsystemUtils', 'OnlineSubsystemNull') {
        $e = $names | Where-Object { $_.Name -eq $p } | Select-Object -First 1
        if (-not $e -or -not ($e.PSObject.Properties['PlatformDenyList'] -and @($e.PlatformDenyList) -contains 'Wasm')) { Add-Warning "$p has no PlatformDenyList Wasm" }
    }
    $at = $names | Where-Object { $_.Name -eq 'AllToolsets' -and $_.Enabled } | Select-Object -First 1
    if ($at) { Add-Warning 'AllToolsets is enabled: the Wasm cook fails (GameFeatureData rule)' }
}
else {
    & $EnginePython -I (Join-Path $PSScriptRoot 'uproject_web_ready.py') $UProjectPath $(if ($KeepAIAssistant) { '--keep-ai-assistant' })
    if ($LASTEXITCODE -ne 0) { throw 'uproject_web_ready.py failed' }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Wasm project settings (Config/DefaultEngine.ini)'

$defaultEngine = Join-Path $ProjectRoot 'Config\DefaultEngine.ini'
$defaultGame = Join-Path $ProjectRoot 'Config\DefaultGame.ini'
$wasmSection = '/Script/WasmTargetPlatform.WasmTargetSettings'

$gameMap = Get-IniValue $defaultEngine 'GameDefaultMap'
if (-not $gameMap -or $gameMap -like '/Engine/*') { Add-Warning "GameDefaultMap is '$gameMap': set the game's start map (Project Settings > Maps & Modes)" }
$mobileHdr = Get-IniValue $defaultEngine 'r.MobileHDR'
if ($mobileHdr -match '^(False|0)$' -and -not $ForwardOnly) { Add-Warning 'r.MobileHDR=False: the deferred tier cannot run, consider -ForwardOnly' }

if (-not $CheckOnly) {
    if (-not $PageTitle -and -not (Get-IniValue $defaultEngine 'PageTitle')) { $PageTitle = $ProjectName }
    if ($PageTitle) { Set-IniValue $defaultEngine $wasmSection 'PageTitle' $PageTitle }
    if ($StartMode) { Set-IniValue $defaultEngine $wasmSection 'StartMode' $StartMode }
    if ($MobileDevices) { Set-IniValue $defaultEngine $wasmSection 'MobileDevices' $MobileDevices }
    if ($ForwardOnly) { Set-IniValue $defaultEngine $wasmSection 'bTargetMobileDeferredTier' 'False' }
    if ($InjectIsolationHeaders) { Set-IniValue $defaultEngine $wasmSection 'bInjectIsolationHeaders' 'True' }
    foreach ($kv in $WebSetting) {
        if ($kv -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Add-Warning "Bad -WebSetting '$kv' (expected Key=Value)"; continue }
        Set-IniValue $defaultEngine $wasmSection $Matches[1] $Matches[2]
    }
    if ($gameMap -like '/Game/*') {
        $mapPackage = $gameMap -replace '\.[^./]+$', ''
        Add-IniLine $defaultGame '/Script/UnrealEd.ProjectPackagingSettings' "+MapsToCook=(FilePath=`"$mapPackage`")"
    }
    $lines = Get-IniLines $defaultEngine
    $range = Find-IniSection $lines $wasmSection
    if ($range[0] -ge 0) { for ($i = $range[0]; $i -lt $range[1]; $i++) { if ($lines[$i].Trim()) { Write-Host "  $($lines[$i])" } } }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'devops_ue web scripts, engine web skills, AGENTS.md'

$devopsUe = Join-Path $ProjectRoot 'devops_ue'
if (Test-Path -LiteralPath (Join-Path $devopsUe 'setup')) {
    if (-not $CheckOnly) {
        if (-not (Test-Path -LiteralPath $configBat)) { Invoke-Bat (Join-Path $devopsUe 'setup.bat') | Out-Null }
        foreach ($name in 'package_wasm', 'run_wasm', 'setup_emsdk') {
            $src = Join-Path $devopsUe "setup\$name.template"
            $dst = Join-Path $ProjectRoot "$name.bat"
            if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $src -Destination $dst; Write-Host "  $name.bat" }
        }
        if (Test-Path -LiteralPath $configBat) {
            $cfg = Read-Text $configBat
            $cfgEngine = ($cfg -split "`r?`n" | Where-Object { $_ -match '^set EnginePath=(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
            if ($cfgEngine -ne $EnginePath) {
                $cfg = [regex]::Replace($cfg, '(?m)^set EnginePath=[^\r\n]*', ("set EnginePath=$EnginePath").Replace('$', '$$'))
                Write-Text $configBat $cfg
                Write-Host "  devops_data\config.bat: EnginePath=$EnginePath"
            }
        }
    }
}
else { Add-Warning 'devops_ue is not in the project: package_wasm.bat/run_wasm.bat were not added (git submodule add https://github.com/life-exe/devops_ue)' }

if (-not $SkipEngineSkills -and -not $CheckOnly) {
    $engineSkills = Join-Path $WasmPlatform 'Skills'
    $skillsDst = Join-Path $ProjectRoot '.claude\skills'
    foreach ($skill in Get-ChildItem -LiteralPath $engineSkills -Directory -ErrorAction SilentlyContinue) {
        if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md'))) { continue }
        New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
        Copy-Item -LiteralPath $skill.FullName -Destination $skillsDst -Recurse -Force
        Write-Host "  .claude\skills\$($skill.Name) (engine)"
    }
}

$agents = Join-Path $ProjectRoot 'AGENTS.md'
if ((Test-Path -LiteralPath $agents) -and -not $CheckOnly) {
    $text = Read-Text $agents
    if ($text -notmatch '(?m)^## Web') {
        $text = $text.TrimEnd() + "`r`n`r`n## Web (Wasm)`r`n`r`n" +
            "* Engine docs: ``$WasmPlatform\Docs`` (GettingStarted.md first); skills ``web-deploy``, ``web-perf-hillclimb``, ``web-texture-sets`` in ``.claude/skills``.`r`n" +
            "* Settings: ``[$wasmSection]`` in ``Config/DefaultEngine.ini``.`r`n" +
            "* Package: ``package_wasm.bat [Development|Shipping]`` (output ``Build\Wasm``), run locally: ``run_wasm.bat`` (never open index.html from disk).`r`n" +
            "* Requires emscripten $EmsdkVersion (``WASM_EMSDK_ROOT``) and a C++ module; keep ``AllToolsets`` off and online subsystems denied for Wasm.`r`n" +
            "* Never upload builds; Development builds are not for the public.`r`n"
        Write-Text $agents $text
        Write-Host '  AGENTS.md: Web section'
    }
}

# ---------------------------------------------------------------------------------------------
if (-not $SkipVerify -and $emsdkOk) {
    Write-Step 'Turnkey VerifySdk -platform=Wasm'
    $runUat = Join-Path $EnginePath 'Engine\Build\BatchFiles\RunUAT.bat'
    $code = Invoke-Bat $runUat 'Turnkey -command=VerifySdk -platform=Wasm -unattended'
    $Status['VerifySdk'] = if ($code -eq 0) { 'ok' } else { "failed (code $code)" }
    if ($code -ne 0) { Add-Warning "VerifySdk failed (code $code)" }
}

# ---------------------------------------------------------------------------------------------
if ($BuildEditor -and $isCpp -and -not $CheckOnly) {
    $genBat = Join-Path $ProjectRoot 'generate_project_files.bat'
    if (Test-Path -LiteralPath $genBat) { Write-Step 'Generating project files'; Invoke-Bat $genBat | Out-Null }
    Write-Step "Building ${ProjectName}Editor Win64 Development"
    $code = Invoke-Bat (Join-Path $EnginePath 'Engine\Build\BatchFiles\Build.bat') "${ProjectName}Editor Win64 Development -Project=`"$UProjectPath`" -WaitMutex"
    $Status['editor build'] = if ($code -eq 0) { 'ok' } else { "failed (code $code)" }
    if ($code -ne 0) { Add-Warning "Editor build failed (code $code)" }
}

# ---------------------------------------------------------------------------------------------
if ($Package -and -not $CheckOnly) {
    if (-not $isCpp) { Add-Warning 'Packaging skipped: Blueprint-only project' }
    elseif (-not $emsdkOk) { Add-Warning 'Packaging skipped: emscripten SDK is missing' }
    else {
        Write-Step "Packaging for Wasm ($Package) - C++ link and cook take a while"
        $archive = Join-Path $ProjectRoot 'Build\Wasm'
        $runUat = Join-Path $EnginePath 'Engine\Build\BatchFiles\RunUAT.bat'
        $uatArgs = "BuildCookRun -project=`"$UProjectPath`" -platform=Wasm -clientconfig=$Package " +
            "-build -cook -stage -pak -iostore -package -archive -archivedirectory=`"$archive`" -unattended -utf8output " +
            '-AdditionalCookerOptions="-unattended -nopause -nosplash -nullrhi"'
        $code = Invoke-Bat $runUat $uatArgs
        # UAT puts the site (index.html) into the archive folder itself or into its Wasm subfolder depending on the engine version
        $stageDir = @("$archive\Wasm", $archive) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'index.html') } | Select-Object -First 1
        if (-not $stageDir) { $stageDir = $archive }
        $Status['package'] = if ($code -eq 0) { "ok ($stageDir)" } else { "failed (code $code)" }
        if ($code -ne 0) { Add-Warning "Wasm packaging failed (code $code)" }
        elseif ($Package -ne 'Development') {
            $code = Invoke-Exe $EnginePython "-I `"$WasmPlatform\Build\Tools\deploy\check_stage.py`" `"$stageDir`""
            $Status['check_stage'] = if ($code -eq 0) { 'ok' } else { "failed (code $code)" }
            if ($code -ne 0) { Add-Warning 'check_stage.py failed' }
        }
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Summary'
foreach ($k in $Status.Keys) { Write-Host ("  {0,-12} {1}" -f $k, $Status[$k]) }
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
if ([Environment]::GetEnvironmentVariable('WASM_EMSDK_ROOT', 'User') -and -not $CheckOnly) {
    Write-Host 'Restart the editor and open terminals so they pick up WASM_EMSDK_ROOT.'
}
