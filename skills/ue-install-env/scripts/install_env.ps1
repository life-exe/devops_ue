# Copyright LifeEXE. All Rights Reserved.
# Installs the tools the devops_ue skills need (what ue-check-env reports as missing).
#   install_env.ps1 -WhatIf                         # plan only: what is missing and how it would be installed
#   install_env.ps1                                 # install everything installable that is missing
#   install_env.ps1 -Tools node,vercel,gh           # only these (installed ones are skipped)
#   install_env.ps1 -Tools gituser -GitUserName "Name" -GitUserEmail "me@example.com"
# Not installed automatically (printed as manual steps): Unreal Engine, Visual Studio C++, Windows long paths (admin).
[CmdletBinding()]
param(
    # git, gitlfs, gituser, gh, node, vercel, butler, python, clangformat, doxygen, opencppcoverage, emsdk, playwright
    # (comma-separated works with powershell -File too, where "-Tools a,b" arrives as one string)
    [string[]]$Tools = @(),
    [switch]$WhatIf,
    [string]$EnginePath = '',
    [string]$EmsdkDir = 'C:\emsdk',
    [string]$GitUserName = '',
    [string]$GitUserEmail = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Warnings = New-Object System.Collections.ArrayList

# --- step timing (same as the other skill scripts) ---
$ScriptTimer = [Diagnostics.Stopwatch]::StartNew()
$StepTimes = New-Object System.Collections.ArrayList
$script:CurrentStep = $null
function Complete-Step {
    if ($script:CurrentStep) {
        [void]$StepTimes.Add([pscustomobject]@{ Step = $script:CurrentStep.Name; Time = $ScriptTimer.Elapsed - $script:CurrentStep.Start })
        $script:CurrentStep = $null
    }
}
function Write-Step([string]$Text) {
    Complete-Step
    $script:CurrentStep = [pscustomobject]@{ Name = $Text; Start = $ScriptTimer.Elapsed }
    Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan
}
function Write-FinalStep([string]$Text) { Complete-Step; Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Format-Duration([TimeSpan]$T) {
    if ($T.TotalHours -ge 1) { return '{0}h {1:D2}m {2:D2}s' -f [int][math]::Floor($T.TotalHours), $T.Minutes, $T.Seconds }
    if ($T.TotalMinutes -ge 1) { return '{0}m {1:D2}s' -f $T.Minutes, $T.Seconds }
    return '{0:N1}s' -f $T.TotalSeconds
}
function Write-Timing([string]$Result = 'total') {
    Complete-Step
    Write-Host ''; Write-Host 'Time:' -ForegroundColor Cyan
    foreach ($s in $StepTimes) { Write-Host ('  {0,-10} {1}' -f (Format-Duration $s.Time), $s.Step) }
    Write-Host ('  {0,-10} {1}' -f (Format-Duration $ScriptTimer.Elapsed), $Result) -ForegroundColor Green
}
trap { Write-Timing 'total (FAILED)'; break }
function Add-Warning([string]$Text) { [void]$Warnings.Add($Text); Write-Host "WARNING: $Text" -ForegroundColor Yellow }

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $lfsDir = 'C:\Program Files\Git LFS'; if ((Test-Path $lfsDir) -and ($env:Path -split ';') -notcontains $lfsDir) { $env:Path += ";$lfsDir" }
}
function Add-UserPath([string]$Dir) {
    $parts = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })
    if ($parts -notcontains $Dir) { [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User') }
    if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
}
function Get-Exe([string]$Name) { (Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
# exit code of a native command, stderr never turns into a PowerShell error
function Test-Run([string]$File, [string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $File @Arguments *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false } finally { $ErrorActionPreference = $prev }
}
function Invoke-Native([string]$File, [string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $File @Arguments 2>&1 | ForEach-Object { "  $_" } | Out-Host; return $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
}
function Install-Winget([string]$Id) {
    if (-not (Get-Exe 'winget')) { throw "winget is not available (Microsoft Store: App Installer); install $Id by hand" }
    Write-Host "  winget install --id $Id -e (a UAC prompt may appear)"
    $code = Invoke-Native 'winget' @('install', '--id', $Id, '-e', '--silent', '--accept-source-agreements', '--accept-package-agreements')
    Update-SessionPath
    # -1978335189 = already installed / no applicable upgrade
    if ($code -ne 0 -and $code -ne -1978335189) { throw "winget install $Id failed (code $code)" }
}

# ---------------------------------------------------------------------------------------------
# engine (for emsdk version and its Python)
$common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
$engine = $null
if (Test-Path -LiteralPath $common) {
    . $common
    $engines = @(Get-UnrealEngines)
    $engine = if ($EnginePath) { $engines | Where-Object { $_.Path -eq (Resolve-Path -LiteralPath $EnginePath).Path } | Select-Object -First 1 } else { $engines | Select-Object -First 1 }
}
$enginePy = if ($engine) { Join-Path $engine.Path 'Engine\Binaries\ThirdParty\Python3\Win64\python.exe' } else { '' }
$wasmDir = if ($engine) { Join-Path $engine.Path 'Engine\Platforms\Wasm' } else { '' }
$emsdkVersion = if ($wasmDir -and (Test-Path -LiteralPath (Join-Path $wasmDir 'Config\Wasm_SDK.json'))) {
    ([IO.File]::ReadAllText((Join-Path $wasmDir 'Config\Wasm_SDK.json')) | ConvertFrom-Json).MainVersion
} else { '' }
function Get-EmsdkRoot {
    foreach ($r in @($env:WASM_EMSDK_ROOT, [Environment]::GetEnvironmentVariable('WASM_EMSDK_ROOT', 'User'), $env:EMSDK, $EmsdkDir)) {
        if ($r -and (Test-Path -LiteralPath (Join-Path $r 'upstream\emscripten\emscripten-version.txt'))) { return $r }
    }
    return ''
}
function Get-EmsdkInstalledVersion { $r = Get-EmsdkRoot; if ($r) { ([IO.File]::ReadAllText((Join-Path $r 'upstream\emscripten\emscripten-version.txt'))).Trim().Trim('"') } else { '' } }

# ---------------------------------------------------------------------------------------------
# tool table: order matters (node before vercel, git before git lfs / emsdk, python before clang-format via pip)
$catalog = [ordered]@{
    git         = @{ Name = 'Git'; Test = { [bool](Get-Exe 'git') }; How = 'winget Git.Git'
                     Install = { Install-Winget 'Git.Git' } }
    gitlfs      = @{ Name = 'Git LFS'; Test = { (Get-Exe 'git') -and (Test-Run 'git' @('lfs', 'version')) }; How = 'winget GitHub.GitLFS'
                     Install = { Install-Winget 'GitHub.GitLFS' } }
    gituser     = @{ Name = 'Git user (name/email)'; Test = { (Get-Exe 'git') -and (Test-Run 'git' @('config', '--global', 'user.name')) -and (Test-Run 'git' @('config', '--global', 'user.email')) }
                     How = 'git config --global user.name/user.email (-GitUserName/-GitUserEmail)'
                     Install = {
                         if (-not $GitUserName -or -not $GitUserEmail) { throw 'pass -GitUserName and -GitUserEmail' }
                         Invoke-Native 'git' @('config', '--global', 'user.name', $GitUserName) | Out-Null
                         Invoke-Native 'git' @('config', '--global', 'user.email', $GitUserEmail) | Out-Null
                     } }
    gh          = @{ Name = 'GitHub CLI'; Test = { [bool](Get-Exe 'gh') -or (Test-Path 'C:\Program Files\GitHub CLI\gh.exe') }; How = 'winget GitHub.cli'
                     Install = { Install-Winget 'GitHub.cli' } }
    node        = @{ Name = 'Node.js LTS + npm'; Test = { [bool](Get-Exe 'node') -and [bool](Get-Exe 'npm') }; How = 'winget OpenJS.NodeJS.LTS'
                     Install = { Install-Winget 'OpenJS.NodeJS.LTS' } }
    vercel      = @{ Name = 'Vercel CLI'; Test = { [bool](Get-Exe 'vercel') }; How = 'npm install -g vercel'
                     Install = {
                         if (-not (Get-Exe 'npm')) { throw 'npm is missing: install node first' }
                         $code = Invoke-Native 'npm' @('install', '-g', 'vercel'); Update-SessionPath
                         if ($code -ne 0) { throw "npm install -g vercel failed (code $code)" }
                     } }
    butler      = @{ Name = 'butler (itch.io)'; Test = { [bool](Get-Exe 'butler') -or (Test-Path (Join-Path $env:LOCALAPPDATA 'itch-butler\butler.exe')) }
                     How = 'download from broth.itch.zone to %LOCALAPPDATA%\itch-butler + user PATH'
                     Install = {
                         $dir = Join-Path $env:LOCALAPPDATA 'itch-butler'
                         $zip = Join-Path $env:TEMP 'butler-windows-amd64.zip'
                         [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                         Invoke-WebRequest -Uri 'https://broth.itch.zone/butler/windows-amd64/LATEST/archive/default' -OutFile $zip -UseBasicParsing
                         New-Item -ItemType Directory -Force -Path $dir | Out-Null
                         Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
                         Remove-Item -LiteralPath $zip -Force
                         Add-UserPath $dir
                     } }
    python      = @{ Name = 'Python 3 (system)'; Test = { [bool](Get-Exe 'python') -and (Test-Run 'python' @('--version')) }; How = 'winget Python.Python.3.12'
                     Install = { Install-Winget 'Python.Python.3.12' } }
    clangformat = @{ Name = 'clang-format'; Test = { [bool](Get-Exe 'clang-format') }; How = 'pip install --user clang-format (or winget LLVM.LLVM without Python)'
                     Install = {
                         if ((Get-Exe 'python') -and (Test-Run 'python' @('--version'))) {
                             $code = Invoke-Native 'python' @('-m', 'pip', 'install', '--user', 'clang-format')
                             if ($code -ne 0) { throw "pip install clang-format failed (code $code)" }
                             $scripts = (& python -c 'import sysconfig,os;print(sysconfig.get_path("scripts", os.name + "_user"))' 2>$null)
                             if ($scripts -and (Test-Path $scripts)) { Add-UserPath $scripts }
                             Update-SessionPath
                         }
                         else { Install-Winget 'LLVM.LLVM' }
                     } }
    doxygen     = @{ Name = 'Doxygen (ue-docs)'; Test = { [bool](Get-Exe 'doxygen') -or (Test-Path 'C:\Program Files\doxygen\bin\doxygen.exe') }; How = 'winget DimitriVanHeesch.Doxygen'
                     Install = { Install-Winget 'DimitriVanHeesch.Doxygen'; if (Test-Path 'C:\Program Files\doxygen\bin') { Add-UserPath 'C:\Program Files\doxygen\bin' } } }
    opencppcoverage = @{ Name = 'OpenCppCoverage (test coverage)'; Test = { Test-Path 'C:\Program Files\OpenCppCoverage\OpenCppCoverage.exe' }; How = 'winget OpenCppCoverage.OpenCppCoverage'
                     Install = { Install-Winget 'OpenCppCoverage.OpenCppCoverage' } }
    emsdk       = @{ Name = "emscripten $emsdkVersion (emsdk)"; Test = { -not $emsdkVersion -or (Get-EmsdkInstalledVersion) -eq $emsdkVersion }
                     How = "git clone emsdk to $EmsdkDir, emsdk install/activate $emsdkVersion, WASM_EMSDK_ROOT (~1 GB)"
                     Install = {
                         if (-not (Get-Exe 'git')) { throw 'git is missing: install git first' }
                         if (-not (Test-Path -LiteralPath (Join-Path $EmsdkDir 'emsdk.bat'))) {
                             $code = Invoke-Native 'git' @('clone', 'https://github.com/emscripten-core/emsdk.git', $EmsdkDir)
                             if ($code -ne 0) { throw 'git clone emsdk failed' }
                         }
                         $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /s /c `"cd /d `"$EmsdkDir`" && emsdk.bat install $emsdkVersion && emsdk.bat activate $emsdkVersion < nul`"" -NoNewWindow -Wait -PassThru
                         if ($p.ExitCode -ne 0) { throw "emsdk install $emsdkVersion failed (code $($p.ExitCode))" }
                         [Environment]::SetEnvironmentVariable('WASM_EMSDK_ROOT', $EmsdkDir, 'User'); $env:WASM_EMSDK_ROOT = $EmsdkDir
                     } }
    playwright  = @{ Name = 'Playwright (engine Python)'; Test = { -not $enginePy -or -not (Test-Path -LiteralPath $enginePy) -or (Test-Run $enginePy @('-I', '-c', 'import playwright')) }
                     How = 'engine Python: pip install -r Engine\Platforms\Wasm\Build\Tools\web\requirements.txt'
                     Install = {
                         $req = Join-Path $wasmDir 'Build\Tools\web\requirements.txt'
                         $code = Invoke-Native $enginePy @('-m', 'pip', 'install', '-r', $req)
                         if ($code -ne 0) { throw "pip install failed (code $code): the engine is under Program Files - run from an elevated terminal: `"$enginePy`" -m pip install -r `"$req`"" }
                     } }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Plan'
$Tools = @($Tools | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
$unknown = @($Tools | Where-Object { -not $catalog.Contains($_) })
if ($unknown) { throw "Unknown tool(s): $($unknown -join ', '). Known: $(@($catalog.Keys) -join ', ')" }
$selected = if ($Tools.Count) { $Tools } else { @($catalog.Keys) }
$plan = New-Object System.Collections.ArrayList
foreach ($key in $catalog.Keys) {
    if ($selected -notcontains $key) { continue }
    $t = $catalog[$key]
    $installed = & $t.Test
    if ($installed) { Write-Host ("  [ok]   {0}" -f $t.Name) }
    elseif ($key -eq 'gituser' -and -not ($GitUserName -and $GitUserEmail)) { Write-Host ("  [ask]  {0}: needs -GitUserName and -GitUserEmail" -f $t.Name); Add-Warning 'Git user is not set: ask the user for name and email' }
    elseif ($key -eq 'emsdk' -and -not $emsdkVersion) { Write-Host '  [skip] emscripten: no UE 5.9+ with the Wasm platform found' }
    elseif ($key -eq 'playwright' -and -not $enginePy) { Write-Host '  [skip] Playwright: no engine found' }
    else { Write-Host ("  [todo] {0}: {1}" -f $t.Name, $t.How) -ForegroundColor Yellow; [void]$plan.Add($key) }
}

# manual items (never automated)
$manual = @()
if (-not $engine) { $manual += 'Unreal Engine 5: Epic Games Launcher > Unreal Engine > Library (launcher: winget install --id EpicGames.EpicGamesLauncher -e)' }
elseif ([version]$engine.MajorMinor -ge [version]'5.9' -and -not (Test-Path -LiteralPath $wasmDir)) { $manual += "UE Wasm platform: Launcher > $($engine.MajorMinor) > Options > Wasm" }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$hasVc = (Test-Path -LiteralPath $vswhere) -and (Test-Run $vswhere @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')) -and
    ((& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null) -ne $null)
if (-not $hasVc) { $manual += 'Visual Studio C++: Visual Studio Installer > workload "Game development with C++" (see the UE docs for the version that matches your engine)' }
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction SilentlyContinue).LongPathsEnabled -ne 1) {
    $manual += 'Windows long paths (optional): elevated PowerShell: Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem LongPathsEnabled 1'
}
if ($manual) { Write-Host ''; Write-Host 'Manual (not installed by this script):' -ForegroundColor Yellow; foreach ($m in $manual) { Write-Host "  - $m" -ForegroundColor Yellow } }

if ($WhatIf) {
    Write-FinalStep $(if ($plan.Count) { "Plan only: $($plan.Count) to install ($($plan -join ', '))" } else { 'Plan only: nothing to install' })
    Write-Timing
    exit 0
}

# ---------------------------------------------------------------------------------------------
$failed = @()
foreach ($key in $plan) {
    $t = $catalog[$key]
    Write-Step "Install $($t.Name)"
    try {
        & $t.Install
        if (& $t.Test) { Write-Host '  installed' -ForegroundColor Green }
        else { Add-Warning "$($t.Name): installed, but not found yet - open a new terminal (PATH) and re-check"; }
    }
    catch { $failed += $t.Name; Add-Warning "$($t.Name): $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------------------------
Write-FinalStep 'Re-check (ue-check-env)'
$check = Join-Path $PSScriptRoot '..\..\ue-check-env\scripts\check_env.ps1'
if (Test-Path -LiteralPath $check) { & powershell -NoProfile -ExecutionPolicy Bypass -File $check | Out-Host }
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Host 'Open a new terminal / restart Claude Code and the editor so they see the new PATH and WASM_EMSDK_ROOT.'
Write-Timing $(if ($failed) { "total ($($failed.Count) failed: $($failed -join ', '))" } else { 'total' })
if ($failed) { exit 1 }
