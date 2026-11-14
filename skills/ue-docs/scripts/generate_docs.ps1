# Copyright LifeEXE. All Rights Reserved.
# Generates Doxygen documentation for an Unreal project (devops_data\Doxyfile + devops_ue\docs themes/filter).
#   generate_docs.ps1 -ProjectPath C:\Game [-Title "My Game"] [-Version 1.2.0] [-Open]
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [string]$Title = '',
    [string]$Version = '',
    [switch]$Open,
    [string]$Doxygen = ''
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

# ---------------------------------------------------------------------------------------------
Write-Step 'Project and tools'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$ProjectName = $uprojectFile.BaseName
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'Source'))) { throw 'No Source folder: Doxygen documents C++ code (Blueprint-only project?)' }

if (-not $Doxygen) {
    $Doxygen = (Get-Command doxygen -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $Doxygen -and (Test-Path 'C:\Program Files\doxygen\bin\doxygen.exe')) { $Doxygen = 'C:\Program Files\doxygen\bin\doxygen.exe' }
}
if (-not $Doxygen) { throw 'Doxygen not found: winget install --id DimitriVanHeesch.Doxygen -e (or ue-install-env -Tools doxygen)' }
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$doxVer = (& $Doxygen --version 2>$null | Select-Object -First 1)
$ErrorActionPreference = $prev
Write-Host "  doxygen $doxVer ($Doxygen)"

# the UE macro filter is a Python script; the Doxyfile template calls it with "py", which isn't always installed
$python = ''
foreach ($cand in 'python', 'py') {
    $c = (Get-Command $cand -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($c -and $c -notmatch 'WindowsApps') { $python = $c; break }
}
$devopsUe = Join-Path $ProjectRoot 'devops_ue'
if (-not $python) {
    $cfg = Join-Path $ProjectRoot 'devops_data\config.bat'
    $engine = if (Test-Path -LiteralPath $cfg) { [IO.File]::ReadAllLines($cfg) | Where-Object { $_ -match '^set EnginePath=(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1 } else { '' }
    $ep = if ($engine) { Join-Path $engine 'Engine\Binaries\ThirdParty\Python3\Win64\python.exe' } else { '' }
    if ($ep -and (Test-Path -LiteralPath $ep)) { $python = $ep }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Doxyfile'
$doxyfile = Join-Path $ProjectRoot 'devops_data\Doxyfile'
if (-not (Test-Path -LiteralPath $doxyfile)) {
    $tpl = Join-Path $devopsUe 'setup\Doxyfile.template'
    if (-not (Test-Path -LiteralPath $tpl)) { throw "No devops_data\Doxyfile and no $tpl" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $doxyfile) | Out-Null
    Copy-Item -LiteralPath $tpl -Destination $doxyfile
    Write-Host '  devops_data\Doxyfile created from the template (commit it if you customize it)'
}
$base = [IO.File]::ReadAllText($doxyfile)
function Get-DoxValue([string]$Key) { ([regex]::Match($base, "(?m)^$Key\s*=\s*(.*)$")).Groups[1].Value.Trim() }

# theme submodules (devops_ue\docs\Doxygen-*-Theme, Unreal-Engine-Doxygen-Filter)
$docsDir = Join-Path $devopsUe 'docs'
$needed = @('Doxygen-Flat-Theme\src\doxygen-style.css', 'Doxygen-Dark-Theme\html_footer.html', 'Unreal-Engine-Doxygen-Filter')
$missing = @($needed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $docsDir $_)) -or ((Test-Path -LiteralPath (Join-Path $docsDir $_) -PathType Container) -and -not (Get-ChildItem -LiteralPath (Join-Path $docsDir $_) -Force | Select-Object -First 1)) })
if ($missing.Count -and (Test-Path -LiteralPath (Join-Path $devopsUe '.git'))) {
    Write-Host '  fetching the docs submodules of devops_ue (themes, UE macro filter)'
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & git -C $devopsUe submodule update --init --recursive 2>&1 | ForEach-Object { "  $_" } | Out-Host
    $ErrorActionPreference = $prev
    $missing = @($needed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $docsDir $_)) })
}

