#Requires -Version 7.0

<#
.SYNOPSIS
    Konfiguration Manager - Firebird Tabellen Auswahl (Toggle Logik)

.DESCRIPTION
    Dieses Skript liest alle Tabellen aus Firebird aus.
    Logik:
    - Tabellen auswählen, die GEÄNDERT werden sollen.
    - Ist eine Tabelle NOCH NICHT in der Config -> Wird HINZUGEFÜGT.
    - Ist eine Tabelle BEREITS in der Config -> Wird ENTFERNT.
    - Nicht ausgewählte Tabellen bleiben UNVERÄNDERT.

.PARAMETER ConfigFile
    Optional. Zu bearbeitende Konfigurationsdatei (Default: config.json im Skriptordner);
    relativ zum Skriptordner oder absolut.

.PARAMETER KeepBackups
    Optional. Anzahl der Backups (<Konfig>.<yyyyMMdd_HHmmss>.bak) dieser Konfig, die nach dem Speichern
    erhalten bleiben; ältere werden gelöscht (Default 5, 1..1000).

.NOTES
    Version: 2.2 (Backup-Rotation -KeepBackups)

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL

#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,

    # Anzahl der Backups dieser Konfig, die nach dem Speichern erhalten bleiben (ältere werden gelöscht)
    [ValidateRange(1, 1000)]
    [int]$KeepBackups = 5
)

# -----------------------------------------------------------------------------
# 0. MODUL IMPORTIEREN
# -----------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
$ModulePath = Join-Path $ScriptDir "SQLSyncCommon.psm1"

if (-not (Test-Path $ModulePath)) {
    Write-Error "KRITISCH: SQLSyncCommon.psm1 nicht gefunden in $ScriptDir"
    exit 1
}
Import-Module $ModulePath -Force

# -----------------------------------------------------------------------------
# 1. KONFIGURATION LADEN
# -----------------------------------------------------------------------------
$ConfigPath = Resolve-SQLSyncConfigPath -ConfigFile $ConfigFile -ScriptDir $ScriptDir

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Konfigurationsdatei nicht gefunden: $ConfigPath"
    exit 1
}

# Vor dem Bearbeiten prüfen (Schema + Namens-Whitelist, wie beim Sync) – keine kaputte Konfig weiterbearbeiten
try {
    $null = Get-SQLSyncConfig -ConfigPath $ConfigPath -SchemaPath (Join-Path $ScriptDir "config.schema.json")
}
catch {
    Write-Error "Fehler beim Laden der Konfiguration: $($_.Exception.Message)"
    exit 2
}

# Raw Config laden (für Modifikation)
$ConfigJsonContent = Get-Content -Path $ConfigPath -Raw
$Config = $ConfigJsonContent | ConvertFrom-Json

# Aktuelle Tabellenliste
$CurrentTables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($Config.Tables) {
    $Config.Tables | ForEach-Object { [void]$CurrentTables.Add($_) }
}

# Column Configuration (v2.10)
# Spaltennamen werden unten in SQL-Text eingesetzt; die Whitelist-Prüfung hat Get-SQLSyncConfig oben erledigt
$IdColumn = Get-ConfigValue $Config.General "IdColumn" "ID"
$TimestampColumns = @(Get-ConfigValue $Config.General "TimestampColumns" @("GESPEICHERT"))

# -----------------------------------------------------------------------------
# 2. CREDENTIALS AUFLÖSEN
# -----------------------------------------------------------------------------
try {
    $FbCreds = Resolve-FirebirdCredentials -Config $Config
}
catch {
    Write-Error $_.Exception.Message
    exit 5
}

# -----------------------------------------------------------------------------
# 3. TREIBER LADEN
# -----------------------------------------------------------------------------
try {
    $DllPath = Get-ConfigValue $Config.Firebird "DllPath" ""
    $DllSha256 = Get-ConfigValue $Config.Firebird "DllSha256" $null
    $ResolvedDllPath = Initialize-FirebirdDriver -DllPath $DllPath -ScriptDir $ScriptDir -ExpectedSha256 $DllSha256
}
catch {
    Write-Error $_.Exception.Message
    exit 3
}

# -----------------------------------------------------------------------------
# 4. FIREBIRD DATEN ABRUFEN
# -----------------------------------------------------------------------------
$FBServer = $Config.Firebird.Server
$FBDatabase = $Config.Firebird.Database
$FBPort = Get-ConfigValue $Config.Firebird "Port" 3050
$FBCharset = Get-ConfigValue $Config.Firebird "Charset" "UTF8"

