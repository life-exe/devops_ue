# Copyright LifeEXE. All Rights Reserved.
# Cooks an Unreal project's content with BuildCookRun (-build -cook -skippackage - no stage, no package) and reports errors.
#   cook.ps1 -ProjectPath C:\Game                                  # Game, Win64, Development -> Saved\Cooked\Windows
#   cook.ps1 -ProjectPath C:\Game -Iterative                       # incremental: re-cook only what changed since the last cook
#   cook.ps1 -ProjectPath C:\Game -Maps "/Game/Maps/Main+/Game/Maps/Arena"
#   cook.ps1 -ProjectPath C:\Game -Target Server -Platform Linux   # dedicated server (source-built engine)
#   cook.ps1 -ProjectPath C:\Game -Platform Wasm -Configuration Shipping
#   cook.ps1 -ProjectPath C:\Game -WhatIf                          # print the BuildCookRun line only
# Same BuildCookRun line as devops_ue\cook\cook_game.bat / cook_client.bat / cook_server.bat. Cook errors are the main
# reason a package fails late: this is the quick way to find them. Packaging is ue-package.
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [ValidateSet('Game', 'Client', 'Server')][string]$Target = 'Game',
    [ValidateSet('Win64', 'Linux', 'Wasm')][string]$Platform = 'Win64',
    [ValidateSet('Development', 'Shipping', 'DebugGame', 'Test')][string]$Configuration = 'Development',
    [string]$Maps = '',
    [switch]$Iterative,
    [switch]$SkipBuild,
    [switch]$WhatIf,
    [string]$EnginePath = '',
    [int]$TimeoutMinutes = 180
)

$ErrorActionPreference = 'Stop'
$Warnings = New-Object System.Collections.ArrayList

# --- step timing (same block in every devops_ue skill script) ---
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
function Format-Size([double]$Bytes) { if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) } else { '{0:N1} MB' -f ($Bytes / 1MB) } }
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }

