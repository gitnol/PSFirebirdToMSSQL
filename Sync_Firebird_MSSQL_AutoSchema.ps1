# -----------------------------------------------------------------------------
# KONFIGURATION & INIT
# -----------------------------------------------------------------------------
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Timeout (2 Stunden)
$GlobalTimeout = 7200 

# Standardmäßig auf $false, damit Staging-Tabellen wiederverwendet werden
$RecreateStagingTable = $false 

# Debug-Optionen (Zeigt an, welche Datentypen gemappt werden)
$ShowSchemaDetails = $false

$ConfigPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $ConfigPath)) { Write-Error "config.json fehlt!"; exit }
$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

# Firebird Config
$FBservername = $Config.Firebird.Server
$FBpassword = $Config.Firebird.Password
$FBdatabase = $Config.Firebird.Database
$FBport = $Config.Firebird.Port
$FBcharset = $Config.Firebird.Charset
$DllPath = $Config.Firebird.DllPath

# MSSQL Config
$MSSQLservername = $Config.MSSQL.Server
$MSSQLdatabase = $Config.MSSQL.Database
$MSSQLUser = $Config.MSSQL.Username
$MSSQLPass = $Config.MSSQL.Password
$MSSQLIntSec = $Config.MSSQL."Integrated Security"

# Treiber laden
if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue)) {
    Install-Package FirebirdSql.Data.FirebirdClient -Force -Confirm:$false | Out-Null
}
if (-not (Test-Path $DllPath)) {
    $DllPath = (Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse | Select-Object -First 1).FullName
}
Add-Type -Path $DllPath

# Connection Strings
$FirebirdConnString = "User=SYSDBA;Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"
if ($MSSQLIntSec) {
    $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;Integrated Security=True;"
}
else {
    $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;User Id=$MSSQLUser;Password=$MSSQLPass;"
}

$Tabellen = $Config.Tables
if (-not $Tabellen -or $Tabellen.Count -eq 0) { Write-Error "Keine Tabellen definiert."; exit }

Write-Host "Starte Synchronisation für $($Tabellen.Count) Tabellen..." -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

# -----------------------------------------------------------------------------
# HAUPTSCHLEIFE
# -----------------------------------------------------------------------------

