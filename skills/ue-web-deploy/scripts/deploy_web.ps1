# Copyright LifeEXE. All Rights Reserved.
# Deploys a packaged Unreal Wasm (web) build to itch.io (butler), Vercel or a GitHub release.
#   deploy_web.ps1 -ProjectPath C:\Projects\MyGame -Target itch -ItchTarget user/my-game
#   deploy_web.ps1 -ProjectPath C:\Projects\MyGame -Target vercel -VercelProject my-game -Prod
#   deploy_web.ps1 -ProjectPath C:\Projects\MyGame -Target github -GitHubTag web-1.0
#   deploy_web.ps1 -ProjectPath C:\Projects\MyGame -Target zip [-Prefix v1] [-TestZip]   # zip for portals, no upload
#   add -DryRun to prepare and check everything without uploading
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [Parameter(Mandatory)][ValidateSet('itch', 'vercel', 'github', 'zip')][string]$Target,
    # zip / github: deploy id; default: short HEAD commit, or v<N> when the repo has no commits
    [string]$Prefix = '',
    # zip / github: extract the archive to a short path and run the engine boot test on it (needs Playwright)
    [switch]$TestZip,
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
    # after a Vercel deploy: run the engine boot test (webrun.py --url) on the live URL (needs Playwright)
    [switch]$TestDeploy,
    # Vercel: link preview (OpenGraph / Twitter card) - image copied as og.<ext>, meta tags added to the uploaded
    # index.html (the stage is not changed). og:image must be absolute: -SiteUrl, else https://<project>.vercel.app (-Prod)
    [string]$OgImage = '',
    [string]$OgTitle = '',
    [string]$OgDescription = '',
    [string]$SiteUrl = '',
    # with -OgImage: also write devops_data\web\head.html + public\og.<ext>, added to every later web package
    [switch]$OgSave,
    # GitHub
    [string]$GitHubTag = '',
    [string]$GitHubRepo = '',
    [switch]$AllowDevelopment,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Warnings = New-Object System.Collections.ArrayList

# --- step timing: every Write-Step starts a timed step, Write-Timing prints the table (also on failure) ---
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
# final header: closes the last step without starting a new timed one
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

