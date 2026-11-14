# Copyright LifeEXE. All Rights Reserved.
# Cleans generated Unreal project files and reports how much space each item takes.
#   clean.ps1 -WhatIf                                  # sizes only, deletes nothing
#   clean.ps1                                          # Intermediate, Binaries, DerivedDataCache, .vs, *.sln/.slnx, source plugins' Intermediate/Binaries
#   clean.ps1 -Include Saved,Build,Documentation       # plus these (opt-in)
#   clean.ps1 -Include GlobalDDC                       # plus the shared engine DDC of ALL projects (%LOCALAPPDATA%\UnrealEngine\Common\DerivedDataCache)
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    # opt-in: Saved, Build, Documentation, GlobalDDC (comma-separated works with powershell -File)
    [string[]]$Include = @(),
    # keep these default items: Intermediate, Binaries, DerivedDataCache, VS, Plugins
    [string[]]$Keep = @(),
    [switch]$WhatIf
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
function Format-Size([double]$Bytes) { if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) } elseif ($Bytes -ge 1MB) { '{0:N1} MB' -f ($Bytes / 1MB) } else { '{0:N0} KB' -f ($Bytes / 1KB) } }

function Get-Size([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return $item.Length }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($sum) { return [double]$sum } else { return 0 }
}
function Remove-Path([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
    catch {
        # deep paths (> 260 chars) - cmd with the \\?\ prefix handles them
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($item -and $item.PSIsContainer) { cmd.exe /d /c "rd /s /q `"\\?\$Path`"" | Out-Null } else { cmd.exe /d /c "del /f /q `"\\?\$Path`"" | Out-Null }
        if (Test-Path -LiteralPath $Path) { throw "could not delete $Path ($($_.Exception.Message))" }
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$ProjectName = $uprojectFile.BaseName
$isCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot 'Source')
Write-Host "  $($uprojectFile.FullName) ($(if ($isCpp) { 'C++' } else { 'Blueprint' }))"

$Include = @($Include | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
$Keep = @($Keep | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
$knownInclude = 'Saved', 'Build', 'Documentation', 'GlobalDDC'
$bad = @($Include | Where-Object { $knownInclude -notcontains $_ }); if ($bad) { throw "Unknown -Include: $($bad -join ', ') (known: $($knownInclude -join ', '))" }

# the editor (or a commandlet) holding this project would keep files locked / rebuild them while we delete
$running = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'UnrealEditor%' OR Name LIKE 'UE4Editor%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match [regex]::Escape($uprojectFile.Name) })
if ($running.Count -gt 0 -and -not $WhatIf) { throw "Unreal Editor is running with $($uprojectFile.Name) (PID $($running.ProcessId -join ', ')): close it first" }

# ---------------------------------------------------------------------------------------------
Write-Step 'Measuring'
$items = New-Object System.Collections.ArrayList
function Add-Item([string]$Group, [string]$Label, [string[]]$Paths, [bool]$Default, [string]$Note) {
    $existing = @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    $size = 0; foreach ($p in $existing) { $size += Get-Size $p }
    $selected = if ($Default) { $Keep -notcontains $Group } else { $Include -contains $Group }
    [void]$items.Add([pscustomobject]@{ Group = $Group; Item = $Label; Paths = $existing; Size = $size; Delete = ($selected -and $existing.Count -gt 0); Note = $Note })
}

Add-Item 'Intermediate' 'Intermediate' @((Join-Path $ProjectRoot 'Intermediate')) $true 'rebuilt by UBT / the editor'
Add-Item 'Binaries' 'Binaries' @((Join-Path $ProjectRoot 'Binaries')) $true $(if ($isCpp) { 'C++: rebuild before opening the editor' } else { 'rebuilt' })
Add-Item 'DerivedDataCache' 'DerivedDataCache (project)' @((Join-Path $ProjectRoot 'DerivedDataCache')) $true 'shaders/DDC: next editor start is slower'
$vsPaths = @((Join-Path $ProjectRoot '.vs')) + @(Get-ChildItem -LiteralPath $ProjectRoot -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.sln', '.slnx' } | ForEach-Object { $_.FullName })
Add-Item 'VS' '.vs, *.sln, *.slnx' $vsPaths $true 'regenerate: generate_project_files.bat'
$pluginPaths = @()
foreach ($plugin in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Plugins') -Directory -ErrorAction SilentlyContinue) {
    # only plugins with sources: precompiled plugins can't rebuild their binaries
    if (Test-Path -LiteralPath (Join-Path $plugin.FullName 'Source')) { $pluginPaths += @((Join-Path $plugin.FullName 'Intermediate'), (Join-Path $plugin.FullName 'Binaries')) }
}
Add-Item 'Plugins' 'Plugins\*\Intermediate, Binaries (source plugins)' $pluginPaths $true 'rebuilt with the project'
Add-Item 'Saved' 'Saved' @((Join-Path $ProjectRoot 'Saved')) $false 'logs, autosaves, editor layout, local config - opt-in'
Add-Item 'Build' 'Build' @((Join-Path $ProjectRoot 'Build')) $false 'packaged builds - opt-in'
Add-Item 'Documentation' 'Documentation' @((Join-Path $ProjectRoot 'Documentation')) $false 'generated docs - opt-in'
$globalDdc = Join-Path $env:LOCALAPPDATA 'UnrealEngine\Common\DerivedDataCache'
Add-Item 'GlobalDDC' 'Engine DDC (all projects)' @($globalDdc) $false 'shared by every project - opt-in'
$zen = Join-Path $env:LOCALAPPDATA 'UnrealEngine\Common\Zen\Data'
if (Test-Path -LiteralPath $zen) {
    [void]$items.Add([pscustomobject]@{ Group = 'Zen'; Item = 'Zen storage (all projects)'; Paths = @(); Size = (Get-Size $zen); Delete = $false; Note = 'report only: managed by the Zen server (UnrealZenServer)' })
}

$items | Select-Object @{ n = 'Action'; e = { if ($_.Delete) { 'DELETE' } elseif ($_.Size -gt 0) { 'keep' } else { '-' } } }, Item,
    @{ n = 'Size'; e = { Format-Size $_.Size } }, Note | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
$toDelete = @($items | Where-Object { $_.Delete })
$total = ($toDelete | Measure-Object Size -Sum).Sum; if (-not $total) { $total = 0 }

if ($WhatIf) {
    Write-FinalStep "Plan only: would free $(Format-Size $total)"
    Write-Timing
    exit 0
}

# ---------------------------------------------------------------------------------------------
$freed = 0
foreach ($i in $toDelete) {
    Write-Step "Delete $($i.Item)"
    foreach ($p in $i.Paths) {
        try { Remove-Path $p; Write-Host "  removed $p" } catch { Add-Warning $_.Exception.Message }
    }
    $freed += $i.Size
}

Write-FinalStep "Freed $(Format-Size $freed)"
$driveRoot = [IO.Path]::GetPathRoot($ProjectRoot)
Write-Host "  free on ${driveRoot}: $(Format-Size (New-Object IO.DriveInfo $driveRoot).AvailableFreeSpace)"
if ($isCpp -and ($toDelete | Where-Object { $_.Group -in 'Binaries', 'Intermediate' })) {
    Write-Host '  next: generate_project_files.bat, then build the editor target (or open the .uproject and let it rebuild)'
}
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}

Write-Timing
