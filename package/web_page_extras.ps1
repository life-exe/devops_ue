# Copyright LifeEXE. All Rights Reserved.
# Project additions to a packaged web (Wasm) page, kept outside the engine template so an engine update never drops them:
#   <ExtrasDir>\head.html  - inserted before </head> of index.html (meta description, OpenGraph / Twitter tags, ...)
#   <ExtrasDir>\public\*   - copied next to index.html (og-image.jpg, ...)
# Idempotent: a page that already has the block gets it replaced, not duplicated.
param(
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][string]$ExtrasDir
)
$ErrorActionPreference = 'Stop'

$index = Join-Path $Stage 'index.html'
if (-not (Test-Path $index)) { Write-Host "web extras: no index.html in $Stage, skipped"; exit 0 }

$head = Join-Path $ExtrasDir 'head.html'
if (Test-Path $head) {
    $begin = '<!-- project-head:begin -->'
    $end = '<!-- project-head:end -->'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $page = [IO.File]::ReadAllText($index, $utf8)
    $page = [regex]::Replace($page, '(?s)\r?\n?' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end), '')
    $block = $begin + "`n" + [IO.File]::ReadAllText($head, $utf8).Trim() + "`n" + $end + "`n"
    $at = $page.IndexOf('</head>')
    if ($at -lt 0) { throw "web extras: </head> not found in $index" }
    $page = $page.Insert($at, $block)
    [IO.File]::WriteAllText($index, $page, $utf8)
    Write-Host "web extras: head.html inserted into $index"
    # the packaged index.html.br is stale now; like the engine's update_stage_binaries.py, drop it (hosts serve index.html)
    if (Test-Path "$index.br") { Remove-Item "$index.br" -Force; Write-Host 'web extras: stale index.html.br removed' }
}

$public = Join-Path $ExtrasDir 'public'
if (Test-Path $public) {
    Get-ChildItem $public -Force | ForEach-Object {
        Copy-Item $_.FullName -Destination $Stage -Recurse -Force
        Write-Host "web extras: $($_.Name) copied to $Stage"
    }
}
