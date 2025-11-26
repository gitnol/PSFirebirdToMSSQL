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

    Empfehlung:
    - Täglich: Inkrementeller Sync (schnell, Updates/Inserts).
    - Wöchentlich (Wochenende): Ein Job, der die Tabellen leert (TRUNCATE) und einmal voll lädt (Snapshot oder $RecreateStagingTable=$true mit Datum-Reset). 

.NOTES
    Version: 2.1 (Prod)
    
    CREDENTIAL SETUP:
    Führe einmalig Setup_Credentials.ps1 aus, um Passwörter sicher zu speichern.
    Alternativ: Passwörter in config.json (unsicher, nur für Tests).
#>

# -----------------------------------------------------------------------------
# 1. INITIALISIERUNG & LOGGING
# -----------------------------------------------------------------------------
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Pfade
$ScriptDir = $PSScriptRoot
$LogDir = Join-Path $ScriptDir "Logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# Logging starten (Schreibt Konsole UND Datei)
$LogFile = Join-Path $LogDir "Sync_$(Get-Date -Format 'yyyy-MM-dd_HHmm').log"
Start-Transcript -Path $LogFile -Append

Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "SQLSync STARTED at $(Get-Date)" -ForegroundColor White
Write-Host "--------------------------------------------------------" -ForegroundColor Gray


# -----------------------------------------------------------------------------
# 2. CREDENTIAL MANAGER FUNKTION
# -----------------------------------------------------------------------------

function Get-StoredCredential {
    <#
    .SYNOPSIS
        Liest Credentials aus dem Windows Credential Manager.
    .PARAMETER Target
        Name des gespeicherten Credentials (z.B. "SQLSync_Firebird")
    .OUTPUTS
        PSCustomObject mit Username und Password, oder $null wenn nicht gefunden.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Target
    )
    
    # P/Invoke für Windows Credential API
    Add-Type -Namespace "CredManager" -Name "Util" -MemberDefinition @'
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool CredRead(
            string target,
            int type,
            int reserved,
            out IntPtr credential);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern void CredFree(IntPtr credential);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CREDENTIAL {
            public int Flags;
            public int Type;
            public string TargetName;
            public string Comment;
            public long LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }
'@ -ErrorAction SilentlyContinue

    $CredPtr = [IntPtr]::Zero
    $Success = [CredManager.Util]::CredRead($Target, 1, 0, [ref]$CredPtr)
    
    if (-not $Success) {
        return $null
    }
    
    try {
        $Cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($CredPtr, [Type][CredManager.Util+CREDENTIAL])
        
        $Password = ""
        if ($Cred.CredentialBlobSize -gt 0) {
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($Cred.CredentialBlob, $Cred.CredentialBlobSize / 2)
        }
        
        return [PSCustomObject]@{
            Username = $Cred.UserName
            Password = $Password
        }
    }
    finally {
        [CredManager.Util]::CredFree($CredPtr)
    }
}


# Config laden
$ConfigPath = Join-Path $ScriptDir "config.json"
if (-not (Test-Path $ConfigPath)) { 
    Write-Error "KRITISCH: config.json fehlt!"
    Stop-Transcript
    exit 1 
}
try {
    $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "KRITISCH: config.json ist kein gültiges JSON."
    Stop-Transcript
    exit 2
}

# -----------------------------------------------------------------------------
# 3. CONFIG & CREDENTIALS LADEN
# -----------------------------------------------------------------------------

$ConfigPath = Join-Path $ScriptDir "config.json"
if (-not (Test-Path $ConfigPath)) { 
    Write-Error "KRITISCH: config.json fehlt!"
    Stop-Transcript
    exit 3
}
try {
    $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "KRITISCH: config.json ist kein gültiges JSON."
    Stop-Transcript
    exit 4
}

