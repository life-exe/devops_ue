# Copyright LifeEXE. All Rights Reserved.
# Creates a new Unreal Engine project wired up with devops_ue.
#
# Example:
#   create_project.ps1 -ProjectName MyGame -ParentDir C:\Projects -Type Cpp `
#       -EnginePath "C:\Program Files\Epic Games\UE_5.9" -Template Empty `
#       -Copyright "Copyright MyCompany. All Rights Reserved."
#
# In place (folder prepared by hand: git init + git submodule add .../devops_ue):
#   create_project.ps1 -ProjectName MyGame -ProjectDir C:\Projects\MyGame ...
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectName,
    # creates <ParentDir>\<ProjectName>
    [string]$ParentDir = '',
    # or the exact project folder; may already contain only .git, .gitmodules and devops_ue
    [string]$ProjectDir = '',
    [Parameter(Mandatory)][ValidateSet('Cpp', 'Blueprint')][string]$Type,
    [Parameter(Mandatory)][string]$EnginePath,
    # 'Empty' = blank project + empty /Game/Maps/MainLevel, otherwise an engine template folder name (TP_ThirdPerson, TP_TopDownBP, ...)
    [string]$Template = 'Empty',
    [Parameter(Mandatory)][string]$Copyright,
    [string]$CompanyName = '',
    [string]$EngineAssociation = '',
    # path to the local devops_ue repo (autodetected when empty)
    [string]$DevopsSource = '',
    [ValidateSet('Submodule', 'Copy')][string]$DevopsMode = 'Submodule',
    [string]$DevopsUrl = '',
    [switch]$SkipBuild,
    [switch]$SkipMainLevel,
    [switch]$Package
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ue_common.ps1')

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
}function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

# Runs a process with a verbatim argument string (avoids PowerShell 5.1 native quoting issues).
function Invoke-Exe([string]$FilePath, [string]$Arguments) {
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    $p.WaitForExit()
    return $p.ExitCode
}

function Invoke-Bat([string]$BatPath, [string]$Arguments = '') {
    # stdin from nul so that `pause` in the scripts doesn't block
    return Invoke-Exe $env:ComSpec "/d /s /c `"`"$BatPath`" $Arguments < nul`""
}

# Sets key=value inside [section]; creates the section/key when missing.
function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) { $lines.AddRange([string[]]([IO.File]::ReadAllLines($Path))) }
    $header = "[$Section]"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $header) { $start = $i; break } }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
        $lines.Add($header); $lines.Add("$Key=$Value")
    }
    else {
        $end = $lines.Count
        for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -match '^\[.+\]$') { $end = $i; break } }
        $replaced = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $lines[$i] = "$Key=$Value"; $replaced = $true; break }
        }
        if (-not $replaced) {
            $insertAt = $end
            while ($insertAt -gt $start + 1 -and $lines[$insertAt - 1].Trim() -eq '') { $insertAt-- }
            $lines.Insert($insertAt, "$Key=$Value")
        }
    }
    [IO.File]::WriteAllLines($Path, $lines, $Utf8NoBom)
}

# Adds a raw line (e.g. +MapsToCook=...) to [section] if it isn't there yet.
function Add-IniLine([string]$Path, [string]$Section, [string]$Line) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) { $lines.AddRange([string[]]([IO.File]::ReadAllLines($Path))) }
    if ($lines -contains $Line) { return }
    $header = "[$Section]"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $header) { $start = $i; break } }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
        $lines.Add($header); $lines.Add($Line)
    }
    else {
        $end = $lines.Count
        for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -match '^\[.+\]$') { $end = $i; break } }
        $insertAt = $end
        while ($insertAt -gt $start + 1 -and $lines[$insertAt - 1].Trim() -eq '') { $insertAt-- }
        $lines.Insert($insertAt, $Line)
    }
    [IO.File]::WriteAllLines($Path, $lines, $Utf8NoBom)
}

