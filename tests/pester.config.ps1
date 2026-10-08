#Requires -Version 7.0
<#
.SYNOPSIS
    Führt die Unit-Tests mit der gepinnten Pester-Version und Code-Coverage für SQLSyncCommon.psm1 aus.

.EXAMPLE
    pwsh -NoProfile -File .\tests\pester.config.ps1

.NOTES
    Endet mit Exit-Code 1, wenn ein Test fehlschlägt oder die Coverage unter dem Ziel liegt.
    Ohne Datenbankverbindung lauffähig; nur Windows (Credential Manager, Typ-Pfade).
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Required = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'RequiredModules.psd1')
Import-Module Pester -RequiredVersion $Required.Pester.RequiredVersion -Force

$Config = New-PesterConfiguration
$Config.Run.Path = Join-Path $PSScriptRoot 'Unit'
$Config.Run.Exit = $true
$Config.Output.Verbosity = 'Normal'
$Config.CodeCoverage.Enabled = $true
$Config.CodeCoverage.Path = Join-Path $RepoRoot 'SQLSyncCommon.psm1'
$Config.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'coverage.xml'
# Kalibriert in I3 (Messwert siehe docs/testing/UNIT_TESTS.md); nur anheben, nie absenken.
$Config.CodeCoverage.CoveragePercentTarget = 80

Invoke-Pester -Configuration $Config
