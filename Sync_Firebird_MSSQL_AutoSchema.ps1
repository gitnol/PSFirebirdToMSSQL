<#
.SYNOPSIS
    Synchronisiert Daten inkrementell von Firebird nach MS SQL Server.

.DESCRIPTION
    Dieses Skript implementiert einen High-Performance ETL-Prozess mittels .NET SqlBulkCopy.
    
    Ablauflogik pro Tabelle:
    1. Analyse: Prüft Quell-Schema auf ID (Primary Key) und GESPEICHERT (Zeitstempel).
       - Bestimmt Strategie: Incremental (Delta), FullMerge (Alles) oder Snapshot (Truncate/Insert).
    2. Staging: Erstellt bei Bedarf eine STG_<Tabelle> im SQL Server (automatisches Type-Mapping).
    3. Extrakt: Lädt Daten aus Firebird (Memory-Stream via IDataReader).
       - Bei Incremental: Nur Daten > MAX(GESPEICHERT) im Ziel.
    4. Load: Bulk Insert in die Staging-Tabelle.
    5. Merge: Ruft sp_Merge_Generic auf, um Staging -> Final zu mergen.
       - Repariert fehlende Indizes auf der Zieltabelle automatisch.
    6. Sanity: Vergleicht Row-Counts (Quelle vs. Ziel) zur Plausibilisierung.

.PARAMETER -
    Keine Parameter. Konfiguration erfolgt über 'config.json' im Skriptverzeichnis.

.NOTES
    Autor: [Dein Name/Firma]
    Datum: 2025-11-24
    Version: 1.0
#>

# -----------------------------------------------------------------------------
# 1. INITIALISIERUNG & KONFIGURATION
# -----------------------------------------------------------------------------
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Globaler Timeout für SQL-Befehle und BulkCopy (in Sekunden).
# Bei sehr großen Tabellen (> 1 Mio Zeilen) ggf. erhöhen.
$GlobalTimeout = 7200 

# Steuert, ob die Staging-Tabelle bei jedem Lauf gedroppt und neu angelegt wird.
# $false = Performanter (Truncate). $true = Sicherer bei Schema-Änderungen.
$RecreateStagingTable = $false 

# Debug-Option: Zeigt Mapping-Details (Firebird Type -> SQL Type) in der Konsole.
$ShowSchemaDetails = $false

# Führt am Ende einen Count(*) Vergleich durch. Kostet Zeit, aber schafft Vertrauen.
$RunSanityCheck = $true

# Config-Datei laden
$ConfigPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $ConfigPath)) { Write-Error "KRITISCH: config.json fehlt!"; exit }
$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

# Credentials aus Config extrahieren
$FBservername = $Config.Firebird.Server
$FBpassword = $Config.Firebird.Password
$FBdatabase = $Config.Firebird.Database
$FBport = $Config.Firebird.Port
$FBcharset = $Config.Firebird.Charset
$DllPath = $Config.Firebird.DllPath

$MSSQLservername = $Config.MSSQL.Server
$MSSQLdatabase = $Config.MSSQL.Database
$MSSQLUser = $Config.MSSQL.Username
$MSSQLPass = $Config.MSSQL.Password
$MSSQLIntSec = $Config.MSSQL."Integrated Security"

# Firebird .NET Provider laden (Assembly)
if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue)) {
    Install-Package FirebirdSql.Data.FirebirdClient -Force -Confirm:$false | Out-Null
}
if (-not (Test-Path $DllPath)) {
    # Fallback: Suche im Standard-NuGet-Pfad, falls Config-Pfad falsch ist
    $DllPath = (Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse | Select-Object -First 1).FullName
}
Add-Type -Path $DllPath

# Connection Strings aufbauen
$FirebirdConnString = "User=SYSDBA;Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"
if ($MSSQLIntSec) {
    $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;Integrated Security=True;"
}
else {
    $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;User Id=$MSSQLUser;Password=$MSSQLPass;"
}

# Tabellenliste laden
$Tabellen = $Config.Tables
if (-not $Tabellen -or $Tabellen.Count -eq 0) { Write-Error "Keine Tabellen in config.json definiert."; exit }

