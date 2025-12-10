#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Erstellt die Windows Aufgabenplanung (Task Scheduler) Jobs für SQLSync.

.DESCRIPTION
    Legt zwei Aufgaben an:
    1. "SQLSync_Firebird_Daily_Diff": Mo-Fr, 06:01 - 21:01 alle 30 Min.
    2. "SQLSync_Firebird_Weekly_Full": So, 05:13 (Einmalig/Full).
    
    Die Aufgaben laufen UNABHÄNGIG von der Benutzeranmeldung (Passwort wird abgefragt).

.NOTES
    Fixes & Anpassungen:
    - MultipleInstances: IgnoreNew (verhindert parallele Starts wenn ein Job hängt)
    - LogonType Parameter entfernt (wird durch -Password impliziert)
    - StopAtDurationEnd deaktiviert (kein harter Abbruch um 21:01)

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL
#>

# -----------------------------------------------------------------------------
# KONFIGURATION
# -----------------------------------------------------------------------------
$ScriptPath = "E:\SQLSync_Firebird_to_MSSQL\Sync_Firebird_MSSQL_AutoSchema.ps1"
$WorkDir = "E:\SQLSync_Firebird_to_MSSQL"

# Prüfen, ob wir wirklich in PowerShell Core (7+) laufen. (Sollte durch Direktive weiter oben schon sichergestellt sein)
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "KRITISCH: Dieses Skript muss mit PowerShell 7 (pwsh.exe) ausgeführt werden!"
    Write-Host "Aktuelle Version: $($PSVersionTable.PSVersion.ToString())" -ForegroundColor Red
    exit 1
}

# Sicherer Pfad zur aktuellen Executable (jetzt wissen wir, dass es v7 ist)
$PwshPath = (Get-Process -Id $PID).Path

if (-not (Test-Path $PwshPath)) { $PwshPath = "pwsh.exe" } # Fallback auf PATH

# Task 1: Daily Diff
$TaskName1 = "SQLSync_Firebird_Daily_Diff"
$ConfigPath1 = "E:\SQLSync_Firebird_to_MSSQL\config_LEWAECHT_DIFF_ONLY.json"

# Task 2: Weekly Full
$TaskName2 = "SQLSync_Firebird_Weekly_Full"
$ConfigPath2 = "E:\SQLSync_Firebird_to_MSSQL\config_LEWAECHT_RecreateTable_ForceFullSync.json"

# -----------------------------------------------------------------------------
# HELPER
# -----------------------------------------------------------------------------
function Test-Admin {
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [System.Security.Principal.WindowsPrincipal]$Identity
    return $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Warning "Dieses Skript benötigt Administrator-Rechte."
    Write-Warning "Bitte starte PowerShell als Administrator neu."
    exit
}

if (-not (Test-Path $ScriptPath)) {
    Write-Warning "ACHTUNG: Skript nicht gefunden unter: $ScriptPath"
    Write-Host "Die Tasks werden trotzdem angelegt." -ForegroundColor Yellow
}

$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "Erstelle Tasks für Benutzer: $CurrentUser" -ForegroundColor Cyan
Write-Host "HINWEIS: Damit die Tasks auch laufen, wenn niemand angemeldet ist," -ForegroundColor Yellow
Write-Host "muss das Windows-Passwort hinterlegt werden." -ForegroundColor Yellow
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

# Passwort sicher abfragen
try {
    $Creds = Get-Credential -UserName $CurrentUser -Message "Bitte Windows-Passwort eingeben (für Task-Planer)"
    $UserPassword = $Creds.GetNetworkCredential().Password
}
catch {
    Write-Error "Passwort-Eingabe abgebrochen. Skript beendet."
    exit
}

# -----------------------------------------------------------------------------
# TASK 1: Mo-Fr, 06:01 - 21:01, alle 30 Min
# -----------------------------------------------------------------------------
Write-Host "Konfiguriere Task 1: $TaskName1 ..." -ForegroundColor Yellow

$Action1 = New-ScheduledTaskAction `
    -Execute $PwshPath `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -ConfigFile `"$ConfigPath1`"" `
    -WorkingDirectory $WorkDir

# TRICK: Wir erstellen einen 'Dummy' Trigger (Einmalig)
$DummyTrigger = New-ScheduledTaskTrigger -Once -At "00:00" `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration (New-TimeSpan -Hours 15)

# WICHTIG: Verhindert, dass der Task um 21:01 hart gekillt wird, falls er noch läuft
$DummyTrigger.Repetition.StopAtDurationEnd = $false

# Der echte Trigger (Mo-Fr)
$Trigger1 = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday `
    -At "06:01"

# Das Repetition-Objekt vom Dummy in den echten Trigger injizieren
$Trigger1.Repetition = $DummyTrigger.Repetition

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew # HIER GEÄNDERT: Neue Instanz wird ignoriert, wenn alte noch läuft

# Task registrieren (Mit Passwort, OHNE expliziten LogonType Parameter)
Unregister-ScheduledTask -TaskName $TaskName1 -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask `
    -TaskName $TaskName1 `
    -Action $Action1 `
    -Trigger $Trigger1 `
    -Settings $Settings `
    -User $CurrentUser `
    -Password $UserPassword `
    -Description "Firebird Sync: Inkrementell (Mo-Fr, alle 30 Min)" `
    -Force | Out-Null

Write-Host "OK: $TaskName1 erstellt." -ForegroundColor Green


# -----------------------------------------------------------------------------
# TASK 2: Sonntag, 05:13
# -----------------------------------------------------------------------------
Write-Host "Konfiguriere Task 2: $TaskName2 ..." -ForegroundColor Yellow

$Action2 = New-ScheduledTaskAction `
    -Execute $PwshPath `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -ConfigFile `"$ConfigPath2`"" `
    -WorkingDirectory $WorkDir

$Trigger2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "05:13"

Register-ScheduledTask `
    -TaskName $TaskName2 `
    -Action $Action2 `
    -Trigger $Trigger2 `
    -Settings $Settings `
    -User $CurrentUser `
    -Password $UserPassword `
    -Description "Firebird Sync: Weekly Full & Repair (Sonntag)" `
    -Force | Out-Null

Write-Host "OK: $TaskName2 erstellt." -ForegroundColor Green
Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "FERTIG. Bitte prüfe die Aufgaben in der Aufgabenplanung." -ForegroundColor Cyan