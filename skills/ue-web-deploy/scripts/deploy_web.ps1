# Copyright LifeEXE. All Rights Reserved.
# Deploys a packaged Unreal Wasm (web) build to itch.io (butler), Vercel or a GitHub release.
#   deploy_web.ps1 -ProjectPath C:\Projects\MyGame -Target itch -ItchTarget user/my-game
#   deploy_web.ps1 -ProjectPath C:\Projects\MyGame -Target vercel -VercelProject my-game -Prod
#   deploy_web.ps1 -ProjectPath C:\Projects\MyGame -Target github -GitHubTag web-1.0
#   add -DryRun to prepare and check everything without uploading
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [Parameter(Mandatory)][ValidateSet('itch', 'vercel', 'github')][string]$Target,
    # staged Wasm folder (the one with index.html); autodetected under <project>\Build when empty
    [string]$Stage = '',
    [string]$EnginePath = '',
    # itch.io
    [string]$ItchTarget = '',
    [string]$ItchChannel = 'html5',
    [string]$Version = '',
    # Vercel
    [string]$VercelProject = '',
    [string]$VercelScope = '',
    [switch]$Prod,
    # GitHub
    [string]$GitHubTag = '',
    [string]$GitHubRepo = '',
    [switch]$AllowDevelopment,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Warnings = New-Object System.Collections.ArrayList