# SHA256 that ignores CRLF/LF differences in text files (core.autocrlf differs between machines)
function Get-ContentHash([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ([Array]::IndexOf($bytes, [byte]0) -lt 0) { $bytes = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n")) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') } finally { $sha.Dispose() }
}
# warns when this copy of the skill (user/project install) differs from devops_ue\skills - a stale copy
function Test-SkillCopy([string]$DevopsRoot) {
    if (-not $DevopsRoot) { return }
    $skillDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path.TrimEnd('\')
    $name = Split-Path -Leaf $skillDir
    $src = Join-Path $DevopsRoot "skills\$name"
    if (-not (Test-Path -LiteralPath $src)) { return }
    $src = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
    if ($src -eq $skillDir) { return }
    $list = {
        param($d)
        Get-ChildItem -LiteralPath $d -Recurse -File -Force |
            Where-Object { $_.Name -ne 'devops_source.txt' -and $_.FullName -notmatch '\\__pycache__\\' } |
            ForEach-Object { $_.FullName.Substring($d.Length + 1) + '|' + (Get-ContentHash $_.FullName) } |
            Sort-Object
    }
    if (Compare-Object @(& $list $src) @(& $list $skillDir)) {
        Add-Warning "This copy of the '$name' skill ($skillDir) differs from $src - reinstall: devops_ue\skills\install_skills.bat global|project (check: devops_ue\skills\check_skills.ps1)"
    }
}function Format-Size([double]$Bytes) { if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) } else { '{0:N1} MB' -f ($Bytes / 1MB) } }
function Invoke-Capture([string]$File, [string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $File @Arguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable lines | Out-Host; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
    return @($code, ($lines -join "`n"))
}
function Show-Command([string]$File, [string[]]$Arguments) {
    Write-Host ("  > {0} {1}" -f $File, (($Arguments | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '))
}

# zip of the stage the way the engine plans it: deploy.py --host zip (plan only) + make_zip.py (the archive)
function New-WebZip([string]$DeployPrefix) {
    $zipDir = Join-Path $ProjectRoot 'Build\WasmDeploy'
    $planDir = Join-Path $zipDir "plan-$DeployPrefix"
    $zipPath = Join-Path $zipDir "$ProjectName-web-$DeployPrefix.zip"
    New-Item -ItemType Directory -Force -Path $zipDir | Out-Null
    Write-Host "  deploy plan: deploy.py --host zip --prefix $DeployPrefix"
    & $EnginePython -I (Join-Path $WasmTools 'deploy\deploy.py') --stage $Stage --host zip --prefix $DeployPrefix --out $planDir | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "deploy.py --host zip failed (code $LASTEXITCODE): see the release scan above" }
    $planJson = Join-Path $planDir 'deploy-plan.json'
    & $EnginePython -I (Join-Path $PSScriptRoot 'make_zip.py') $planJson $Stage $zipPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "make_zip.py failed (code $LASTEXITCODE)" }
    return $zipPath
}

# boot test of an archive: extract and run webrun.py with SHORT paths (a long --out breaks the service worker cache
# in webrun's Chrome profile: "The game script could not be loaded" / net::ERR_FAILED while ?sw=0 passes)
function Test-WebZip([string]$ZipPath, [string]$DeployPrefix) {
    $safe = ($DeployPrefix -replace '[^A-Za-z0-9]', '')
    $extract = Join-Path $env:TEMP "wz_$safe"
    $out = Join-Path $env:TEMP "wr_$safe"
    if ($out.Length -gt 40) { $extract = Join-Path ([IO.Path]::GetPathRoot($env:TEMP)) "wz_$safe"; $out = Join-Path ([IO.Path]::GetPathRoot($env:TEMP)) "wr_$safe" }
    foreach ($d in $extract, $out) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
    Write-Host "  extracting to $extract"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $extract)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $EnginePython -I -c 'import playwright' 2>$null | Out-Null
    $hasPlaywright = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $prev
    if (-not $hasPlaywright) { Add-Warning 'Playwright is missing in the engine Python: zip boot test skipped (ue-web-setup -InstallPlaywright)'; return }
    Write-Host "  webrun.py run --fixture boot --out $out"
    & $EnginePython (Join-Path $WasmTools 'web\webrun.py') run --stage $extract --fixture boot --out $out | Out-Host
    $resultFile = Get-ChildItem -LiteralPath $out -Recurse -Filter 'result.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resultFile) {
        $result = [IO.File]::ReadAllText($resultFile.FullName) | ConvertFrom-Json
        $ready = if ($result.PSObject.Properties['markers_s'] -and $result.markers_s.ready) { '{0:N1}s' -f [double]$result.markers_s.ready } else { '-' }
        if ($result.pass) { Write-Host "  boot test PASS, READY $ready (no .br in a zip: the cold load is ~3x larger than from the stage)" }
        else { Add-Warning "zip boot test FAILED, see $out" }
    }
    else { Add-Warning "zip boot test gave no result.json (exit $LASTEXITCODE), see $out" }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project, engine and stage'

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
$ProjectName = if ($uprojectFile) { $uprojectFile.BaseName } else { Split-Path -Leaf $ProjectRoot }
Test-SkillCopy (Join-Path $ProjectRoot 'devops_ue')

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

if ($OgImage -and $Target -ne 'vercel') { Add-Warning "-OgImage is used only for -Target vercel (itch.io: set the cover image on the game page)" }
$deployRoot = Join-Path $ProjectRoot "Saved\WebDeploy\$Target"
$site = Join-Path $deployRoot 'site'
New-Item -ItemType Directory -Force -Path $site | Out-Null
# hosts.json excludes + .br siblings: itch.io/GitHub/zip don't serve .br with Content-Encoding: br. Vercel can, through a
# rewrite + header - its target puts the needed .br files back below (the game .wasm is >100 MB raw, Vercel's file limit).
# .vercelignore / .env* (vercel link writes .env.local with a token) are excluded here only so /MIR doesn't purge them.
$exclude = @('*.br', 'Manifest_*.txt', '*.js.symbols', '*.pdb', '*.sym', '*.debug.wasm', '*.bat', '*.sh', 'build-stamp.json', '*.tmp',
    'vercel.json', '.vercelignore', '.env*')
# .br files of an earlier run are excluded from /MIR's purge - remove them first
Get-ChildItem -LiteralPath $site -Recurse -File -Filter '*.br' -Force -ErrorAction SilentlyContinue | Remove-Item -Force
# FileOpenOrder: open-order logs the engine leaves in older stages (build machine paths), never public
$robo = @($Stage, $site, '/MIR', '/XD', '.vercel', 'FileOpenOrder', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XF') + $exclude
& robocopy @robo | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }

function Get-SiteFiles { @(Get-ChildItem -LiteralPath $site -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.vercel\\' -and $_.Name -notlike '.env*' -and $_.Name -ne '.vercelignore' }) }
$files = Get-SiteFiles
$total = ($files | Measure-Object Length -Sum).Sum
$largest = $files | Sort-Object Length -Descending | Select-Object -First 1
Write-Host "  $($files.Count) files, $(Format-Size $total), largest $($largest.Name) $(Format-Size $largest.Length)"

switch ($Target) {
    { $_ -in 'itch', 'zip' } {
        # itch.io HTML game limits (a zip is usually made for itch.io-like portals) (verify on https://itch.io/docs/creators/html5 if a warning shows)
        if ($files.Count -gt 1000) { Add-Warning 'itch.io HTML games allow up to 1000 files' }
        if ($largest.Length -gt 200MB) { Add-Warning 'itch.io HTML games limit a single file to ~200 MB' }
        if ($total -gt 500MB) { Add-Warning 'itch.io HTML games limit the extracted size to ~500 MB (can be raised by itch support)' }
    }
    # vercel: the 100 MB limit is checked after the .br swap, in the Vercel step
    'github' {
        if ($total -gt 2GB) { Add-Warning 'GitHub release assets are limited to 2 GB each' }
    }
}

if ($Target -in 'zip', 'github') {
    # zips are built with the engine Python (stdlib zipfile) - no 7z or other external tools
    if (-not $WasmTools -or -not (Test-Path -LiteralPath $EnginePython)) { throw "Engine Python not found ($EnginePython): pass -EnginePath" }
    # stage + zip + extracted copy for the test: ~2x the stage
    $stageBytes = (Get-ChildItem -LiteralPath $Stage -Recurse -File -Force | Measure-Object Length -Sum).Sum
    $drive = [IO.Path]::GetPathRoot($ProjectRoot)
    $free = (New-Object IO.DriveInfo $drive).AvailableFreeSpace
    Write-Host "  disk $drive free $(Format-Size $free), need ~$(Format-Size (2 * $stageBytes))"
    if ($free -lt 2 * $stageBytes) { throw "Not enough free space on $drive ($(Format-Size $free)); ~$(Format-Size (2 * $stageBytes)) is needed for the zip and its test copy" }

    if (-not $Prefix) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $head = (& git -C $ProjectRoot rev-parse --short HEAD 2>$null)
        $ErrorActionPreference = $prev
        if ($LASTEXITCODE -eq 0 -and $head) { $Prefix = "$head".Trim() }
        else {
            $n = 1
            while (Test-Path -LiteralPath (Join-Path $ProjectRoot "Build\WasmDeploy\$ProjectName-web-v$n.zip")) { $n++ }
            $Prefix = "v$n"
        }
    }
    Write-Host "  prefix: $Prefix"
}

# ---------------------------------------------------------------------------------------------
switch ($Target) {
    'itch' {
        Write-Step 'itch.io (butler push)'
        if (-not $ItchTarget) { throw '-ItchTarget <user>/<game> is required (the game page must exist on itch.io: itch.io/game/new, Kind of project: HTML)' }
        $butler = (Get-Command butler -ErrorAction SilentlyContinue).Source
        if (-not $butler) { $b = Join-Path $env:LOCALAPPDATA 'itch-butler\butler.exe'; if (Test-Path -LiteralPath $b) { $butler = $b } }
        if (-not $butler) { throw 'butler not found: run install_tools.ps1 -Tools butler' }
        # butler installed after this session started is not on its PATH: give a login command that runs as-is
        $butlerLogin = if (Get-Command butler -ErrorAction SilentlyContinue) { 'butler login' } else { "& `"$butler`" login" }

        # quiet `butler status <user/game>` (without :channel, so a missing channel is not an error)
        function Get-ItchChannelRow {
            # butler writes UTF-8 (the √ mark); PowerShell 5.1 would decode it with the OEM code page
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $prevEnc = [Console]::OutputEncoding
            try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $out = @(& $butler status $ItchTarget 2>&1 | ForEach-Object { "$_" }) }
            finally { [Console]::OutputEncoding = $prevEnc; $ErrorActionPreference = $prev }
            return ($out | Where-Object { $_ -match "^\s*\|?\s*$([regex]::Escape($ItchChannel))\s*\|" } | Select-Object -First 1)
        }

        $cmdArgs = @('push', $site, "${ItchTarget}:$ItchChannel")
        if ($Version) { $cmdArgs += @('--userversion', $Version) }
        Show-Command 'butler' $cmdArgs
        $firstPush = $false
        if (-not $DryRun) {
            $firstPush = -not (Get-ItchChannelRow)
            $r = Invoke-Capture $butler $cmdArgs
            if ($r[0] -ne 0) { throw "butler push failed (code $($r[0])). Not logged in? Run: $butlerLogin" }

            # itch.io creates the channel only after it has processed the first build: wait for the build (√), up to ~2 min
            Write-Step 'itch.io processing the build'
            $row = $null; $deadline = (Get-Date).AddMinutes(2)
            while ((Get-Date) -lt $deadline) {
                $row = Get-ItchChannelRow
                if ($row -and $row -match [regex]::Escape([string][char]0x221A)) { break }  # √ = processed
                Start-Sleep -Seconds 10
            }
            if ($row -and $row -match [regex]::Escape([string][char]0x221A)) { Write-Host "  processed: $($row.Trim())" -ForegroundColor Green }
            elseif ($row) { Add-Warning "itch.io is still processing the build: $($row.Trim()) - check later with: butler status $ItchTarget" }
            else { Add-Warning "itch.io is still processing the first build (the '$ItchChannel' channel appears when it is done) - check later with: butler status $ItchTarget" }
        }
        Write-Host ''
        if ($firstPush -or $DryRun) {
            Write-Host "First upload to this channel: until the page is configured, itch.io shows" -ForegroundColor Yellow
            Write-Host "  `"There was a problem loading your project: You've selected a HTML5 game but haven't configured how your project is embedded`"" -ForegroundColor Yellow
            Write-Host "That is expected. Fix it once on itch.io (Edit game):" -ForegroundColor Yellow
        }
        else { Write-Host 'Check once on the itch.io game page (Edit game):' -ForegroundColor Yellow }
        Write-Host '  1. Kind of project: HTML' -ForegroundColor Yellow
        Write-Host "  2. Uploads: mark the '$ItchChannel' upload 'This file will be played in the browser'" -ForegroundColor Yellow
        Write-Host '  3. Embed options: viewport e.g. 1280x720, SharedArrayBuffer support = ON (Wasm threads), Fullscreen button' -ForegroundColor Yellow
        Write-Host '  4. Save, reopen Edit game and check SharedArrayBuffer support stayed on' -ForegroundColor Yellow
        Write-Host '  5. Visibility & access: keep Draft/Restricted until the game runs in the browser, then Public' -ForegroundColor Yellow
        $user, $game = $ItchTarget -split '/', 2
        Write-Host "Page: https://$user.itch.io/$game"
    }

    'vercel' {
        Write-Step 'Vercel'
        if (-not (Get-Command vercel -ErrorAction SilentlyContinue)) { throw 'vercel CLI not found: run install_tools.ps1 -Tools vercel' }

        # Vercel rejects files over 100 MB, and the game .wasm is bigger raw (e.g. 133 MB). Upload <file>.br INSTEAD of
        # <file> and serve it at the original URL with a rewrite + Content-Encoding: br: the browser decodes it, so the
        # sha1 in wasm-cache.json still matches. Done for every .wasm and for other >100 MB files that have a .br sibling,
        # never for .ucas/.utoc/.pak: the engine reads containers with Range requests, a compressed range breaks them.
        # Everything else is uploaded raw (Vercel compresses it itself and answers Range on containers with 206).
        $brSwaps = New-Object System.Collections.ArrayList
        foreach ($f in Get-SiteFiles) {
            if ($f.Extension -in '.ucas', '.utoc', '.pak', '.br') { continue }
            if ($f.Extension -ne '.wasm' -and $f.Length -le 100MB) { continue }
            $rel = $f.FullName.Substring($site.TrimEnd('\').Length + 1)
            $brSrc = Join-Path $Stage "$rel.br"
            if (-not (Test-Path -LiteralPath $brSrc)) { continue }
            Copy-Item -LiteralPath $brSrc -Destination "$($f.FullName).br" -Force
            Remove-Item -LiteralPath $f.FullName -Force
            [void]$brSwaps.Add([pscustomobject]@{ Path = '/' + ($rel -replace '\\', '/'); Ext = $f.Extension; Raw = $f.Length; Br = (Get-Item -LiteralPath "$($f.FullName).br").Length })
            Write-Host ("  {0}: upload .br {1} instead of {2} (rewrite + Content-Encoding: br)" -f $rel, (Format-Size $brSwaps[-1].Br), (Format-Size $f.Length))
        }

        # the limit after the swap
        $tooBig = @(Get-SiteFiles | Where-Object { $_.Length -gt 100MB })
        if ($tooBig.Count -gt 0) {
            $list = ($tooBig | ForEach-Object { "$($_.Name) ($(Format-Size $_.Length))" }) -join ', '
            $containers = @($tooBig | Where-Object { $_.Extension -in '.ucas', '.utoc', '.pak' })
            if ($containers.Count -gt 0) {
                throw "Vercel can't host this build: $list over its 100 MB file limit. Containers are read with Range requests and can't be uploaded compressed. Use another host (own server: deploy.py --host static; Cloudflare R2 + worker.js; itch.io via -Target itch) or split the content into more pak chunks."
            }
            throw "Files over Vercel's 100 MB limit without a .br sibling: $list. Repackage (package_wasm.bat writes .br) or use another host."
        }

        $mime = @{ '.wasm' = 'application/wasm'; '.js' = 'text/javascript'; '.json' = 'application/json' }
        # cross-origin isolation for Wasm threads + revalidation (sw.js versions files by sha1); engine netlify.toml/_headers equivalent
        $headers = New-Object System.Collections.ArrayList
        [void]$headers.Add([ordered]@{ source = '/(.*)'; headers = @(
                @{ key = 'Cross-Origin-Opener-Policy'; value = 'same-origin' },
                @{ key = 'Cross-Origin-Embedder-Policy'; value = 'require-corp' },
                @{ key = 'Cross-Origin-Resource-Policy'; value = 'same-origin' },
                @{ key = 'Cache-Control'; value = 'no-cache' },
                @{ key = 'X-Content-Type-Options'; value = 'nosniff' }) })
        [void]$headers.Add([ordered]@{ source = '/(.*)\.wasm'; headers = @(@{ key = 'Content-Type'; value = 'application/wasm' }) })
        [void]$headers.Add([ordered]@{ source = '/(.*)\.(ucas|utoc|pak)'; headers = @(@{ key = 'Content-Type'; value = 'application/octet-stream' }) })
        $rewrites = New-Object System.Collections.ArrayList
        foreach ($s in $brSwaps) {
            $type = if ($mime.ContainsKey($s.Ext)) { $mime[$s.Ext] } else { 'application/octet-stream' }
            [void]$rewrites.Add([ordered]@{ source = $s.Path; destination = "$($s.Path).br" })
            [void]$headers.Add([ordered]@{ source = $s.Path; headers = @(
                    @{ key = 'Content-Type'; value = $type },
                    @{ key = 'Content-Encoding'; value = 'br' }) })
        }
        $vercelJson = [ordered]@{
            '$schema'     = 'https://openapi.vercel.sh/vercel.json'
            cleanUrls     = $false
            trailingSlash = $false
            headers       = $headers.ToArray()
        }
        if ($rewrites.Count -gt 0) { $vercelJson['rewrites'] = $rewrites.ToArray() }
        [IO.File]::WriteAllText((Join-Path $site 'vercel.json'), ($vercelJson | ConvertTo-Json -Depth 6), $Utf8NoBom)
        # vercel link writes .env.local (VERCEL_OIDC_TOKEN) into this folder: never upload it
        [IO.File]::WriteAllText((Join-Path $site '.vercelignore'), ".env*`n.vercel`n", $Utf8NoBom)
        if (-not $VercelProject) { $VercelProject = ($ProjectName.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-') }

        # link preview: og.<ext> + OpenGraph/Twitter meta in the uploaded index.html (index.html is in no manifest:
        # wasm-manifest.json / wasm-cache.json sha1s stay valid). Crawlers fetch server-side, COEP/CORP don't affect them.
        $ogUrl = ''
        if ($OgImage) {
            if (-not (Test-Path -LiteralPath $OgImage)) { throw "-OgImage not found: $OgImage" }
            $ogExt = [IO.Path]::GetExtension($OgImage).ToLowerInvariant()
            if ($ogExt -notin '.png', '.jpg', '.jpeg', '.webp') { throw '-OgImage must be .png, .jpg or .webp' }
            $ogBytes = (Get-Item -LiteralPath $OgImage).Length
            if ($ogBytes -gt 5MB) { Add-Warning "OG image is $(Format-Size $ogBytes): X/Twitter ignores images over 5 MB, keep it under ~1 MB" }
            $base = if ($SiteUrl) { $SiteUrl.TrimEnd('/') } elseif ($Prod) { "https://$VercelProject.vercel.app" } else { '' }
            if (-not $base) { Add-Warning 'OG tags skipped: og:image needs an absolute URL - deploy with -Prod (https://<project>.vercel.app) or pass -SiteUrl' }
            else {
                $ogName = "og$ogExt"
                Copy-Item -LiteralPath $OgImage -Destination (Join-Path $site $ogName) -Force
                $ogUrl = "$base/$ogName"
                $w = 0; $h = 0
                try { Add-Type -AssemblyName System.Drawing; $img = [Drawing.Image]::FromFile((Resolve-Path -LiteralPath $OgImage).Path); $w = $img.Width; $h = $img.Height; $img.Dispose() } catch { }
                if ($w -and $h -and [math]::Abs($w / $h - 1.91) -gt 0.25 -and [math]::Abs($w / $h - 16 / 9) -gt 0.05) { Add-Warning "OG image is ${w}x${h}: previews crop to ~1.91:1 (1200x630 is the usual size)" }
                $title = if ($OgTitle) { $OgTitle } else { $ProjectName }
                $esc = { param($s) [Net.WebUtility]::HtmlEncode($s) }
                $tags = New-Object System.Collections.ArrayList
                [void]$tags.Add("<meta property=`"og:type`" content=`"website`">")
                [void]$tags.Add("<meta property=`"og:url`" content=`"$(& $esc "$base/")`">")
                [void]$tags.Add("<meta property=`"og:title`" content=`"$(& $esc $title)`">")
                if ($OgDescription) {
                    [void]$tags.Add("<meta name=`"description`" content=`"$(& $esc $OgDescription)`">")
                    [void]$tags.Add("<meta property=`"og:description`" content=`"$(& $esc $OgDescription)`">")
                }
                [void]$tags.Add("<meta property=`"og:image`" content=`"$(& $esc $ogUrl)`">")
                if ($w -and $h) { [void]$tags.Add("<meta property=`"og:image:width`" content=`"$w`"><meta property=`"og:image:height`" content=`"$h`">") }
                [void]$tags.Add("<meta property=`"og:image:alt`" content=`"$(& $esc $title)`">")
                [void]$tags.Add("<meta name=`"twitter:card`" content=`"summary_large_image`">")
                [void]$tags.Add("<meta name=`"twitter:title`" content=`"$(& $esc $title)`">")
                if ($OgDescription) { [void]$tags.Add("<meta name=`"twitter:description`" content=`"$(& $esc $OgDescription)`">") }
                [void]$tags.Add("<meta name=`"twitter:image`" content=`"$(& $esc $ogUrl)`">")
                # same markers as devops_ue\package\web_page_extras.ps1 (devops_data\web\head.html): a block the page
                # already got at packaging is replaced, never duplicated
                $begin = '<!-- project-head:begin -->'; $end = '<!-- project-head:end -->'
                $indexPath = Join-Path $site 'index.html'
                $html = [IO.File]::ReadAllText($indexPath)
                if ($html.Contains($begin)) { Write-Host '  the page already has a project-head block (devops_data\web): replaced by -OgImage' }
                $html = [regex]::Replace($html, '(?s)\r?\n?' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end) + '\r?\n?', '')
                $i = $html.IndexOf('</head>', [StringComparison]::OrdinalIgnoreCase)
                if ($i -lt 0) { throw 'index.html has no </head>: cannot add the OG tags' }
                $html = $html.Insert($i, $begin + "`n" + ($tags -join "`n") + "`n" + $end + "`n")
                [IO.File]::WriteAllText($indexPath, $html, $Utf8NoBom)
                Write-Host ("  link preview: {0} ({1}{2}), og:image {3}" -f $ogName, (Format-Size $ogBytes), $(if ($w) { ", ${w}x${h}" } else { '' }), $ogUrl)

                # -OgSave: keep it in the project (devops_data\web), so every later package (ue-package -Platform Wasm,
                # package_wasm.bat) has the preview and later deploys need no -Og* arguments
                if ($OgSave) {
                    $webDir = Join-Path $ProjectRoot 'devops_data\web'
                    New-Item -ItemType Directory -Force -Path (Join-Path $webDir 'public') | Out-Null
                    Copy-Item -LiteralPath $OgImage -Destination (Join-Path $webDir "public\$ogName") -Force
                    $headText = "<!-- inserted before </head> of index.html by devops_ue\package\web_page_extras.ps1 (package_wasm.bat, ue-package); files in public\ are copied next to index.html -->`n" + ($tags -join "`n") + "`n"
                    [IO.File]::WriteAllText((Join-Path $webDir 'head.html'), $headText, $Utf8NoBom)
                    Write-Host "  saved to the project: $webDir\head.html, public\$ogName (commit them)" -ForegroundColor Green
                }
            }
        }
        elseif ($OgTitle -or $OgDescription -or $OgSave) { Add-Warning '-OgTitle/-OgDescription/-OgSave need -OgImage: no link preview tags added' }

        # og:image of the final page (from -OgImage or devops_data\web at packaging) - checked after the deploy
        $ogUrl = ([regex]::Match([IO.File]::ReadAllText((Join-Path $site 'index.html')), '<meta property="og:image" content="([^"]+)"')).Groups[1].Value
        if ($ogUrl -and -not $OgImage) { Write-Host "  link preview from the page (devops_data\web): og:image $ogUrl" }

        $final = Get-SiteFiles
        Write-Host ("  vercel.json written (COOP/COEP/CORP, no-cache, MIME, {0} .br rewrite(s)); .vercelignore: .env*, .vercel" -f $rewrites.Count)
        Write-Host ("  upload: {0} files, {1}, largest {2}" -f $final.Count, (Format-Size (($final | Measure-Object Length -Sum).Sum)), (Format-Size (($final | Measure-Object Length -Maximum).Maximum)))

        $scopeArgs =if ($VercelScope) { @('--scope', $VercelScope) } else { @() }
        if (-not (Test-Path -LiteralPath (Join-Path $site '.vercel\project.json'))) {
            $linkArgs = @('link', '--yes', '--cwd', $site, '--project', $VercelProject) + $scopeArgs
            Show-Command 'vercel' $linkArgs
            if (-not $DryRun) {
                $r = Invoke-Capture 'vercel' $linkArgs
                if ($r[0] -ne 0) { throw "vercel link failed (code $($r[0])). Not logged in? Run: vercel login" }
                # the site folder sits inside the game repo: vercel link connects that repo to the project (auto-deploy
                # of the source repo on every push - never wanted for a prebuilt stage). No flag skips it: disconnect.
                if ($r[1] -match 'Connecting (GitHub|GitLab|Bitbucket) repository') {
                    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                    & vercel git disconnect --yes --cwd $site @scopeArgs *> $null
                    $ErrorActionPreference = $prev
                    Write-Host '  git repository connection removed from the Vercel project (deploys come only from this script)'
                }
            }
        }
        $deployArgs = @('deploy', '--cwd', $site, '--yes') + $scopeArgs
        if ($Prod) { $deployArgs += '--prod' }
        Show-Command 'vercel' $deployArgs
        if (-not $DryRun) {
            $r = Invoke-Capture 'vercel' $deployArgs
            if ($r[0] -ne 0) { throw "vercel deploy failed (code $($r[0]))" }
            $url = ([regex]::Matches($r[1], 'https://[^\s]+\.vercel\.app') | Select-Object -Last 1).Value
            if ($ogUrl) {
                # the default https://<project>.vercel.app is right only if Vercel gave the project that domain;
                # right after a first deploy the alias needs a few seconds (404 meanwhile) - retry for ~40 s
                $resp = $null; $ogErr = ''
                for ($try = 0; $try -lt 8 -and -not $resp; $try++) {
                    if ($try) { Start-Sleep -Seconds 5 }
                    try { $resp = Invoke-WebRequest -Uri $ogUrl -Method Head -UseBasicParsing -TimeoutSec 20 } catch { $ogErr = $_.Exception.Message }
                }
                if ($resp) { Write-Host "  og:image reachable: $ogUrl ($($resp.Headers['Content-Type']))" -ForegroundColor Green }
                else { Add-Warning "og:image $ogUrl is not reachable ($ogErr): the production domain differs? Redeploy with -SiteUrl https://<your domain>" }
                Write-Host '  check the preview: https://www.opengraph.xyz/url/ or paste the link in Telegram/Discord (they cache previews)'
            }
            if ($url) {
                Write-Host "URL: $url"
                if ($WasmTools) {
                    Write-Step 'webdoctor.py (headers, MIME, ranges, isolation - read-only)'
                    & $EnginePython -I (Join-Path $WasmTools 'deploy\webdoctor.py') "$url/"
                    if ($LASTEXITCODE -ne 0) { Add-Warning 'webdoctor.py reported problems (preview deployments may be behind Vercel Authentication: check the URL in a browser or deploy with -Prod)' }
                    if ($TestDeploy) {
                        Write-Step 'Boot test of the live URL (webrun.py, short --out)'
                        $out = Join-Path $env:TEMP 'wr_vercel'
                        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
                        & $EnginePython (Join-Path $WasmTools 'web\webrun.py') run --url "$url/index.html" --fixture boot --out $out | Out-Host
                        $resultFile = Get-ChildItem -LiteralPath $out -Recurse -Filter 'result.json' -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($resultFile) {
                            $result = [IO.File]::ReadAllText($resultFile.FullName) | ConvertFrom-Json
                            $ready = if ($result.PSObject.Properties['markers_s'] -and $result.markers_s.ready) { '{0:N1}s' -f [double]$result.markers_s.ready } else { '-' }
                            if ($result.pass) { Write-Host "  boot test PASS, READY $ready" } else { Add-Warning "live boot test FAILED, see $out" }
                        }
                        else { Add-Warning "live boot test gave no result.json, see $out" }
                    }
                }
            }
        }
    }

    'github' {
        Write-Step 'GitHub release'
        $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
        if (-not $gh) { throw 'gh not found: run install_tools.ps1 -Tools gh' }
        if (-not $GitHubTag) { $GitHubTag = "web-$Prefix" }
        $zip = New-WebZip $Prefix
        if ($TestZip) { Test-WebZip $zip $Prefix }
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
                & $gh @cmdArgs
                if ($LASTEXITCODE -ne 0) { throw "gh release failed (code $LASTEXITCODE). Not logged in? Run: gh auth login" }
                & $gh release view $GitHubTag @repoArgs --json url --jq .url
            }
        }
        finally { Pop-Location; $ErrorActionPreference = $prev }
    }

    'zip' {
        Write-Step "Zip for portals (prefix $Prefix)"
        $zip = New-WebZip $Prefix
        if ($TestZip) { Write-Step 'Zip boot test (short paths)'; Test-WebZip $zip $Prefix }
        Write-Host ''
        Write-Host "Archive: $zip (index.html at the root - upload it to itch.io or a similar portal)" -ForegroundColor Green
        Write-Host 'A zip host does not serve the .br copies: the download is ~3x larger than from your own server (--host static) or Vercel.' -ForegroundColor Yellow
        $site = $zip
    }
}

# ---------------------------------------------------------------------------------------------
Write-FinalStep $(if ($DryRun) { 'Dry run finished (nothing uploaded)' } else { 'Done' })
Write-Host "Upload folder: $site"
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}

Write-Timing
