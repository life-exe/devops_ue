# Copyright LifeEXE. All Rights Reserved.
# Shared helpers for ue-create-project scripts (dot-source this file).

function Get-UnrealEngineInfo {
    param([string]$Path, [string]$Association = '', [string]$Source = '')

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $Path = $Path.Trim().TrimEnd('\', '/')
    $buildVersion = Join-Path $Path 'Engine\Build\Build.version'
    if (-not (Test-Path -LiteralPath $buildVersion)) { return $null }

    try { $json = [IO.File]::ReadAllText($buildVersion) | ConvertFrom-Json } catch { return $null }
    if ([int]$json.MajorVersion -lt 5) { return $null }

    $installed = Test-Path -LiteralPath (Join-Path $Path 'Engine\Build\InstalledBuild.txt')
    [pscustomobject]@{
        Version     = "$($json.MajorVersion).$($json.MinorVersion).$($json.PatchVersion)"
        MajorMinor  = "$($json.MajorVersion).$($json.MinorVersion)"
        Path        = (Resolve-Path -LiteralPath $Path).Path
        Association = $Association
        Installed   = $installed
        EditorBuilt = Test-Path -LiteralPath (Join-Path $Path 'Engine\Binaries\Win64\UnrealEditor.exe')
        Source      = $Source
    }
}

function Get-UnrealEngines {
    $found = New-Object System.Collections.ArrayList

    # 1. Epic Games Launcher installs (registry)
    foreach ($root in 'HKLM:\SOFTWARE\EpicGames\Unreal Engine', 'HKLM:\SOFTWARE\WOW6432Node\EpicGames\Unreal Engine') {
        if (-not (Test-Path $root)) { continue }
        foreach ($key in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            $dir = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstalledDirectory
            $info = Get-UnrealEngineInfo -Path $dir -Association $key.PSChildName -Source 'Launcher'
            if ($info) { [void]$found.Add($info) }
        }
    }

    # 2. Epic Games Launcher manifest
    $launcherDat = Join-Path $env:ProgramData 'Epic\UnrealEngineLauncher\LauncherInstalled.dat'
    if (Test-Path -LiteralPath $launcherDat) {
        try {
            $dat = [IO.File]::ReadAllText($launcherDat) | ConvertFrom-Json
            foreach ($item in $dat.InstallationList) {
                if ($item.AppName -notmatch '^UE_(\d+\.\d+)') { continue }
                $info = Get-UnrealEngineInfo -Path $item.InstallLocation -Association $Matches[1] -Source 'Launcher'
                if ($info) { [void]$found.Add($info) }
            }
        } catch { }
    }

    # 3. Source / custom builds registered by UnrealVersionSelector
    $builds = 'HKCU:\Software\Epic Games\Unreal Engine\Builds'
    if (Test-Path $builds) {
        $props = Get-ItemProperty $builds
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $info = Get-UnrealEngineInfo -Path $p.Value -Association $p.Name -Source 'Registered build'
            if ($info) { [void]$found.Add($info) }
        }
    }

    # 4. Well-known folders on every local drive
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root -match '^[A-Z]:\\$' }
    foreach ($d in $drives) {
        foreach ($pattern in 'Program Files\Epic Games\UE_*', 'Epic Games\UE_*', 'EpicGames\UE_*', 'UE_*', 'UnrealEngine*', 'Unreal\UE_*', 'Unreal\UnrealEngine*') {
            foreach ($dir in Get-ChildItem -Path (Join-Path $d.Root $pattern) -Directory -ErrorAction SilentlyContinue) {
                $assoc = ''
                $isInstalled = Test-Path -LiteralPath (Join-Path $dir.FullName 'Engine\Build\InstalledBuild.txt')
                if ($isInstalled -and $dir.Name -match '^UE_(\d+\.\d+)$') { $assoc = $Matches[1] }
                $info = Get-UnrealEngineInfo -Path $dir.FullName -Association $assoc -Source 'Folder scan'
                if ($info) { [void]$found.Add($info) }
            }
        }
    }

    # de-duplicate by path, prefer entries that know their association
    $found | Group-Object { $_.Path.ToLowerInvariant() } | ForEach-Object {
        $withAssoc = $_.Group | Where-Object { $_.Association } | Select-Object -First 1
        if ($withAssoc) { $withAssoc } else { $_.Group[0] }
    } | Sort-Object { [version]$_.Version } -Descending
}