function Read-SharedLines([string]$Path) {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    return @($text -split "`r?`n")
}
# runs a process, streams its output and keeps it in $LogFile; returns the exit code (-1 on timeout)
function Invoke-Logged([string]$FilePath, [string]$Arguments, [string]$LogFile, [int]$TimeoutMin = 0) {
    $dir = Split-Path -Parent $LogFile; if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $errFile = "$LogFile.stderr"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $LogFile -RedirectStandardError $errFile
    $null = $p.Handle
    $pos = 0L; $started = Get-Date
    while ($true) {
        $exited = $p.HasExited
        if (Test-Path -LiteralPath $LogFile) {
            $fs = [IO.File]::Open($LogFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { [void]$fs.Seek($pos, [IO.SeekOrigin]::Begin); $sr = New-Object IO.StreamReader($fs); $chunk = $sr.ReadToEnd(); $pos = $fs.Position } finally { $fs.Dispose() }
            if ($chunk) { Write-Host -NoNewline $chunk }
        }
        if ($exited) { break }
        if ($TimeoutMin -gt 0 -and ((Get-Date) - $started).TotalMinutes -gt $TimeoutMin) {
            Add-Warning "Timeout after $TimeoutMin min: stopping $FilePath"
            try { Stop-Process -Id $p.Id -Force } catch { }
            return -1
        }
        Start-Sleep -Milliseconds 700
    }
    $p.WaitForExit()
    if (Test-Path -LiteralPath $errFile) {
        try {
            $e = (Read-SharedLines $errFile) -join "`r`n"
            if ($e.Trim()) { Write-Host $e; try { Add-Content -LiteralPath $LogFile -Value $e -ErrorAction Stop } catch { } }
        } catch { }
        try { Remove-Item -LiteralPath $errFile -Force -ErrorAction Stop } catch { }
    }
    return $p.ExitCode
}
function Invoke-BatLogged([string]$BatPath, [string]$Arguments, [string]$LogFile, [int]$TimeoutMin = 0) {
    return Invoke-Logged $env:ComSpec "/d /s /c `"`"$BatPath`" $Arguments < nul`"" $LogFile $TimeoutMin
}
function Get-ConfigValue([string]$ConfigBat, [string]$Name) {
    if (-not (Test-Path -LiteralPath $ConfigBat)) { return '' }
    $v = [IO.File]::ReadAllLines($ConfigBat) | Where-Object { $_ -match "^set $([regex]::Escape($Name))=(.*)$" } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1
    return "$v"
}
function Resolve-ProjectEngine([string]$Root, [string]$Assoc, [string]$Explicit) {
    if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path.TrimEnd('\') }
    $e = Get-ConfigValue (Join-Path $Root 'devops_data\config.bat') 'EnginePath'
    if ($e -and (Test-Path -LiteralPath (Join-Path $e 'Engine\Build\Build.version'))) { return $e.TrimEnd('\') }
    $common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
    if (Test-Path -LiteralPath $common) {
        . $common
        $m = Get-UnrealEngines | Where-Object { $_.Association -eq $Assoc -or $_.MajorMinor -eq $Assoc } | Select-Object -First 1
        if ($m) { return $m.Path }
    }
    throw "Engine for EngineAssociation '$Assoc' not found: pass -EnginePath"
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$UProjectPath = $uprojectFile.FullName
$ProjectName = $uprojectFile.BaseName
$assoc = ([regex]::Match((Read-Text $UProjectPath), '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
$isCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot 'Source')
$EnginePath = Resolve-ProjectEngine $ProjectRoot $assoc $EnginePath
$runUat = Join-Path $EnginePath 'Engine\Build\BatchFiles\RunUAT.bat'
if (-not (Test-Path -LiteralPath $runUat)) { throw "RunUAT.bat not found in $EnginePath" }
Write-Host "  $UProjectPath ($(if ($isCpp) { 'C++' } else { 'Blueprint' }))"
Write-Host "  engine: $EnginePath"

if ($Target -ne 'Game') {
    if (Test-Path -LiteralPath (Join-Path $EnginePath 'Engine\Build\InstalledBuild.txt')) {
        throw "-Target $Target needs a source-built engine: $EnginePath is a launcher (installed) build"
    }
    if (-not $isCpp) { throw "-Target $Target needs a C++ project (Source\${ProjectName}$Target.Target.cs)" }
    $targetRules = Join-Path $ProjectRoot "Source\$ProjectName$Target.Target.cs"
    if (-not (Test-Path -LiteralPath $targetRules)) {
        throw "No ${targetRules}: create it with devops_ue\targets\create_${Target}_target.bat (or let ue-package create it)"
    }
}

# ---------------------------------------------------------------------------------------------
$uatPlatform = $Platform   # Wasm / Linux / Win64 are UAT platform names as they are
$uatArgs = "BuildCookRun -project=`"$UProjectPath`" -platform=$uatPlatform -clientconfig=$Configuration -nop4 -utf8output -unattended"
if ($isCpp -and -not $SkipBuild) { $uatArgs += ' -build' }
$uatArgs += ' -cook -skippackage -skipstage'
switch ($Target) {
    'Client' { $uatArgs += " -client -noserver" }
    'Server' { $uatArgs += " -server -noclient -serverplatform=$uatPlatform -serverconfig=$Configuration" }
}
if ($Iterative) { $uatArgs += ' -iterate' }
if ($Maps) { $uatArgs += " -map=$Maps" }

Write-Step "BuildCookRun cook $Target $Platform $Configuration"
Write-Host "  RunUAT $uatArgs"
if ($WhatIf) { Write-FinalStep 'WhatIf: nothing was run'; Write-Timing; exit 0 }

$running = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'UnrealEditor%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match [regex]::Escape($uprojectFile.Name) })
if ($running.Count -gt 0 -and $isCpp -and -not $SkipBuild) { Add-Warning "Unreal Editor has this project open (PID $($running.ProcessId -join ', ')): the C++ build may fail on locked binaries (Live Coding)" }

$logFile = Join-Path $ProjectRoot "Saved\Cook\cook_${Target}_$Platform.log"
$started = Get-Date
$code = Invoke-BatLogged $runUat $uatArgs $logFile $TimeoutMinutes

# ---------------------------------------------------------------------------------------------
Write-Step 'Results'
$lines = if (Test-Path -LiteralPath $logFile) { Read-SharedLines $logFile } else { @() }
$cookErrors = @($lines | Where-Object { $_ -match 'Error:|: error [A-Z]*\d*:|error LNK\d+|ERROR:' -and $_ -notmatch 'Display:.*0 error' -and $_ -notmatch 'Warning/Error Summary' } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
$cookWarnings = @($lines | Where-Object { $_ -match 'LogCook: Warning:|LogCook: Display: Warning:' } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
$summary = $lines | Where-Object { $_ -match 'Cook: .*(Packages|Cook Time|Cooked)' } | Select-Object -Last 3

$cookedRoot = Join-Path $ProjectRoot 'Saved\Cooked'
$cookedDir = Get-ChildItem -LiteralPath $cookedRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($cookedDir) {
    $size = (Get-ChildItem -LiteralPath $cookedDir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $fresh = $cookedDir.LastWriteTime -ge $started.AddMinutes(-1)
    Write-Host "  cooked: $($cookedDir.FullName) ($(Format-Size ([double]$size)))$(if (-not $fresh) { ' - OLD, not written by this run' })"
}
$summary | ForEach-Object { Write-Host "  $($_.Trim())" }
Write-Host "  log: $logFile"
Write-Host "  $($cookErrors.Count) error line(s), $($cookWarnings.Count) cook warning(s)"
$cookErrors | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
$cookWarnings | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }

if ($code -ne 0) {
    Write-FinalStep "Cook FAILED (exit code $code)"
    Write-Timing 'total (FAILED)'
    exit 1
}
Write-FinalStep 'Cook finished'
Write-Timing
