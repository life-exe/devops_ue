# Copyright LifeEXE. All Rights Reserved.
# Packages a plugin with UAT BuildPlugin (compiles it for the target platforms into a distributable folder) and reports it.
#   plugin_package.ps1 -ProjectPath C:\Game -Name WeaponSystem                           # Win64 -> Build\Plugins\WeaponSystem_5.9
#   plugin_package.ps1 -ProjectPath C:\Game -Name WeaponSystem -TargetPlatforms Win64,Linux
#   plugin_package.ps1 -ProjectPath C:\Game -Name WeaponSystem -Zip                      # + WeaponSystem_5.9.zip next to the folder
#   plugin_package.ps1 -PluginFile C:\Plugins\Foo\Foo.uplugin -EnginePath "C:\Program Files\Epic Games\UE_5.9"
#   plugin_package.ps1 -ProjectPath C:\Game -Name WeaponSystem -StrictIncludes           # IWYU checks, required by Fab
# BuildPlugin builds against the engine itself, not against the project: the plugin must not need project code.
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [string]$Name = '',
    # alternative to -ProjectPath/-Name: the .uplugin file itself
    [string]$PluginFile = '',
    [string[]]$TargetPlatforms = @('Win64'),
    [string]$OutDir = '',
    [switch]$Zip,
    # leave the Intermediate folder out of the zip (the engine puts build intermediates into the package)
    [switch]$ZipWithoutIntermediate,
    [switch]$StrictIncludes,
    [switch]$NoHostPlatform,
    [switch]$Clean,
    [switch]$WhatIf,
    [string]$EnginePath = '',
    [int]$TimeoutMinutes = 120
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