function Get-IniValue([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    foreach ($l in [IO.File]::ReadAllLines($Path)) { if ($l -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*)$") { return $Matches[1].Trim() } }
    return ''
}

function Replace-TemplateName([string]$Text, [string]$From, [string]$To) {
    $Text = $Text.Replace($From.ToUpperInvariant(), $To.ToUpperInvariant())
    $Text = $Text.Replace($From.ToLowerInvariant(), $To.ToLowerInvariant())
    return [regex]::Replace($Text, [regex]::Escape($From), $To.Replace('$', '$$'), 'IgnoreCase')
}

function Find-DevopsSource {
    $candidates = @(
        (Join-Path $PSScriptRoot '..\..\..'),            # devops_ue\skills\ue-create-project\scripts
        (Join-Path $PSScriptRoot '..\..\..\..\devops_ue') # <project>\.claude\skills\ue-create-project\scripts
    )
    $pathFile = Join-Path $PSScriptRoot '..\devops_source.txt'  # written by devops_ue\skills\install_skills.bat
    if (Test-Path -LiteralPath $pathFile) { $candidates += ([IO.File]::ReadAllText($pathFile).Trim()) }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'setup.bat')) -and (Test-Path -LiteralPath (Join-Path $c 'setup'))) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return ''
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Validating input'