$Results = $Tabellen | ForEach-Object -Parallel {
    $Tabelle = $_
    $FbCS = $using:FirebirdConnString
    $SqlCS = $using:SqlConnString
    $ForceRecreate = $using:RecreateStagingTable
    $ShowDebug = $using:ShowSchemaDetails
    $Timeout = $using:GlobalTimeout
    
    $TableStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Status = "Erfolg"
    $Message = ""
    $RowsLoaded = 0
    $Strategy = ""

    # Live-Statusmeldung mit Write-Host (landet direkt in der Konsole)
    Write-Host "[$Tabelle] Starte Verarbeitung..." -ForegroundColor DarkGray

    try {
        $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbCS)
        $FbConn.Open()
        
        $SqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlCS)
        $SqlConn.Open()

        # --- SCHRITT A: ANALYSE ---
        $FbCmdSchema = $FbConn.CreateCommand()
        $FbCmdSchema.CommandText = "SELECT FIRST 1 * FROM ""$Tabelle"""
        $ReaderSchema = $FbCmdSchema.ExecuteReader([System.Data.CommandBehavior]::SchemaOnly)
        $SchemaTable = $ReaderSchema.GetSchemaTable()
        $ReaderSchema.Close()

        $ColNames = $SchemaTable | ForEach-Object { $_.ColumnName }
        $HasID = "ID" -in $ColNames
        $HasDate = "GESPEICHERT" -in $ColNames

        $SyncStrategy = "Incremental"
        if (-not $HasID) { $SyncStrategy = "Snapshot" }
        elseif (-not $HasDate) { $SyncStrategy = "FullMerge" }
        $Strategy = $SyncStrategy
        
        if ($ShowDebug) { Write-Host "[$Tabelle] Strategie: $SyncStrategy" -ForegroundColor Yellow }

        # --- SCHRITT B: STAGING TABELLE ---
        $StagingTableName = "STG_$Tabelle"
        $CmdCheck = $SqlConn.CreateCommand()
        $CmdCheck.CommandTimeout = $Timeout
        $CmdCheck.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$StagingTableName'"
        $TableExists = $CmdCheck.ExecuteScalar() -gt 0

        if ($ForceRecreate -or -not $TableExists) {
            if ($ShowDebug) { Write-Host "[$Tabelle] Erstelle Staging neu..." -ForegroundColor Yellow }
            
            $CreateSql = "IF OBJECT_ID('$StagingTableName') IS NOT NULL DROP TABLE $StagingTableName; CREATE TABLE $StagingTableName ("
            $Cols = @()
            foreach ($Row in $SchemaTable) {
                $ColName = $Row.ColumnName
                $DotNetType = $Row.DataType
                $Size = $Row.ColumnSize
                $SqlType = switch ($DotNetType.Name) {
                    "Int16" { "SMALLINT" }
                    "Int32" { "INT" }
                    "Int64" { "BIGINT" }
                    "String" { if ($Size -gt 0 -and $Size -le 4000) { "NVARCHAR($Size)" } else { "NVARCHAR(MAX)" } }
                    "DateTime" { "DATETIME2" }
                    "TimeSpan" { "TIME" }
                    "Decimal" { "DECIMAL(18,4)" }
                    "Double" { "FLOAT" }
                    "Single" { "REAL" }
                    "Byte[]" { "VARBINARY(MAX)" }
                    "Boolean" { "BIT" }
                    Default { "NVARCHAR(MAX)" }
                }
                
                # WICHTIG: ID darf für Primary Key nicht NULL sein
                if ($ColName -eq "ID") {
                    $SqlType += " NOT NULL"
                }

                if ($ShowDebug) { Write-Host "   -> Map $ColName ($($DotNetType.Name)) ==> $SqlType" -ForegroundColor DarkGray }
                $Cols += "[$ColName] $SqlType"
            }
            $CreateSql += [string]::Join(", ", $Cols) + ");"
            
            $CmdCreate = $SqlConn.CreateCommand()
            $CmdCreate.CommandTimeout = $Timeout
            $CmdCreate.CommandText = $CreateSql
            [void]$CmdCreate.ExecuteNonQuery()
        }

        # --- SCHRITT C: DATEN LADEN ---
        $FbCmdData = $FbConn.CreateCommand()
        if ($SyncStrategy -eq "Incremental") {
            $CmdMax = $SqlConn.CreateCommand()
            $CmdMax.CommandTimeout = $Timeout
            $CmdMax.CommandText = "SELECT ISNULL(MAX(GESPEICHERT), '1900-01-01') FROM $Tabelle" 
            try { $LastSyncDate = [DateTime]$CmdMax.ExecuteScalar() } catch { $LastSyncDate = [DateTime]"1900-01-01" }
            $FbCmdData.CommandText = "SELECT * FROM ""$Tabelle"" WHERE ""GESPEICHERT"" > @LastDate"
            $FbCmdData.Parameters.Add("@LastDate", $LastSyncDate) | Out-Null
        }
        else {
            $FbCmdData.CommandText = "SELECT * FROM ""$Tabelle"""
        }
        
        $ReaderData = $FbCmdData.ExecuteReader()
        
        $BulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($SqlConn)
        $BulkCopy.DestinationTableName = $StagingTableName
        $BulkCopy.BulkCopyTimeout = $Timeout
        for ($i = 0; $i -lt $ReaderData.FieldCount; $i++) {
            $ColName = $ReaderData.GetName($i)
            [void]$BulkCopy.ColumnMappings.Add($ColName, $ColName) 
        }

        if (-not $ForceRecreate) {
            $TruncCmd = $SqlConn.CreateCommand()
            $TruncCmd.CommandTimeout = $Timeout
            $TruncCmd.CommandText = "TRUNCATE TABLE $StagingTableName"
            [void]$TruncCmd.ExecuteNonQuery()
        }
        
        try {
            $BulkCopy.WriteToServer($ReaderData)
            $RowsCopied = $SqlConn.CreateCommand()
            $RowsCopied.CommandTimeout = $Timeout
            $RowsCopied.CommandText = "SELECT COUNT(*) FROM $StagingTableName"
            $Count = $RowsCopied.ExecuteScalar()
            $RowsLoaded = $Count
            
            # --- SCHRITT D: STRUKTUR & INDEX PFLEGE ---
            
            # 1. Zieltabelle existiert?
            $CheckFinal = $SqlConn.CreateCommand()
            $CheckFinal.CommandTimeout = $Timeout
            $CheckFinal.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$Tabelle'"
            $FinalTableExists = $CheckFinal.ExecuteScalar() -gt 0

            if (-not $FinalTableExists) {
                $InitCmd = $SqlConn.CreateCommand()
                $InitCmd.CommandTimeout = $Timeout
                # Wichtig: Auch hier muss ID NOT NULL sein für späteren PK
                $InitCmd.CommandText = "SELECT * INTO $Tabelle FROM $StagingTableName WHERE 1=0;" 
                [void]$InitCmd.ExecuteNonQuery()
            }

            # 2. Index auf Zieltabelle (FINAL) - Immer prüfen!
            if ($HasID) {
                try {
                    $IdxCheckCmd = $SqlConn.CreateCommand()
                    $IdxCheckCmd.CommandTimeout = $Timeout
                    $IdxCheckCmd.CommandText = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$Tabelle') AND is_primary_key = 1"
                    $HasPK = $IdxCheckCmd.ExecuteScalar() -gt 0

                    if (-not $HasPK) {
                        # Sicherheitsnetz: Spalte auf NOT NULL setzen
                        $AlterColCmd = $SqlConn.CreateCommand()
                        $AlterColCmd.CommandTimeout = $Timeout
                        
                        $GetTypeCmd = $SqlConn.CreateCommand()
                        $GetTypeCmd.CommandText = "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$Tabelle' AND COLUMN_NAME = 'ID'"
                        $IdType = $GetTypeCmd.ExecuteScalar()
                        
                        if ($IdType) {
                            $AlterColCmd.CommandText = "ALTER TABLE [$Tabelle] ALTER COLUMN [ID] $IdType NOT NULL;"
                            try { [void]$AlterColCmd.ExecuteNonQuery() } catch { }
                        }

                        $IdxCmd = $SqlConn.CreateCommand()
                        $IdxCmd.CommandTimeout = $Timeout
                        $IdxCmd.CommandText = "ALTER TABLE [$Tabelle] ADD CONSTRAINT [PK_$Tabelle] PRIMARY KEY CLUSTERED ([ID] ASC);"
                        [void]$IdxCmd.ExecuteNonQuery()
                        $Message += " (PK Final erstellt)"
                    }
                }
                catch {
                    $Message += " [PK Error: $($_.Exception.Message)]"
                }
            }

            # --- SCHRITT E: MERGE / SNAPSHOT ---
            if ($Count -gt 0) {
                # Index auf Staging (Optional, für Performance)
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

                if ($SyncStrategy -eq "Snapshot") {
                    $FinalCmd = $SqlConn.CreateCommand()
                    $FinalCmd.CommandTimeout = $Timeout
                    $FinalCmd.CommandText = "TRUNCATE TABLE $Tabelle; INSERT INTO $Tabelle SELECT * FROM $StagingTableName;"
                    [void]$FinalCmd.ExecuteNonQuery()
                }
                else {
                    $MergeCmd = $SqlConn.CreateCommand()
                    $MergeCmd.CommandTimeout = $Timeout
                    $MergeCmd.CommandText = "EXEC sp_Merge_Generic @TableName = '$Tabelle'"
                    [void]$MergeCmd.ExecuteNonQuery()
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
    
    # Live-Statusmeldung Abschluss
    Write-Host "[$Tabelle] Fertig ($RowsLoaded Zeilen)" -ForegroundColor Green

    # Rückgabe für die Gesamttabelle am Ende
    [PSCustomObject]@{
        Tabelle   = $Tabelle
        Status    = $Status
        Strategie = $Strategy
        Zeilen    = $RowsLoaded
        Dauer     = $TableStopwatch.Elapsed
        Speed     = if ($TableStopwatch.Elapsed.TotalSeconds -gt 0) { [math]::Round($RowsLoaded / $TableStopwatch.Elapsed.TotalSeconds, 0) } else { 0 }
        Info      = $Message
    }

} -ThrottleLimit 4

# -----------------------------------------------------------------------------
# ABSCHLUSS BERICHT
# -----------------------------------------------------------------------------
$TotalStopwatch.Stop()

Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "ZUSAMMENFASSUNG" -ForegroundColor White
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

$Results | Format-Table -AutoSize @{Label = "Tabelle"; Expression = { $_.Tabelle } },
@{Label = "Status"; Expression = { $_.Status } },
@{Label = "Strat"; Expression = { $_.Strategie } },
@{Label = "Zeilen"; Expression = { $_.Zeilen }; Align = "Right" },
@{Label = "Dauer"; Expression = { $_.Dauer.ToString("mm\:ss\.fff") } },
@{Label = "Zeilen/s"; Expression = { $_.Speed }; Align = "Right" },
@{Label = "Info"; Expression = { $_.Info } }

Write-Host "GESAMTLAUFZEIT: $($TotalStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green