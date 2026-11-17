# Copyright LifeEXE. All Rights Reserved.
# Creates a C++ plugin skeleton in <project>\Plugins\<Name> (.uplugin, module Build.cs, module header/source).
#   plugin_create.ps1 -ProjectPath C:\Game -Name WeaponSystem                       # Runtime module
#   plugin_create.ps1 -ProjectPath C:\Game -Name WeaponSystem -EditorModule         # + WeaponSystemEditor (Editor module)
#   plugin_create.ps1 -ProjectPath C:\Game -Name WeaponSystem -Content              # plugin may contain content (Content\ folder)
#   plugin_create.ps1 -ProjectPath C:\Game -Name WeaponSystem -AddToProject         # + the module in <Game>.Build.cs dependencies
#   plugin_create.ps1 -ProjectPath C:\Game -Name WeaponSystem -GenerateProjectFiles # + regenerate the .sln
# The files are written by this script (no editor needed), formatted with the project's .clang-format.
# Packaging the plugin is ue-plugin-package.
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [Parameter(Mandatory)][string]$Name,
    [ValidateSet('Runtime', 'Developer', 'Editor')][string]$ModuleType = 'Runtime',
    [ValidateSet('Default', 'PreDefault', 'PostDefault', 'PostEngineInit', 'PreLoadingScreen')][string]$LoadingPhase = 'Default',
    # adds a second module <Name>Editor (Type Editor, loaded PostEngineInit)
    [switch]$EditorModule,
    [switch]$Content,
    [string]$FriendlyName = '',
    [string]$Description = '',
    [string]$Category = 'Other',
    [string]$Author = '',
    # add the plugin's module to PublicDependencyModuleNames of the project's own module
    [switch]$AddToProject,
    [switch]$GenerateProjectFiles,
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
function Add-Warning([string]$Text) { [void]$Warnings.Add($Text); Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path, [string]$Text) {
    $d = Split-Path -Parent $Path; if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Utf8NoBom)
}
function Get-ConfigValue([string]$ConfigBat, [string]$Name) {
    if (-not (Test-Path -LiteralPath $ConfigBat)) { return '' }
    $v = [IO.File]::ReadAllLines($ConfigBat) | Where-Object { $_ -match "^set $([regex]::Escape($Name))=(.*)$" } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1
    return "$v"
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$ProjectName = $uprojectFile.BaseName
$isCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot "Source\$ProjectName")
Write-Host "  $($uprojectFile.FullName) ($(if ($isCpp) { 'C++' } else { 'Blueprint' }))"
if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw "Invalid plugin name '$Name': letters, digits, underscore; must start with a letter" }
if ($Name -eq $ProjectName) { throw "Plugin name '$Name' equals the project name: module names must be unique" }
if (-not $isCpp) { Add-Warning 'Blueprint-only project: it becomes a C++ project once a source plugin is compiled (needs Visual Studio C++); use ue-web-setup / add a C++ module if the project is meant for the web' }

$pluginDir = Join-Path $ProjectRoot "Plugins\$Name"
if (Test-Path -LiteralPath $pluginDir) { throw "Already exists: $pluginDir" }
foreach ($m in $Name, "${Name}Editor") {
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot "Source\$m")) { throw "A project module named '$m' already exists in Source: pick another plugin name" }
}

# copyright / author
$configBat = Join-Path $ProjectRoot 'devops_data\config.bat'
$copyright = Get-ConfigValue $configBat 'COPYRIGHT_LINE'
$defaultGame = Join-Path $ProjectRoot 'Config\DefaultGame.ini'
$gameIni = if (Test-Path -LiteralPath $defaultGame) { Read-Text $defaultGame } else { '' }
if (-not $copyright -or $copyright -match 'My game copyright') {
    $notice = ([regex]::Match($gameIni, '(?m)^CopyrightNotice=(.*)$')).Groups[1].Value.Trim()
    $copyright = if ($notice) { "// $notice" } else { "// Copyright $ProjectName. All Rights Reserved." }
}
if (-not $Author) { $Author = ([regex]::Match($gameIni, '(?m)^CompanyName=(.*)$')).Groups[1].Value.Trim() }
if (-not $FriendlyName) { $FriendlyName = ($Name -creplace '([a-z0-9])([A-Z])', '$1 $2') }
if (-not $Description) { $Description = "$FriendlyName plugin" }
$up = $Name.ToUpperInvariant()

