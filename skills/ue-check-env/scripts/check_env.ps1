# Copyright LifeEXE. All Rights Reserved.
# Checks everything the devops_ue skills need on this machine. Read-only: installs nothing.
#   check_env.ps1                        # everything
#   check_env.ps1 -For create            # only what ue-create-project needs (create | web | deploy | all)
#   check_env.ps1 -ProjectDir C:\Game    # also disk space / long paths for that drive
#   check_env.ps1 -Report env_report.md  # also save the report as Markdown
# Exit code 1 when something required for -For is missing.
[CmdletBinding()]
param(
    [ValidateSet('all', 'create', 'web', 'deploy')][string]$For = 'all',
    [string]$ProjectDir = '.',
    [string]$EnginePath = '',
    # Markdown report file (date, machine, scope, the table, the result)
    [string]$Report = ''
)

$ErrorActionPreference = 'Stop'
$ScriptTimer = [Diagnostics.Stopwatch]::StartNew()
$rows = New-Object System.Collections.ArrayList

# Need: 'required' for the listed scopes, otherwise 'optional'
function Add-Row([string]$Tool, [string]$State, [string]$Version, [string[]]$RequiredFor, [string]$UsedFor, [string]$Fix) {
    [void]$rows.Add([pscustomobject]@{ Tool = $Tool; State = $State; Version = $Version; RequiredFor = $RequiredFor; UsedFor = $UsedFor; Fix = $Fix })
}

