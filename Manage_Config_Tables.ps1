# -----------------------------------------------------------------------------
# KONFIGURATION MANAGER - FIREBIRD TABELLEN AUSWAHL (TOGGLE LOGIK)
# -----------------------------------------------------------------------------
# Dieses Skript liest alle Tabellen aus Firebird aus.
# Logik:
# - Tabellen auswählen, die GEÄNDERT werden sollen.
# - Ist eine Tabelle NOCH NICHT in der Config -> Wird HINZUGEFÜGT.
# - Ist eine Tabelle BEREITS in der Config -> Wird ENTFERNT.
# - Nicht ausgewählte Tabellen bleiben UNVERÄNDERT.

$ConfigPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $ConfigPath)) { Write-Error "config.json fehlt!"; exit }

# 1. Config laden
$ConfigJsonContent = Get-Content -Path $ConfigPath -Raw
$Config = $ConfigJsonContent | ConvertFrom-Json

# Firebird Credentials auslesen
$FBservername = $Config.Firebird.Server
$FBpassword = $Config.Firebird.Password
$FBdatabase = $Config.Firebird.Database
$FBport = $Config.Firebird.Port
$FBcharset = $Config.Firebird.Charset
$DllPath = $Config.Firebird.DllPath

# Aktuelle Tabellenliste
$CurrentTables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($Config.Tables) {
    $Config.Tables | ForEach-Object { [void]$CurrentTables.Add($_) }
}

# 2. Treiber laden
if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue)) {
    Write-Host "Installiere fehlenden Treiber..." -ForegroundColor Yellow
    Install-Package FirebirdSql.Data.FirebirdClient -Force -Confirm:$false | Out-Null
}
if (-not (Test-Path $DllPath)) {
    # Fallback Suche
    $DllPath = (Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse | Select-Object -First 1).FullName
}
Add-Type -Path $DllPath

# 3. Firebird Daten abrufen
$ConnectionString = "User=SYSDBA;Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"

try {
    Write-Host "Verbinde zu Firebird ($FBservername)..." -ForegroundColor Cyan
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($ConnectionString)
    $FbConn.Open()

    $Sql = @'
    SELECT 
        TRIM(REL.RDB$RELATION_NAME) as TABELLENNAME,
        MAX(CASE WHEN TRIM(FLD.RDB$FIELD_NAME) = 'ID' THEN 1 ELSE 0 END) as HAT_ID,
        MAX(CASE WHEN TRIM(FLD.RDB$FIELD_NAME) = 'GESPEICHERT' THEN 1 ELSE 0 END) as HAT_DATUM
    FROM RDB$RELATIONS REL
    LEFT JOIN RDB$RELATION_FIELDS FLD ON REL.RDB$RELATION_NAME = FLD.RDB$RELATION_NAME
    WHERE REL.RDB$SYSTEM_FLAG = 0 
      AND REL.RDB$VIEW_BLR IS NULL
    GROUP BY REL.RDB$RELATION_NAME
    ORDER BY REL.RDB$RELATION_NAME
'@

    $Cmd = $FbConn.CreateCommand()
    $Cmd.CommandText = $Sql
    $Reader = $Cmd.ExecuteReader()

    $TableList = @()

    while ($Reader.Read()) {
        $Name = $Reader["TABELLENNAME"]
        $HatId = [int]$Reader["HAT_ID"] -eq 1
        $HatDatum = [int]$Reader["HAT_DATUM"] -eq 1
        
        $Status = "Neu"
        if ($CurrentTables.Contains($Name)) {
            $Status = "Aktiv (Konfiguriert)"
        }

        $Hinweis = ""
        if (-not $HatId) { $Hinweis = "ACHTUNG: Keine ID Spalte (Snapshot Modus)" }
        elseif (-not $HatDatum) { $Hinweis = "Warnung: Kein Datum (Full Merge)" }

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
    $FbConn.Close()

}
catch {
    Write-Error "Fehler beim Lesen der Firebird-Metadaten: $($_.Exception.Message)"
    try { if ($_.Exception.InnerException) { Write-Host "Details: $($_.Exception.InnerException.Message)" -ForegroundColor Red } } catch {}
    exit
}

# 4. GUI Auswahl
Write-Host "Öffne Auswahlfenster..." -ForegroundColor Yellow
Write-Host "ANLEITUNG (TOGGLE MODUS):" -ForegroundColor White
Write-Host "1. Wählen Sie die Tabellen aus, deren Status Sie ÄNDERN wollen."
Write-Host "   - Neue Tabellen auswählen -> Werden HINZUGEFÜGT."
Write-Host "   - Aktive Tabellen auswählen -> Werden ENTFERNT."
Write-Host "2. Nicht ausgewählte Tabellen bleiben UNVERÄNDERT."

$SelectedItems = $TableList | Sort-Object Status, Tabelle | Out-GridView -Title "Tabellen zum Ändern auswählen (Toggle: Add/Remove)" -PassThru

if (-not $SelectedItems) {
    Write-Host "Keine Auswahl getroffen. Keine Änderungen." -ForegroundColor Yellow
    exit
}

# -----------------------------------------------------------------------------
# TOGGLE LOGIK
# -----------------------------------------------------------------------------
$SelectedNames = $SelectedItems | Select-Object -ExpandProperty Tabelle

# Listen vorbereiten
$TablesToAdd = @()
$TablesToRemove = @()
$FinalTableList = [System.Collections.Generic.List[string]]::new()

# 1. Bestehende Liste übernehmen (Standard: Behalten)
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

# 2. Neue hinzufügen
foreach ($Sel in $SelectedNames) {
    if ($Sel -notin $Config.Tables) {
        # War NICHT drin UND wurde ausgewählt -> HINZUFÜGEN
        $TablesToAdd += $Sel
        $FinalTableList.Add($Sel)
    }
}

# Sortieren für Sauberkeit
$FinalTableList.Sort()

# -----------------------------------------------------------------------------
# VORSCHAU & BESTÄTIGUNG
# -----------------------------------------------------------------------------

if ($TablesToAdd.Count -eq 0 -and $TablesToRemove.Count -eq 0) {
    Write-Host "Keine effektiven Änderungen (vielleicht haben Sie nichts ausgewählt?)." -ForegroundColor Yellow
    exit
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
    exit
}

# -----------------------------------------------------------------------------
# SPEICHERN
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
}
else {
    Write-Error "Backup fehlgeschlagen. Abbruch."
}