# Copyright LifeEXE. All Rights Reserved.
# Compares installed Claude Code skills with devops_ue\skills (SHA256 of every file, devops_source.txt ignored).
#   check_skills.ps1                       # user copies + copies of the project that holds this devops_ue
#   check_skills.ps1 -ProjectDir C:\Game   # another project
# Exit code 1 when an installed copy differs (stale), 0 otherwise.
[CmdletBinding()]
param([string]$ProjectDir = '')

$ErrorActionPreference = 'Stop'
$skillsSrc = $PSScriptRoot
if (-not $ProjectDir) { $ProjectDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }

function Get-SkillFileHashes([string]$Dir) {
    $root = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\')
    $map = @{}
    foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        if ($f.Name -eq 'devops_source.txt' -or $f.FullName -match '\\__pycache__\\') { continue }
        $map[$f.FullName.Substring($root.Length + 1)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    return $map
}

$locations = @(
    @{ Name = 'user'; Dir = Join-Path $env:USERPROFILE '.claude\skills' },
    @{ Name = 'project'; Dir = Join-Path $ProjectDir '.claude\skills' }
)

$stale = 0
$rows = foreach ($skill in Get-ChildItem -LiteralPath $skillsSrc -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }) {
    $srcHashes = Get-SkillFileHashes $skill.FullName
    foreach ($loc in $locations) {
        $dst = Join-Path $loc.Dir $skill.Name
        if (-not (Test-Path -LiteralPath $dst)) { continue }
        $dstHashes = Get-SkillFileHashes $dst
        $changed = @($srcHashes.Keys | Where-Object { $dstHashes.ContainsKey($_) -and $dstHashes[$_] -ne $srcHashes[$_] })
        $missing = @($srcHashes.Keys | Where-Object { -not $dstHashes.ContainsKey($_) })
        $extra = @($dstHashes.Keys | Where-Object { -not $srcHashes.ContainsKey($_) })
        $ok = ($changed.Count + $missing.Count + $extra.Count) -eq 0
        if (-not $ok) { $stale++ }
        $details = @()
        if ($changed) { $details += "changed: $($changed -join ', ')" }
        if ($missing) { $details += "missing: $($missing -join ', ')" }
        if ($extra) { $details += "extra: $($extra -join ', ')" }
        [pscustomobject]@{ Skill = $skill.Name; Where = $loc.Name; State = $(if ($ok) { 'same' } else { 'STALE' }); Details = ($details -join '; '); Path = $dst }
    }
}

if (-not $rows) { Write-Host 'No installed copies of devops_ue skills found.'; exit 0 }
$rows | Format-Table Skill, Where, State, Details -AutoSize -Wrap | Out-String -Width 220 | Write-Host
if ($stale -gt 0) {
    Write-Host "WARNING: $stale installed skill copies differ from $skillsSrc." -ForegroundColor Yellow
    Write-Host '  Reinstall: devops_ue\skills\install_skills.bat global|project' -ForegroundColor Yellow
    exit 1
}
Write-Host "All installed copies match $skillsSrc." -ForegroundColor Green
exit 0
