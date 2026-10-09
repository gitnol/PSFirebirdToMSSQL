#Requires -Version 7.0

<#
.SYNOPSIS
    Erstellt die Windows Aufgabenplanung (Task Scheduler) Jobs für SQLSync.

.DESCRIPTION
    Legt zwei Aufgaben an (Namen, Konfigdateien und Zeitpläne per Parameter):
    1. Tageslauf (Default "SQLSync_Firebird_Daily_Diff"): Mo-Fr ab 06:01 alle 30 Min. für 15 Std.
    2. Wochenlauf (Default "SQLSync_Firebird_Weekly_Full"): So 05:13.

    Ausführungskonto:
    - Standard: der aktuelle (bzw. per -RunAsUser angegebene) Benutzer; das Windows-Passwort wird
      abgefragt, damit die Aufgabe auch ohne Anmeldung läuft.
    - -GmsaAccount: Group Managed Service Account, kein Passwort nötig. Achtung: Credential-Manager-
      Einträge (Setup_Credentials.ps1) sind an das Konto gebunden, das sie anlegt – für ein gMSA
      eignet sich daher v. a. "Integrated Security" für SQL Server (siehe docs/architecture/CREDENTIAL_STRATEGY.md).

    Mit -WhatIf werden die Aufgaben nur berechnet und ausgegeben (keine Adminrechte, keine
    Passwortabfrage, keine Registrierung).

.PARAMETER InstallDir
    Ordner mit Sync_Firebird_MSSQL_AutoSchema.ps1 und den Konfigdateien (Default: Ordner dieses Skripts).

.PARAMETER DailyConfigFile
    Konfigdatei des Tageslaufs; relativ zu InstallDir oder absolut (Default: config.json).

.PARAMETER WeeklyConfigFile
    Konfigdatei des Wochenlaufs; relativ zu InstallDir oder absolut (Default: config_weekly_full.json).

.PARAMETER RunAsUser
    Ausführungskonto (Default: aktueller Benutzer). Wird ignoriert, wenn -GmsaAccount gesetzt ist.

.PARAMETER GmsaAccount
    gMSA im Format DOMAIN\name$ – Aufgaben laufen ohne gespeichertes Passwort.

.EXAMPLE
    .\Setup-ScheduledTasks.ps1 -WhatIf

.EXAMPLE
    .\Setup-ScheduledTasks.ps1 -InstallDir D:\Apps\SQLSync -DailyConfigFile config_daily.json -WeeklyConfigFile config_full.json

.NOTES
    - MultipleInstances: IgnoreNew (keine parallelen Starts, wenn ein Lauf hängt)
    - StopAtDurationEnd deaktiviert (kein harter Abbruch am Ende des Wiederholungsfensters)
    - Ohne -WhatIf sind Administratorrechte nötig.

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$InstallDir = $PSScriptRoot,

    [ValidateNotNullOrEmpty()]
    [string]$DailyConfigFile = "config.json",

    [ValidateNotNullOrEmpty()]
    [string]$WeeklyConfigFile = "config_weekly_full.json",

    [ValidateNotNullOrEmpty()]
    [string]$DailyTaskName = "SQLSync_Firebird_Daily_Diff",

    [ValidateNotNullOrEmpty()]
    [string]$WeeklyTaskName = "SQLSync_Firebird_Weekly_Full",

    [ValidatePattern('^\d{2}:\d{2}$')]
    [string]$DailyStart = "06:01",

    [System.DayOfWeek[]]$DailyDays = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'),

    [ValidateRange(1, 1440)]
    [int]$DailyIntervalMinutes = 30,

    [ValidateRange(1, 24)]
    [int]$DailyDurationHours = 15,

    [System.DayOfWeek]$WeeklyDay = 'Sunday',

    [ValidatePattern('^\d{2}:\d{2}$')]
    [string]$WeeklyStart = "05:13",

    [string]$RunAsUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,

    [ValidatePattern('^[^\\]+\\[^\\]+\$$')]
    [string]$GmsaAccount
)

# -----------------------------------------------------------------------------
# VORBEDINGUNGEN
# -----------------------------------------------------------------------------
$IsWhatIf = [bool]$WhatIfPreference

if (-not $IsWhatIf) {
    $Principal = [System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Dieses Skript benötigt Administrator-Rechte (oder -WhatIf für eine Vorschau)."
        exit 1
    }
}

