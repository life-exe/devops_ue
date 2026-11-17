# Copyright LifeEXE. All Rights Reserved.
# Formats the project's C++ / C# sources with clang-format (the project's .clang-format) and reports what changed.
#   format.ps1 -ProjectPath C:\Game                    # Source\**\*.cpp,*.h,*.cs - only files that really change are rewritten
#   format.ps1 -ProjectPath C:\Game -Check             # nothing is written, lists unformatted files, exit code 1 if any (CI / pre-commit)
#   format.ps1 -ProjectPath C:\Game -Changed           # only files changed in git (modified + untracked)
#   format.ps1 -ProjectPath C:\Game -IncludePlugins    # + Plugins\*\Source (plugins with sources)
#   format.ps1 -ProjectPath C:\Game -Path Source\Game\Weapon,Source\Game\Player\PlayerCharacter.cpp
# Same file set as devops_ue\misc\format_all_files.bat (SourceCodePath), but a file is rewritten only when it differs,
# so untouched files keep their timestamps (no needless rebuilds).
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [switch]$Check,
    [switch]$Changed,
    [switch]$IncludePlugins,
    # files or folders (relative to the project root) to format instead of the whole Source
    [string[]]$Path = @(),
    [string]$ClangFormat = ''
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

# ---------------------------------------------------------------------------------------------
Write-Step 'Project'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
Write-Host "  $($uprojectFile.FullName)"

$styleFile = Join-Path $ProjectRoot '.clang-format'
if (-not (Test-Path -LiteralPath $styleFile)) {
    throw "No .clang-format in ${ProjectRoot}: without it clang-format falls back to LLVM style. Copy devops_ue\setup\.clang-format.template to .clang-format"
}

if (-not $ClangFormat) {
    $cmd = Get-Command clang-format -ErrorAction SilentlyContinue
    if ($cmd) { $ClangFormat = $cmd.Source }
}
if (-not $ClangFormat -or -not (Test-Path -LiteralPath $ClangFormat)) { throw 'clang-format not found: run ue-install-env -Tools clang-format (or winget install LLVM.LLVM)' }
$cfVersion = (& $ClangFormat --version) -join ' '
Write-Host "  $cfVersion"

# ---------------------------------------------------------------------------------------------
Write-Step 'Collecting files'
$extensions = '.cpp', '.h', '.cs', '.hpp', '.inl'
$roots = @()
if ($Path.Count -gt 0) {
    foreach ($p in @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
        $full = if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ProjectRoot $p }
        if (-not (Test-Path -LiteralPath $full)) { throw "Path not found: $full" }
        $roots += (Resolve-Path -LiteralPath $full).Path
    }
}
else {
    $src = Join-Path $ProjectRoot 'Source'
    if (-not (Test-Path -LiteralPath $src)) { throw "No Source folder in $ProjectRoot (Blueprint-only project: nothing to format)" }
    $roots += $src
    if ($IncludePlugins) {
        foreach ($plugin in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Plugins') -Directory -ErrorAction SilentlyContinue) {
            $ps = Join-Path $plugin.FullName 'Source'
            if (Test-Path -LiteralPath $ps) { $roots += $ps }
        }
    }
}

$files = @()
foreach ($r in $roots) {
    $item = Get-Item -LiteralPath $r
    if ($item.PSIsContainer) { $files += Get-ChildItem -LiteralPath $r -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } | ForEach-Object FullName }
    elseif ($extensions -contains $item.Extension.ToLowerInvariant()) { $files += $item.FullName }
}
# third party code and generated files are not ours to format
$files = @($files | Where-Object { $_ -notmatch '\\(ThirdParty|Intermediate|Binaries)\\' -and $_ -notmatch '\.generated\.h$' } | Sort-Object -Unique)

if ($Changed) {
    $names = @()
    & git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '-Changed needs a git repository' }
    $names += @(& git -C $ProjectRoot diff --name-only --relative HEAD 2>$null)
    $names += @(& git -C $ProjectRoot ls-files --others --exclude-standard)
    $changedSet = @{}
    foreach ($n in $names) { if ($n) { $changedSet[(Join-Path $ProjectRoot ($n -replace '/', '\')).ToLowerInvariant()] = $true } }
    $files = @($files | Where-Object { $changedSet.ContainsKey($_.ToLowerInvariant()) })
}
Write-Host "  $($files.Count) file(s)"
if ($files.Count -eq 0) { Write-FinalStep 'Nothing to format'; Write-Timing; exit 0 }

# ---------------------------------------------------------------------------------------------
Write-Step 'Checking'
$listFile = Join-Path $env:TEMP "ue-format-$PID.txt"
[IO.File]::WriteAllLines($listFile, $files, (New-Object System.Text.UTF8Encoding($false)))
try {
    # --dry-run --Werror prints "<file>:<line>:<col>: error: code should be clang-formatted" for each violation (stderr merged by cmd)
    $out = cmd.exe /d /c "`"$ClangFormat`" --dry-run --Werror --style=file --files=`"$listFile`" 2>&1"
}
finally { Remove-Item -LiteralPath $listFile -Force -ErrorAction SilentlyContinue }

$dirty = @{}
$other = New-Object System.Collections.ArrayList
foreach ($line in @($out)) {
    if ($line -match '^(.+?\.(?:cpp|h|cs|hpp|inl)):\d+:\d+:\s*(?:error|warning):.*clang-format') { $dirty[$Matches[1]] = $true }
    elseif ($line -match 'error:|Error') { [void]$other.Add($line) }
}
foreach ($o in ($other | Select-Object -First 10)) { Add-Warning "clang-format: $o" }
$dirtyFiles = @($dirty.Keys | Sort-Object)
Write-Host "  $($dirtyFiles.Count) of $($files.Count) file(s) need formatting"

if ($Check) {
    $dirtyFiles | ForEach-Object { Write-Host "  would reformat $($_.Replace($ProjectRoot + '\', ''))" -ForegroundColor Yellow }
    Write-FinalStep $(if ($dirtyFiles.Count) { "FAILED: $($dirtyFiles.Count) unformatted file(s) - run ue-format without -Check" } else { 'All files are formatted' })
    Write-Timing
    exit $(if ($dirtyFiles.Count) { 1 } else { 0 })
}

# ---------------------------------------------------------------------------------------------
if ($dirtyFiles.Count -gt 0) {
    Write-Step 'Formatting'
    foreach ($f in $dirtyFiles) {
        & $ClangFormat -i --style=file $f
        if ($LASTEXITCODE -ne 0) { Add-Warning "clang-format failed on $f" }
        else { Write-Host "  formatted $($f.Replace($ProjectRoot + '\', ''))" }
    }
}

Write-FinalStep "Done: $($dirtyFiles.Count) formatted, $($files.Count - $dirtyFiles.Count) already clean"
if ($Warnings.Count -gt 0) { Write-Host "  $($Warnings.Count) warning(s)" -ForegroundColor Yellow }
Write-Timing
