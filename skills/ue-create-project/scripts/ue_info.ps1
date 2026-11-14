# Copyright LifeEXE. All Rights Reserved.
# Prints information required by the ue-create-project skill as JSON.
#   ue_info.ps1 -Engines
#   ue_info.ps1 -Templates -EnginePath "C:\Program Files\Epic Games\UE_5.9" -Type Cpp
[CmdletBinding()]
param(
    [switch]$Engines,
    [switch]$Templates,
    [string]$EnginePath,
    [ValidateSet('Cpp', 'Blueprint')][string]$Type = 'Cpp'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ue_common.ps1')

if ($Engines) {
    $list = @(Get-UnrealEngines)
    ConvertTo-Json -InputObject $list -Depth 3
}
elseif ($Templates) {
    if (-not $EnginePath) { throw '-EnginePath is required with -Templates' }
    $list = @(Get-UnrealTemplates -EnginePath $EnginePath -Type $Type | Sort-Object Category, DisplayName)
    ConvertTo-Json -InputObject $list -Depth 3
}
else {
    Write-Host 'Usage: ue_info.ps1 -Engines | -Templates -EnginePath <path> -Type Cpp|Blueprint'
    exit 1
}
