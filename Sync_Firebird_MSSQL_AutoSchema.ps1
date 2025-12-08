#Requires -Version 7.0

<#
.SYNOPSIS
    Synchronisiert Daten inkrementell von Firebird nach MS SQL Server (Produktions-Version).

.DESCRIPTION
    Features:
    - High-Performance Bulk Copy
    - Inkrementeller Delta-Sync
    - Automatische Schema-Erstellung & Reparatur
    - Sanity Checks
    - Datei-Logging (Logs\...)
    - Retry-Logik bei Verbindungsfehlern
    - Sichere Credential-Verwaltung via Windows Credential Manager
    - Config-Datei per Parameter wählbar
    - Unterstützung für Prefix/Suffix bei Zieltabellen
    - Sicheres Connection Handling (kein Resource Leak)

.PARAMETER ConfigFile
    Optional. Der Pfad zur JSON-Konfigurationsdatei.
    Standard: "config.json" im Skript-Verzeichnis.

.NOTES
    Version: 2.7 (Refactored - Modul-basiert)

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL    
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile
)

# -----------------------------------------------------------------------------
# 1. INITIALISIERUNG & MODUL LADEN
# -----------------------------------------------------------------------------
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$ScriptDir = $PSScriptRoot

# Modul importieren
$ModulePath = Join-Path $ScriptDir "SQLSyncCommon.psm1"
if (-not (Test-Path $ModulePath)) {
    Write-Error "KRITISCH: SQLSyncCommon.psm1 nicht gefunden in $ScriptDir"
    exit 1
}
Import-Module $ModulePath -Force

# -----------------------------------------------------------------------------
# 2. KONFIGURATIONSDATEI ERMITTELN
# -----------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigPath = Join-Path $ScriptDir "config.json"
}
else {
    if (Test-Path $ConfigFile) {
        $ConfigPath = Convert-Path $ConfigFile
    }
    elseif (Test-Path (Join-Path $ScriptDir $ConfigFile)) {
        $ConfigPath = Join-Path $ScriptDir $ConfigFile
    }
    else {
        $ConfigPath = $ConfigFile
    }
}

# -----------------------------------------------------------------------------
# 3. LOGGING STARTEN
# -----------------------------------------------------------------------------
$LogDir = Join-Path $ScriptDir "Logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

$ConfigName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
$LogFile = Join-Path $LogDir "Sync_${ConfigName}_$(Get-Date -Format 'yyyy-MM-dd_HHmm').log"

Start-Transcript -Path $LogFile -Append

Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "SQLSync STARTED at $(Get-Date)" -ForegroundColor White
Write-Host "Config File: $ConfigPath" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

# -----------------------------------------------------------------------------
# 4. KONFIGURATION LADEN (via Modul)
# -----------------------------------------------------------------------------
try {
    $Config = Get-SQLSyncConfig -ConfigPath $ConfigPath
}
catch {
    Write-Error "KRITISCH: $($_.Exception.Message)"
    Stop-Transcript
    exit 2
}

# Variablen für einfacheren Zugriff
$GlobalTimeout = $Config.GlobalTimeout
$RecreateStagingTable = $Config.RecreateStagingTable
$RunSanityCheck = $Config.RunSanityCheck
$MaxRetries = $Config.MaxRetries
$RetryDelaySeconds = $Config.RetryDelaySeconds
$DeleteLogOlderThanDays = $Config.DeleteLogOlderThanDays
$ForceFullSync = $Config.ForceFullSync
$CleanupOrphans = $Config.CleanupOrphans
$OrphanCleanupBatchSize = $Config.OrphanCleanupBatchSize
$MSSQLPrefix = $Config.MSSQLPrefix
$MSSQLSuffix = $Config.MSSQLSuffix
$Tabellen = $Config.Tables

