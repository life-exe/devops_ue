# Copyright LifeEXE. All Rights Reserved.
# After create_project.ps1: optional Git LFS setup and the first commit (never pushes).
#   finalize_git.ps1 -ProjectDir C:\Projects\MyGame -UseLfs -Commit
#   finalize_git.ps1 -ProjectDir C:\Projects\MyGame -UseLfs                 # LFS only, commit later
#   finalize_git.ps1 -ProjectDir C:\Projects\MyGame -Commit -CommitLocalConfig
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    # track Unreal binary assets with Git LFS (.gitattributes); must happen before the first commit of those files
    [switch]$UseLfs,
    [switch]$Commit,
    [string]$Message = '',
    # commit devops_data\config.bat (local engine path) - fine for a solo project; otherwise it is git-ignored
    [switch]$CommitLocalConfig
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Warnings = New-Object System.Collections.ArrayList

# --- step timing (same as the other skill scripts) ---
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

# git writes progress to stderr: run it without PowerShell turning that into errors
function Invoke-Git([string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & git -C $ProjectDir @Arguments 2>&1 | ForEach-Object { "$_" }; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Code = $code; Output = @($out) }
}

# Unreal assets and typical source art / media
$LfsPatterns = @(
    '*.uasset', '*.umap', '*.ubulk', '*.uexp', '*.upk',
    '*.fbx', '*.obj', '*.abc', '*.blend', '*.max', '*.ma', '*.mb',
    '*.png', '*.jpg', '*.jpeg', '*.tga', '*.tif', '*.tiff', '*.bmp', '*.psd', '*.exr', '*.hdr', '*.dds',
    '*.wav', '*.mp3', '*.ogg', '*.flac', '*.bank',
    '*.mp4', '*.mov', '*.avi', '*.bk2',
    '*.ttf', '*.otf',
    '*.zip', '*.7z', '*.rar'
)

# ---------------------------------------------------------------------------------------------
Write-Step 'Repository'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is not installed' }
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir '.git'))) { throw "$ProjectDir is not a git repository (expected create_project.ps1 to run git init)" }
$uproject = Get-ChildItem -LiteralPath $ProjectDir -Filter '*.uproject' -File | Select-Object -First 1
$ProjectName = if ($uproject) { $uproject.BaseName } else { Split-Path -Leaf $ProjectDir }
$headRes = Invoke-Git @('rev-parse', '--verify', '--quiet', 'HEAD')
$hasCommits = $headRes.Code -eq 0
Write-Host "  $ProjectDir ($ProjectName), $(if ($hasCommits) { 'has commits' } else { 'no commits yet' })"

# ---------------------------------------------------------------------------------------------
$gitignore = Join-Path $ProjectDir '.gitignore'
if (-not $CommitLocalConfig) {
    Write-Step 'devops_data\config.bat stays local (git-ignored)'
    $text = if (Test-Path -LiteralPath $gitignore) { [IO.File]::ReadAllText($gitignore) } else { '' }
    if ($text -notmatch '(?m)^devops_data/config\.bat\s*$') {
        $text = $text.TrimEnd() + "`r`n# local paths (EnginePath, ...): every developer keeps their own copy`r`ndevops_data/config.bat`r`n"
        [IO.File]::WriteAllText($gitignore, $text.TrimStart(), $Utf8NoBom)
        Write-Host '  .gitignore += devops_data/config.bat'
    }
}

# ---------------------------------------------------------------------------------------------
if ($UseLfs) {
    Write-Step 'Git LFS'
    $lfs = Invoke-Git @('lfs', 'version')
    if ($lfs.Code -ne 0) { throw 'Git LFS is not installed: winget install --id GitHub.GitLFS -e  (then re-run with -UseLfs)' }
    Write-Host "  $($lfs.Output | Select-Object -First 1)"
    $r = Invoke-Git @('lfs', 'install', '--local')
    if ($r.Code -ne 0) { throw "git lfs install --local failed: $($r.Output -join ' ')" }
    $r = Invoke-Git (@('lfs', 'track') + $LfsPatterns)
    if ($r.Code -ne 0) { throw "git lfs track failed: $($r.Output -join ' ')" }
    Write-Host "  .gitattributes: $($LfsPatterns.Count) patterns (*.uasset, *.umap, textures, audio, video, fonts, archives)"
    if ($hasCommits) {
        $already = Invoke-Git @('ls-files', '--', '*.uasset', '*.umap')
        if ($already.Output.Count -gt 0) {
            Add-Warning "$($already.Output.Count) .uasset/.umap files are already committed without LFS; new commits use LFS, old history stays as is (git lfs migrate import rewrites history - only with the team's agreement)"
        }
    }
}

# ---------------------------------------------------------------------------------------------
if ($Commit) {
    Write-Step 'First commit'
    $name = (Invoke-Git @('config', 'user.name')).Output | Select-Object -First 1
    $email = (Invoke-Git @('config', 'user.email')).Output | Select-Object -First 1
    if (-not $name -or -not $email) {
        throw 'git user is not configured: git config --global user.name "Your Name"; git config --global user.email "you@example.com"'
    }
    Write-Host "  author: $name"

    $r = Invoke-Git @('add', '-A')
    if ($r.Code -ne 0) { throw "git add failed: $($r.Output -join ' ')" }
    $staged = @((Invoke-Git @('diff', '--cached', '--name-only')).Output | Where-Object { $_ })
    if ($staged.Count -eq 0) { Add-Warning 'Nothing to commit' }
    else {
        if (-not $UseLfs) {
            # GitHub rejects files over 100 MB without LFS
            $big = foreach ($f in $staged) {
                $p = Join-Path $ProjectDir $f
                if ((Test-Path -LiteralPath $p -PathType Leaf) -and (Get-Item -LiteralPath $p).Length -gt 50MB) { $f }
            }
            if ($big) { Add-Warning "Files over 50 MB committed without LFS (GitHub rejects >100 MB): $($big -join ', ')" }
        }
        if (-not $Message) {
            $Message = if ($hasCommits) { "Set up $ProjectName project" } else { "Initial $ProjectName project" }
        }
        $r = Invoke-Git @('commit', '-q', '-m', $Message)
        if ($r.Code -ne 0) { throw "git commit failed: $($r.Output -join ' ')" }
        $hash = ((Invoke-Git @('rev-parse', '--short', 'HEAD')).Output | Select-Object -First 1)
        Write-Host "  commit $hash '$Message': $($staged.Count) files"
        if ($UseLfs) {
            $lfsFiles = @((Invoke-Git @('lfs', 'ls-files')).Output | Where-Object { $_ })
            Write-Host "  in LFS: $($lfsFiles.Count) files"
        }
        Write-Host '  not pushed (add a remote and push yourself, e.g. gh repo create --private --source . --push)'
    }
}

# ---------------------------------------------------------------------------------------------
Write-FinalStep 'Done'
$status = @((Invoke-Git @('status', '--short')).Output | Where-Object { $_ })
Write-Host "  uncommitted changes: $($status.Count)"
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}

Write-Timing