Write-Host "Starte Synchronisation für $($Tabellen.Count) Tabellen..." -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

# -----------------------------------------------------------------------------
# 2. HAUPTSCHLEIFE (PARALLELISIERT)
# -----------------------------------------------------------------------------
# Wir nutzen -Parallel, um mehrere Tabellen gleichzeitig zu verarbeiten.
# Das lastet Netzwerk und I/O besser aus als eine serielle Verarbeitung.

$Results = $Tabellen | ForEach-Object -Parallel {
    # Variablen aus dem Haupt-Scope in den Parallel-Scope holen
    $Tabelle = $_
    $FbCS = $using:FirebirdConnString
    $SqlCS = $using:SqlConnString
    $ForceRecreate = $using:RecreateStagingTable
    $ShowDebug = $using:ShowSchemaDetails
    $Timeout = $using:GlobalTimeout
    $DoSanity = $using:RunSanityCheck
    
    $TableStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Status = "Erfolg"
    $Message = ""
    $RowsLoaded = 0
    $Strategy = ""
    
    # Initiale Werte für Sanity Check
    $FbCount = -1
    $SqlCount = -1
    $SanityStatus = "N/A"

    Write-Host "[$Tabelle] Starte Verarbeitung..." -ForegroundColor DarkGray

    try {
        # Eigene Verbindungen pro Thread öffnen (Wichtig: Nicht global teilen!)
        $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbCS)
        $FbConn.Open()
        
        $SqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlCS)
        $SqlConn.Open()

        # -------------------------------------------------------------
        # SCHRITT A: ANALYSE & STRATEGIE-WAHL
        # -------------------------------------------------------------
        # Wir holen nur das Schema (keine Daten), um zu entscheiden, wie wir vorgehen.
        
        $FbCmdSchema = $FbConn.CreateCommand()
        $FbCmdSchema.CommandText = "SELECT FIRST 1 * FROM ""$Tabelle"""
        $ReaderSchema = $FbCmdSchema.ExecuteReader([System.Data.CommandBehavior]::SchemaOnly)
        $SchemaTable = $ReaderSchema.GetSchemaTable()
        $ReaderSchema.Close()

        $ColNames = $SchemaTable | ForEach-Object { $_.ColumnName }
        $HasID = "ID" -in $ColNames
        $HasDate = "GESPEICHERT" -in $ColNames

        # Strategie-Entscheidung:
        # - Snapshot: Wenn kein PK (ID) da ist, müssen wir löschen & neu füllen.
        # - FullMerge: Wenn kein Datum da ist, müssen wir alles vergleichen.
        # - Incremental: Der Standard (schnell).
        $SyncStrategy = "Incremental"
        if (-not $HasID) { $SyncStrategy = "Snapshot" }
        elseif (-not $HasDate) { $SyncStrategy = "FullMerge" }
        $Strategy = $SyncStrategy
        
        if ($ShowDebug) { Write-Host "[$Tabelle] Strategie: $SyncStrategy" -ForegroundColor Yellow }

        # -------------------------------------------------------------
        # SCHRITT B: STAGING TABELLE (Auto-Creation)
        # -------------------------------------------------------------
        $StagingTableName = "STG_$Tabelle"
        $CmdCheck = $SqlConn.CreateCommand()
        $CmdCheck.CommandTimeout = $Timeout
        $CmdCheck.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$StagingTableName'"
        $TableExists = $CmdCheck.ExecuteScalar() -gt 0

        # Wenn Tabelle fehlt oder Recreate erzwungen -> Neu bauen
        if ($ForceRecreate -or -not $TableExists) {
            $CreateSql = "IF OBJECT_ID('$StagingTableName') IS NOT NULL DROP TABLE $StagingTableName; CREATE TABLE $StagingTableName ("
            $Cols = @()
            foreach ($Row in $SchemaTable) {
                $ColName = $Row.ColumnName
                $DotNetType = $Row.DataType
                $Size = $Row.ColumnSize
                
                # Type-Mapping: Firebird (.NET Type) -> SQL Server (T-SQL)
                $SqlType = switch ($DotNetType.Name) {
                    "Int16" { "SMALLINT" }
                    "Int32" { "INT" }
                    "Int64" { "BIGINT" }
                    # Strings: Länge übernehmen wenn sinnvoll, sonst MAX (für BLOB Text)
                    "String" { if ($Size -gt 0 -and $Size -le 4000) { "NVARCHAR($Size)" } else { "NVARCHAR(MAX)" } }
                    "DateTime" { "DATETIME2" }
                    "TimeSpan" { "TIME" } # Wichtig: Firebird TIME ist .NET TimeSpan -> SQL TIME
                    "Decimal" { "DECIMAL(18,4)" }
                    "Double" { "FLOAT" }
                    "Single" { "REAL" }
                    "Byte[]" { "VARBINARY(MAX)" }
                    "Boolean" { "BIT" }
                    Default { "NVARCHAR(MAX)" } # Fallback
                }
                
                # WICHTIG: ID darf für Primary Key (später) nicht NULL sein!
                if ($ColName -eq "ID") { $SqlType += " NOT NULL" }
                
                $Cols += "[$ColName] $SqlType"
            }
            $CreateSql += [string]::Join(", ", $Cols) + ");"
            
            $CmdCreate = $SqlConn.CreateCommand()
            $CmdCreate.CommandTimeout = $Timeout
            $CmdCreate.CommandText = $CreateSql
            [void]$CmdCreate.ExecuteNonQuery()
        }

        # -------------------------------------------------------------
        # SCHRITT C: DATEN LADEN (EXTRAKT)
        # -------------------------------------------------------------
        $FbCmdData = $FbConn.CreateCommand()
        
        if ($SyncStrategy -eq "Incremental") {
            # "High Watermark": Hole maximales Datum aus Ziel-DB
            $CmdMax = $SqlConn.CreateCommand()
            $CmdMax.CommandTimeout = $Timeout
            $CmdMax.CommandText = "SELECT ISNULL(MAX(GESPEICHERT), '1900-01-01') FROM $Tabelle" 
            try { $LastSyncDate = [DateTime]$CmdMax.ExecuteScalar() } catch { $LastSyncDate = [DateTime]"1900-01-01" }
            
            # Nur Delta laden
            $FbCmdData.CommandText = "SELECT * FROM ""$Tabelle"" WHERE ""GESPEICHERT"" > @LastDate"
            $FbCmdData.Parameters.Add("@LastDate", $LastSyncDate) | Out-Null
        }
        else {
            # Alles laden (für Snapshot oder FullMerge)
            $FbCmdData.CommandText = "SELECT * FROM ""$Tabelle"""
        }
        
        # Wichtig: ExecuteReader streamt Daten (Memory effizient)
        $ReaderData = $FbCmdData.ExecuteReader()
        
        # -------------------------------------------------------------
        # SCHRITT D: BULK INSERT (LOAD)
        # -------------------------------------------------------------
        $BulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($SqlConn)
        $BulkCopy.DestinationTableName = $StagingTableName
        $BulkCopy.BulkCopyTimeout = $Timeout
        
        # Spalten mappen (verhindert Fehler bei falscher Reihenfolge)
        for ($i = 0; $i -lt $ReaderData.FieldCount; $i++) {
            $ColName = $ReaderData.GetName($i)
            [void]$BulkCopy.ColumnMappings.Add($ColName, $ColName) 
        }

        # Staging leeren (Truncate ist schneller als Drop)
        if (-not $ForceRecreate) {
            $TruncCmd = $SqlConn.CreateCommand()
            $TruncCmd.CommandTimeout = $Timeout
            $TruncCmd.CommandText = "TRUNCATE TABLE $StagingTableName"
            [void]$TruncCmd.ExecuteNonQuery()
        }
        
        try {
            # Der eigentliche Datentransfer
            $BulkCopy.WriteToServer($ReaderData)
            
            # Prüfen: Haben wir Daten geladen?
            $RowsCopied = $SqlConn.CreateCommand()
            $RowsCopied.CommandTimeout = $Timeout
            $RowsCopied.CommandText = "SELECT COUNT(*) FROM $StagingTableName"
            $Count = $RowsCopied.ExecuteScalar()
            $RowsLoaded = $Count
            
            # -------------------------------------------------------------
            # SCHRITT E: STRUKTUR & INDEX PFLEGE (SELF-HEALING)
            # -------------------------------------------------------------
            
            # 1. Zieltabelle anlegen (falls noch nie gelaufen)
            $CheckFinal = $SqlConn.CreateCommand()
            $CheckFinal.CommandTimeout = $Timeout
            $CheckFinal.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$Tabelle'"
            $FinalTableExists = $CheckFinal.ExecuteScalar() -gt 0

            if (-not $FinalTableExists) {
                $InitCmd = $SqlConn.CreateCommand()
                $InitCmd.CommandTimeout = $Timeout
                # SELECT INTO kopiert Struktur + NOT NULL Properties aus Staging
                $InitCmd.CommandText = "SELECT * INTO $Tabelle FROM $StagingTableName WHERE 1=0;" 
                [void]$InitCmd.ExecuteNonQuery()
            }

            # 2. Index auf Zieltabelle sicherstellen (WICHTIG für Performance!)
            if ($HasID) {
                try {
                    $IdxCheckCmd = $SqlConn.CreateCommand()
                    $IdxCheckCmd.CommandTimeout = $Timeout
                    $IdxCheckCmd.CommandText = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$Tabelle') AND is_primary_key = 1"
                    $HasPK = $IdxCheckCmd.ExecuteScalar() -gt 0

                    if (-not $HasPK) {
                        # Reparatur: Spalte auf NOT NULL setzen (falls noch NULL)
                        $AlterColCmd = $SqlConn.CreateCommand()
                        $AlterColCmd.CommandTimeout = $Timeout
                        $GetTypeCmd = $SqlConn.CreateCommand()
                        $GetTypeCmd.CommandText = "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$Tabelle' AND COLUMN_NAME = 'ID'"
                        $IdType = $GetTypeCmd.ExecuteScalar()
                        
                        if ($IdType) {
                            $AlterColCmd.CommandText = "ALTER TABLE [$Tabelle] ALTER COLUMN [ID] $IdType NOT NULL;"
                            try { [void]$AlterColCmd.ExecuteNonQuery() } catch { }
                        }
                        
                        # Primary Key anlegen
                        $IdxCmd = $SqlConn.CreateCommand()
                        $IdxCmd.CommandTimeout = $Timeout
                        $IdxCmd.CommandText = "ALTER TABLE [$Tabelle] ADD CONSTRAINT [PK_$Tabelle] PRIMARY KEY CLUSTERED ([ID] ASC);"
                        [void]$IdxCmd.ExecuteNonQuery()
                        $Message += " (PK Final erstellt)"
                    }
                }
                catch { $Message += " [PK Error]" }
            }

            # -------------------------------------------------------------
            # SCHRITT F: MERGE / SNAPSHOT (TRANSFORM)
            # -------------------------------------------------------------
            if ($Count -gt 0) {
                # Optional: Index auf Staging (Beschleunigt den Join beim Merge)
                if ($HasID) {
                    try {
                        $StgIdxCmd = $SqlConn.CreateCommand()
                        $StgIdxCmd.CommandTimeout = $Timeout
                        $CheckStgIdx = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$StagingTableName') AND name = 'PK_$StagingTableName'"
                        $StgIdxCmd.CommandText = $CheckStgIdx
                        if (($StgIdxCmd.ExecuteScalar()) -eq 0) {
                            $StgIdxCmd.CommandText = "ALTER TABLE [$StagingTableName] ADD CONSTRAINT [PK_$StagingTableName] PRIMARY KEY CLUSTERED ([ID] ASC);"
                            [void]$StgIdxCmd.ExecuteNonQuery()
                        }
                    }
                    catch { }
                }

                # Anwenden der Daten
                if ($SyncStrategy -eq "Snapshot") {
                    # Harter Reset: Alles löschen und neu füllen
                    $FinalCmd = $SqlConn.CreateCommand()
                    $FinalCmd.CommandTimeout = $Timeout
                    $FinalCmd.CommandText = "TRUNCATE TABLE $Tabelle; INSERT INTO $Tabelle SELECT * FROM $StagingTableName;"
                    [void]$FinalCmd.ExecuteNonQuery()
                }
                else {
                    # Smart Merge via Stored Procedure
                    $MergeCmd = $SqlConn.CreateCommand()
                    $MergeCmd.CommandTimeout = $Timeout
                    $MergeCmd.CommandText = "EXEC sp_Merge_Generic @TableName = '$Tabelle'"
                    [void]$MergeCmd.ExecuteNonQuery()
                }
            }
            
            # -------------------------------------------------------------
            # SCHRITT G: SANITY CHECK (PLAUSIBILITÄT)
            # -------------------------------------------------------------
            if ($DoSanity) {
                # Vergleich Zeilenanzahl Quelle vs. Ziel
                $FbCountCmd = $FbConn.CreateCommand()
                $FbCountCmd.CommandText = "SELECT COUNT(*) FROM ""$Tabelle"""
                $FbCount = [int64]$FbCountCmd.ExecuteScalar()
                
                $SqlCountCmd = $SqlConn.CreateCommand()
                $SqlCountCmd.CommandTimeout = $Timeout
                $SqlCountCmd.CommandText = "SELECT COUNT(*) FROM $Tabelle"
                $SqlCount = [int64]$SqlCountCmd.ExecuteScalar()
                
                $CountDiff = $SqlCount - $FbCount
                
                if ($CountDiff -eq 0) {
                    $SanityStatus = "OK"
                }
                elseif ($CountDiff -gt 0) {
                    $SanityStatus = "WARNUNG (+ $CountDiff)" # SQL hat mehr (Deletes?)
                }
                else {
                    $SanityStatus = "FEHLER ($CountDiff)" # Firebird hat mehr (Datenverlust?)
                }
            }
        }
        catch {
            $Status = "Fehler"
            $Message = "Bulk/Merge: $($_.Exception.Message)"
            Write-Host "[$Tabelle] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
        $ReaderData.Close()
    }
    catch {
        $Status = "Kritischer Fehler"
        $Message = $_.Exception.Message
        Write-Host "[$Tabelle] CRITICAL: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if ($FbConn) { $FbConn.Close() }
        if ($SqlConn) { $SqlConn.Close() }
    }
    
    $TableStopwatch.Stop()
    
    Write-Host "[$Tabelle] Fertig ($RowsLoaded Zeilen). Sanity: $SanityStatus" -ForegroundColor Green

    # Ergebnis-Objekt zurückgeben (wird in $Results gesammelt)
    [PSCustomObject]@{
        Tabelle     = $Tabelle
        Status      = $Status
        Strategie   = $Strategy
        RowsLoaded  = $RowsLoaded
        FbTotal     = if ($DoSanity) { $FbCount } else { "-" }
        SqlTotal    = if ($DoSanity) { $SqlCount } else { "-" }
        SanityCheck = $SanityStatus
        Duration    = $TableStopwatch.Elapsed
        Speed       = if ($TableStopwatch.Elapsed.TotalSeconds -gt 0) { [math]::Round($RowsLoaded / $TableStopwatch.Elapsed.TotalSeconds, 0) } else { 0 }
        Info        = $Message
    }

} -ThrottleLimit 4

# -----------------------------------------------------------------------------
# 3. ABSCHLUSS & BERICHT
# -----------------------------------------------------------------------------
$TotalStopwatch.Stop()

Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "ZUSAMMENFASSUNG" -ForegroundColor White
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

$Results | Format-Table -AutoSize @{Label = "Tabelle"; Expression = { $_.Tabelle } },
@{Label = "Status"; Expression = { $_.Status } },
@{Label = "Sync"; Expression = { $_.RowsLoaded }; Align = "Right" },
@{Label = "FB Total"; Expression = { $_.FbTotal }; Align = "Right" },
@{Label = "SQL Total"; Expression = { $_.SqlTotal }; Align = "Right" },
@{Label = "Sanity"; Expression = { $_.SanityCheck } },
@{Label = "Dauer"; Expression = { $_.Duration.ToString("mm\:ss\.fff") } },
@{Label = "Info"; Expression = { $_.Info } }

Write-Host "GESAMTLAUFZEIT: $($TotalStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green