# runs a command and returns its first output line ('' on failure); never throws on stderr
function Get-FirstLine([string]$File, [string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $File @Arguments 2>&1 | ForEach-Object { "$_" } | Where-Object { $_.Trim() -and $_ -notmatch '^\s*<claude-code-hint' }
        if ($LASTEXITCODE -ne 0) { return '' }
        return "$($out | Select-Object -First 1)".Trim()
    }
    catch { return '' }
    finally { $ErrorActionPreference = $prev }
}
function Get-Exe([string]$Name) { (Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
function Get-Version([string]$Text) { ([regex]::Match($Text, '\d+\.\d+(\.\d+)?')).Value }

# ---------------------------------------------------------------------------------------------
# Unreal Engine
$common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
$engines = @()
if (Test-Path -LiteralPath $common) { . $common; $engines = @(Get-UnrealEngines) }
if ($EnginePath) { $engine = $engines | Where-Object { $_.Path -eq (Resolve-Path -LiteralPath $EnginePath).Path } | Select-Object -First 1 }
else { $engine = $engines | Select-Object -First 1 }
if ($engines.Count -gt 0) {
    $list = ($engines | ForEach-Object { "$($_.Version) $($_.Path)" }) -join '; '
    $state = if ($engine.EditorBuilt) { 'ok' } else { 'warn' }
    Add-Row 'Unreal Engine 5' $state $list @('create', 'web', 'deploy') 'everything' $(if ($engine.EditorBuilt) { '' } else { 'source build: build UnrealEditor first' })
}
else { Add-Row 'Unreal Engine 5' 'missing' '' @('create', 'web', 'deploy') 'everything' 'Epic Games Launcher > Unreal Engine > Library' }

$wasm = $null
if ($engine) {
    $wasm = Join-Path $engine.Path 'Engine\Platforms\Wasm'
    $ver = [version]$engine.MajorMinor
    if ($ver -ge [version]'5.9' -and (Test-Path -LiteralPath $wasm)) { Add-Row 'UE Wasm platform' 'ok' $engine.Version @('web', 'deploy') 'web build' '' }
    else { Add-Row 'UE Wasm platform' 'missing' $engine.Version @('web', 'deploy') 'web build' 'UE 5.9+ with web libraries (Launcher: Options > Wasm)' ; $wasm = $null }
}

# Visual Studio C++ toolset (C++ projects, Wasm needs a C++ module)
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = ''
if (Test-Path -LiteralPath $vswhere) {
    $vs = Get-FirstLine $vswhere @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'displayName')
}
if ($vs) { Add-Row 'Visual Studio C++' 'ok' $vs @('web') 'C++ projects, Wasm' '' }
else { Add-Row 'Visual Studio C++' 'missing' '' @('web') 'C++ projects, Wasm' 'Visual Studio Installer: workload "Game development with C++"' }

# ---------------------------------------------------------------------------------------------
# Git and friends
$git = Get-Exe 'git'
if ($git) { Add-Row 'Git' 'ok' (Get-Version (Get-FirstLine $git @('--version'))) @('create', 'web', 'deploy') 'repo, submodule' '' }
else { Add-Row 'Git' 'missing' '' @('create', 'web', 'deploy') 'repo, submodule' 'winget install --id Git.Git -e' }

$lfs = if ($git) { Get-FirstLine $git @('lfs', 'version') } else { '' }
if ($lfs) { Add-Row 'Git LFS' 'ok' (Get-Version $lfs) @() 'large assets (finalize_git.ps1 -UseLfs)' '' }
else { Add-Row 'Git LFS' 'missing' '' @() 'large assets (finalize_git.ps1 -UseLfs)' 'winget install --id GitHub.GitLFS -e' }

if ($git) {
    $gitUser = Get-FirstLine $git @('config', '--global', 'user.name')
    if ($gitUser) { Add-Row 'Git user' 'ok' $gitUser @() 'commits' '' }
    else { Add-Row 'Git user' 'missing' '' @() 'commits' 'git config --global user.name "Name"; git config --global user.email "you@example.com"' }
}

$clang = Get-Exe 'clang-format'
if ($clang) { Add-Row 'clang-format' 'ok' (Get-Version (Get-FirstLine $clang @('--version'))) @() 'format_all_files.bat' '' }
else { Add-Row 'clang-format' 'missing' '' @() 'format_all_files.bat' 'winget install --id LLVM.LLVM -e  (or pip install clang-format)' }

# Python: the engine has its own; a system Python is only a fallback for scripts/launchers
$py = Get-Exe 'python'; if (-not $py) { $py = Get-Exe 'py' }
$pyVer = if ($py) { Get-Version (Get-FirstLine $py @('--version')) } else { '' }
if ($pyVer) { Add-Row 'Python 3 (system)' 'ok' $pyVer @() 'Play_<Game>.bat launcher on other PCs' '' }
else { Add-Row 'Python 3 (system)' 'missing' '' @() 'Play_<Game>.bat launcher on other PCs' 'winget install --id Python.Python.3.12 -e' }

if ($engine) {
    $enginePy = Join-Path $engine.Path 'Engine\Binaries\ThirdParty\Python3\Win64\python.exe'
    if (Test-Path -LiteralPath $enginePy) {
        Add-Row 'Engine Python' 'ok' (Get-Version (Get-FirstLine $enginePy @('--version'))) @('web', 'deploy') 'Wasm tools, make_zip.py' ''
        $pw = Get-FirstLine $enginePy @('-I', '-c', 'import playwright, importlib.metadata as m; print(m.version(\"playwright\"))')
        if ($pw) { Add-Row 'Playwright (engine Python)' 'ok' $pw @() 'browser load test (webrun.py)' '' }
        else { Add-Row 'Playwright (engine Python)' 'missing' '' @() 'browser load test (webrun.py)' 'ue-web-setup -InstallPlaywright' }
    }
    else { Add-Row 'Engine Python' 'missing' '' @('web', 'deploy') 'Wasm tools' 'reinstall/verify the engine' }
}

# emscripten
if ($wasm) {
    $need = ([IO.File]::ReadAllText((Join-Path $wasm 'Config\Wasm_SDK.json')) | ConvertFrom-Json).MainVersion
    $root = $env:WASM_EMSDK_ROOT; if (-not $root) { $root = [Environment]::GetEnvironmentVariable('WASM_EMSDK_ROOT', 'User') }
    if (-not $root) { $root = $env:EMSDK }
    if (-not $root -and (Test-Path 'C:\emsdk')) { $root = 'C:\emsdk' }
    $have = ''
    if ($root) { $vf = Join-Path $root 'upstream\emscripten\emscripten-version.txt'; if (Test-Path -LiteralPath $vf) { $have = ([IO.File]::ReadAllText($vf)).Trim().Trim('"') } }
    if ($have -eq $need) { Add-Row 'emscripten (emsdk)' 'ok' "$have ($root)" @('web') 'Wasm build' '' }
    elseif ($have) { Add-Row 'emscripten (emsdk)' 'warn' "$have, need $need ($root)" @('web') 'Wasm build' "emsdk install $need; emsdk activate $need (or ue-web-setup)" }
    else { Add-Row 'emscripten (emsdk)' 'missing' "need $need" @('web') 'Wasm build' 'ue-web-setup (installs to C:\emsdk) or devops_ue\setup\setup_emsdk.bat' }
}

# ---------------------------------------------------------------------------------------------
# deploy tools
$winget = Get-Exe 'winget'
if ($winget) { Add-Row 'winget' 'ok' (Get-Version (Get-FirstLine $winget @('--version'))) @() 'installing tools' '' }
else { Add-Row 'winget' 'missing' '' @() 'installing tools' 'Microsoft Store: App Installer' }

$node = Get-Exe 'node'
if ($node) { Add-Row 'Node.js' 'ok' (Get-Version (Get-FirstLine $node @('--version'))) @() 'Vercel CLI' '' }
else { Add-Row 'Node.js' 'missing' '' @() 'Vercel CLI' 'winget install --id OpenJS.NodeJS.LTS -e' }
$npm = Get-Exe 'npm'
if ($npm) { Add-Row 'npm' 'ok' (Get-Version (Get-FirstLine $npm @('--version'))) @() 'Vercel CLI' '' }
else { Add-Row 'npm' 'missing' '' @() 'Vercel CLI' 'comes with Node.js' }

$vercel = Get-Exe 'vercel'
if ($vercel) {
    # whoami prints a "Vercel CLI x.y.z" banner first, the user name is the last line
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $whoLines = @(& vercel whoami 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^(Vercel CLI|<claude-code-hint|>)' })
    $who = if ($LASTEXITCODE -eq 0 -and $whoLines.Count) { $whoLines[-1] } else { '' }
    $ErrorActionPreference = $prev
    Add-Row 'Vercel CLI' $(if ($who -or $env:VERCEL_TOKEN) { 'ok' } else { 'warn' }) "$(Get-Version (Get-FirstLine 'vercel' @('--version')))$(if ($who) { ", $who" } else { ', not logged in' })" @() 'deploy to Vercel' $(if ($who) { '' } else { 'vercel login' })
}
else { Add-Row 'Vercel CLI' 'missing' '' @() 'deploy to Vercel' 'ue-web-deploy install_tools.ps1 -Tools vercel' }

$gh = Get-Exe 'gh'; if (-not $gh -and (Test-Path 'C:\Program Files\GitHub CLI\gh.exe')) { $gh = 'C:\Program Files\GitHub CLI\gh.exe' }
if ($gh) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $gh auth status *> $null; $ghAuth = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $prev
    Add-Row 'GitHub CLI' $(if ($ghAuth) { 'ok' } else { 'warn' }) "$(Get-Version (Get-FirstLine $gh @('--version')))$(if ($ghAuth) { ', logged in' } else { ', not logged in' })" @() 'GitHub releases, repos' $(if ($ghAuth) { '' } else { 'gh auth login' })
}
else { Add-Row 'GitHub CLI' 'missing' '' @() 'GitHub releases, repos' 'ue-web-deploy install_tools.ps1 -Tools gh' }

$butler = Get-Exe 'butler'; if (-not $butler) { $b = Join-Path $env:LOCALAPPDATA 'itch-butler\butler.exe'; if (Test-Path -LiteralPath $b) { $butler = $b } }
if ($butler) {
    $creds = Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.config\itch\butler_creds')
    # butler prints its version to stderr
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $bv = ([regex]::Match((& $butler -V 2>&1 | ForEach-Object { "$_" } | Out-String), 'v\d+\.\d+\.\d+')).Value
    $ErrorActionPreference = $prev
    Add-Row 'butler (itch.io)' $(if ($creds -or $env:BUTLER_API_KEY) { 'ok' } else { 'warn' }) "$bv$(if ($creds) { ', logged in' } else { ', not logged in' })" @() 'deploy to itch.io' $(if ($creds) { '' } else { 'butler login' })
}
else { Add-Row 'butler (itch.io)' 'missing' '' @() 'deploy to itch.io' 'ue-web-deploy install_tools.ps1 -Tools butler' }

# ---------------------------------------------------------------------------------------------
# machine
$longPaths = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction SilentlyContinue).LongPathsEnabled
if ($longPaths -eq 1) { Add-Row 'Windows long paths' 'ok' 'enabled' @() 'deep UE/Chrome paths' '' }
else { Add-Row 'Windows long paths' 'warn' 'disabled' @() 'deep UE/Chrome paths' 'admin PowerShell: Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem LongPathsEnabled 1; keep project paths short anyway' }