# Status-Ausgaben
if ($MSSQLPrefix -ne "" -or $MSSQLSuffix -ne "") {
    Write-Host "INFO: MSSQL Zieltabellen werden angepasst: '$MSSQLPrefix' + [Name] + '$MSSQLSuffix'" -ForegroundColor Cyan
}
if ($ForceFullSync) { 
    Write-Host "WARNUNG: ForceFullSync ist AKTIViert. Es werden ALLE Daten neu geladen!" -ForegroundColor Magenta 
}
if ($CleanupOrphans) {
    Write-Host "INFO: CleanupOrphans ist AKTIViert. Verwaiste Datensätze werden gelöscht." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 5. CREDENTIALS AUFLÖSEN (via Modul)
# -----------------------------------------------------------------------------
try {
    $FbCreds = Resolve-FirebirdCredentials -Config $Config.RawConfig
    $SqlCreds = Resolve-MSSQLCredentials -Config $Config.RawConfig
}
catch {
    Write-Error "KRITISCH: $($_.Exception.Message)"
    Stop-Transcript
    exit 5
}

# -----------------------------------------------------------------------------
# 6. TREIBER LADEN & CONNECTION STRINGS
# -----------------------------------------------------------------------------
try {
    $ResolvedDllPath = Initialize-FirebirdDriver -DllPath $Config.DllPath -ScriptDir $ScriptDir
}
catch {
    Write-Error "KRITISCH: $($_.Exception.Message)"
    Stop-Transcript
    exit 7
}

# Connection Strings erstellen
$FirebirdConnString = New-FirebirdConnectionString `
    -Server $Config.FBServer `
    -Database $Config.FBDatabase `
    -Username $FbCreds.Username `
    -Password $FbCreds.Password `
    -Port $Config.FBPort `
    -Charset $Config.FBCharset

$SqlConnString = New-MSSQLConnectionString `
    -Server $Config.MSSQLServer `
    -Database $Config.MSSQLDatabase `
    -Username $SqlCreds.Username `
    -Password $SqlCreds.Password `
    -IntegratedSecurity $SqlCreds.IntegratedSecurity

# Verbindungs-Info (ohne Passwörter)
Write-Host "Firebird: Server=$($Config.FBServer);Database=$($Config.FBDatabase);Port=$($Config.FBPort)" -ForegroundColor Cyan
Write-Host "SQL Server: Server=$($Config.MSSQLServer);Database=$($Config.MSSQLDatabase);IntegratedSecurity=$($SqlCreds.IntegratedSecurity)" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 7. PRE-FLIGHT CHECK (MSSQL) & AUTO-SETUP
# -----------------------------------------------------------------------------
Write-Host "Führe Pre-Flight Checks durch..." -ForegroundColor Cyan

# --- TEIL 1: DATENBANK PRÜFEN / ERSTELLEN (via master) ---
$MasterConn = $null
try {
    $MasterConnString = New-MSSQLConnectionString `
        -Server $Config.MSSQLServer `
        -Database "master" `
        -Username $SqlCreds.Username `
        -Password $SqlCreds.Password `
        -IntegratedSecurity $SqlCreds.IntegratedSecurity

    $MasterConn = New-Object System.Data.SqlClient.SqlConnection($MasterConnString)
    $MasterConn.Open()

    $DbName = $Config.MSSQLDatabase
    $CreateDbCmd = $MasterConn.CreateCommand()
    $CreateDbCmd.CommandText = @"
    IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'$DbName')
    BEGIN
        CREATE DATABASE [$DbName];
        ALTER DATABASE [$DbName] SET RECOVERY SIMPLE;
        SELECT 1; 
    END
    ELSE
    BEGIN
        SELECT 0;
    END
"@
    $WasCreated = $CreateDbCmd.ExecuteScalar()

    if ($WasCreated -eq 1) {
        Write-Host "INFO: Datenbank '$DbName' wurde ERSTELLT (Recovery: Simple)." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    else {
        Write-Host "OK: Datenbank '$DbName' ist vorhanden." -ForegroundColor Green
    }
}
catch {
    Write-Error "KRITISCH: Fehler beim Prüfen/Erstellen der Datenbank: $($_.Exception.Message)"
    Stop-Transcript
    exit 9
}
finally {
    if ($MasterConn) {
        try { $MasterConn.Close() } catch { }
        try { $MasterConn.Dispose() } catch { }
    }
}

