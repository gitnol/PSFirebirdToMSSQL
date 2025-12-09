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

.NOTES
    Version: 2.0 (Refactored - Modul-basiert)

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL    

#>

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
$ConfigPath = Join-Path $ScriptDir "config.json"

if (-not (Test-Path $ConfigPath)) { 
    Write-Error "config.json fehlt!" 
    exit 1 
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
    $ResolvedDllPath = Initialize-FirebirdDriver -DllPath $DllPath -ScriptDir $ScriptDir
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
        if (-not $HatId) { $Hinweis = "ACHTUNG: Keine $IdColumn Spalte (Snapshot Modus)" }
        elseif (-not $HatDatum) { $Hinweis = "Warnung: Kein Timestamp (Full Merge)" }

        $TableList += [PSCustomObject]@{
            Aktion      = if ($Status -like "Aktiv*") { "Löschen bei Auswahl" } else { "Hinzufügen bei Auswahl" } 
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
}
else {
    Write-Error "Backup fehlgeschlagen. Abbruch."
    exit 4
}