# overrides for this run only - the user's Doxyfile stays as it is
$over = [ordered]@{}
$projName = Get-DoxValue 'PROJECT_NAME'
if ($Title) { $over['PROJECT_NAME'] = "`"$Title`"" } elseif ($projName -eq '"My Project"' -or -not $projName) { $over['PROJECT_NAME'] = "`"$ProjectName`"" }
if ($Version) { $over['PROJECT_NUMBER'] = $Version }
$filterScript = Join-Path $docsDir 'Unreal-Engine-Doxygen-Filter\filter_ue4_macros.py'
if ((Test-Path -LiteralPath $filterScript) -and $python) {
    $over['INPUT_FILTER'] = "`"$($python.Replace('\', '/'))`" devops_ue/docs/Unreal-Engine-Doxygen-Filter/filter_ue4_macros.py"
}
else {
    $over['INPUT_FILTER'] = ''
    Add-Warning "UE macro filter disabled ($(if (-not $python) { 'no Python found' } else { 'filter script missing' })): UCLASS/UPROPERTY macros may confuse Doxygen"
}
if ($missing | Where-Object { $_ -like 'Doxygen-*' }) {
    $over['HTML_FOOTER'] = ''; $over['HTML_EXTRA_STYLESHEET'] = ''; $over['HTML_EXTRA_FILES'] = ''; $over['HTML_HEADER'] = ''
    Add-Warning 'Doxygen themes not available (devops_ue docs submodules): default Doxygen look'
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'README.md'))) { $over['INPUT'] = 'Source'; $over['USE_MDFILE_AS_MAINPAGE'] = '' }
$warnLog = Join-Path $ProjectRoot 'Saved\Docs\doxygen_warnings.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $warnLog) | Out-Null
$over['WARN_LOGFILE'] = "`"$($warnLog.Replace('\', '/'))`""

$effective = $base.TrimEnd() + "`r`n`r`n# --- overrides by ue-docs (generate_docs.ps1) ---`r`n" + (($over.Keys | ForEach-Object { "$_ = $($over[$_])" }) -join "`r`n") + "`r`n"
$effectiveFile = Join-Path $ProjectRoot 'Saved\Docs\Doxyfile.effective'
[IO.File]::WriteAllText($effectiveFile, $effective, $Utf8NoBom)
$over.Keys | ForEach-Object { Write-Host "  $_ = $($over[$_])" }

# ---------------------------------------------------------------------------------------------
Write-Step 'doxygen'
$outRel = (Get-DoxValue 'OUTPUT_DIRECTORY').Trim('"'); if (-not $outRel) { $outRel = 'Documentation' }
$outDir = if ([IO.Path]::IsPathRooted($outRel)) { $outRel } else { Join-Path $ProjectRoot $outRel }
if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
$logFile = Join-Path $ProjectRoot 'Saved\Docs\doxygen.log'
$p = Start-Process -FilePath $Doxygen -ArgumentList "`"$effectiveFile`"" -WorkingDirectory $ProjectRoot -NoNewWindow -Wait -PassThru -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"
$code = $p.ExitCode
$index = Join-Path $outDir 'html\index.html'

# ---------------------------------------------------------------------------------------------
Write-Step 'Result'
$warnLines = @(); if (Test-Path -LiteralPath $warnLog) { $warnLines = @([IO.File]::ReadAllLines($warnLog) | Where-Object { $_ -match 'warning:' }) }
if ($code -ne 0 -or -not (Test-Path -LiteralPath $index)) {
    Get-Content -LiteralPath "$logFile.err" -ErrorAction SilentlyContinue | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" }
    throw "doxygen failed (code $code), see $logFile"
}
$pages = @(Get-ChildItem -LiteralPath (Join-Path $outDir 'html') -Filter '*.html' -File).Count
Write-Host "  $index ($pages pages)" -ForegroundColor Green
Write-Host "  doxygen warnings: $($warnLines.Count)$(if ($warnLines.Count) { " -> $warnLog" })"
$warnLines | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
if ($Open) { Start-Process $index }

Write-FinalStep 'Documentation ready'
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Timing