$ConnectionString = New-FirebirdConnectionString `
    -Server $FBServer `
    -Database $FBDatabase `
    -Username $FbCreds.Username `
    -Password $FbCreds.Password `
    -Port $FBPort `
    -Charset $FBCharset

$TableList = @()
$FbConn = $null

try {
    Write-Host "Verbinde zu Firebird ($FBServer)..." -ForegroundColor Cyan
    
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($ConnectionString)
    $FbConn.Open()

    # Dynamische Bedingung für Timestamp-Spalten (wird via Format-Operator eingefügt)
    $TsConditions = ($TimestampColumns | ForEach-Object { "TRIM(FLD.RDB`$FIELD_NAME) = '$_'" }) -join " OR "
    
    # Fallback auf "1=0" (nie wahr), falls keine Timestamp-Spalten konfiguriert
    if (-not $TsConditions) { $TsConditions = "1=0" }
    
    # Literal Here-String mit Format-Operator für sichere RDB$-Referenzen
    $Sql = @'
    SELECT 
        TRIM(REL.RDB$RELATION_NAME) as TABELLENNAME,
        MAX(CASE WHEN TRIM(FLD.RDB$FIELD_NAME) = '{0}' THEN 1 ELSE 0 END) as HAT_ID,
        MAX(CASE WHEN {1} THEN 1 ELSE 0 END) as HAT_DATUM
    FROM RDB$RELATIONS REL
    LEFT JOIN RDB$RELATION_FIELDS FLD ON REL.RDB$RELATION_NAME = FLD.RDB$RELATION_NAME
    WHERE REL.RDB$SYSTEM_FLAG = 0 
      AND REL.RDB$VIEW_BLR IS NULL
    GROUP BY REL.RDB$RELATION_NAME
    ORDER BY REL.RDB$RELATION_NAME
'@ -f $IdColumn, $TsConditions

    $Cmd = $FbConn.CreateCommand()
    $Cmd.CommandText = $Sql
    $Reader = $Cmd.ExecuteReader()

    while ($Reader.Read()) {
        $Name = $Reader["TABELLENNAME"]
        $HatId = [int]$Reader["HAT_ID"] -eq 1
        $HatDatum = [int]$Reader["HAT_DATUM"] -eq 1
        
        $Status = "Neu"
        if ($CurrentTables.Contains($Name)) {
            $Status = "Aktiv (Konfiguriert)"
        }

        $Hinweis = ""
        $NameGueltig = $true
        try { Assert-SqlIdentifier -Name $Name -Field "Tables" } catch { $NameGueltig = $false }

        if (-not $NameGueltig) { $Hinweis = "UNGÜLTIGER NAME (nur A-Z, a-z, 0-9, _, `$; max. 63 Zeichen) - wird nicht übernommen" }
        elseif (-not $HatId) { $Hinweis = "ACHTUNG: Keine $IdColumn Spalte (Snapshot Modus)" }
        elseif (-not $HatDatum) { $Hinweis = "Warnung: Kein Timestamp (Full Merge)" }

        $TableList += [PSCustomObject]@{
            Aktion      = if ($Status -like "Aktiv*") { "Löschen bei Auswahl" } elseif (-not $NameGueltig) { "Keine (ungültiger Name)" } else { "Hinzufügen bei Auswahl" }
            Tabelle     = $Name
            Status      = $Status
            "Hat ID"    = $HatId
            "Hat Datum" = $HatDatum
            Hinweis     = $Hinweis
        }
    }
    $Reader.Close()
}
catch {
    Write-Error "Fehler beim Lesen der Firebird-Metadaten: $($_.Exception.Message)"
    if ($_.Exception.InnerException) { 
        Write-Host "Details: $($_.Exception.InnerException.Message)" -ForegroundColor Red 
    }
    exit 2
}
finally {
    # WICHTIG: Connection immer aufräumen
    if ($FbConn) {
        try { $FbConn.Close() } catch { }
        try { $FbConn.Dispose() } catch { }
    }
}

# -----------------------------------------------------------------------------
# 5. GUI AUSWAHL
# -----------------------------------------------------------------------------
Write-Host "Öffne Auswahlfenster..." -ForegroundColor Yellow
Write-Host "ANLEITUNG (TOGGLE MODUS):" -ForegroundColor White
Write-Host "1. Wählen Sie die Tabellen aus, deren Status Sie ÄNDERN wollen."
Write-Host "   - Neue Tabellen auswählen -> Werden HINZUGEFÜGT."
Write-Host "   - Aktive Tabellen auswählen -> Werden ENTFERNT."
Write-Host "2. Nicht ausgewählte Tabellen bleiben UNVERÄNDERT."