# Generelle Konfiguration
$GlobalTimeout = $Config.General.$GlobalTimeout # Standard: 7200 
$RecreateStagingTable = $Config.General.$RecreateStagingTable # Standard: $false
$RunSanityCheck = $Config.General.$RunSanityCheck # Standard: $true
$MaxRetries = $Config.General.$MaxRetries         # Wie oft soll bei Fehler wiederholt werden? (Standard: 3)
$RetryDelaySeconds = $Config.General.$RetryDelaySeconds  # Wartezeit zwischen Versuchen (Standard: 10)

# --- FIREBIRD CREDENTIALS ---
$FBservername = $Config.Firebird.Server
$FBdatabase = $Config.Firebird.Database
$FBport = $Config.Firebird.Port
$FBcharset = $Config.Firebird.Charset
$DllPath = $Config.Firebird.DllPath

# Versuche Credentials aus Credential Manager zu laden
$FbCred = Get-StoredCredential -Target "SQLSync_Firebird"
if ($FbCred) {
    $FBuser = $FbCred.Username
    $FBpassword = $FbCred.Password
    Write-Host "[Credentials] Firebird: Credential Manager" -ForegroundColor Green
    if ($Config.Firebird.Password -or $Config.MSSQL.Password) {
        Write-Host "WARNUNG: Passwörter in config.json werden ignoriert, da Credential Manager verwendet wird." -ForegroundColor Yellow
        Write-Host "WARNUNG: Es wird empfohlen, die Passwörter in der config.json zu entfernen." -ForegroundColor Yellow
    }
}
elseif ($Config.Firebird.Password) {
    # Fallback auf config.json
    $FBuser = if ($Config.Firebird.User) { $Config.Firebird.User } else { "SYSDBA" }
    $FBpassword = $Config.Firebird.Password
    Write-Host "[Credentials] Firebird: config.json (WARNUNG: unsicher!)" -ForegroundColor Yellow
}
else {
    Write-Error "KRITISCH: Keine Firebird Credentials! Führe Setup_Credentials.ps1 aus."
    Stop-Transcript
    exit 5
}

# --- MSSQL CREDENTIALS ---
$MSSQLservername = $Config.MSSQL.Server
$MSSQLdatabase = $Config.MSSQL.Database
$MSSQLIntSec = $Config.MSSQL."Integrated Security"

if ($MSSQLIntSec) {
    Write-Host "[Credentials] SQL Server: Windows Authentication" -ForegroundColor Green
    $MSSQLUser = $null
    $MSSQLPass = $null
}
else {
    $SqlCred = Get-StoredCredential -Target "SQLSync_MSSQL"
    if ($SqlCred) {
        $MSSQLUser = $SqlCred.Username
        $MSSQLPass = $SqlCred.Password
        Write-Host "[Credentials] SQL Server: Credential Manager" -ForegroundColor Green
    }
    elseif ($Config.MSSQL.Password) {
        $MSSQLUser = $Config.MSSQL.Username
        $MSSQLPass = $Config.MSSQL.Password
        Write-Host "[Credentials] SQL Server: config.json (WARNUNG: unsicher!)" -ForegroundColor Yellow
    }
    else {
        Write-Error "KRITISCH: Keine SQL Server Credentials! Führe Setup_Credentials.ps1 aus."
        Stop-Transcript
        exit 6
    }
}

# -----------------------------------------------------------------------------
# 4. TREIBER & CONNECTION STRINGS
# -----------------------------------------------------------------------------

# Treiber laden
if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue)) {
    Install-Package FirebirdSql.Data.FirebirdClient -Force -Confirm:$false | Out-Null
}
if (-not (Test-Path $DllPath)) {
    $DllPath = (Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse | Select-Object -First 1).FullName
}
if (-not $DllPath) {
    Write-Error "KRITISCH: Firebird Treiber DLL nicht gefunden."
    Stop-Transcript
    exit 7
}
Add-Type -Path $DllPath

