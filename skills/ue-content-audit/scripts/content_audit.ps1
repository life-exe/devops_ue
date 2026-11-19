# Copyright LifeEXE. All Rights Reserved.
# Content audit of an Unreal project.
#   content_audit.ps1 -ProjectPath C:\Game                    # quick, no editor: size by folder / file type, largest packages
#   content_audit.ps1 -ProjectPath C:\Game -Deep              # + editor asset registry: by class, unreferenced candidates,
#                                                             #   big textures, redirectors (starts UnrealEditor-Cmd, ~1-3 min)
#   content_audit.ps1 -ProjectPath C:\Game -Deep -Report Saved\content_audit.md
#   content_audit.ps1 -ProjectPath C:\Game -Deep -Html -Open -Lang ru   # a minimal HTML report (Saved\ContentAudit\content_audit.html), opened in the browser
#   content_audit.ps1 -ProjectPath C:\Game -Report Saved\audit.html     # -Report ending in .html writes the HTML report there
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [switch]$Deep,
    # the engine's DataValidation plugin (UnrealEditor-Cmd -run=DataValidation): every enabled validator over /Game assets
    # (project validators written in C++ / Blueprint run too); errors and warnings go into the report
    [switch]$Validate,
    # only assets of this class, e.g. Texture2D or /Script/Engine.StaticMesh (default: all)
    [string]$ValidateAssetType = '',
    # exit code 1 when the validation found errors (CI)
    [switch]$FailOnIssues,
    [int]$Top = 20,
    [int]$TextureLimit = 2048,
    [string]$Report = '',
    [switch]$Html,      # HTML report (self-contained page with filter, RU/EN switch, light/dark theme)
    [switch]$Open,      # open the HTML report in the default browser
    [ValidateSet('ru', 'en')][string]$Lang = 'en',   # language the HTML page starts in
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
function Add-Warning([string]$Text) {
    if ($Warnings.Contains($Text)) { return }   # the same warning from two editor runs is shown once
    [void]$Warnings.Add($Text); Write-Host "WARNING: $Text" -ForegroundColor Yellow
}
function Format-Size([double]$Bytes) { if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) } elseif ($Bytes -ge 1MB) { '{0:N1} MB' -f ($Bytes / 1MB) } else { '{0:N0} KB' -f ($Bytes / 1KB) } }
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

