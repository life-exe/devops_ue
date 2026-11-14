# Copyright LifeEXE. All Rights Reserved.
# Moves an Unreal project to another engine version and builds it.
#   upgrade_engine.ps1 -ProjectPath C:\Game -Version 5.9           # target engine by version (auto-detected installs)
#   upgrade_engine.ps1 -ProjectPath C:\Game -EnginePath D:\UE_5.9  # or by path (source builds)
#   upgrade_engine.ps1 -ProjectPath C:\Game -BuildOnly             # after fixing code: rebuild and list errors again
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [string]$Version = '',
    [string]$EnginePath = '',
    # delete Intermediate, Binaries, .vs, *.sln before building (recommended between major versions)
    [switch]$Clean,
    [switch]$SkipBuild,
    [switch]$BuildOnly,
    [switch]$WhatIf
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
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom) }

# reads a file another process may still hold open for writing
function Read-SharedLines([string]$Path) {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    return @($text -split "`r?`n")
}

# runs a process, streams its output and keeps it in $LogFile; returns the exit code
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
function Invoke-BatLogged([string]$BatPath, [string]$Arguments, [string]$LogFile) {
    return Invoke-Logged $env:ComSpec "/d /s /c `"`"$BatPath`" $Arguments < nul`"" $LogFile
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project and engines'
$common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
if (-not (Test-Path -LiteralPath $common)) { throw "ue_common.ps1 not found ($common): install the ue-create-project skill next to this one" }
. $common

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$UProjectPath = $uprojectFile.FullName
$ProjectName = $uprojectFile.BaseName
$uprojectText = Read-Text $UProjectPath
$currentAssoc = ([regex]::Match($uprojectText, '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
$isCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot 'Source')
$engines = @(Get-UnrealEngines)

if ($EnginePath) { $target = Get-UnrealEngineInfo -Path $EnginePath; if ($target -and -not $target.Association) { $target.Association = Get-EngineAssociation -EnginePath $target.Path } }
elseif ($Version) { $target = $engines | Where-Object { $_.MajorMinor -eq $Version -or $_.Version -eq $Version } | Select-Object -First 1 }
elseif ($BuildOnly) { $target = $engines | Where-Object { $_.Association -eq $currentAssoc -or $_.MajorMinor -eq $currentAssoc } | Select-Object -First 1 }
else { $target = $engines | Select-Object -First 1 }
if (-not $target) {
    $list = ($engines | ForEach-Object { "$($_.Version) $($_.Path)" }) -join '; '
    throw "Target engine not found (-Version '$Version' -EnginePath '$EnginePath'). Detected: $list"
}
$current = $engines | Where-Object { $_.Association -eq $currentAssoc -or ($currentAssoc -match '^\d+\.\d+$' -and $_.MajorMinor -eq $currentAssoc) } | Select-Object -First 1
Write-Host "  project : $UProjectPath ($(if ($isCpp) { 'C++' } else { 'Blueprint' }))"
Write-Host "  current : '$currentAssoc'$(if ($current) { " -> $($current.Path)" } else { ' (not installed here)' })"
Write-Host "  target  : $($target.Version) $($target.Path) (association '$($target.Association)')"
if (-not $target.EditorBuilt) { Add-Warning "Target engine has no built UnrealEditor.exe (source build not compiled yet)" }
if ($current -and [version]$current.Version -gt [version]$target.Version) { Add-Warning "Downgrade ($($current.Version) -> $($target.Version)): assets saved with the newer engine will not load" }

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git -and (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $dirty = @(& git -C $ProjectRoot status --porcelain 2>$null)
    $ErrorActionPreference = $prev
    if ($dirty.Count -gt 0) { Add-Warning "$($dirty.Count) uncommitted changes: commit them first so the upgrade is one reviewable diff" }
}

$logDir = Join-Path $ProjectRoot 'Saved\UpgradeEngine'
$changes = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------------------------
if (-not $BuildOnly) {
    Write-Step "Project files for $($target.MajorMinor)"

    # .uproject
    if ($target.Association) {
        $newText = [regex]::Replace($uprojectText, '"EngineAssociation"\s*:\s*"[^"]*"', "`"EngineAssociation`": `"$($target.Association)`"")
        if ($newText -ne $uprojectText) { [void]$changes.Add("$($uprojectFile.Name): EngineAssociation '$currentAssoc' -> '$($target.Association)'"); if (-not $WhatIf) { Write-Text $UProjectPath $newText } }
    }
    else { [void]$changes.Add("$($uprojectFile.Name): engine registered with UnrealVersionSelector (unregistered build)") }

    # devops_data\config.bat
    $configBat = Join-Path $ProjectRoot 'devops_data\config.bat'
    if (Test-Path -LiteralPath $configBat) {
        $cfg = Read-Text $configBat
        $newCfg = [regex]::Replace($cfg, '(?m)^set EnginePath=[^\r\n]*', ("set EnginePath=$($target.Path)").Replace('$', '$$'))
        if ($newCfg -ne $cfg) { [void]$changes.Add("devops_data\config.bat: EnginePath -> $($target.Path)"); if (-not $WhatIf) { Write-Text $configBat $newCfg } }
    }

    # *.Target.cs: build settings / include order of the target engine, taken from its blank C++ template
    if ($isCpp) {
        $tpl = Join-Path $target.Path 'Templates\TP_Blank\Source\TP_Blank.Target.cs'
        $buildSettings = ''; $includeOrder = ''
        if (Test-Path -LiteralPath $tpl) {
            $t = Read-Text $tpl
            $buildSettings = ([regex]::Match($t, 'DefaultBuildSettings\s*=\s*(BuildSettingsVersion\.\w+)')).Groups[1].Value
            $includeOrder = ([regex]::Match($t, 'IncludeOrderVersion\s*=\s*(EngineIncludeOrderVersion\.\w+)')).Groups[1].Value
        }
        else { Add-Warning "No $tpl - Target.cs settings were not updated" }
        foreach ($tf in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Source') -Filter '*.Target.cs' -File) {
            $text = Read-Text $tf.FullName; $orig = $text
            if ($buildSettings) { $text = [regex]::Replace($text, 'DefaultBuildSettings\s*=\s*BuildSettingsVersion\.\w+', "DefaultBuildSettings = $buildSettings") }
            if ($includeOrder) {
                if ($text -match 'IncludeOrderVersion\s*=') { $text = [regex]::Replace($text, 'IncludeOrderVersion\s*=\s*EngineIncludeOrderVersion\.\w+', "IncludeOrderVersion = $includeOrder") }
                elseif ($text -match 'DefaultBuildSettings\s*=[^\r\n]*') { $text = [regex]::Replace($text, '([ \t]*)(DefaultBuildSettings\s*=[^\r\n]*)', "`$1`$2`r`n`$1IncludeOrderVersion = $includeOrder;") }
            }
            if ($text -ne $orig) { [void]$changes.Add("Source\$($tf.Name): $buildSettings, $includeOrder"); if (-not $WhatIf) { Write-Text $tf.FullName $text } }
        }
    }

    # plugins of the project: precompiled-only plugins must come in a version built for the target engine
    foreach ($up in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Plugins') -Recurse -Filter '*.uplugin' -File -ErrorAction SilentlyContinue) {
        $pdir = $up.Directory.FullName
        $j = $null; try { $j = Read-Text $up.FullName | ConvertFrom-Json } catch { }
        $ev = if ($j -and $j.PSObject.Properties['EngineVersion']) { $j.EngineVersion } else { '' }
        if (-not (Test-Path -LiteralPath (Join-Path $pdir 'Source'))) { Add-Warning "Plugin $($up.BaseName) has no sources (precompiled$(if ($ev) { " for $ev" })): get a build for $($target.MajorMinor)" }
        elseif ($ev -and $ev -notlike "$($target.MajorMinor)*") { Add-Warning "Plugin $($up.BaseName): EngineVersion $ev in the .uplugin (it is rebuilt from source; update the field if it is marketplace-style)" }
    }

    # per-version scripts of older workflows
    $oldGen = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter 'generate_project_files_*.bat' -File -ErrorAction SilentlyContinue)
    if ($oldGen) { Add-Warning "Per-version scripts in the root ($($oldGen.Name -join ', ')): generate_project_files.bat + devops_data\config.bat replace them" }

    if ($changes.Count) { $changes | ForEach-Object { Write-Host "  $_" } } else { Write-Host '  nothing to change (already on this engine)' }

    if ($WhatIf) {
        Write-FinalStep 'Plan only (nothing written)'
        if ($Warnings.Count) { Write-Host 'Warnings:' -ForegroundColor Yellow; $Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow } }
        Write-Timing; exit 0
    }

    if (-not $target.Association) {
        $vs = 'C:\Program Files (x86)\Epic Games\Launcher\Engine\Binaries\Win64\UnrealVersionSelector.exe'
        if (-not (Test-Path -LiteralPath $vs)) { $vs = Join-Path $env:LOCALAPPDATA 'Epic Games\Launcher\Engine\Binaries\Win64\UnrealVersionSelector.exe' }
        if (Test-Path -LiteralPath $vs) { & $vs -switchversionsilent $UProjectPath $target.Path | Out-Null } else { Add-Warning 'UnrealVersionSelector not found: open the .uproject and pick the engine' }
    }

    if ($Clean) {
        Write-Step 'Clean Intermediate, Binaries, .vs, *.sln'
        $paths = @('Intermediate', 'Binaries', '.vs') | ForEach-Object { Join-Path $ProjectRoot $_ }
        $paths += @(Get-ChildItem -LiteralPath $ProjectRoot -File | Where-Object { $_.Extension -in '.sln', '.slnx' } | ForEach-Object { $_.FullName })
        foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force; Write-Host "  removed $p" } }
    }
}