function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Add-Warning([string]$Text) { [void]$Warnings.Add($Text); Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Format-Size([double]$Bytes) { if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) } else { '{0:N1} MB' -f ($Bytes / 1MB) } }
function Invoke-Capture([string]$File, [string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $File @Arguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable lines | Out-Host; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
    return @($code, ($lines -join "`n"))
}
function Show-Command([string]$File, [string[]]$Arguments) {
    Write-Host ("  > {0} {1}" -f $File, (($Arguments | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '))
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project, engine and stage'

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
$ProjectName = if ($uprojectFile) { $uprojectFile.BaseName } else { Split-Path -Leaf $ProjectRoot }

if (-not $EnginePath) {
    $configBat = Join-Path $ProjectRoot 'devops_data\config.bat'
    if (Test-Path -LiteralPath $configBat) {
        $EnginePath = ([IO.File]::ReadAllLines($configBat) | Where-Object { $_ -match '^set EnginePath=(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
    }
}
$WasmTools = if ($EnginePath) { Join-Path $EnginePath 'Engine\Platforms\Wasm\Build\Tools' } else { '' }
$EnginePython = if ($EnginePath) { Join-Path $EnginePath 'Engine\Binaries\ThirdParty\Python3\Win64\python.exe' } else { '' }
if (-not $WasmTools -or -not (Test-Path -LiteralPath $WasmTools)) { Add-Warning 'Engine Wasm tools not found (pass -EnginePath): stage checks are skipped'; $WasmTools = '' }

if (-not $Stage) {
    $candidates = @('Build\Wasm\Wasm', 'Build\Wasm', 'Saved\StagedBuilds\Wasm') | ForEach-Object { Join-Path $ProjectRoot $_ } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ 'index.html') }
    # priority order: archived build (package_wasm.bat / -archive) first, then the raw stage
    $Stage = $candidates | Select-Object -First 1
}
if (-not $Stage -or -not (Test-Path -LiteralPath (Join-Path $Stage 'index.html'))) {
    throw 'Packaged Wasm stage (folder with index.html) not found. Package first: package_wasm.bat Shipping, or pass -Stage.'
}
$Stage = (Resolve-Path -LiteralPath $Stage).Path
$stageTime = (Get-Item -LiteralPath (Join-Path $Stage 'index.html')).LastWriteTime
Write-Host "Project: $ProjectRoot"
Write-Host "Stage  : $Stage (packaged $stageTime)"

# UAT writes ue-query-args "all" in Development stages and "safe" in Test/Shipping (unless QueryArgs is overridden)
$indexHtml = [IO.File]::ReadAllText((Join-Path $Stage 'index.html'))
$queryArgs = ([regex]::Match($indexHtml, '<meta name="ue-query-args" content="([^"]*)"')).Groups[1].Value
if ($queryArgs -eq 'all') {
    if ($AllowDevelopment) { Add-Warning 'Development build (ue-query-args=all): fine for a private test, not for public release' }
    else { throw 'This looks like a Development build (ue-query-args=all: links can pass any engine arguments). Package Shipping (package_wasm.bat Shipping) or pass -AllowDevelopment for a private test.' }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'check_stage.py (manifests, sha1, debug files, release scan)'
if ($WasmTools) {
    & $EnginePython -I (Join-Path $WasmTools 'deploy\check_stage.py') $Stage
    if ($LASTEXITCODE -ne 0) {
        if ($AllowDevelopment) { Add-Warning 'check_stage.py failed (allowed by -AllowDevelopment: not for public release)' }
        else { throw 'check_stage.py failed: package with -clientconfig=Shipping (package_wasm.bat Shipping) or pass -AllowDevelopment for a private test.' }
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step "Preparing upload folder for $Target"

$deployRoot = Join-Path $ProjectRoot "Saved\WebDeploy\$Target"
$site = Join-Path $deployRoot 'site'
New-Item -ItemType Directory -Force -Path $site | Out-Null
# hosts.json excludes + .br siblings (itch/Vercel/GitHub don't serve them with Content-Encoding: br)
$exclude = @('*.br', 'Manifest_*.txt', '*.js.symbols', '*.pdb', '*.sym', '*.debug.wasm', '*.bat', '*.sh', 'build-stamp.json', '*.tmp', 'vercel.json')
$robo = @($Stage, $site, '/MIR', '/XD', '.vercel', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XF') + $exclude
& robocopy @robo | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }

$files = @(Get-ChildItem -LiteralPath $site -Recurse -File -Force | Where-Object { $_.FullName -notlike "*\.vercel\*" })
$total = ($files | Measure-Object Length -Sum).Sum
$largest = $files | Sort-Object Length -Descending | Select-Object -First 1
Write-Host "  $($files.Count) files, $(Format-Size $total), largest $($largest.Name) $(Format-Size $largest.Length)"

switch ($Target) {
    'itch' {
        # itch.io HTML game limits (verify on https://itch.io/docs/creators/html5 if a warning shows)
        if ($files.Count -gt 1000) { Add-Warning 'itch.io HTML games allow up to 1000 files' }
        if ($largest.Length -gt 200MB) { Add-Warning 'itch.io HTML games limit a single file to ~200 MB' }
        if ($total -gt 500MB) { Add-Warning 'itch.io HTML games limit the extracted size to ~500 MB (can be raised by itch support)' }
    }
    'vercel' {
        if ($largest.Length -gt 100MB) { Add-Warning "$($largest.Name) is over 100 MB: it may exceed Vercel's per-file upload limit for your plan" }
    }
    'github' {
        if ($total -gt 2GB) { Add-Warning 'GitHub release assets are limited to 2 GB each' }
    }
}

# ---------------------------------------------------------------------------------------------
switch ($Target) {
    'itch' {
        Write-Step 'itch.io (butler push)'
        if (-not $ItchTarget) { throw '-ItchTarget <user>/<game> is required (the game page must exist on itch.io: itch.io/game/new, Kind of project: HTML)' }
        $butler = (Get-Command butler -ErrorAction SilentlyContinue).Source
        if (-not $butler) { $b = Join-Path $env:LOCALAPPDATA 'itch-butler\butler.exe'; if (Test-Path -LiteralPath $b) { $butler = $b } }
        if (-not $butler) { throw 'butler not found: run install_tools.ps1 -Tools butler' }
        $cmdArgs = @('push', $site, "${ItchTarget}:$ItchChannel")
        if ($Version) { $cmdArgs += @('--userversion', $Version) }
        Show-Command 'butler' $cmdArgs
        if (-not $DryRun) {
            $r = Invoke-Capture $butler $cmdArgs
            if ($r[0] -ne 0) { throw "butler push failed (code $($r[0])). Not logged in? Run: butler login" }
            Invoke-Capture $butler @('status', "${ItchTarget}:$ItchChannel") | Out-Null
        }
        Write-Host ''
        Write-Host 'On the itch.io game page (Edit game) once:' -ForegroundColor Yellow
        Write-Host "  - Kind of project: HTML; mark the '$ItchChannel' upload 'This file will be played in the browser'" -ForegroundColor Yellow
        Write-Host '  - Embed options: SharedArrayBuffer support = ON (required for Wasm threads), save and check it stayed on' -ForegroundColor Yellow
        Write-Host '  - Viewport e.g. 1280x720, enable Fullscreen button' -ForegroundColor Yellow
        $user, $game = $ItchTarget -split '/', 2
        Write-Host "Page: https://$user.itch.io/$game"
    }

    'vercel' {
        Write-Step 'Vercel'
        if (-not (Get-Command vercel -ErrorAction SilentlyContinue)) { throw 'vercel CLI not found: run install_tools.ps1 -Tools vercel' }
        # cross-origin isolation for Wasm threads + revalidation (sw.js versions files by sha1); engine netlify.toml/_headers equivalent
        $vercelJson = [ordered]@{
            '$schema'     = 'https://openapi.vercel.sh/vercel.json'
            cleanUrls     = $false
            trailingSlash = $false
            headers       = @(
                [ordered]@{ source = '/(.*)'; headers = @(
                        @{ key = 'Cross-Origin-Opener-Policy'; value = 'same-origin' },
                        @{ key = 'Cross-Origin-Embedder-Policy'; value = 'require-corp' },
                        @{ key = 'Cross-Origin-Resource-Policy'; value = 'same-origin' },
                        @{ key = 'Cache-Control'; value = 'no-cache' },
                        @{ key = 'X-Content-Type-Options'; value = 'nosniff' }) },
                [ordered]@{ source = '/(.*)\.wasm'; headers = @(@{ key = 'Content-Type'; value = 'application/wasm' }) },
                [ordered]@{ source = '/(.*)\.(ucas|utoc|pak)'; headers = @(@{ key = 'Content-Type'; value = 'application/octet-stream' }) }
            )
        }
        [IO.File]::WriteAllText((Join-Path $site 'vercel.json'), ($vercelJson | ConvertTo-Json -Depth 6), $Utf8NoBom)
        Write-Host '  vercel.json written (COOP/COEP/CORP, no-cache, wasm MIME)'

        if (-not $VercelProject) { $VercelProject = ($ProjectName.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-') }
        $scopeArgs = if ($VercelScope) { @('--scope', $VercelScope) } else { @() }
        if (-not (Test-Path -LiteralPath (Join-Path $site '.vercel\project.json'))) {
            $linkArgs = @('link', '--yes', '--cwd', $site, '--project', $VercelProject) + $scopeArgs
            Show-Command 'vercel' $linkArgs
            if (-not $DryRun) {
                $r = Invoke-Capture 'vercel' $linkArgs
                if ($r[0] -ne 0) { throw "vercel link failed (code $($r[0])). Not logged in? Run: vercel login" }
            }
        }
        $deployArgs = @('deploy', '--cwd', $site, '--yes') + $scopeArgs
        if ($Prod) { $deployArgs += '--prod' }
        Show-Command 'vercel' $deployArgs
        if (-not $DryRun) {
            $r = Invoke-Capture 'vercel' $deployArgs
            if ($r[0] -ne 0) { throw "vercel deploy failed (code $($r[0]))" }
            $url = ([regex]::Matches($r[1], 'https://[^\s]+\.vercel\.app') | Select-Object -Last 1).Value
            if ($url) {
                Write-Host "URL: $url"
                if ($WasmTools) {
                    Write-Step 'webdoctor.py (headers, MIME, ranges, isolation - read-only)'
                    & $EnginePython -I (Join-Path $WasmTools 'deploy\webdoctor.py') "$url/"
                    if ($LASTEXITCODE -ne 0) { Add-Warning 'webdoctor.py reported problems (preview deployments may be behind Vercel Authentication: check the URL in a browser or deploy with -Prod)' }
                }
            }
        }
    }

    'github' {
        Write-Step 'GitHub release'
        $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
        if (-not $gh) { throw 'gh not found: run install_tools.ps1 -Tools gh' }
        if (-not $GitHubTag) { $GitHubTag = 'web-' + (Get-Date -Format 'yyyyMMdd-HHmm') }
        $zip = Join-Path $deployRoot "$ProjectName-$GitHubTag.zip"
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        Write-Host "  zipping -> $zip"
        Compress-Archive -Path (Join-Path $site '*') -DestinationPath $zip -CompressionLevel Optimal
        $repoArgs = if ($GitHubRepo) { @('--repo', $GitHubRepo) } else { @() }
        $notes = "Web (Wasm) build of $ProjectName. Unzip and serve with run_wasm.bat / serve.py (COOP/COEP headers required, file:// does not work)."
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        Push-Location $ProjectRoot
        try {
            & $gh release view $GitHubTag @repoArgs *> $null
            $exists = $LASTEXITCODE -eq 0
            $cmdArgs = if ($exists) { @('release', 'upload', $GitHubTag, $zip, '--clobber') + $repoArgs }
            else { @('release', 'create', $GitHubTag, $zip, '--title', "$ProjectName web $GitHubTag", '--notes', $notes) + $repoArgs }
            Show-Command 'gh' $cmdArgs
            if (-not $DryRun) {
                & $gh @args
                if ($LASTEXITCODE -ne 0) { throw "gh release failed (code $LASTEXITCODE). Not logged in? Run: gh auth login" }
                & $gh release view $GitHubTag @repoArgs --json url --jq .url
            }
        }
        finally { Pop-Location; $ErrorActionPreference = $prev }
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step $(if ($DryRun) { 'Dry run finished (nothing uploaded)' } else { 'Done' })
Write-Host "Upload folder: $site"
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