$md = New-Object System.Text.StringBuilder
function Add-MdTable([string]$Heading, $Rows, [string[]]$Columns) {
    [void]$md.AppendLine("## $Heading"); [void]$md.AppendLine()
    if (-not $Rows) { [void]$md.AppendLine('_none_'); [void]$md.AppendLine(); return }
    [void]$md.AppendLine('| ' + ($Columns -join ' | ') + ' |')
    [void]$md.AppendLine('|' + (($Columns | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($r in $Rows) { [void]$md.AppendLine('| ' + (($Columns | ForEach-Object { "$($r.$_)".Replace('|', '\|') }) -join ' | ') + ' |') }
    [void]$md.AppendLine()
}
$sections = New-Object System.Collections.ArrayList   # the same tables for the HTML report
function Show-Table([string]$Heading, $Rows, [string[]]$Columns, [string]$Key = '', $Meta = @{}) {
    Write-Host ''; Write-Host "  $Heading" -ForegroundColor Cyan
    [void]$sections.Add([ordered]@{
            key = $Key; heading = $Heading; columns = $Columns; meta = $Meta
            rows = @($Rows | ForEach-Object { $r = $_; $o = [ordered]@{}; foreach ($c in $Columns) { $o[$c] = "$($r.$c)" }; $o })
        })
    if (-not $Rows) { Write-Host '    none'; return }
    $Rows | Select-Object $Columns | Format-Table -AutoSize | Out-String -Width 220 | ForEach-Object { $_.TrimEnd() } | Write-Host
    Add-MdTable $Heading $Rows $Columns
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Scan Content (files)'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$UProjectPath = $uprojectFile.FullName
$ProjectName = $uprojectFile.BaseName
$content = Join-Path $ProjectRoot 'Content'
if (-not (Test-Path -LiteralPath $content)) { throw "No Content folder in $ProjectRoot" }
$contentFull = (Resolve-Path -LiteralPath $content).Path.TrimEnd('\')

$files = @(Get-ChildItem -LiteralPath $contentFull -Recurse -File -Force -ErrorAction SilentlyContinue)
$total = ($files | Measure-Object Length -Sum).Sum
[void]$md.AppendLine("# Content audit: $ProjectName"); [void]$md.AppendLine()
[void]$md.AppendLine("- Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$md.AppendLine("- Content: $($files.Count) files, $(Format-Size $total)"); [void]$md.AppendLine()
Write-Host "  $contentFull : $($files.Count) files, $(Format-Size $total)"

# packages: .uasset/.umap + .uexp/.ubulk/.uptnl of the same base name
$packages = @{}
foreach ($f in $files) {
    $rel = $f.FullName.Substring($contentFull.Length + 1)
    $ext = $f.Extension.ToLowerInvariant()
    if ($ext -notin '.uasset', '.umap', '.uexp', '.ubulk', '.uptnl') { continue }
    $pkg = '/Game/' + ($rel.Substring(0, $rel.Length - $f.Extension.Length) -replace '\\', '/')
    if (-not $packages.ContainsKey($pkg)) { $packages[$pkg] = [pscustomobject]@{ Package = $pkg; Bytes = 0; IsMap = $false; Folder = ($rel -split '\\')[0] } }
    $packages[$pkg].Bytes += $f.Length
    if ($ext -eq '.umap') { $packages[$pkg].IsMap = $true }
}

$byFolder = $files | Group-Object { $r = $_.FullName.Substring($contentFull.Length + 1); if ($r -match '^__External') { '(World Partition actors)' } else { ($r -split '\\')[0] + $(if ($r -notmatch '\\') { ' (file)' }) } } |
    ForEach-Object { [pscustomobject]@{ Folder = $_.Name; Files = $_.Count; Bytes = ($_.Group | Measure-Object Length -Sum).Sum } } | Sort-Object Bytes -Descending |
    ForEach-Object { $_ | Add-Member -NotePropertyName Size -NotePropertyValue (Format-Size $_.Bytes) -PassThru | Add-Member -NotePropertyName Share -NotePropertyValue ('{0:P0}' -f ($_.Bytes / [math]::Max(1, $total))) -PassThru }
Show-Table 'Size by top folder' $byFolder @('Folder', 'Files', 'Size', 'Share') 'folders'

$byExt = $files | Group-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { '(none)' } } |
    ForEach-Object { [pscustomobject]@{ Type = $_.Name; Files = $_.Count; Bytes = ($_.Group | Measure-Object Length -Sum).Sum } } | Sort-Object Bytes -Descending |
    ForEach-Object { $_ | Add-Member -NotePropertyName Size -NotePropertyValue (Format-Size $_.Bytes) -PassThru }
Show-Table 'Size by file type' $byExt @('Type', 'Files', 'Size') 'types'

$largest = $packages.Values | Sort-Object Bytes -Descending | Select-Object -First $Top |
    ForEach-Object { [pscustomobject]@{ Package = $_.Package; Size = (Format-Size $_.Bytes); Map = $(if ($_.IsMap) { 'map' } else { '' }) } }
Show-Table "Largest $Top packages" $largest @('Package', 'Size', 'Map') 'largest' @{ top = $Top }

# ---------------------------------------------------------------------------------------------
# engine + editor binaries check shared by -Deep and -Validate; $false (with a warning) when the editor cannot be started
function Initialize-Editor([string]$What) {
    $assoc = ([regex]::Match([IO.File]::ReadAllText($UProjectPath), '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
    $script:EnginePath = Resolve-ProjectEngine $ProjectRoot $assoc $script:EnginePath
    $script:editorCmd = Join-Path $script:EnginePath 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
    $isCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot 'Source')
    $dll = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Binaries\Win64') -Filter "UnrealEditor-$ProjectName*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($isCpp -and -not $dll) {
        Add-Warning "Editor binaries of $ProjectName are not built: build ${ProjectName}Editor first ($What skipped)"
        return $false
    }
    return $true
}

# Runs UnrealEditor-Cmd with the log in $LogFile. An engine plugin whose binaries do not match the engine build stops the editor
# at start-up (seen with Fab): when $Succeeded says the run did not do its job and the log names such a plugin, run again without it.
function Invoke-EditorRun([string]$EditorArgs, [string]$LogFile, [scriptblock]$Succeeded) {
    $disable = @()
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if (Test-Path -LiteralPath $LogFile) { Remove-Item -LiteralPath $LogFile -Force }
        $dis = if ($disable) { " -DisablePlugins=$($disable -join ',')" } else { '' }
        $proc = Start-Process -FilePath $script:editorCmd -ArgumentList "$EditorArgs$dis `"-abslog=$LogFile`"" -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput "$LogFile.stdout" -RedirectStandardError "$LogFile.stderr"
        Remove-Item -LiteralPath "$LogFile.stdout", "$LogFile.stderr" -Force -ErrorAction SilentlyContinue   # the editor's own log is in $LogFile
        if (& $Succeeded) { break }
        $text = if (Test-Path -LiteralPath $LogFile) { [IO.File]::ReadAllText($LogFile) } else { '' }
        $bad = @([regex]::Matches($text, "Plugin '(\w+)' failed to load because module") | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin $disable } | Select-Object -Unique)
        if (-not $bad) { break }
        $disable += $bad
        Add-Warning "Plugin(s) $($bad -join ', ') failed to load (binaries of another engine build?): ran without them. Fix: Epic Games Launcher > Verify the engine."
    }
    return $proc
}

if ($Validate) {
    Write-Step 'Data validation (UnrealEditor-Cmd -run=DataValidation)'
    if (Initialize-Editor 'data validation') {
        $outDirV = Join-Path $ProjectRoot 'Saved\ContentAudit'
        New-Item -ItemType Directory -Force -Path $outDirV | Out-Null
        $vlog = Join-Path $outDirV 'validation.log'
        $baseArgs = "`"$UProjectPath`" -run=DataValidation" + $(if ($ValidateAssetType) { " -AssetType=$ValidateAssetType" }) + ' -unattended -nopause -nosplash -nullrhi -nosound -nop4'
        $vp = Invoke-EditorRun $baseArgs $vlog { (Test-Path -LiteralPath $vlog) -and ([IO.File]::ReadAllText($vlog) -match 'Starting to validate') }
        $vtext = if (Test-Path -LiteralPath $vlog) { [IO.File]::ReadAllText($vlog) } else { '' }
        $started = [regex]::Match($vtext, 'Starting to validate (\d+) assets')
        if (-not $started.Success) {
            Add-Warning "Data validation did not run (exit $($vp.ExitCode)), see $vlog"
        }
        else {
            $assetCount = [int]$started.Groups[1].Value
            $issues = New-Object System.Collections.ArrayList
            $seen = @{}
            foreach ($line in ($vtext -split "`r?`n")) {
                if ($line -notmatch '^(?:\[[^\]]*\]\[[^\]]*\])?(AssetCheck|LogContentValidation|LogDataValidation|LoadErrors): (Error|Warning): (.*)$') { continue }
                $sev = $Matches[2]; $msg = $Matches[3].Trim()
                $asset = ''
                if ($msg -match "^\S*'(/[^']+)'\s*(.*)$") { $asset = ($Matches[1] -replace '\.[^./]+$', ''); $msg = $Matches[2] }
                elseif ($msg -match "^Unable to load package '(/[^']+)'\.\s*(.*)$") { $asset = $Matches[1]; $msg = $Matches[2] }   # the reason behind "Failed to load object"
                $k = "$sev|$asset|$msg"
                if ($seen.ContainsKey($k)) { continue }
                $seen[$k] = $true
                [void]$issues.Add([pscustomobject]@{ Severity = $sev; Asset = $asset; Message = $msg })
            }
            $errCount = @($issues | Where-Object Severity -eq 'Error').Count
            $warnCount = $issues.Count - $errCount
            $validators = @([regex]::Matches($vtext, '(?m)^(?:\[[^\]]*\]\[[^\]]*\])?LogContentValidation:\s+/Script/(\S+)\s*:\s*(\d+)\s*$') |
                ForEach-Object { [pscustomobject]@{ Validator = $_.Groups[1].Value; Assets = [int]$_.Groups[2].Value } })
            $sorted = @($issues | Sort-Object @{ e = { if ($_.Severity -eq 'Error') { 0 } else { 1 } } }, Asset)
            Show-Table "Data validation: $assetCount assets, $errCount errors, $warnCount warnings" $sorted @('Severity', 'Asset', 'Message') 'validation' @{ assets = $assetCount; errors = $errCount; warnings = $warnCount }
            Show-Table 'Validators that ran (assets checked)' @($validators | Sort-Object Assets -Descending) @('Validator', 'Assets') 'validators'
            Write-Host "  log: $vlog"
            $script:validationErrors = $errCount
        }
    }
}

if ($Deep) {
    Write-Step 'Asset registry (UnrealEditor-Cmd, Python)'
    $jsonOut = Join-Path $ProjectRoot 'Saved\ContentAudit\assets.json'
    if (-not (Initialize-Editor 'deep audit')) { }
    else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $jsonOut) | Out-Null
        if (Test-Path -LiteralPath $jsonOut) { Remove-Item -LiteralPath $jsonOut -Force }
        $env:UE_AUDIT_OUT = $jsonOut
        $py = Join-Path $PSScriptRoot 'content_audit.py'
        $log = Join-Path $ProjectRoot 'Saved\ContentAudit\editor.log'
        $p = Invoke-EditorRun "`"$UProjectPath`" -run=pythonscript -script=`"$py`" -EnablePlugins=PythonScriptPlugin -unattended -nopause -nosplash -nullrhi -nosound -nop4" $log { Test-Path -LiteralPath $jsonOut }
        Remove-Item Env:\UE_AUDIT_OUT -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $jsonOut)) {
            Add-Warning "Editor run gave no result (exit $($p.ExitCode)), see $log"
        }
        else {
            $assets = @(([IO.File]::ReadAllText($jsonOut) | ConvertFrom-Json).assets)
            Write-Host "  $($assets.Count) assets in /Game"
            foreach ($a in $assets) {
                $b = if ($packages.ContainsKey($a.package)) { $packages[$a.package].Bytes } else { 0 }
                $a | Add-Member -NotePropertyName Bytes -NotePropertyValue $b
            }

            $byClass = $assets | Group-Object class | ForEach-Object { [pscustomobject]@{ Class = $_.Name; Assets = $_.Count; Bytes = ($_.Group | Measure-Object Bytes -Sum).Sum } } |
                Sort-Object Bytes -Descending | Select-Object -First 25 | ForEach-Object { $_ | Add-Member -NotePropertyName Size -NotePropertyValue (Format-Size $_.Bytes) -PassThru }
            Show-Table 'Size by asset class (top 25)' $byClass @('Class', 'Assets', 'Size') 'classes'

            # unreferenced: no package references them - minus roots (maps), redirectors and anything named in Config/*.ini / .uproject
            $configText = ((Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Config') -Filter '*.ini' -File -ErrorAction SilentlyContinue | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n") + [IO.File]::ReadAllText($UProjectPath)
            $configRefs = @{}
            foreach ($m in [regex]::Matches($configText, '/Game/[A-Za-z0-9_/\-\.]+')) { $configRefs[($m.Value -replace '\..*$', '')] = $true }
            $roots = 'World', 'ObjectRedirector', 'MapBuildDataRegistry', 'WorldPartitionHLOD'
            $unref = @($assets | Where-Object { $_.referencer_count -eq 0 -and $roots -notcontains $_.class -and -not $configRefs.ContainsKey($_.package) })
            $unrefBytes = ($unref | Measure-Object Bytes -Sum).Sum
            $unrefTop = $unref | Sort-Object Bytes -Descending | Select-Object -First $Top | ForEach-Object { [pscustomobject]@{ Package = $_.package; Class = $_.class; Size = (Format-Size $_.Bytes) } }
            Show-Table "Unreferenced candidates: $($unref.Count) assets, $(Format-Size $unrefBytes) (top $Top)" $unrefTop @('Package', 'Class', 'Size') 'unref' @{ count = $unref.Count; size = (Format-Size $unrefBytes); top = $Top }

            $big = @($assets | Where-Object { $_.dimensions -match '^(\d+)x(\d+)' -and [math]::Max([int]$Matches[1], [int]$Matches[2]) -gt $TextureLimit }) |
                Sort-Object Bytes -Descending | Select-Object -First $Top | ForEach-Object { [pscustomobject]@{ Package = $_.package; Dimensions = $_.dimensions; Size = (Format-Size $_.Bytes) } }
            Show-Table "Textures larger than $TextureLimit px (top $Top)" $big @('Package', 'Dimensions', 'Size') 'textures' @{ limit = $TextureLimit; top = $Top }

            $redirectors = @($assets | Where-Object { $_.class -eq 'ObjectRedirector' } | ForEach-Object { [pscustomobject]@{ Package = $_.package } })
            Show-Table "Redirectors ($($redirectors.Count))" $redirectors @('Package') 'redirectors' @{ count = $redirectors.Count }
            if ($redirectors.Count) { Write-Host '    fix in the editor: Content Browser > right-click the folder > Fix Up Redirectors' }
        }
    }
}

# ---------------------------------------------------------------------------------------------
$htmlReport = $Html -or ($Report -like '*.html')
if ($htmlReport) {
    Write-Step 'HTML report'
    $template = Join-Path $PSScriptRoot '..\assets\report.html'
    if (-not (Test-Path -LiteralPath $template)) { throw "HTML template not found: $template" }
    $htmlPath = if ($Report -like '*.html') { if ([IO.Path]::IsPathRooted($Report)) { $Report } else { Join-Path $ProjectRoot $Report } } else { Join-Path $ProjectRoot 'Saved\ContentAudit\content_audit.html' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $htmlPath) | Out-Null
    $data = [ordered]@{
        project    = $ProjectName
        date       = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        files      = $files.Count
        size       = (Format-Size $total)
        contentDir = $contentFull
        deep       = [bool]$Deep
        lang       = $Lang
        langForced = $PSBoundParameters.ContainsKey('Lang')   # an explicit -Lang wins over the language remembered by the page
        warnings   = @($Warnings)
        sections   = @($sections)
    }
    # "</" would end the <script> block the JSON is embedded in
    $json = ($data | ConvertTo-Json -Depth 8 -Compress).Replace('</', '<\/')
    $page = [IO.File]::ReadAllText($template, [Text.Encoding]::UTF8).Replace('__AUDIT_JSON__', $json)
    [IO.File]::WriteAllText($htmlPath, $page, (New-Object Text.UTF8Encoding($true)))
    Write-Host "  html report: $htmlPath"
    if ($Open) { Start-Process -FilePath $htmlPath }
}
if ($Report -and $Report -notlike '*.html') {
    $reportPath = if ([IO.Path]::IsPathRooted($Report)) { $Report } else { Join-Path $ProjectRoot $Report }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath) | Out-Null
    if ($Deep) { [void]$md.AppendLine('> Unreferenced = no package references it and it is not named in Config/*.ini. Assets loaded only by path strings in code or data tables also look unreferenced: check before deleting.') }
    [IO.File]::WriteAllText($reportPath, $md.ToString(), $Utf8NoBom)
    Write-Host ''; Write-Host "  report: $reportPath"
}

Write-FinalStep 'Content audit done'
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Timing
if ($FailOnIssues -and $script:validationErrors -gt 0) { exit 1 }