# Pfade auflösen (relative Konfignamen gegen InstallDir)
function Resolve-InstallPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path $InstallDir $Path
}
$ScriptPath = Join-Path $InstallDir "Sync_Firebird_MSSQL_AutoSchema.ps1"
$DailyConfigPath = Resolve-InstallPath $DailyConfigFile
$WeeklyConfigPath = Resolve-InstallPath $WeeklyConfigFile

foreach ($p in @($ScriptPath, $DailyConfigPath, $WeeklyConfigPath)) {
    if (-not (Test-Path $p)) {
        Write-Warning "Nicht gefunden: $p (die Aufgabe wird trotzdem angelegt)."
    }
}

# Pfad zur PowerShell-7-Executable der aktuellen Sitzung
$PwshPath = (Get-Process -Id $PID).Path
if (-not $PwshPath -or -not (Test-Path $PwshPath)) { $PwshPath = "pwsh.exe" }

# -----------------------------------------------------------------------------
# TASK-DEFINITIONEN
# -----------------------------------------------------------------------------
function New-SyncAction([string]$ConfigPath) {
    New-ScheduledTaskAction `
        -Execute $PwshPath `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -ConfigFile `"$ConfigPath`"" `
        -WorkingDirectory $InstallDir
}

# Tageslauf: Wiederholung über einen Hilfs-Trigger erzeugen und in den Wochen-Trigger übernehmen
$RepetitionTrigger = New-ScheduledTaskTrigger -Once -At "00:00" `
    -RepetitionInterval (New-TimeSpan -Minutes $DailyIntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Hours $DailyDurationHours)
$RepetitionTrigger.Repetition.StopAtDurationEnd = $false

$DailyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DailyDays -At $DailyStart
$DailyTrigger.Repetition = $RepetitionTrigger.Repetition

$WeeklyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $WeeklyDay -At $WeeklyStart

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

if ($GmsaAccount) {
    $TaskPrincipal = New-ScheduledTaskPrincipal -UserId $GmsaAccount -LogonType Password
}
else {
    $TaskPrincipal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType Password
}

$Tasks = @(
    [PSCustomObject]@{ TaskName = $DailyTaskName; Action = (New-SyncAction $DailyConfigPath); Trigger = $DailyTrigger
        Description = "Firebird Sync: Inkrementell ($($DailyDays -join ','), alle $DailyIntervalMinutes Min.)" }
    [PSCustomObject]@{ TaskName = $WeeklyTaskName; Action = (New-SyncAction $WeeklyConfigPath); Trigger = $WeeklyTrigger
        Description = "Firebird Sync: Weekly Full & Repair ($WeeklyDay)" }
)

# -----------------------------------------------------------------------------
# REGISTRIEREN
# -----------------------------------------------------------------------------
$Password = $null
if (-not $IsWhatIf -and -not $GmsaAccount) {
    Write-Host "Aufgaben laufen als: $RunAsUser" -ForegroundColor Cyan
    Write-Host "HINWEIS: Damit die Aufgaben auch ohne Anmeldung laufen, wird das Windows-Passwort hinterlegt." -ForegroundColor Yellow
    try {
        $Creds = Get-Credential -UserName $RunAsUser -Message "Windows-Passwort für die Aufgabenplanung"
        $Password = $Creds.GetNetworkCredential().Password
    }
    catch {
        Write-Error "Passwort-Eingabe abgebrochen. Skript beendet."
        exit 1
    }
}

foreach ($Task in $Tasks) {
    $Registered = $false
    if ($PSCmdlet.ShouldProcess($Task.TaskName, "Aufgabe registrieren ($($Task.Action.Arguments))")) {
        Unregister-ScheduledTask -TaskName $Task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        $RegisterParams = @{
            TaskName    = $Task.TaskName
            Action      = $Task.Action
            Trigger     = $Task.Trigger
            Settings    = $Settings
            Description = $Task.Description
            Force       = $true
        }
        if ($GmsaAccount) { $RegisterParams.Principal = $TaskPrincipal }
        else { $RegisterParams.User = $RunAsUser; $RegisterParams.Password = $Password }
        Register-ScheduledTask @RegisterParams | Out-Null
        $Registered = $true
        Write-Host "OK: $($Task.TaskName) erstellt." -ForegroundColor Green
    }

    [PSCustomObject]@{
        TaskName   = $Task.TaskName
        Action     = $Task.Action
        Trigger    = $Task.Trigger
        Settings   = $Settings
        Principal  = $TaskPrincipal
        Registered = $Registered
    }
}