# ---------------------------------------------------------------------------------------------
function New-ModuleFiles([string]$Module, [string]$Type, [string]$Phase, [bool]$IsEditor) {
    $modDir = Join-Path $pluginDir "Source\$Module"
    $editorDeps = if ($IsEditor) { ', "UnrealEd"' } else { '' }
    Write-Text (Join-Path $modDir "$Module.Build.cs") @"
$copyright

using UnrealBuildTool;

public class $Module : ModuleRules
{
    public $Module(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = ModuleRules.PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(new string[] { "Core" });

        PrivateDependencyModuleNames.AddRange(new string[] { "CoreUObject", "Engine", "Slate", "SlateCore"$editorDeps });
    }
}
"@
    Write-Text (Join-Path $modDir "Public\$Module.h") @"
$copyright

#pragma once

#include "Modules/ModuleManager.h"

class F${Module}Module : public IModuleInterface
{
public:
    virtual void StartupModule() override;
    virtual void ShutdownModule() override;
};
"@
    Write-Text (Join-Path $modDir "Private\$Module.cpp") @"
$copyright

#include "$Module.h"

#define LOCTEXT_NAMESPACE "F${Module}Module"

void F${Module}Module::StartupModule() {}

void F${Module}Module::ShutdownModule() {}

#undef LOCTEXT_NAMESPACE

IMPLEMENT_MODULE(F${Module}Module, $Module)
"@
}

Write-Step "Creating Plugins\$Name"
New-ModuleFiles $Name $ModuleType $LoadingPhase ($ModuleType -eq 'Editor')
$modules = @([pscustomobject]@{ Name = $Name; Type = $ModuleType; Phase = $LoadingPhase })
if ($EditorModule) {
    New-ModuleFiles "${Name}Editor" 'Editor' 'PostEngineInit' $true
    $modules += [pscustomobject]@{ Name = "${Name}Editor"; Type = 'Editor'; Phase = 'PostEngineInit' }
}