function Get-EngineAssociation {
    param([Parameter(Mandatory)][string]$EnginePath)
    $target = (Resolve-Path -LiteralPath $EnginePath).Path.TrimEnd('\').ToLowerInvariant()
    $match = Get-UnrealEngines | Where-Object { $_.Path.TrimEnd('\').ToLowerInvariant() -eq $target } | Select-Object -First 1
    if ($match) { return $match.Association }
    return ''
}

function Get-TemplateDisplayName {
    param([string]$TemplateDefsPath)
    if (-not (Test-Path -LiteralPath $TemplateDefsPath)) { return '' }
    foreach ($line in [IO.File]::ReadAllLines($TemplateDefsPath)) {
        if ($line -match '^LocalizedDisplayNames=\(Language="en",Text="([^"]+)"\)') { return $Matches[1] }
    }
    return ''
}

# Genre variants of a C++ template (UE 5.6+: Content\Variant_<Name>\...\<Level>.umap). The editor's "Variants" dropdown only picks
# the start map / game mode; the template files of all variants are always copied. Returns Name, Folder, Map (/Game/... without
# the object suffix), GameMode (/Game/...BP_x.BP_x_C or '' when the variant has no game mode blueprint).
function Get-TemplateVariants {
    param([Parameter(Mandatory)][string]$TemplateDir)

    $content = Join-Path $TemplateDir 'Content'
    foreach ($dir in Get-ChildItem -LiteralPath $content -Directory -Filter 'Variant_*' -ErrorAction SilentlyContinue | Sort-Object Name) {
        $map = Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter '*.umap' -File | Sort-Object { $_.FullName.Length } | Select-Object -First 1
        if (-not $map) { continue }
        $toGame = { param($f) '/Game/' + $f.FullName.Substring($content.TrimEnd('\').Length + 1).Replace('\', '/') -replace '\.[^./]+$', '' }
        $gm = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'BP_*GameMode*.uasset' -File)
        $gmPath = ''
        if ($gm.Count -eq 1) { $p = & $toGame $gm[0]; $gmPath = "$p.$([IO.Path]::GetFileNameWithoutExtension($gm[0].Name))_C" }
        $mapPath = & $toGame $map
        [pscustomobject]@{
            Name     = $dir.Name.Substring('Variant_'.Length)
            Folder   = $dir.Name
            Map      = $mapPath
            GameMode = $gmPath
        }
    }
}

function Get-UnrealTemplates {
    param([Parameter(Mandatory)][string]$EnginePath, [ValidateSet('Cpp', 'Blueprint')][string]$Type = 'Cpp')

    $templatesDir = Join-Path $EnginePath 'Templates'
    foreach ($dir in Get-ChildItem -LiteralPath $templatesDir -Directory -Filter 'TP_*' -ErrorAction SilentlyContinue) {
        if ($dir.Name -in 'TP_Blank', 'TP_BlankBP') { continue }  # used for the empty MainLevel option
        $defs = Join-Path $dir.FullName 'Config\TemplateDefs.ini'
        if (-not (Test-Path -LiteralPath $defs)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName "$($dir.Name).uproject"))) { continue }
        $hasSource = Test-Path -LiteralPath (Join-Path $dir.FullName 'Source')
        if ($Type -eq 'Cpp' -and -not $hasSource) { continue }
        if ($Type -eq 'Blueprint' -and $hasSource) { continue }

        $category = ''
        foreach ($line in [IO.File]::ReadAllLines($defs)) { if ($line -match '^Categories=(.+)$') { $category = $Matches[1].Trim(); break } }

        [pscustomobject]@{
            Name        = $dir.Name
            DisplayName = Get-TemplateDisplayName $defs
            Category    = $category
            Variants    = @(Get-TemplateVariants -TemplateDir $dir.FullName | ForEach-Object Name)
        }
    }
}