# Connection Strings
$FirebirdConnString = "User=$($FBuser);Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"
if ($MSSQLIntSec) {
    $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;Integrated Security=True;"
}
else {
    $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;User Id=$MSSQLUser;Password=$MSSQLPass;"
}

$Tabellen = $Config.Tables
if (-not $Tabellen -or $Tabellen.Count -eq 0) { 
    Write-Error "Keine Tabellen definiert."
    Stop-Transcript
    exit 8
}

Write-Host "Konfiguration geladen. Tabellen: $($Tabellen.Count). Retries: $MaxRetries" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 5. HAUPTSCHLEIFE (PARALLEL MIT RETRY)
# -----------------------------------------------------------------------------

$Results = $Tabellen | ForEach-Object -Parallel {
    $Tabelle = $_
    # Variablen in Scope holen
    $FbCS = $using:FirebirdConnString
    $SqlCS = $using:SqlConnString
    $ForceRecreate = $using:RecreateStagingTable
    $Timeout = $using:GlobalTimeout
    $DoSanity = $using:RunSanityCheck
    $Retries = $using:MaxRetries
    $Delay = $using:RetryDelaySeconds
    
    $TableStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Status = "Offen"
    $Message = ""
    $RowsLoaded = 0
    $Strategy = ""
    $FbCount = -1
    $SqlCount = -1
    $SanityStatus = "N/A"
    
    # RETRY LOOP
    $Attempt = 0
    $Success = $false
    
    while (-not $Success -and $Attempt -lt ($Retries + 1)) {
        $Attempt++
        if ($Attempt -gt 1) {
            Write-Host "[$Tabelle] Warnung: Versuch $Attempt von $($Retries + 1)... (Warte ${Delay}s)" -ForegroundColor Yellow
            Start-Sleep -Seconds $Delay
        }
        else {
            Write-Host "[$Tabelle] Starte Verarbeitung..." -ForegroundColor DarkGray
        }

        try {
            # VERBINDUNGEN AUFBAUEN
            $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbCS)
            $FbConn.Open()
            
            $SqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlCS)
            $SqlConn.Open()

            # A: ANALYSE
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

            # B: STAGING
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
                    if ($ColName -eq "ID") { $SqlType += " NOT NULL" }
                    $Cols += "[$ColName] $SqlType"
                }
                $CreateSql += [string]::Join(", ", $Cols) + ");"
                
                $CmdCreate = $SqlConn.CreateCommand()
                $CmdCreate.CommandTimeout = $Timeout
                $CmdCreate.CommandText = $CreateSql
                [void]$CmdCreate.ExecuteNonQuery()
            }

            # C: EXTRAKT
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
            
            # D: LOAD (BULK)
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
            $ReaderData.Close() # Wichtig: Reader schließen bevor weitere SQL Befehle kommen

            # E: MERGE / STRUKTUR
            $RowsCopied = $SqlConn.CreateCommand()
            $RowsCopied.CommandTimeout = $Timeout
            $RowsCopied.CommandText = "SELECT COUNT(*) FROM $StagingTableName"
            $Count = $RowsCopied.ExecuteScalar()
            $RowsLoaded = $Count
            
            # Zieltabelle anlegen?
            $CheckFinal = $SqlConn.CreateCommand()
            $CheckFinal.CommandTimeout = $Timeout
            $CheckFinal.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$Tabelle'"
            $FinalTableExists = $CheckFinal.ExecuteScalar() -gt 0
            if (-not $FinalTableExists) {
                $InitCmd = $SqlConn.CreateCommand()
                $InitCmd.CommandTimeout = $Timeout
                $InitCmd.CommandText = "SELECT * INTO $Tabelle FROM $StagingTableName WHERE 1=0;" 
                [void]$InitCmd.ExecuteNonQuery()
            }

            # Index Pflege
            if ($HasID) {
                try {
                    $IdxCheckCmd = $SqlConn.CreateCommand()
                    $IdxCheckCmd.CommandTimeout = $Timeout
                    $IdxCheckCmd.CommandText = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$Tabelle') AND is_primary_key = 1"
                    if (($IdxCheckCmd.ExecuteScalar()) -eq 0) {
                        # Repair Nullable ID
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
                        $Message += "(PK created) "
                    }
                }
                catch { $Message += "(PK Err) " }
            }

            # Merge Ausführen
            if ($Count -gt 0) {
                # Staging Index (Speedup)
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

            # F: SANITY
            if ($DoSanity) {
                $FbCountCmd = $FbConn.CreateCommand()
                $FbCountCmd.CommandText = "SELECT COUNT(*) FROM ""$Tabelle"""
                $FbCount = [int64]$FbCountCmd.ExecuteScalar()
                
                $SqlCountCmd = $SqlConn.CreateCommand()
                $SqlCountCmd.CommandTimeout = $Timeout
                $SqlCountCmd.CommandText = "SELECT COUNT(*) FROM $Tabelle"
                $SqlCount = [int64]$SqlCountCmd.ExecuteScalar()
                
                $CountDiff = $SqlCount - $FbCount
                if ($CountDiff -eq 0) { $SanityStatus = "OK" }
                elseif ($CountDiff -gt 0) { $SanityStatus = "WARNUNG (+$CountDiff)" }
                else { $SanityStatus = "FEHLER ($CountDiff)" }
            }

            $Status = "Erfolg"
            $Success = $true # Schleife beenden

        }
        catch {
            $Status = "Fehler"
            $Message = $_.Exception.Message
            Write-Host "[$Tabelle] ERROR (Versuch $Attempt): $Message" -ForegroundColor Red
            
            # Connections sauber schließen vor Retry
            if ($FbConn) { $FbConn.Close(); $FbConn.Dispose() }
            if ($SqlConn) { $SqlConn.Close(); $SqlConn.Dispose() }
        }
        finally {
            # Sicherstellen, dass am Ende geschlossen wird
            if ($Success) {
                if ($FbConn) { $FbConn.Close() }
                if ($SqlConn) { $SqlConn.Close() }
            }
        }
    } # End While Retry

    $TableStopwatch.Stop()
    Write-Host "[$Tabelle] Abschluss: $Status ($SanityStatus)" -ForegroundColor ($Status -eq "Erfolg" ? "Green" : "Red")

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
        Versuche    = $Attempt
    }

} -ThrottleLimit 4

