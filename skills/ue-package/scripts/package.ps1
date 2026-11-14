# Copyright LifeEXE. All Rights Reserved.
# Packages an Unreal project with BuildCookRun and reports the result (folder, size, executables, errors).
#   package.ps1 -ProjectPath C:\Game                                   # Game, Win64, Development -> Build\Windows
#   package.ps1 -ProjectPath C:\Game -Configuration Shipping
#   package.ps1 -ProjectPath C:\Game -Target Server                    # dedicated server (source-built engine)
#   package.ps1 -ProjectPath C:\Game -Target ClientServer -Platform Linux
#   package.ps1 -ProjectPath C:\Game -Maps "/Game/Maps/Main+/Game/Maps/Arena"
# The web (Wasm) build is done by ue-web-setup / package_wasm.bat.
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [ValidateSet('Game', 'Client', 'Server', 'ClientServer')][string]$Target = 'Game',
    [ValidateSet('Win64', 'Linux')][string]$Platform = 'Win64',
    [ValidateSet('Development', 'Shipping', 'DebugGame', 'Test')][string]$Configuration = 'Development',
    [string]$OutDir = '',
    [string]$Maps = '',
    [switch]$Clean,
    [switch]$WhatIf,
    [string]$EnginePath = ''
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
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

# reads a file another process may still hold open for writing
function Read-SharedLines([string]$Path) {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    return @($text -split "`r?`n")
}