$drive = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $ProjectDir).Path)
$free = (New-Object IO.DriveInfo $drive).AvailableFreeSpace
$freeGb = [math]::Round($free / 1GB, 1)
# a C++ project + Wasm build + DDC easily takes 30-50 GB
Add-Row "Free space $drive" $(if ($freeGb -ge 50) { 'ok' } elseif ($freeGb -ge 20) { 'warn' } else { 'missing' }) "$freeGb GB" @('create', 'web') 'project, builds, DDC (50 GB+ recommended)' $(if ($freeGb -ge 50) { '' } else { 'free disk space' })

# ---------------------------------------------------------------------------------------------
$scopes = if ($For -eq 'all') { @('create', 'web', 'deploy') } else { @($For) }
$table = foreach ($r in $rows) {
    $required = @($r.RequiredFor | Where-Object { $scopes -contains $_ }).Count -gt 0
    [pscustomobject]@{
        ' '       = switch ($r.State) { 'ok' { '[ok]' } 'warn' { '[!!]' } default { if ($required) { '[XX]' } else { '[--]' } } }
        Tool      = $r.Tool
        Version   = $r.Version
        Need      = $(if ($required) { 'required' } else { 'optional' })
        'Used for' = $r.UsedFor
        Fix       = $r.Fix
    }
}
$table | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host