# ---------------------------------------------------------------------------------------------
Write-Step 'Plugin'
$ProjectRoot = ''
$assoc = ''
if (-not $PluginFile) {
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    $ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
    $uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
    if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot (or pass -PluginFile)" }
    $assoc = ([regex]::Match((Read-Text $uprojectFile.FullName), '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
    $found = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Plugins') -Recurse -Filter '*.uplugin' -File -ErrorAction SilentlyContinue)
    if (-not $Name) {
        $found | ForEach-Object { Write-Host "  $($_.BaseName)  ($($_.FullName.Replace($ProjectRoot + '\', '')))" }
        throw "Pass -Name <plugin> ($($found.Count) plugin(s) listed above)"
    }
    $match = @($found | Where-Object { $_.BaseName -eq $Name })
    if ($match.Count -eq 0) { throw "Plugin '$Name' not found under $ProjectRoot\Plugins" }
    $PluginFile = $match[0].FullName
}
$PluginFile = (Resolve-Path -LiteralPath $PluginFile).Path
$PluginName = [IO.Path]::GetFileNameWithoutExtension($PluginFile)
$PluginDir = Split-Path -Parent $PluginFile
try { $uplugin = (Read-Text $PluginFile) | ConvertFrom-Json } catch { throw "$PluginFile is not valid JSON: $($_.Exception.Message)" }
$moduleList = @($uplugin.Modules)
Write-Host "  $PluginFile"
Write-Host "  $($uplugin.FriendlyName) $($uplugin.VersionName) - modules: $(if ($moduleList.Count) { ($moduleList | ForEach-Object { "$($_.Name) [$($_.Type)]" }) -join ', ' } else { '(none: content-only plugin)' })"
$hasSource = Test-Path -LiteralPath (Join-Path $PluginDir 'Source')
if ($moduleList.Count -gt 0 -and -not $hasSource) { Add-Warning 'The .uplugin lists modules but there is no Source folder' }
if ($moduleList.Count -eq 0 -and -not $NoHostPlatform) { Add-Warning 'Content-only plugin: -NoHostPlatform is usually what you want' }

# ---------------------------------------------------------------------------------------------
Write-Step 'Engine'
if (-not $EnginePath -and $ProjectRoot) {
    $e = Get-ConfigValue (Join-Path $ProjectRoot 'devops_data\config.bat') 'EnginePath'
    if ($e -and (Test-Path -LiteralPath (Join-Path $e 'Engine\Build\Build.version'))) { $EnginePath = $e }
}
if (-not $EnginePath -and $assoc) {
    $common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
    if (Test-Path -LiteralPath $common) {
        . $common
        $m = Get-UnrealEngines | Where-Object { $_.Association -eq $assoc -or $_.MajorMinor -eq $assoc } | Select-Object -First 1
        if ($m) { $EnginePath = $m.Path }
    }
}
if (-not $EnginePath) { throw 'Engine not found: pass -EnginePath' }
$EnginePath = (Resolve-Path -LiteralPath $EnginePath).Path.TrimEnd('\')
$runUat = Join-Path $EnginePath 'Engine\Build\BatchFiles\RunUAT.bat'
if (-not (Test-Path -LiteralPath $runUat)) { throw "RunUAT.bat not found in $EnginePath" }
$ver = (Read-Text (Join-Path $EnginePath 'Engine\Build\Build.version')) | ConvertFrom-Json
$engineMajorMinor = "$($ver.MajorVersion).$($ver.MinorVersion)"
Write-Host "  $EnginePath (UE $engineMajorMinor)"

$platforms = @($TargetPlatforms | ForEach-Object { $_ -split '[,+\s]+' } | Where-Object { $_ })
if ($platforms.Count -eq 0 -and -not $NoHostPlatform) { $platforms = @('Win64') }

if (-not $OutDir) {
    $base = if ($ProjectRoot) { Join-Path $ProjectRoot 'Build\Plugins' } else { Join-Path (Split-Path -Parent $PluginDir) 'Build' }
    $OutDir = Join-Path $base "${PluginName}_$engineMajorMinor"
}
$OutDir = [IO.Path]::GetFullPath($OutDir)
# UAT refuses a package folder inside the plugin (it would be copied into itself) or inside the engine
if ($OutDir.StartsWith($PluginDir + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "-OutDir must be outside the plugin folder ($PluginDir)" }
if ($OutDir.StartsWith($EnginePath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '-OutDir must be outside the engine folder' }
if ((Test-Path -LiteralPath $OutDir) -and @(Get-ChildItem -LiteralPath $OutDir -Force).Count -gt 0) {
    if (-not $Clean) { throw "$OutDir is not empty: pass -Clean to delete it first (or another -OutDir)" }
    if (-not $WhatIf) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
}

# ---------------------------------------------------------------------------------------------
$uatArgs = "BuildPlugin -Plugin=`"$PluginFile`" -Package=`"$OutDir`" -Rocket"
if ($platforms.Count -gt 0) { $uatArgs += " -TargetPlatforms=$($platforms -join '+')" }
if ($NoHostPlatform) { $uatArgs += ' -NoHostPlatform' }
if ($StrictIncludes) { $uatArgs += ' -StrictIncludes' }

Write-Step "BuildPlugin $PluginName ($($platforms -join ', '))"
Write-Host "  RunUAT $uatArgs"
if ($WhatIf) { Write-FinalStep 'WhatIf: nothing was run'; Write-Timing; exit 0 }

$running = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'UnrealEditor%'" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) { Add-Warning "Unreal Editor is running (PID $($running.ProcessId -join ', ')): it can lock engine binaries the build needs" }

$logRoot = if ($ProjectRoot) { Join-Path $ProjectRoot 'Saved\PluginPackage' } else { Join-Path $env:TEMP 'ue-plugin-package' }
$logFile = Join-Path $logRoot "$PluginName.log"
$code = Invoke-BatLogged $runUat $uatArgs $logFile $TimeoutMinutes

# ---------------------------------------------------------------------------------------------
Write-Step 'Results'
$lines = if (Test-Path -LiteralPath $logFile) { Read-SharedLines $logFile } else { @() }
$errors = @($lines | Where-Object { $_ -match ':\s*(fatal )?error\s*[A-Z]*\d*\s*:|error LNK\d+|ERROR:|Error:' -and $_ -notmatch 'Display:.*\b0 error' } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
$errors | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
Write-Host "  log: $logFile"
if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $OutDir "$PluginName.uplugin"))) {
    Write-FinalStep "BuildPlugin FAILED (exit code $code)"
    Write-Timing 'total (FAILED)'
    exit 1
}

$files = @(Get-ChildItem -LiteralPath $OutDir -Recurse -File -ErrorAction SilentlyContinue)
$size = ($files | Measure-Object Length -Sum).Sum
Write-Host "  package: $OutDir ($(Format-Size ([double]$size)), $($files.Count) files)"
foreach ($p in $platforms) {
    $bin = Join-Path $OutDir "Binaries\$p"
    $dlls = @(Get-ChildItem -LiteralPath $bin -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.dll', '.so', '.a', '.wasm', '.lib' })
    if ($moduleList.Count -eq 0) { continue }
    if ($dlls.Count -gt 0) { Write-Host "  Binaries\$p : $($dlls.Count) binary file(s)" }
    else { Add-Warning "No binaries for $p in the package (Binaries\$p is empty or missing)" }
}
$pkgPlugin = (Read-Text (Join-Path $OutDir "$PluginName.uplugin")) | ConvertFrom-Json
Write-Host "  packaged .uplugin: EngineVersion $($pkgPlugin.EngineVersion), Installed $($pkgPlugin.Installed)"
if (Test-Path -LiteralPath (Join-Path $OutDir 'Intermediate')) {
    $inter = (Get-ChildItem -LiteralPath (Join-Path $OutDir 'Intermediate') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Host "  Intermediate\ : $(Format-Size ([double]$inter)) (generated by the build; the engine keeps it in the package)"
}

if ($Zip -or $ZipWithoutIntermediate) {
    Write-Step 'Zip'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = "$OutDir.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    $archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($OutDir.Length + 1)
            if ($ZipWithoutIntermediate -and $rel -like 'Intermediate\*') { continue }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, ("$PluginName/" + $rel.Replace('\', '/')), [IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally { $archive.Dispose() }
    Write-Host "  $zipPath ($(Format-Size ([double](Get-Item -LiteralPath $zipPath).Length)))"
}

Write-FinalStep "Plugin '$PluginName' packaged"
if ($Warnings.Count -gt 0) { Write-Host "  $($Warnings.Count) warning(s)" -ForegroundColor Yellow }
Write-Timing