# ---------------------------------------------------------------------------------------------
$buildOk = $null
$errorsFile = Join-Path $logDir 'build_errors.txt'
if ($isCpp -and -not $SkipBuild) {
    $buildBat = Join-Path $target.Path 'Engine\Build\BatchFiles\Build.bat'
    Write-Step 'Generate project files'
    $code = Invoke-BatLogged $buildBat "-projectfiles -project=`"$UProjectPath`" -game -progress" (Join-Path $logDir 'projectfiles.log')
    if ($code -ne 0) { Add-Warning "Project file generation failed (code $code), see $logDir\projectfiles.log" }

    Write-Step "Build ${ProjectName}Editor Win64 Development"
    $buildLog = Join-Path $logDir 'build.log'
    $code = Invoke-BatLogged $buildBat "${ProjectName}Editor Win64 Development -Project=`"$UProjectPath`" -WaitMutex" $buildLog
    $buildOk = ($code -eq 0)

    # errors and deprecations (the usual work of an upgrade)
    $lines = if (Test-Path -LiteralPath $buildLog) { (Read-SharedLines $buildLog) } else { @() }
    $errors = @($lines | Where-Object { $_ -match ':\s*(fatal )?error\s*[A-Z]*\d*\s*:|error LNK\d+|^\s*ERROR:|: error:' } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    $deprecations = @($lines | Where-Object { $_ -match 'warning C4996|deprecated' } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    $report = New-Object System.Text.StringBuilder
    [void]$report.AppendLine("Build of ${ProjectName}Editor with UE $($target.Version): $(if ($buildOk) { 'SUCCEEDED' } else { "FAILED (code $code)" })")
    [void]$report.AppendLine("Errors: $($errors.Count)"); $errors | ForEach-Object { [void]$report.AppendLine("  $_") }
    [void]$report.AppendLine("Deprecation warnings: $($deprecations.Count)"); $deprecations | ForEach-Object { [void]$report.AppendLine("  $_") }
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    Write-Text $errorsFile $report.ToString()

    Write-Host ''
    if ($buildOk) { Write-Host "  build SUCCEEDED, $($deprecations.Count) deprecation warning(s)" -ForegroundColor Green }
    else {
        Write-Host "  build FAILED: $($errors.Count) error line(s) (first 30):" -ForegroundColor Red
        $errors | Select-Object -First 30 | ForEach-Object { Write-Host "    $_" }
    }
    if ($deprecations.Count) { Write-Host '  deprecations (first 15):'; $deprecations | Select-Object -First 15 | ForEach-Object { Write-Host "    $_" } }
    Write-Host "  full list: $errorsFile"
}
elseif (-not $isCpp) { Write-Host ''; Write-Host '  Blueprint project: nothing to build. Open it in the new editor; assets are upgraded when resaved.' }

# ---------------------------------------------------------------------------------------------
Write-FinalStep $(if ($buildOk -eq $false) { 'Upgrade applied, build FAILED - fix the errors and run again with -BuildOnly' } else { "Project is on UE $($target.Version)" })
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Timing $(if ($buildOk -eq $false) { 'total (build failed)' } else { 'total' })
if ($buildOk -eq $false) { exit 2 }
