# Copyright LifeEXE. All Rights Reserved.
# Creates Client / Server / Editor target rules (Source\<Name>Client.Target.cs ...) from the project's game target.
#   target_create.ps1 -ProjectPath C:\Game                       # Client + Server
#   target_create.ps1 -ProjectPath C:\Game -Type Server          # one of: Client, Server, ClientServer, Editor, All
#   target_create.ps1 -ProjectPath C:\Game -Type All -Force      # overwrite existing files
#   target_create.ps1 -ProjectPath C:\Game -GenerateProjectFiles # + regenerate the .sln
#   target_create.ps1 -ProjectPath C:\Game -WhatIf               # show what would be created
# The text is taken from Source\<Name>.Target.cs (so DefaultBuildSettings / IncludeOrderVersion / ExtraModuleNames match
# the project); devops_ue\targets\GameModule.Target.cs.template is the fallback. Cooking / packaging is ue-cook / ue-package.
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [ValidateSet('Client', 'Server', 'ClientServer', 'Editor', 'All')][string]$Type = 'ClientServer',
    [switch]$Force,
    [switch]$GenerateProjectFiles,
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
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Get-ConfigValue([string]$ConfigBat, [string]$Name) {
    if (-not (Test-Path -LiteralPath $ConfigBat)) { return '' }
    $v = [IO.File]::ReadAllLines($ConfigBat) | Where-Object { $_ -match "^set $([regex]::Escape($Name))=(.*)$" } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1
    return "$v"
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$ProjectName = $uprojectFile.BaseName
$sourceDir = Join-Path $ProjectRoot 'Source'
if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $ProjectName))) {
    throw "$ProjectName is a Blueprint-only project: target rules need a C++ game module (Source\$ProjectName). Add one first (ue-web-setup adds a module for web projects, or create a C++ class in the editor)."
}
Write-Host "  $($uprojectFile.FullName)"

$gameTarget = Join-Path $sourceDir "$ProjectName.Target.cs"
$templateFile = Join-Path $PSScriptRoot '..\..\..\targets\GameModule.Target.cs.template'
$baseText = $null
if (Test-Path -LiteralPath $gameTarget) {
    $baseText = Read-Text $gameTarget
    Write-Host "  base: Source\$ProjectName.Target.cs"
}
else {
    Add-Warning "Source\$ProjectName.Target.cs not found: using the devops_ue template (check ExtraModuleNames)"
    if (-not (Test-Path -LiteralPath $templateFile)) { throw "Neither $gameTarget nor $templateFile exist" }
    $configBat = Join-Path $ProjectRoot 'devops_data\config.bat'
    $copyright = Get-ConfigValue $configBat 'COPYRIGHT_LINE'
    if (-not $copyright) { $copyright = "// Copyright $ProjectName. All Rights Reserved." }
    $lines = foreach ($l in [IO.File]::ReadAllLines($templateFile)) { if ($l -eq 'NEW_LINE') { '' } else { $l } }
    $baseText = ($lines -join "`r`n").Replace('%COPYRIGHT_LINE%', $copyright).Replace('%MODULE_NAME%%TARGET_TYPE%Target', "${ProjectName}Target").Replace('%TARGET_TYPE%', 'Game').Replace('%EXTRA_MODULE_NAMES%', "`"$ProjectName`"")
}
if ($baseText -notmatch "class\s+${ProjectName}Target\b") { Add-Warning "The game target class in $ProjectName.Target.cs is not named ${ProjectName}Target: class names in the new files may be wrong" }
if ($baseText -notmatch 'TargetType\.Game') { throw "$ProjectName.Target.cs has no 'Type = TargetType.Game': cannot derive other targets from it" }

$types = switch ($Type) { 'Client' { @('Client') } 'Server' { @('Server') } 'ClientServer' { @('Client', 'Server') } 'Editor' { @('Editor') } 'All' { @('Client', 'Server', 'Editor') } }

Write-Step 'Target rules'
$created = @(); $skipped = @()
foreach ($t in $types) {
    $rel = "Source\$ProjectName$t.Target.cs"
    $file = Join-Path $ProjectRoot $rel
    if ((Test-Path -LiteralPath $file) -and -not $Force) { $skipped += $rel; Write-Host "  exists, kept: $rel"; continue }
    $text = $baseText.Replace("${ProjectName}Target", "$ProjectName${t}Target") -replace 'TargetType\.Game', "TargetType.$t"
    $text = ($text -replace "`r?`n", "`r`n")
    if ($WhatIf) { Write-Host "  would create: $rel" }
    else {
        [IO.File]::WriteAllText($file, $text, $Utf8NoBom)
        Write-Host "  created: $rel"
    }
    $created += $rel
}

# an installed (Launcher) engine ships no client/server binaries
if (-not $EnginePath) {
    $configBat2 = Join-Path $ProjectRoot 'devops_data\config.bat'
    $e = Get-ConfigValue $configBat2 'EnginePath'
    if ($e) { $EnginePath = $e }
}
if (($types -contains 'Client' -or $types -contains 'Server') -and $EnginePath -and (Test-Path -LiteralPath (Join-Path $EnginePath 'Engine\Build\InstalledBuild.txt'))) {
    Add-Warning 'The engine is an installed (Launcher) build: Client/Server targets compile only with an engine built from source. The files are created anyway.'
}

if ($GenerateProjectFiles -and $created -and -not $WhatIf) {
    Write-Step 'Generating project files'
    if (-not $EnginePath -or -not (Test-Path -LiteralPath (Join-Path $EnginePath 'Engine\Build\Build.version'))) {
        $EnginePath = ''
        $common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
        if (Test-Path -LiteralPath $common) {
            . $common
            $assoc = ([regex]::Match((Read-Text $uprojectFile.FullName), '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
            $m = Get-UnrealEngines | Where-Object { $_.Association -eq $assoc -or $_.MajorMinor -eq $assoc } | Select-Object -First 1
            if ($m) { $EnginePath = $m.Path }
        }
    }
    $ubt = if ($EnginePath) { Join-Path $EnginePath 'Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.exe' } else { '' }
    if (-not $ubt -or -not (Test-Path -LiteralPath $ubt)) { Add-Warning 'UnrealBuildTool not found: run devops_ue\misc\generate_project_files.bat yourself' }
    else {
        & $ubt -projectfiles "-project=$($uprojectFile.FullName)" -game -rocket -progress
        if ($LASTEXITCODE -ne 0) { Add-Warning "UnrealBuildTool -projectfiles exited with $LASTEXITCODE" }
    }
}

Write-FinalStep "$(if ($WhatIf) { 'Would create' } else { 'Created' }) $($created.Count) target(s), kept $($skipped.Count)"
if ($created -and -not $WhatIf) { Write-Host '  next: generate project files (-GenerateProjectFiles), then ue-cook / ue-package -Target Client|Server' }
if ($Warnings.Count -gt 0) { Write-Host "  $($Warnings.Count) warning(s)" -ForegroundColor Yellow }
Write-Timing