$moduleJson = ($modules | ForEach-Object {
        "        {`n            `"Name`": `"$($_.Name)`",`n            `"Type`": `"$($_.Type)`",`n            `"LoadingPhase`": `"$($_.Phase)`"`n        }"
    }) -join ",`n"
$canContent = if ($Content) { 'true' } else { 'false' }
function ConvertTo-JsonString([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }
Write-Text (Join-Path $pluginDir "$Name.uplugin") @"
{
    "FileVersion": 3,
    "Version": 1,
    "VersionName": "1.0",
    "FriendlyName": "$(ConvertTo-JsonString $FriendlyName)",
    "Description": "$(ConvertTo-JsonString $Description)",
    "Category": "$(ConvertTo-JsonString $Category)",
    "CreatedBy": "$(ConvertTo-JsonString $Author)",
    "CreatedByURL": "",
    "DocsURL": "",
    "MarketplaceURL": "",
    "SupportURL": "",
    "CanContainContent": $canContent,
    "IsBetaVersion": false,
    "IsExperimentalVersion": false,
    "Installed": false,
    "Modules": [
$moduleJson
    ]
}
"@
if ($Content) { Write-Text (Join-Path $pluginDir 'Content\.gitkeep') '' }

# valid JSON?
try { $null = (Read-Text (Join-Path $pluginDir "$Name.uplugin")) | ConvertFrom-Json } catch { throw "Generated $Name.uplugin is not valid JSON: $($_.Exception.Message)" }

# clang-format the C++ / C# files with the project's style
$created = @(Get-ChildItem -LiteralPath $pluginDir -Recurse -File | Where-Object { $_.Extension -in '.cs', '.h', '.cpp' } | ForEach-Object FullName)
if ((Test-Path -LiteralPath (Join-Path $ProjectRoot '.clang-format')) -and (Get-Command clang-format -ErrorAction SilentlyContinue)) {
    foreach ($f in $created) { & clang-format -i --style=file $f }
}
else { Add-Warning 'clang-format or .clang-format missing: files are not formatted (ue-format later)' }
Get-ChildItem -LiteralPath $pluginDir -Recurse -File | ForEach-Object { Write-Host "  created $($_.FullName.Replace($ProjectRoot + '\', ''))" }

# ---------------------------------------------------------------------------------------------
if ($AddToProject) {
    Write-Step "Adding '$Name' to $ProjectName.Build.cs"
    $buildCs = Join-Path $ProjectRoot "Source\$ProjectName\$ProjectName.Build.cs"
    if (-not (Test-Path -LiteralPath $buildCs)) { Add-Warning "$buildCs not found: add `"$Name`" to the module's dependencies yourself" }
    else {
        $text = [IO.File]::ReadAllText($buildCs)
        $rx = [regex]'(PublicDependencyModuleNames\.AddRange\(\s*new\s+string\[\]\s*\{)(\s*)'
        if ($text -match "`"$([regex]::Escape($Name))`"") { Write-Host "  already references $Name" }
        elseif (-not $rx.IsMatch($text)) { Add-Warning "No PublicDependencyModuleNames.AddRange(new string[] { ... }) in ${buildCs}: add `"$Name`" yourself" }
        else {
            # the name goes first in the existing array: works for any layout of the file
            $text = $rx.Replace($text, { param($m) $m.Groups[1].Value + ' "' + $Name + '",' + $m.Groups[2].Value }, 1)
            [IO.File]::WriteAllText($buildCs, $text, $Utf8NoBom)
            Write-Host "  added `"$Name`" to PublicDependencyModuleNames in $ProjectName.Build.cs"
        }
    }
}
if ($GenerateProjectFiles) {
    Write-Step 'Generating project files'
    if (-not $EnginePath) {
        $e = Get-ConfigValue $configBat 'EnginePath'
        if ($e -and (Test-Path -LiteralPath (Join-Path $e 'Engine\Build\Build.version'))) { $EnginePath = $e }
        else {
            $common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
            if (Test-Path -LiteralPath $common) {
                . $common
                $assoc = ([regex]::Match((Read-Text $uprojectFile.FullName), '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
                $m = Get-UnrealEngines | Where-Object { $_.Association -eq $assoc -or $_.MajorMinor -eq $assoc } | Select-Object -First 1
                if ($m) { $EnginePath = $m.Path }
            }
        }
    }
    $ubt = if ($EnginePath) { Join-Path $EnginePath 'Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.exe' } else { '' }
    if (-not $ubt -or -not (Test-Path -LiteralPath $ubt)) { Add-Warning 'UnrealBuildTool not found: run devops_ue\misc\generate_project_files.bat yourself' }
    else {
        & $ubt -projectfiles "-project=$($uprojectFile.FullName)" -game -rocket -progress
        if ($LASTEXITCODE -ne 0) { Add-Warning "UnrealBuildTool -projectfiles exited with $LASTEXITCODE" }
    }
}

Write-FinalStep "Plugin '$Name' created in Plugins\$Name"
Write-Host "  next: generate project files + build the editor target (ue-run-tests builds it, or open the .uproject); then add classes under Plugins\$Name\Source\$Name\Public|Private"
if ($Warnings.Count -gt 0) { Write-Host "  $($Warnings.Count) warning(s)" -ForegroundColor Yellow }
Write-Timing