# -----------------------------------------------------------------------------
# 6. ABSCHLUSS
# -----------------------------------------------------------------------------
$TotalStopwatch.Stop()

Write-Host "ZUSAMMENFASSUNG" -ForegroundColor White
$Results | Format-Table -AutoSize @{Label = "Tabelle"; Expression = { $_.Tabelle } },
@{Label = "Status"; Expression = { $_.Status } },
@{Label = "Sync"; Expression = { $_.RowsLoaded }; Align = "Right" },
@{Label = "FB"; Expression = { $_.FbTotal }; Align = "Right" },
@{Label = "SQL"; Expression = { $_.SqlTotal }; Align = "Right" },
@{Label = "Sanity"; Expression = { $_.SanityCheck } },
@{Label = "Time"; Expression = { $_.Duration.ToString("mm\:ss") } },
@{Label = "Try"; Expression = { $_.Versuche } },
@{Label = "Info"; Expression = { $_.Info } }

Write-Host "GESAMTLAUFZEIT: $($TotalStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green
Write-Host "LOGDATEI: $LogFile" -ForegroundColor Gray

Stop-Transcript

if ($Config.Firebird.Password -or $Config.MSSQL.Password) {
    Write-Host "WARNUNG: Passwörter in config.json werden ignoriert, da Credential Manager verwendet wird." -ForegroundColor Yellow
    Write-Host "WARNUNG: Es wird empfohlen, die Passwörter in der config.json zu entfernen." -ForegroundColor Yellow
}