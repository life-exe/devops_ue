# Copyright LifeEXE. All Rights Reserved.
# Installs and checks web deploy tools: itch.io butler, Vercel CLI, GitHub CLI.
#   install_tools.ps1                      # install missing tools, print status
#   install_tools.ps1 -Tools butler,vercel # only these
#   install_tools.ps1 -CheckOnly
# Never logs in: authentication is interactive (butler login / vercel login / gh auth login).
[CmdletBinding()]
param(
    [ValidateSet('butler', 'vercel', 'gh')][string[]]$Tools = @('butler', 'vercel', 'gh'),
    [string]$ButlerDir = (Join-Path $env:LOCALAPPDATA 'itch-butler'),
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- step timing: every Write-Step starts a timed step, Write-Timing prints the table (also on failure) ---
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
# final header: closes the last step without starting a new timed one
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

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Add-UserPath([string]$Dir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($userPath -split ';' | Where-Object { $_ })
    if ($parts -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User')
        Write-Host "  added to user PATH: $Dir"
    }
    if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
}

function Get-ToolPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return ''
}

# runs a command, returns @(exitCode, outputText) without throwing on stderr
function Invoke-Capture([string]$File, [string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $File @Arguments 2>&1 | Out-String; $code = $LASTEXITCODE }
    catch { $out = $_.Exception.Message; $code = 1 }
    finally { $ErrorActionPreference = $prev }
    return @($code, $out.Trim())
}

$status = New-Object System.Collections.ArrayList
function Add-Status([string]$Tool, [string]$Path, [string]$Version, [string]$Auth, [string]$Login) {
    [void]$status.Add([pscustomobject]@{ Tool = $Tool; Path = $Path; Version = $Version; Auth = $Auth; LoginCommand = $Login })
}

# ---------------------------------------------------------------------------------------------
if ($Tools -contains 'butler') {
    Write-Step 'itch.io butler'
    $butler = Get-ToolPath 'butler'
    if (-not $butler -and (Test-Path -LiteralPath (Join-Path $ButlerDir 'butler.exe'))) { Add-UserPath $ButlerDir; $butler = Join-Path $ButlerDir 'butler.exe' }
    if (-not $butler -and -not $CheckOnly) {
        # official channel: https://itch.io/docs/butler/installing.html
        $url = 'https://broth.itch.zone/butler/windows-amd64/LATEST/archive/default'
        $zip = Join-Path $env:TEMP 'butler-windows-amd64.zip'
        Write-Host "  downloading $url"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        New-Item -ItemType Directory -Force -Path $ButlerDir | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $ButlerDir -Force
        Remove-Item -LiteralPath $zip -Force
        Add-UserPath $ButlerDir
        $butler = Join-Path $ButlerDir 'butler.exe'
    }
    if ($butler) {
        $ver = ([regex]::Match((Invoke-Capture $butler @('-V'))[1], 'v\d+\.\d+\.\d+')).Value
        $creds = Join-Path $env:USERPROFILE '.config\itch\butler_creds'
        $auth = if ($env:BUTLER_API_KEY) { 'BUTLER_API_KEY' } elseif (Test-Path -LiteralPath $creds) { 'logged in' } else { 'not logged in' }
        Add-Status 'butler' $butler $ver $auth 'butler login'
    }
    else { Add-Status 'butler' '' '' 'not installed' '' }
}

# ---------------------------------------------------------------------------------------------
if ($Tools -contains 'vercel') {
    Write-Step 'Vercel CLI'
    $vercel = Get-ToolPath 'vercel'
    if (-not $vercel -and -not $CheckOnly) {
        if (-not (Get-ToolPath 'npm')) {
            if (-not (Get-ToolPath 'winget')) { throw 'Node.js (npm) is required for Vercel CLI and winget is not available: install Node.js LTS from https://nodejs.org' }
            Write-Host '  installing Node.js LTS (winget)'
            winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements
            Update-SessionPath
        }
        Write-Host '  npm install -g vercel'
        $r = Invoke-Capture 'npm' @('install', '-g', 'vercel')
        if ($r[0] -ne 0) { Write-Host $r[1]; throw 'npm install -g vercel failed' }
        Update-SessionPath
        $vercel = Get-ToolPath 'vercel'
    }
    if ($vercel) {
        $ver = ((Invoke-Capture 'vercel' @('--version'))[1] -split "`r?`n" | Where-Object { $_ -match '\d+\.\d+' } | Select-Object -Last 1)
        $who = Invoke-Capture 'vercel' @('whoami')
        $auth = if ($env:VERCEL_TOKEN) { 'VERCEL_TOKEN' } elseif ($who[0] -eq 0) { "logged in ($(($who[1] -split "`r?`n")[-1].Trim()))" } else { 'not logged in' }
        Add-Status 'vercel' $vercel $ver $auth 'vercel login'
    }
    else { Add-Status 'vercel' '' '' 'not installed' '' }
}

# ---------------------------------------------------------------------------------------------
if ($Tools -contains 'gh') {
    Write-Step 'GitHub CLI'
    $gh = Get-ToolPath 'gh'
    if (-not $gh -and (Test-Path 'C:\Program Files\GitHub CLI\gh.exe')) { Add-UserPath 'C:\Program Files\GitHub CLI'; $gh = 'C:\Program Files\GitHub CLI\gh.exe' }
    if (-not $gh -and -not $CheckOnly) {
        if (-not (Get-ToolPath 'winget')) { throw 'winget is not available: install GitHub CLI from https://cli.github.com' }
        Write-Host '  installing GitHub CLI (winget)'
        winget install --id GitHub.cli -e --silent --accept-source-agreements --accept-package-agreements
        Update-SessionPath
        $gh = Get-ToolPath 'gh'
        if (-not $gh -and (Test-Path 'C:\Program Files\GitHub CLI\gh.exe')) { $gh = 'C:\Program Files\GitHub CLI\gh.exe' }
    }
    if ($gh) {
        $ver = ((Invoke-Capture $gh @('--version'))[1] -split "`r?`n" | Select-Object -First 1)
        $authRes = Invoke-Capture $gh @('auth', 'status')
        $auth = if ($env:GH_TOKEN -or $env:GITHUB_TOKEN) { 'GH_TOKEN' } elseif ($authRes[0] -eq 0) { 'logged in' } else { 'not logged in' }
        Add-Status 'gh' $gh $ver $auth 'gh auth login'
    }
    else { Add-Status 'gh' '' '' 'not installed' '' }
}

# ---------------------------------------------------------------------------------------------
Write-FinalStep 'Status'
$status | Format-Table -AutoSize | Out-String -Width 300 | Write-Host
$needLogin = @($status | Where-Object { $_.Auth -eq 'not logged in' })
if ($needLogin.Count -gt 0) {
    Write-Host 'Log in interactively (in Claude Code prefix with "!"):' -ForegroundColor Yellow
    foreach ($s in $needLogin) { Write-Host "  $($s.LoginCommand)" -ForegroundColor Yellow }
}
Write-Host 'New terminals pick up PATH changes; restart open ones.'

Write-Timing