function Invoke-Logged([string]$FilePath, [string]$Arguments, [string]$LogFile) {
    $dir = Split-Path -Parent $LogFile; if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $errFile = "$LogFile.stderr"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $LogFile -RedirectStandardError $errFile
    $null = $p.Handle
    $pos = 0L
    while ($true) {
        $exited = $p.HasExited
        if (Test-Path -LiteralPath $LogFile) {
            $fs = [IO.File]::Open($LogFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { [void]$fs.Seek($pos, [IO.SeekOrigin]::Begin); $sr = New-Object IO.StreamReader($fs); $chunk = $sr.ReadToEnd(); $pos = $fs.Position } finally { $fs.Dispose() }
            if ($chunk) { Write-Host -NoNewline $chunk }
        }
        if ($exited) { break }
        Start-Sleep -Milliseconds 700
    }
    $p.WaitForExit()
    if (Test-Path -LiteralPath $errFile) {
        # processes the tool starts (UnrealZenServer, ShaderCompileWorker) inherit the redirected handles and may keep them open
        try {
            $e = (Read-SharedLines $errFile) -join "`r`n"
            if ($e.Trim()) { Write-Host $e; try { Add-Content -LiteralPath $LogFile -Value $e -ErrorAction Stop } catch { } }
        } catch { }
        try { Remove-Item -LiteralPath $errFile -Force -ErrorAction Stop } catch { }
    }
    return $p.ExitCode
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
Write-Step 'Project, engine and checks'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$UProjectPath = $uprojectFile.FullName
$ProjectName = $uprojectFile.BaseName
$assoc = ([regex]::Match((Read-Text $UProjectPath), '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
$EnginePath = Resolve-ProjectEngine $ProjectRoot $assoc $EnginePath
$isCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot 'Source')
$installedEngine = Test-Path -LiteralPath (Join-Path $EnginePath 'Engine\Build\InstalledBuild.txt')
if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot 'Build' }
Write-Host "  project: $UProjectPath ($(if ($isCpp) { 'C++' } else { 'Blueprint' }))"
Write-Host "  engine : $EnginePath ($(if ($installedEngine) { 'installed/Launcher' } else { 'source build' }))"
Write-Host "  package: $Target, $Platform, $Configuration -> $OutDir"

if ($Target -ne 'Game') {
    if ($installedEngine) { throw "$Target targets need an engine built from source: the installed (Launcher) engine ships no client/server binaries. Package -Target Game, or use a source build (-EnginePath)." }
    if (-not $isCpp) { throw "$Target targets need a C++ project (Source\<Name>.Target.cs). Add a C++ class/module first." }
}
if ($Platform -eq 'Linux' -and -not $env:LINUX_MULTIARCH_ROOT) {
    throw 'Linux packaging needs the cross-compile toolchain: install the clang toolchain version listed for this engine in the UE docs ("Linux Development Requirements") and set LINUX_MULTIARCH_ROOT, then restart the terminal.'
}

# client / server target rules from the game target (devops_ue\targets does the same with a template)
$createdTargets = @()
if ($Target -ne 'Game') {
    $gameTarget = Join-Path $ProjectRoot "Source\$ProjectName.Target.cs"
    if (-not (Test-Path -LiteralPath $gameTarget)) { throw "Source\$ProjectName.Target.cs not found" }
    $types = switch ($Target) { 'Client' { @('Client') } 'Server' { @('Server') } 'ClientServer' { @('Client', 'Server') } }
    foreach ($type in $types) {
        $file = Join-Path $ProjectRoot "Source\$ProjectName$type.Target.cs"
        if (Test-Path -LiteralPath $file) { continue }
        $text = (Read-Text $gameTarget).Replace("${ProjectName}Target", "$ProjectName${type}Target") -replace 'TargetType\.Game', "TargetType.$type"
        if (-not $WhatIf) { [IO.File]::WriteAllText($file, $text, $Utf8NoBom) }
        $createdTargets += "Source\$ProjectName$type.Target.cs"
    }
    if ($createdTargets) { Write-Host "  created target rules: $($createdTargets -join ', ')" }
}

$configs = switch ($Target) {
    'Game' { "-clientconfig=$Configuration" }
    'Client' { "-clientconfig=$Configuration -client" }
    'Server' { "-serverconfig=$Configuration -server -noclient" }
    'ClientServer' { "-clientconfig=$Configuration -serverconfig=$Configuration -client -server" }
}
$mapArg = if ($Maps) { "-map=`"$Maps`"" } else { '' }
$cleanArg = if ($Clean) { '-clean' } else { '' }
$uatArgs = "BuildCookRun -project=`"$UProjectPath`" -platform=$Platform $configs -build -cook -stage -package -pak -archive " +
    "-archivedirectory=`"$OutDir`" $mapArg $cleanArg -unattended -utf8output -nop4"
$runUat = Join-Path $EnginePath 'Engine\Build\BatchFiles\RunUAT.bat'
Write-Host "  > RunUAT $uatArgs"

if ($WhatIf) { Write-FinalStep 'Plan only (nothing built)'; Write-Timing; exit 0 }

# ---------------------------------------------------------------------------------------------
Write-Step "BuildCookRun ($Target $Platform $Configuration)"
$started = Get-Date
$logFile = Join-Path $ProjectRoot "Saved\Package\$Target-$Platform-$Configuration.log"
$code = Invoke-Logged $env:ComSpec "/d /s /c `"`"$runUat`" $uatArgs < nul`"" $logFile

# ---------------------------------------------------------------------------------------------
Write-Step 'Result'
if ($code -ne 0) {
    $lines = (Read-SharedLines $logFile)
    $errs = @($lines | Where-Object { $_ -match ':\s*(fatal )?error\s*[A-Z]*\d*\s*:|error LNK\d+|^\s*ERROR:|LogCook: Error:|Error: ' } | ForEach-Object { $_.Trim() } | Select-Object -Unique -First 30)
    Write-Host "  BuildCookRun FAILED (code $code), first errors:" -ForegroundColor Red
    $errs | ForEach-Object { Write-Host "    $_" }
    Write-Host "  log: $logFile"
}
else {
    # folders written by this run: Windows / WindowsClient / WindowsServer / Linux / LinuxServer ...
    $outs = @(Get-ChildItem -LiteralPath $OutDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $started.AddMinutes(-1) -and $_.Name -notmatch '^Wasm' })
    foreach ($o in $outs) {
        $files = @(Get-ChildItem -LiteralPath $o.FullName -Recurse -File -Force)
        $size = ($files | Measure-Object Length -Sum).Sum
        $exes = @($files | Where-Object { $_.Extension -eq '.exe' -or ($Platform -eq 'Linux' -and $_.Extension -eq '.sh') } | Where-Object { $_.FullName -notmatch '\\Engine\\' } | ForEach-Object { $_.FullName.Substring($o.FullName.Length + 1) })
        Write-Host ("  {0}: {1}, {2} files" -f $o.FullName, (Format-Size $size), $files.Count) -ForegroundColor Green
        $exes | ForEach-Object { Write-Host "    run: $_" }
    }
    if (-not $outs) { Add-Warning "BuildCookRun succeeded, but no new folder in $OutDir (check -archivedirectory / the log)" }
    if ($Configuration -ne 'Shipping') { Write-Host "  $Configuration build: for players use -Configuration Shipping" }
}
if ($createdTargets) { Write-Host "  new target files to commit: $($createdTargets -join ', ')" }

Write-FinalStep $(if ($code -eq 0) { 'Package ready' } else { 'Package FAILED' })
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Timing $(if ($code -eq 0) { 'total' } else { 'total (FAILED)' })
if ($code -ne 0) { exit 1 }