if ($ProjectName -notmatch '^[A-Za-z][A-Za-z0-9_]{0,19}$') {
    throw "Invalid project name '$ProjectName': must start with a letter, contain only letters, digits or '_' and be at most 20 characters."
}
$EnginePath = (Resolve-Path -LiteralPath $EnginePath).Path.TrimEnd('\')
$engineInfo = Get-UnrealEngineInfo -Path $EnginePath
if (-not $engineInfo) { throw "Not an Unreal Engine 5 folder: $EnginePath" }
if (-not $EngineAssociation) { $EngineAssociation = Get-EngineAssociation -EnginePath $EnginePath }

if ($ProjectDir) {
    if (-not (Test-Path -LiteralPath $ProjectDir)) { New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null }
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectDir).Path.TrimEnd('\')
}
elseif ($ParentDir) {
    if (-not (Test-Path -LiteralPath $ParentDir)) { New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null }
    $ProjectRoot = Join-Path (Resolve-Path -LiteralPath $ParentDir).Path $ProjectName
}
else { throw 'Pass -ProjectDir <project folder> or -ParentDir <folder for <ProjectName>>.' }

# a folder prepared by hand may already hold the git repo, the devops_ue submodule and
# project-local skills (devops_ue\skills\install_skills.bat project) - nothing else
$allowedExisting = @('.git', '.gitmodules', 'devops_ue', '.claude', '.agents')
$existingItems = @()
if (Test-Path -LiteralPath $ProjectRoot) { $existingItems = @(Get-ChildItem -LiteralPath $ProjectRoot -Force) }
$blocking = @($existingItems | Where-Object { $allowedExisting -notcontains $_.Name } | ForEach-Object { $_.Name })
if ($blocking.Count -gt 0) {
    throw "Target folder is not empty: $ProjectRoot (only .git, .gitmodules, devops_ue, .claude and .agents may exist; found: $($blocking -join ', '))"
}
$existingDevops = Join-Path $ProjectRoot 'devops_ue'
$useExistingDevops = Test-Path -LiteralPath (Join-Path $existingDevops 'setup.bat')
if ((Test-Path -LiteralPath $existingDevops) -and -not $useExistingDevops) {
    throw "$existingDevops is empty: run 'git submodule update --init --recursive' in $ProjectRoot"
}

if (-not $DevopsSource) { $DevopsSource = Find-DevopsSource }
if (-not $DevopsSource -and $useExistingDevops) { $DevopsSource = $existingDevops }
if (-not $DevopsSource -or -not (Test-Path -LiteralPath (Join-Path $DevopsSource 'setup.bat'))) {
    throw 'devops_ue repository not found. Pass -DevopsSource <path to devops_ue>.'
}
$DevopsSource = (Resolve-Path -LiteralPath $DevopsSource).Path
$SkillRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Test-SkillCopy $DevopsSource

$isEmpty = $Template -eq 'Empty'
if ($isEmpty) { $TemplateName = if ($Type -eq 'Cpp') { 'TP_Blank' } else { 'TP_BlankBP' } } else { $TemplateName = $Template }
$TemplateDir = Join-Path $EnginePath "Templates\$TemplateName"
if (-not (Test-Path -LiteralPath (Join-Path $TemplateDir "$TemplateName.uproject"))) { throw "Template not found: $TemplateDir" }
$templateHasSource = Test-Path -LiteralPath (Join-Path $TemplateDir 'Source')
if ($Type -eq 'Cpp' -and -not $templateHasSource) { throw "$TemplateName is a Blueprint template, pick its C++ version." }
if ($Type -eq 'Blueprint' -and $templateHasSource) { throw "$TemplateName is a C++ template, pick its Blueprint version." }

$Copyright = $Copyright.Trim() -replace '^//\s*', ''
$CopyrightLine = "// $Copyright"
$ApiMacro = "$($ProjectName.ToUpperInvariant())_API"
$UProjectPath = Join-Path $ProjectRoot "$ProjectName.uproject"

Write-Host "Project : $ProjectRoot ($Type)"
Write-Host "Engine  : $EnginePath ($($engineInfo.Version), association '$EngineAssociation')"
Write-Host "Template: $TemplateName$(if ($isEmpty) { ' + empty MainLevel' })"
Write-Host "Devops  : $DevopsSource ($DevopsMode)"

# ---------------------------------------------------------------------------------------------
Write-Step "Copying template $TemplateName"

$foldersToIgnore = New-Object System.Collections.Generic.List[string]
$filesToIgnore = New-Object System.Collections.Generic.List[string]
$sharedPacks = New-Object System.Collections.Generic.List[object]
foreach ($f in 'Binaries', 'Build', 'Intermediate', 'Saved', 'Media', 'DerivedDataCache') { $foldersToIgnore.Add($f) }
foreach ($f in "$TemplateName.uproject", "$TemplateName.png", 'Config/TemplateDefs.ini', 'Config/config.ini', 'Manifest.json', 'contents.txt') { $filesToIgnore.Add($f) }

$defsPath = Join-Path $TemplateDir 'Config\TemplateDefs.ini'
if (Test-Path -LiteralPath $defsPath) {
    foreach ($line in [IO.File]::ReadAllLines($defsPath)) {
        $l = $line.Trim()
        if ($l -match '^FoldersToIgnore=(.+)$') { $foldersToIgnore.Add($Matches[1].Trim('"').Replace('%TEMPLATENAME%', $TemplateName).Replace('\', '/')) }
        elseif ($l -match '^FilesToIgnore=(.+)$') { $filesToIgnore.Add($Matches[1].Trim('"').Replace('%TEMPLATENAME%', $TemplateName).Replace('\', '/')) }
        elseif ($l -match '^SharedContentPacks=\(MountName="([^"]+)",DetailLevels=\(([^)]*)\)\)') {
            $levels = @($Matches[2] -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
            $sharedPacks.Add([pscustomobject]@{ Mount = $Matches[1]; Levels = $levels })
        }
    }
}

$textExtensions = @('.cpp', '.h', '.ini', '.cs')
$templateDirFull = (Resolve-Path -LiteralPath $TemplateDir).Path.TrimEnd('\')
foreach ($file in Get-ChildItem -LiteralPath $TemplateDir -Recurse -File -Force) {
    $rel = $file.FullName.Substring($templateDirFull.Length + 1).Replace('\', '/')
    $skip = $false
    foreach ($folder in $foldersToIgnore) { if ($rel.StartsWith("$folder/", [StringComparison]::OrdinalIgnoreCase)) { $skip = $true; break } }
    if (-not $skip) { foreach ($ign in $filesToIgnore) { if ($rel -ieq $ign) { $skip = $true; break } } }
    if ($skip) { continue }

    $ext = $file.Extension.ToLowerInvariant()
    $destRel = $rel
    if ($rel.StartsWith('Source/', [StringComparison]::OrdinalIgnoreCase)) {
        $destRel = Replace-TemplateName $rel $TemplateName $ProjectName
    }
    elseif ($textExtensions -contains $ext) {
        $dirPart = Split-Path -Parent $rel
        $namePart = Replace-TemplateName (Split-Path -Leaf $rel) $TemplateName $ProjectName
        $destRel = if ($dirPart) { "$dirPart/$namePart" } else { $namePart }
    }
    $dest = Join-Path $ProjectRoot ($destRel.Replace('/', '\'))

    if ($textExtensions -contains $ext) {
        Write-Text $dest (Replace-TemplateName (Read-Text $file.FullName) $TemplateName $ProjectName)
    }
    else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
    }
}

# shared content packs (LevelPrototyping, Characters, Input, ...) are mounted into /Game/<MountName>
foreach ($pack in $sharedPacks) {
    $resources = Join-Path $EnginePath 'Templates\TemplateResources'
    $packDir = $null
    foreach ($level in @($pack.Levels) + @('High', 'Standard')) {
        $candidate = Join-Path $resources "$level\$($pack.Mount)"
        if (Test-Path -LiteralPath (Join-Path $candidate 'Content')) { $packDir = $candidate; break }
    }
    if (-not $packDir) { Add-Warning "Shared content pack '$($pack.Mount)' not found in $resources"; continue }
    Write-Host "  shared pack $($pack.Mount) <- $packDir"
    $destContent = Join-Path $ProjectRoot "Content\$($pack.Mount)"
    New-Item -ItemType Directory -Force -Path $destContent | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $packDir 'Content') -Force | Where-Object { $_.Name -ne 'manifest.json' } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destContent -Recurse -Force }
    foreach ($external in '__ExternalActors__', '__ExternalObjects__') {
        $src = Join-Path $packDir $external
        if (Test-Path -LiteralPath $src) {
            $dst = Join-Path $ProjectRoot "Content\$external\$($pack.Mount)"
            New-Item -ItemType Directory -Force -Path $dst | Out-Null
            Get-ChildItem -LiteralPath $src -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force }
        }
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Writing .uproject'

$uprojectText = Replace-TemplateName (Read-Text (Join-Path $TemplateDir "$TemplateName.uproject")) $TemplateName $ProjectName
$uprojectText = [regex]::Replace($uprojectText, '"EngineAssociation"\s*:\s*"[^"]*"', "`"EngineAssociation`": `"$EngineAssociation`"")
Write-Text $UProjectPath $uprojectText

# ---------------------------------------------------------------------------------------------
Write-Step 'Configuring Config/*.ini'

$defaultGame = Join-Path $ProjectRoot 'Config\DefaultGame.ini'
$defaultEngine = Join-Path $ProjectRoot 'Config\DefaultEngine.ini'
if (-not (Test-Path -LiteralPath $defaultGame)) { Write-Text $defaultGame '' }
if (-not (Test-Path -LiteralPath $defaultEngine)) { Write-Text $defaultEngine '' }

$general = '/Script/EngineSettings.GeneralProjectSettings'
Set-IniValue $defaultGame $general 'ProjectID' ([guid]::NewGuid().ToString('N').ToUpperInvariant())
Set-IniValue $defaultGame $general 'ProjectName' $ProjectName
Set-IniValue $defaultGame $general 'CopyrightNotice' $Copyright
if ($CompanyName) { Set-IniValue $defaultGame $general 'CompanyName' $CompanyName }

$maps = '/Script/EngineSettings.GameMapsSettings'
if ($isEmpty) {
    $mainMap = '/Game/Maps/MainLevel'
    Set-IniValue $defaultEngine $maps 'GameDefaultMap' "$mainMap.MainLevel"
    Set-IniValue $defaultEngine $maps 'EditorStartupMap' "$mainMap.MainLevel"
}
else {
    $gameMap = Get-IniValue $defaultEngine 'GameDefaultMap'
    $mainMap = if ($gameMap -like '/Game/*') { $gameMap -replace '\.[^./]+$', '' } else { '' }
}
if ($mainMap) { Add-IniLine $defaultGame '/Script/UnrealEd.ProjectPackagingSettings' "+MapsToCook=(FilePath=`"$mainMap`")" }

if ($Type -eq 'Cpp') {
    if ($isEmpty) { Set-IniValue $defaultEngine $maps 'GlobalDefaultGameMode' "/Script/$ProjectName.${ProjectName}GameMode" }

    # Template assets reference /Script/<TemplateName> classes - redirect them to the new module (same as the editor's New Project wizard).
    if (-not $isEmpty) {
        $engineSection = '/Script/Engine.Engine'
        Add-IniLine $defaultEngine $engineSection "+ActiveGameNameRedirects=(OldGameName=`"$TemplateName`",NewGameName=`"/Script/$ProjectName`")"
        Add-IniLine $defaultEngine $engineSection "+ActiveGameNameRedirects=(OldGameName=`"/Script/$TemplateName`",NewGameName=`"/Script/$ProjectName`")"
        $templateHeaders = Get-ChildItem -LiteralPath (Join-Path $TemplateDir 'Source') -Recurse -Filter '*.h' -File
        foreach ($h in $templateHeaders) {
            foreach ($m in [regex]::Matches((Read-Text $h.FullName), '(?:UCLASS|USTRUCT|UENUM|UINTERFACE)\s*\([^)]*\)\s*(?:class|struct|enum(?:\s+class)?)\s+(?:\w+_API\s+)?([AUFIE]?)(\w+)')) {
                $oldName = $m.Groups[2].Value
                if ($oldName -notmatch [regex]::Escape($TemplateName)) { continue }
                $newName = Replace-TemplateName $oldName $TemplateName $ProjectName
                Add-IniLine $defaultEngine $engineSection "+ActiveClassRedirects=(OldClassName=`"$oldName`",NewClassName=`"$newName`")"
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
if ($Type -eq 'Cpp') {
    Write-Step "Creating A${ProjectName}GameMode and copyright headers"

    $moduleDir = Join-Path $ProjectRoot "Source\$ProjectName"
    $existingGameMode = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Source') -Recurse -Filter '*.h' -File |
        Where-Object { (Read-Text $_.FullName) -match "class\s+(?:\w+_API\s+)?A${ProjectName}GameMode\b" } | Select-Object -First 1
    if ($existingGameMode) {
        Write-Host "  A${ProjectName}GameMode already exists in template: $($existingGameMode.FullName)"
    }
    else {
        foreach ($pair in @(@('GameMode.h.template', "${ProjectName}GameMode.h"), @('GameMode.cpp.template', "${ProjectName}GameMode.cpp"))) {
            $text = Read-Text (Join-Path $SkillRoot "templates\$($pair[0])")
            $text = $text.Replace('{{COPYRIGHT_LINE}}', $CopyrightLine).Replace('{{PROJECT_NAME}}', $ProjectName).Replace('{{API_MACRO}}', $ApiMacro)
            Write-Text (Join-Path $moduleDir $pair[1]) $text
            Write-Host "  created Source\$ProjectName\$($pair[1])"
        }
    }

    foreach ($src in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Source') -Recurse -File -Include '*.h', '*.cpp', '*.cs') {
        $text = Read-Text $src.FullName
        $text = $text.TrimStart([char]0xFEFF)
        if ($text -match '^\s*//[^\r\n]*Copyright[^\r\n]*') {
            $text = [regex]::Replace($text, '^\s*//[^\r\n]*Copyright[^\r\n]*', $CopyrightLine.Replace('$', '$$'))
        }
        else {
            $text = "$CopyrightLine`r`n`r`n$text"
        }
        Write-Text $src.FullName $text
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Git repository and devops_ue'

$git = Get-Command git -ErrorAction SilentlyContinue
Push-Location $ProjectRoot
try {
    if ($git -and -not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) { git init --quiet | Out-Null }
    elseif ($git) { Write-Host '  using the existing git repository' }
    $devopsDest = Join-Path $ProjectRoot 'devops_ue'
    $addedAsSubmodule = $false
    if ($useExistingDevops) {
        $addedAsSubmodule = $true  # keep what the user added (submodule or copy)
        Write-Host '  using the existing devops_ue'
    }
    elseif ($DevopsMode -eq 'Submodule' -and $git) {
        if (-not $DevopsUrl) { try { $DevopsUrl = (git -C $DevopsSource config --get remote.origin.url) } catch { $DevopsUrl = '' } }
        if ($DevopsUrl) {
            git submodule add $DevopsUrl devops_ue
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $devopsDest 'setup.bat'))) { $addedAsSubmodule = $true }
            else { Add-Warning "git submodule add $DevopsUrl failed, falling back to copying $DevopsSource" }
        }
        else { Add-Warning 'devops_ue remote url is unknown, copying the local repository instead of adding a submodule' }
    }
    if (-not $addedAsSubmodule) {
        if (Test-Path -LiteralPath $devopsDest) { Remove-Item -LiteralPath $devopsDest -Recurse -Force }
        robocopy $DevopsSource $devopsDest /E /XD .git /XF .git /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }
    }
}
finally { Pop-Location }

# ---------------------------------------------------------------------------------------------
Write-Step 'Running devops_ue\setup.bat'

$code = Invoke-Bat (Join-Path $ProjectRoot 'devops_ue\setup.bat')
$devopsData = Join-Path $ProjectRoot 'devops_data'
$configBat = Join-Path $devopsData 'config.bat'
if (-not (Test-Path -LiteralPath $configBat)) { throw "setup.bat failed (code $code): $configBat was not created" }

$config = Read-Text $configBat
# [^\r\n]* - keep CRLF line endings, cmd.exe misparses LF-only lines
$config = [regex]::Replace($config, '(?m)^set EnginePath=[^\r\n]*', ("set EnginePath=$EnginePath").Replace('$', '$$'))
$config = [regex]::Replace($config, '(?m)^set COPYRIGHT_LINE=[^\r\n]*', ("set COPYRIGHT_LINE=$CopyrightLine").Replace('$', '$$'))
# older config.template: unquoted '<' is parsed as a redirection even when the condition is false
$config = $config.Replace('set ProjectPureName=<ProjectName>', 'set "ProjectPureName=<ProjectName>"')
Write-Text $configBat $config

# ---------------------------------------------------------------------------------------------
Write-Step 'Copying root files, skills and AGENTS.md'

$rootFiles = @('.clang-format', '.gitignore', 'LICENSE.md', 'generate_project_files.bat', 'clean_intermediate_files.bat', 'package_game.bat')
if ($Type -eq 'Cpp') { $rootFiles += @('format_all_files.bat', 'run_tests.bat') }
$templateNames = @{ '.clang-format' = '.clang-format'; '.gitignore' = '.gitignore'; 'LICENSE.md' = 'LICENSE' }
foreach ($f in $rootFiles) {
    # prefer templates of the local devops_ue (may be newer than the submodule revision)
    $tplName = if ($templateNames.ContainsKey($f)) { $templateNames[$f] } else { [IO.Path]::GetFileNameWithoutExtension($f) }
    $src = Join-Path $DevopsSource "setup\$tplName.template"
    if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $devopsData $f }
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $ProjectRoot $f) -Force; Write-Host "  $f" }
    else { Add-Warning "$src not found" }
}
$gitignore = Join-Path $ProjectRoot '.gitignore'
$gitignoreText = Read-Text $gitignore
foreach ($entry in '*.slnx', '.idea/', '*.code-workspace') { if ($gitignoreText -notmatch [regex]::Escape($entry)) { $gitignoreText = $gitignoreText.TrimEnd() + "`r`n$entry`r`n" } }
Write-Text $gitignore $gitignoreText
Write-Text (Join-Path $ProjectRoot 'README.md') "# $ProjectName`r`n"

# devops skills -> .claude/skills
$skillsSrc = Join-Path $DevopsSource 'skills'
# .claude\skills always; .agents\skills (Codex / OpenCode / Antigravity) too when the folder is already there
# (install_skills.bat project codex|opencode|antigravity|all was run in this folder)
$skillsDsts = @('.claude\skills')
if (Test-Path -LiteralPath (Join-Path $ProjectRoot '.agents')) { $skillsDsts += '.agents\skills' }
if (Test-Path -LiteralPath $skillsSrc) {
    foreach ($rel in $skillsDsts) {
        $skillsDst = Join-Path $ProjectRoot $rel
        foreach ($skill in Get-ChildItem -LiteralPath $skillsSrc -Directory) {
            if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md'))) { continue }
            New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
            Copy-Item -LiteralPath $skill.FullName -Destination $skillsDst -Recurse -Force
            Remove-Item -LiteralPath (Join-Path $skillsDst "$($skill.Name)\devops_source.txt") -Force -ErrorAction SilentlyContinue
            Write-Host "  $rel\$($skill.Name)"
        }
    }
}

# AGENTS.md (+ CLAUDE.md that imports it for Claude Code)
$agentsTemplate = Join-Path $DevopsSource 'setup\AGENTS.md.template'
if (Test-Path -LiteralPath $agentsTemplate) {
    $projectTypeText = if ($Type -eq 'Cpp') { 'C++' } else { 'Blueprint' }
    $agents = (Read-Text $agentsTemplate).Replace('{{PROJECT_NAME}}', $ProjectName).Replace('{{PROJECT_TYPE}}', $projectTypeText).
        Replace('{{ENGINE_VERSION}}', $engineInfo.MajorMinor).Replace('{{COPYRIGHT_LINE}}', $CopyrightLine).
        Replace('{{MAIN_MAP}}', $(if ($mainMap) { $mainMap } else { '-' }))
    Write-Text (Join-Path $ProjectRoot 'AGENTS.md') $agents
    Write-Text (Join-Path $ProjectRoot 'CLAUDE.md') "@AGENTS.md`r`n"
    Write-Host '  AGENTS.md, CLAUDE.md'
}
else { Add-Warning "$agentsTemplate not found, AGENTS.md was not created" }

# ---------------------------------------------------------------------------------------------
# Engine registration for unregistered builds (writes the GUID association into the .uproject)
if (-not $EngineAssociation) {
    $vs = 'C:\Program Files (x86)\Epic Games\Launcher\Engine\Binaries\Win64\UnrealVersionSelector.exe'
    if (-not (Test-Path -LiteralPath $vs)) { $vs = Join-Path $env:LOCALAPPDATA 'Epic Games\Launcher\Engine\Binaries\Win64\UnrealVersionSelector.exe' }
    if (Test-Path -LiteralPath $vs) {
        Write-Step 'Registering engine for the project (UnrealVersionSelector)'
        & $vs -switchversionsilent $UProjectPath $EnginePath | Out-Null
    }
    else { Add-Warning 'EngineAssociation is empty and UnrealVersionSelector was not found: open the .uproject once and pick the engine.' }
}

# ---------------------------------------------------------------------------------------------
$editorReady = $true
if ($Type -eq 'Cpp') {
    Write-Step 'Generating project files'
    $code = Invoke-Bat (Join-Path $ProjectRoot 'generate_project_files.bat')
    if ($code -ne 0) { Add-Warning "generate_project_files.bat exited with code $code" }

    if (Get-Command clang-format -ErrorAction SilentlyContinue) {
        Write-Step 'Formatting sources with .clang-format'
        Invoke-Bat (Join-Path $ProjectRoot 'format_all_files.bat') | Out-Null
    }
    else { Add-Warning 'clang-format not found in PATH, sources were not formatted' }

    if (-not $SkipBuild) {
        Write-Step "Building ${ProjectName}Editor Win64 Development"
        $buildBat = Join-Path $EnginePath 'Engine\Build\BatchFiles\Build.bat'
        $code = Invoke-Bat $buildBat "${ProjectName}Editor Win64 Development -Project=`"$UProjectPath`" -WaitMutex"
        if ($code -ne 0) { $editorReady = $false; Add-Warning "Editor build failed (code $code)" }
    }
    else { $editorReady = $false }
}

# ---------------------------------------------------------------------------------------------
if ($isEmpty -and -not $SkipMainLevel) {
    $mapFile = Join-Path $ProjectRoot 'Content\Maps\MainLevel.umap'
    if (-not $editorReady) {
        Add-Warning 'Editor binaries are not built, MainLevel was not created. Create /Game/Maps/MainLevel in the editor (File > New Level > Empty Level).'
    }
    else {
        Write-Step 'Creating empty /Game/Maps/MainLevel (editor commandlet, may take a while on first launch)'
        $editorCmd = Join-Path $EnginePath 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
        $pyScript = Join-Path $PSScriptRoot 'create_main_level.py'
        $env:UE_NEW_LEVEL_PATH = '/Game/Maps/MainLevel'
        $editorArgs = "`"$UProjectPath`" -run=pythonscript -script=`"$pyScript`" -EnablePlugins=PythonScriptPlugin " +
            '-unattended -nopause -nosplash -nullrhi -nosound -nop4'
        Invoke-Exe $editorCmd $editorArgs | Out-Null

        if (-not (Test-Path -LiteralPath $mapFile)) {
            # fallback: enable the Python plugin in the .uproject for one run
            Write-Host '  retrying with PythonScriptPlugin enabled in the .uproject'
            $backup = Read-Text $UProjectPath
            $u = $backup | ConvertFrom-Json
            $plugins = @(); if ($u.PSObject.Properties['Plugins']) { $plugins = @($u.Plugins) }
            $plugins += [pscustomobject]@{ Name = 'PythonScriptPlugin'; Enabled = $true }
            $u | Add-Member -NotePropertyName Plugins -NotePropertyValue $plugins -Force
            Write-Text $UProjectPath ($u | ConvertTo-Json -Depth 10)
            try { Invoke-Exe $editorCmd $editorArgs | Out-Null } finally { Write-Text $UProjectPath $backup }
        }
        Remove-Item Env:\UE_NEW_LEVEL_PATH -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath $mapFile) { Write-Host "  created $mapFile" }
        else { Add-Warning "MainLevel was not created, see $ProjectRoot\Saved\Logs. Create /Game/Maps/MainLevel in the editor." }
    }
}

# ---------------------------------------------------------------------------------------------
if ($Package) {
    Write-Step 'Packaging (package_game.bat)'
    $code = Invoke-Bat (Join-Path $ProjectRoot 'package_game.bat')
    if ($code -ne 0) { Add-Warning "Packaging failed (code $code)" } else { Write-Host "  build: $ProjectRoot\Build" }
}

# ---------------------------------------------------------------------------------------------
Write-FinalStep 'Done'
Write-Host "Project: $UProjectPath"
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}

Write-Timing