$SelectedItems = $TableList | Sort-Object Status, Tabelle | Out-GridView -Title "Tabellen zum Ändern auswählen (Toggle: Add/Remove)" -PassThru

if (-not $SelectedItems) {
    Write-Host "Keine Auswahl getroffen. Keine Änderungen." -ForegroundColor Yellow
    exit 0
}

# -----------------------------------------------------------------------------
# 6. TOGGLE LOGIK
# -----------------------------------------------------------------------------
$SelectedNames = $SelectedItems | Select-Object -ExpandProperty Tabelle

$TablesToAdd = @()
$TablesToRemove = @()
$FinalTableList = [System.Collections.Generic.List[string]]::new()

# Bestehende Liste übernehmen (Standard: Behalten)
foreach ($Tab in $Config.Tables) {
    if ($Tab -in $SelectedNames) {
        # War drin UND wurde ausgewählt -> LÖSCHEN
        $TablesToRemove += $Tab
    }
    else {
        # War drin UND NICHT ausgewählt -> BEHALTEN
        $FinalTableList.Add($Tab)
    }
}

# Neue hinzufügen
foreach ($Sel in $SelectedNames) {
    if ($Sel -notin $Config.Tables) {
        try { Assert-SqlIdentifier -Name $Sel -Field "Tables" }
        catch {
            Write-Host "  [!] Übersprungen: $($_.Exception.Message)" -ForegroundColor Yellow
            continue
        }
        # War NICHT drin UND wurde ausgewählt -> HINZUFÜGEN
        $TablesToAdd += $Sel
        $FinalTableList.Add($Sel)
    }
}

# Sortieren
$FinalTableList.Sort()

# -----------------------------------------------------------------------------
# 7. VORSCHAU & BESTÄTIGUNG
# -----------------------------------------------------------------------------
if ($TablesToAdd.Count -eq 0 -and $TablesToRemove.Count -eq 0) {
    Write-Host "Keine effektiven Änderungen." -ForegroundColor Yellow
    exit 0
}

# Schema und Sync verlangen mindestens eine Tabelle – keine Konfig schreiben, die beim nächsten Lauf durchfällt
if ($FinalTableList.Count -eq 0) {
    Write-Host "Abbruch: Es würden alle Tabellen entfernt. Mindestens eine Tabelle muss konfiguriert bleiben." -ForegroundColor Red
    exit 4
}

Write-Host "GEPLANTE ÄNDERUNGEN:" -ForegroundColor Cyan
if ($TablesToAdd.Count -gt 0) {
    Write-Host "  [+] Hinzufügen ($($TablesToAdd.Count)):" -ForegroundColor Green
    $TablesToAdd | ForEach-Object { Write-Host "      $_" -ForegroundColor Green }
}
if ($TablesToRemove.Count -gt 0) {
    Write-Host "  [-] Entfernen ($($TablesToRemove.Count)):" -ForegroundColor Red
    $TablesToRemove | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
}

Write-Host "Soll diese Änderung angewendet werden?" -ForegroundColor White
$Choice = ""
while ($Choice -notin "J", "N") {
    $Choice = Read-Host "[J]a, speichern / [N]ein, abbrechen"
    $Choice = $Choice.ToUpper()
}

if ($Choice -eq "N") {
    Write-Host "Abbruch." -ForegroundColor Yellow
    exit 0
}

# -----------------------------------------------------------------------------
# 8. SPEICHERN
# -----------------------------------------------------------------------------
Write-Host "Erstelle Backup und speichere..." -ForegroundColor Cyan

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupPath = "$ConfigPath.$Timestamp.bak"
Copy-Item -Path $ConfigPath -Destination $BackupPath

if (Test-Path $BackupPath) {
    $Config.Tables = $FinalTableList
    $FinalJson = $Config | ConvertTo-Json -Depth 10
    Set-Content -Path $ConfigPath -Value $FinalJson
    
    Write-Host "ERFOLG: config.json aktualisiert." -ForegroundColor Green
    Write-Host "Anzahl Tabellen jetzt: $($FinalTableList.Count)" -ForegroundColor Green
    Write-Host "Backup erstellt: $BackupPath" -ForegroundColor Gray
    $Removed = @(Remove-SQLSyncConfigBackup -ConfigPath $ConfigPath -Keep $KeepBackups)
    if ($Removed.Count -gt 0) { Write-Host "Ältere Backups gelöscht: $($Removed.Count) (behalten: $KeepBackups)" -ForegroundColor Gray }
}
else {
    Write-Error "Backup fehlgeschlagen. Abbruch."
    exit 4
}