# --- TEIL 2: PROZEDUR PRÜFEN / INSTALLIEREN (via Ziel-DB) ---
$TargetConn = $null
try {
    $TargetConn = New-Object System.Data.SqlClient.SqlConnection($SqlConnString)
    $TargetConn.Open()

    $CheckCmd = $TargetConn.CreateCommand()
    $CheckCmd.CommandText = "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_Merge_Generic]') AND type in (N'P', N'PC')"
    $ProcCount = $CheckCmd.ExecuteScalar()
    
    if ($ProcCount -eq 0) {
        Write-Host "Stored Procedure 'sp_Merge_Generic' fehlt. Starte Installation..." -ForegroundColor Yellow
        
        $SqlFileName = "sql_server_setup.sql"
        $SqlFile = Join-Path $ScriptDir $SqlFileName
        
        if (-not (Test-Path $SqlFile)) {
            throw "Die Datei '$SqlFileName' wurde im Skript-Verzeichnis nicht gefunden!"
        }

        $SqlContent = Get-Content -Path $SqlFile -Raw

        # Kommentar-Bereinigung
        $SqlContent = [System.Text.RegularExpressions.Regex]::Replace($SqlContent, "/\*[\s\S]*?\*/", "")
        $SqlContent = [System.Text.RegularExpressions.Regex]::Replace($SqlContent, "--.*$", "", [System.Text.RegularExpressions.RegexOptions]::Multiline)

        # Split am GO
        $SqlBatches = [System.Text.RegularExpressions.Regex]::Split($SqlContent, "^\s*GO\s*$", [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        foreach ($Batch in $SqlBatches) {
            if (-not [string]::IsNullOrWhiteSpace($Batch)) {
                $InstallCmd = $TargetConn.CreateCommand()
                $InstallCmd.CommandText = $Batch
                [void]$InstallCmd.ExecuteNonQuery()
            }
        }
        
        Write-Host "INSTALLIERT: 'sp_Merge_Generic' erfolgreich angelegt." -ForegroundColor Green
    }
    else {
        Write-Host "OK: Stored Procedure 'sp_Merge_Generic' ist vorhanden." -ForegroundColor Green
    }
}
catch {
    Write-Error "PRE-FLIGHT CHECK (PROCEDURE) FAILED: $($_.Exception.Message)"
    Stop-Transcript
    exit 9
}
finally {
    if ($TargetConn) {
        try { $TargetConn.Close() } catch { }
        try { $TargetConn.Dispose() } catch { }
    }
}

Write-Host "Konfiguration geladen. Tabellen: $($Tabellen.Count). Retries: $MaxRetries" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 8. HAUPTSCHLEIFE (PARALLEL MIT RETRY)
# -----------------------------------------------------------------------------

$Results = $Tabellen | ForEach-Object -Parallel {
    $Tabelle = $_
    
    # Variablen in Scope holen
    $FbCS = $using:FirebirdConnString
    $SqlCS = $using:SqlConnString
    $ForceRecreate = $using:RecreateStagingTable
    $ForceFull = $using:ForceFullSync
    $Timeout = $using:GlobalTimeout
    $DoSanity = $using:RunSanityCheck
    $Retries = $using:MaxRetries
    $Delay = $using:RetryDelaySeconds
    $Prefix = $using:MSSQLPrefix
    $Suffix = $using:MSSQLSuffix
    $DoCleanupOrphans = $using:CleanupOrphans
    $CleanupBatchSize = $using:OrphanCleanupBatchSize
    
    # Zieltabelle berechnen
    $TargetTableName = "${Prefix}${Tabelle}${Suffix}"
    
    $TableStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Status = "Offen"
    $Message = ""
    $RowsLoaded = 0
    $Strategy = ""
    $FbCount = -1
    $SqlCount = -1
    $SanityStatus = "N/A"
    $OrphansDeleted = 0
    
    # Connection Variablen AUSSERHALB der while-Schleife initialisieren
    $FbConn = $null
    $SqlConn = $null
    
    # RETRY LOOP
    $Attempt = 0
    $Success = $false
    
    while (-not $Success -and $Attempt -lt ($Retries + 1)) {
        $Attempt++
        
        # Connections vor jedem Versuch auf null setzen
        $FbConn = $null
        $SqlConn = $null
        
        if ($Attempt -gt 1) {
            Write-Host "[$Tabelle] Warnung: Versuch $Attempt von $($Retries + 1)... (Warte ${Delay}s)" -ForegroundColor Yellow
            Start-Sleep -Seconds $Delay
        }
        else {
            Write-Host "[$Tabelle] Starte Verarbeitung -> Ziel: $TargetTableName" -ForegroundColor DarkGray
        }

        try {
            $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbCS)
            $FbConn.Open()
            
            $SqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlCS)
            $SqlConn.Open()

            # A: ANALYSE (Quelle = $Tabelle)
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
            
            if ($ForceFull -and $SyncStrategy -eq "Incremental") { $SyncStrategy = "FullMerge (Forced)" }
            $Strategy = $SyncStrategy

            # B: STAGING (Bleibt STG_ + OriginalName)
            $StagingTableName = "STG_$Tabelle"
            $CmdCheck = $SqlConn.CreateCommand()
            $CmdCheck.CommandTimeout = $Timeout
            $CmdCheck.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$StagingTableName'"
            $TableExists = $CmdCheck.ExecuteScalar() -gt 0

            if ($ForceRecreate -or -not $TableExists) {
                $CreateSql = "IF OBJECT_ID('$StagingTableName') IS NOT NULL DROP TABLE $StagingTableName; CREATE TABLE $StagingTableName ("
                $Cols = @()
                foreach ($Row in $SchemaTable) {
                    $ColName = $Row.ColumnName
                    $DotNetType = $Row.DataType
                    $Size = $Row.ColumnSize
                    $AllowDBNull = $Row.AllowDBNull
                    
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
                    
                    if (-not $AllowDBNull -or $ColName -eq "ID") {
                        $SqlType += " NOT NULL"
                    }
                    
                    $Cols += "[$ColName] $SqlType"
                }
                $CreateSql += [string]::Join(", ", $Cols) + ");"
                
                $CmdCreate = $SqlConn.CreateCommand()
                $CmdCreate.CommandTimeout = $Timeout
                $CmdCreate.CommandText = $CreateSql
                [void]$CmdCreate.ExecuteNonQuery()
            }

            # C: EXTRAKT (Quelle = $Tabelle)
            $FbCmdData = $FbConn.CreateCommand()
            if ($SyncStrategy -eq "Incremental") {
                $CmdMax = $SqlConn.CreateCommand()
                $CmdMax.CommandTimeout = $Timeout
                $CmdMax.CommandText = "SELECT ISNULL(MAX(GESPEICHERT), '1900-01-01') FROM $TargetTableName" 
                try { $LastSyncDate = [DateTime]$CmdMax.ExecuteScalar() } catch { $LastSyncDate = [DateTime]"1900-01-01" }
                
                $FbCmdData.CommandText = "SELECT * FROM ""$Tabelle"" WHERE ""GESPEICHERT"" > @LastDate"
                $FbCmdData.Parameters.Add("@LastDate", $LastSyncDate) | Out-Null
            }
            else {
                $FbCmdData.CommandText = "SELECT * FROM ""$Tabelle"""
            }
            $ReaderData = $FbCmdData.ExecuteReader()
            
            # D: LOAD (BULK -> Staging)
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
            $BulkCopy.WriteToServer($ReaderData)
            $ReaderData.Close()

            # E: MERGE / STRUKTUR (Ziel = $TargetTableName)
            $RowsCopied = $SqlConn.CreateCommand()
            $RowsCopied.CommandTimeout = $Timeout
            $RowsCopied.CommandText = "SELECT COUNT(*) FROM $StagingTableName"
            $Count = $RowsCopied.ExecuteScalar()
            $RowsLoaded = $Count
            
            # Zieltabelle anlegen?
            $CheckFinal = $SqlConn.CreateCommand()
            $CheckFinal.CommandTimeout = $Timeout
            $CheckFinal.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TargetTableName'"
            $FinalTableExists = $CheckFinal.ExecuteScalar() -gt 0
            if (-not $FinalTableExists) {
                $InitCmd = $SqlConn.CreateCommand()
                $InitCmd.CommandTimeout = $Timeout
                $InitCmd.CommandText = "SELECT * INTO $TargetTableName FROM $StagingTableName WHERE 1=0;" 
                [void]$InitCmd.ExecuteNonQuery()
            }

            # Index Pflege ($TargetTableName)
            if ($HasID) {
                try {
                    $IdxCheckCmd = $SqlConn.CreateCommand()
                    $IdxCheckCmd.CommandTimeout = $Timeout
                    $IdxCheckCmd.CommandText = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$TargetTableName') AND is_primary_key = 1"
                    if (($IdxCheckCmd.ExecuteScalar()) -eq 0) {
                        # Repair Nullable ID
                        $GetTypeCmd = $SqlConn.CreateCommand()
                        $GetTypeCmd.CommandText = "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$TargetTableName' AND COLUMN_NAME = 'ID'"
                        $IdType = $GetTypeCmd.ExecuteScalar()
                        if ($IdType) {
                            $AlterColCmd = $SqlConn.CreateCommand()
                            $AlterColCmd.CommandTimeout = $Timeout
                            $AlterColCmd.CommandText = "ALTER TABLE [$TargetTableName] ALTER COLUMN [ID] $IdType NOT NULL;"
                            try { [void]$AlterColCmd.ExecuteNonQuery() } catch { }
                        }
                        $IdxCmd = $SqlConn.CreateCommand()
                        $IdxCmd.CommandTimeout = $Timeout
                        $IdxCmd.CommandText = "ALTER TABLE [$TargetTableName] ADD CONSTRAINT [PK_$TargetTableName] PRIMARY KEY CLUSTERED ([ID] ASC);"
                        [void]$IdxCmd.ExecuteNonQuery()
                        $Message += "(PK created) "
                    }
                }
                catch { 
                    $Message += "(PK Err: $($_.Exception.Message)) " 
                }
            }

            # Merge Ausführen
            if ($Count -gt 0) {
                # Staging Index
                if ($HasID) {
                    try {
                        $StgIdxCmd = $SqlConn.CreateCommand()
                        $StgIdxCmd.CommandTimeout = $Timeout
                        $StgIdxCmd.CommandText = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$StagingTableName') AND name = 'PK_$StagingTableName'"
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
                    $FinalCmd.CommandText = "TRUNCATE TABLE $TargetTableName; INSERT INTO $TargetTableName SELECT * FROM $StagingTableName;"
                    [void]$FinalCmd.ExecuteNonQuery()
                }
                else {
                    if ($ForceFull) {
                        $FinalCmd = $SqlConn.CreateCommand()
                        $FinalCmd.CommandTimeout = $Timeout
                        $FinalCmd.CommandText = "TRUNCATE TABLE $TargetTableName;" 
                        [void]$FinalCmd.ExecuteNonQuery()
                    }
                    
                    $MergeCmd = $SqlConn.CreateCommand()
                    $MergeCmd.CommandTimeout = $Timeout
                    $MergeCmd.CommandText = "EXEC sp_Merge_Generic @TargetTableName = '$TargetTableName', @StagingTableName = '$StagingTableName'"
                    [void]$MergeCmd.ExecuteNonQuery()
                    
                    if ($ForceFull) { $Message += "(Reset & Reload) " }
                }
            }

            # G: ORPHAN CLEANUP (nur bei HasID und CleanupOrphans aktiviert)
            # Nicht nötig bei: Snapshot (Truncate+Insert), ForceFullSync (Truncate+Merge)
            if ($DoCleanupOrphans -and $HasID -and $SyncStrategy -notin @("Snapshot", "FullMerge (Forced)")) {
                try {
                    Write-Host "[$Tabelle] Starte Orphan-Cleanup..." -ForegroundColor DarkGray
                    
                    # Temp-Tabelle für Quell-IDs erstellen
                    $TempTableName = "#SourceIDs_$Tabelle"
                    $CreateTempCmd = $SqlConn.CreateCommand()
                    $CreateTempCmd.CommandTimeout = $Timeout
                    $CreateTempCmd.CommandText = "CREATE TABLE $TempTableName (ID BIGINT NOT NULL PRIMARY KEY);"
                    [void]$CreateTempCmd.ExecuteNonQuery()
                    
                    # Alle IDs aus Firebird laden (nur ID-Spalte)
                    $FbIdCmd = $FbConn.CreateCommand()
                    $FbIdCmd.CommandText = "SELECT ID FROM ""$Tabelle"""
                    $IdReader = $FbIdCmd.ExecuteReader()
                    
                    # BulkCopy für IDs in Batches
                    $IdBulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($SqlConn)
                    $IdBulkCopy.DestinationTableName = $TempTableName
                    $IdBulkCopy.BulkCopyTimeout = $Timeout
                    $IdBulkCopy.BatchSize = $CleanupBatchSize
                    [void]$IdBulkCopy.ColumnMappings.Add("ID", "ID")
                    $IdBulkCopy.WriteToServer($IdReader)
                    $IdReader.Close()
                    
                    # Verwaiste Datensätze löschen
                    $DeleteOrphansCmd = $SqlConn.CreateCommand()
                    $DeleteOrphansCmd.CommandTimeout = $Timeout
                    $DeleteOrphansCmd.CommandText = @"
                        DELETE FROM [$TargetTableName] 
                        WHERE ID NOT IN (SELECT ID FROM $TempTableName);
                        SELECT @@ROWCOUNT;
"@
                    $OrphansDeleted = [int]$DeleteOrphansCmd.ExecuteScalar()
                    
                    # Temp-Tabelle aufräumen
                    $DropTempCmd = $SqlConn.CreateCommand()
                    $DropTempCmd.CommandText = "DROP TABLE $TempTableName;"
                    [void]$DropTempCmd.ExecuteNonQuery()
                    
                    if ($OrphansDeleted -gt 0) {
                        $Message += "(Cleanup: $OrphansDeleted gelöscht) "
                        Write-Host "[$Tabelle] Orphan-Cleanup: $OrphansDeleted Datensätze gelöscht." -ForegroundColor Yellow
                    }
                }
                catch {
                    $Message += "(Cleanup-Fehler: $($_.Exception.Message)) "
                    Write-Host "[$Tabelle] Orphan-Cleanup Fehler: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            # H: SANITY ($TargetTableName prüfen)
            if ($DoSanity) {
                $FbCountCmd = $FbConn.CreateCommand()
                $FbCountCmd.CommandText = "SELECT COUNT(*) FROM ""$Tabelle"""
                $FbCount = [int64]$FbCountCmd.ExecuteScalar()
                
                $SqlCountCmd = $SqlConn.CreateCommand()
                $SqlCountCmd.CommandTimeout = $Timeout
                $SqlCountCmd.CommandText = "SELECT COUNT(*) FROM $TargetTableName"
                $SqlCount = [int64]$SqlCountCmd.ExecuteScalar()
                
                $CountDiff = $SqlCount - $FbCount
                if ($CountDiff -eq 0) { $SanityStatus = "OK" }
                elseif ($CountDiff -gt 0) { $SanityStatus = "WARNUNG (+$CountDiff)" }
                else { $SanityStatus = "FEHLER ($CountDiff)" }
            }

            $Status = "Erfolg"
            $Success = $true

        }
        catch {
            $Status = "Fehler"
            $Message = $_.Exception.Message
            Write-Host "[$Tabelle] ERROR (Versuch $Attempt): $Message" -ForegroundColor Red
        }
        finally {
            # WICHTIG: Connections IMMER aufräumen, unabhängig von Erfolg/Misserfolg
            if ($FbConn) {
                try { $FbConn.Close() } catch { }
                try { $FbConn.Dispose() } catch { }
            }
            if ($SqlConn) {
                try { $SqlConn.Close() } catch { }
                try { $SqlConn.Dispose() } catch { }
            }
        }
    } 

    $TableStopwatch.Stop()
    Write-Host "[$Tabelle] Abschluss: $Status ($SanityStatus)" -ForegroundColor ($Status -eq "Erfolg" ? "Green" : "Red")

    [PSCustomObject]@{
        Tabelle        = $Tabelle
        Target         = $TargetTableName
        Status         = $Status
        Strategie      = $Strategy
        RowsLoaded     = $RowsLoaded
        OrphansDeleted = $OrphansDeleted
        FbTotal        = if ($DoSanity) { $FbCount } else { "-" }
        SqlTotal       = if ($DoSanity) { $SqlCount } else { "-" }
        SanityCheck    = $SanityStatus
        Duration       = $TableStopwatch.Elapsed
        Speed          = if ($TableStopwatch.Elapsed.TotalSeconds -gt 0) { [math]::Round($RowsLoaded / $TableStopwatch.Elapsed.TotalSeconds, 0) } else { 0 }
        Info           = $Message
        Versuche       = $Attempt
    }

} -ThrottleLimit 4

# -----------------------------------------------------------------------------
# 9. ABSCHLUSS
# -----------------------------------------------------------------------------
$TotalStopwatch.Stop()

Write-Host "ZUSAMMENFASSUNG" -ForegroundColor White
$Results | Format-Table -AutoSize @{Label = "Quelle"; Expression = { $_.Tabelle } },
@{Label = "Ziel"; Expression = { $_.Target } },
@{Label = "Status"; Expression = { $_.Status } },
@{Label = "Sync"; Expression = { $_.RowsLoaded }; Align = "Right" },
@{Label = "Del"; Expression = { $_.OrphansDeleted }; Align = "Right" },
@{Label = "FB"; Expression = { $_.FbTotal }; Align = "Right" },
@{Label = "SQL"; Expression = { $_.SqlTotal }; Align = "Right" },
@{Label = "Sanity"; Expression = { $_.SanityCheck } },
@{Label = "Time"; Expression = { $_.Duration.ToString("mm\:ss") } },
@{Label = "Info"; Expression = { $_.Info } }

# -----------------------------------------------------------------------------
# 10. LOG ROTATION (CLEANUP)
# -----------------------------------------------------------------------------
if ($DeleteLogOlderThanDays -gt 0) {
    Write-Host "Prüfe auf alte Logs (älter als $DeleteLogOlderThanDays Tage)..." -ForegroundColor Gray
    try {
        $CleanupDate = (Get-Date).AddDays(-$DeleteLogOlderThanDays)
        $OldLogs = Get-ChildItem -Path $LogDir -Filter "Sync_*.log" | Where-Object { $_.LastWriteTime -lt $CleanupDate }
        
        if ($OldLogs) {
            $OldLogs | Remove-Item -Force
            Write-Host "Cleanup: $($OldLogs.Count) alte Log-Dateien gelöscht." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Warnung beim Log-Cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "Log-Cleanup deaktiviert. (Einstellung = 0 Tage)" -ForegroundColor Gray
}

Write-Host "GESAMTLAUFZEIT: $($TotalStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green
Write-Host "LOGDATEI: $LogFile" -ForegroundColor Gray

Stop-Transcript