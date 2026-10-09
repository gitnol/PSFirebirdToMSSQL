#Requires -Version 7.0
<#
.SYNOPSIS
    Statische Analyse aller Skripte mit der gepinnten PSScriptAnalyzer-Version (lokal und in der CI).

.EXAMPLE
    pwsh -NoProfile -File .\tests\scriptanalyzer.ps1

.NOTES
    Endet mit Exit-Code 1, wenn ein Befund der Severity Error vorliegt. Warnungen und Informationen
    werden nur gezählt (Liste in docs/BACKLOG.md). Begründete Ausnahmen stehen als
    SuppressMessageAttribute direkt an der betroffenen Stelle.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Required = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'RequiredModules.psd1')
Import-Module PSScriptAnalyzer -RequiredVersion $Required.PSScriptAnalyzer.RequiredVersion -Force

$Findings = @(Invoke-ScriptAnalyzer -Path $RepoRoot -Recurse)
$Errors = @($Findings | Where-Object Severity -eq 'Error')
Write-Host ("PSScriptAnalyzer {0}: {1} Error, {2} Warning, {3} Information" -f $Required.PSScriptAnalyzer.RequiredVersion,
    $Errors.Count, @($Findings | Where-Object Severity -eq 'Warning').Count, @($Findings | Where-Object Severity -eq 'Information').Count)

if ($Errors.Count -gt 0) {
    $Errors | Format-Table RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    exit 1
}
exit 0