$missingRequired = @($rows | Where-Object { $_.State -eq 'missing' -and @($_.RequiredFor | Where-Object { $scopes -contains $_ }).Count -gt 0 })

if ($Report) {
    $esc = { param($s) "$s".Replace('|', '\|') }
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# Environment check (devops_ue)')
    [void]$md.AppendLine()
    [void]$md.AppendLine("- Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    [void]$md.AppendLine("- Machine: $env:COMPUTERNAME, $((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption)")
    [void]$md.AppendLine("- Checked for: $($scopes -join ', ')")
    [void]$md.AppendLine("- Result: $(if ($missingRequired.Count) { 'MISSING (required): ' + (($missingRequired | ForEach-Object { $_.Tool }) -join ', ') } else { 'everything required is in place' })")
    [void]$md.AppendLine()
    [void]$md.AppendLine('| | Tool | Version | Need | Used for | Fix |')
    [void]$md.AppendLine('|---|---|---|---|---|---|')
    foreach ($t in $table) {
        [void]$md.AppendLine("| $($t.' ') | $(& $esc $t.Tool) | $(& $esc $t.Version) | $($t.Need) | $(& $esc $t.'Used for') | $(if ($t.Fix) { '`' + (& $esc $t.Fix) + '`' }) |")
    }
    [void]$md.AppendLine()
    [void]$md.AppendLine('Legend: `[ok]` ok, `[!!]` works but needs attention, `[XX]` required and missing, `[--]` optional and missing.')
    $reportPath = if ([IO.Path]::IsPathRooted($Report)) { $Report } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Report)) }
    $reportDir = Split-Path -Parent $reportPath
    if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) { New-Item -ItemType Directory -Force -Path $reportDir | Out-Null }
    [IO.File]::WriteAllText($reportPath, $md.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Report saved: $reportPath"
}
Write-Host "Legend: [ok] ok  [!!] works but needs attention  [XX] required and missing  [--] optional and missing"
Write-Host ("Checked in {0:N1}s for: {1}" -f $ScriptTimer.Elapsed.TotalSeconds, ($scopes -join ', '))
if ($missingRequired.Count -gt 0) {
    Write-Host "MISSING (required): $(($missingRequired | ForEach-Object { $_.Tool }) -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'Everything required is in place.' -ForegroundColor Green
exit 0
