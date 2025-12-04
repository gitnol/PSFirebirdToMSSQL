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
    - NEU: Config-Datei per Parameter wählbar
    - NEU: Unterstützung für Prefix/Suffix bei Zieltabellen

.PARAMETER ConfigFile
    Optional. Der Pfad zur JSON-Konfigurationsdatei.
    Standard: "config.json" im Skript-Verzeichnis.

.NOTES
    Version: 2.6 (Prod + Fixes + Clean Code)
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile
)

# -----------------------------------------------------------------------------
# 1. INITIALISIERUNG & LOGGING & PFADE
# -----------------------------------------------------------------------------
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$ScriptDir = $PSScriptRoot

# 1a. Konfigurationsdatei ermitteln
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

# 1b. Logging starten
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
# 2. CREDENTIAL MANAGER FUNKTION (ROBUST)
# -----------------------------------------------------------------------------
function Get-StoredCredential {
    param([Parameter(Mandatory)][string]$Target)
    
    # Prüfen ob Typ schon existiert (verhindert Fehler bei erneutem Laden)
    if (-not ('CredManager.Util' -as [type])) {
        $Source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CredManager {
    public static class Util {
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool CredRead(string target, int type, int reserved, out IntPtr credential);

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
    }
}
'@
        Add-Type -TypeDefinition $Source -Language CSharp
    }

    $CredPtr = [IntPtr]::Zero
    $Success = [CredManager.Util]::CredRead($Target, 1, 0, [ref]$CredPtr)
    
    if (-not $Success) { return $null }
    
    try {
        $Cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($CredPtr, [Type][CredManager.Util+CREDENTIAL])
        $Password = ""
        if ($Cred.CredentialBlobSize -gt 0) {
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($Cred.CredentialBlob, $Cred.CredentialBlobSize / 2)
        }
        return [PSCustomObject]@{ Username = $Cred.UserName; Password = $Password }
    }
    finally { [CredManager.Util]::CredFree($CredPtr) }
}

# -----------------------------------------------------------------------------
# 3. CONFIG & CREDENTIALS LADEN
# -----------------------------------------------------------------------------

if (-not (Test-Path $ConfigPath)) { 
    Write-Error "KRITISCH: Konfigurationsdatei '$ConfigPath' nicht gefunden!"
    Stop-Transcript; exit 1 
}
try {
    $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "KRITISCH: '$ConfigPath' ist kein gültiges JSON."
    Stop-Transcript; exit 2
}

# Generelle Konfiguration
$GlobalTimeout = if ($Config.General.PSObject.Properties.Match("GlobalTimeout").Count) { $Config.General.GlobalTimeout } else { 7200 }
$RecreateStagingTable = if ($Config.General.PSObject.Properties.Match("RecreateStagingTable").Count) { $Config.General.RecreateStagingTable } else { $false }
$RunSanityCheck = if ($Config.General.PSObject.Properties.Match("RunSanityCheck").Count) { $Config.General.RunSanityCheck } else { $true }
$MaxRetries = if ($Config.General.PSObject.Properties.Match("MaxRetries").Count) { $Config.General.MaxRetries } else { 3 }
$RetryDelaySeconds = if ($Config.General.PSObject.Properties.Match("RetryDelaySeconds").Count) { $Config.General.RetryDelaySeconds } else { 10 }
# Wird am Schluss des Scripts unter LOG ROTATION (CLEANUP) verwendet
$DeleteLogOlderThanDays = if ($Config.General.PSObject.Properties.Match("DeleteLogOlderThanDays").Count) { $Config.General.DeleteLogOlderThanDays } else { 30 }

# --- NEU: Prefix und Suffix auslesen ---
$MSSQLPrefix = if ($Config.MSSQL.PSObject.Properties.Match("Prefix").Count) { $Config.MSSQL.Prefix } else { "" }
$MSSQLSuffix = if ($Config.MSSQL.PSObject.Properties.Match("Suffix").Count) { $Config.MSSQL.Suffix } else { "" }

# Validierung
if ($GlobalTimeout -le 0) { Write-Error "KRITISCH: GlobalTimeout muss > 0 sein."; Stop-Transcript; exit 99 }
if ($MSSQLPrefix -ne "" -or $MSSQLSuffix -ne "") {
    Write-Host "INFO: MSSQL Zieltabellen werden angepasst: '$MSSQLPrefix' + [Name] + '$MSSQLSuffix'" -ForegroundColor Cyan
}

# Force Full Sync Check
$ForceFullSync = if ($Config.General.PSObject.Properties.Match("ForceFullSync").Count) { $Config.General.ForceFullSync } else { $false }
if ($ForceFullSync) { Write-Host "WARNUNG: ForceFullSync ist AKTIViert. Es werden ALLE Daten neu geladen!" -ForegroundColor Magenta }

# --- CREDENTIALS (FIREBIRD & MSSQL) ---
$FBservername = $Config.Firebird.Server
$FBdatabase = $Config.Firebird.Database
$FBport = $Config.Firebird.Port
$FBcharset = $Config.Firebird.Charset
$DllPath = $Config.Firebird.DllPath

$FbCred = Get-StoredCredential -Target "SQLSync_Firebird"
if ($FbCred) { $FBuser = $FbCred.Username; $FBpassword = $FbCred.Password; Write-Host "[Credentials] Firebird: Credential Manager" -ForegroundColor Green }
elseif ($Config.Firebird.Password) { $FBuser = if ($Config.Firebird.User) { $Config.Firebird.User } else { "SYSDBA" }; $FBpassword = $Config.Firebird.Password; Write-Host "[Credentials] Firebird: config.json (WARNUNG: unsicher!)" -ForegroundColor Yellow }
else { Write-Error "KRITISCH: Keine Firebird Credentials! Führe Setup_Credentials.ps1 aus."; Stop-Transcript; exit 5 }

$MSSQLservername = $Config.MSSQL.Server
$MSSQLdatabase = $Config.MSSQL.Database
$MSSQLIntSec = $Config.MSSQL."Integrated Security"

if ($MSSQLIntSec) { Write-Host "[Credentials] SQL Server: Windows Authentication" -ForegroundColor Green; $MSSQLUser = $null; $MSSQLPass = $null }
else {
    $SqlCred = Get-StoredCredential -Target "SQLSync_MSSQL"
    if ($SqlCred) { $MSSQLUser = $SqlCred.Username; $MSSQLPass = $SqlCred.Password; Write-Host "[Credentials] SQL Server: Credential Manager" -ForegroundColor Green }
    elseif ($Config.MSSQL.Password) { $MSSQLUser = $Config.MSSQL.Username; $MSSQLPass = $Config.MSSQL.Password; Write-Host "[Credentials] SQL Server: config.json (WARNUNG: unsicher!)" -ForegroundColor Yellow }
    else { Write-Error "KRITISCH: Keine SQL Server Credentials! Führe Setup_Credentials.ps1 aus."; Stop-Transcript; exit 6 }
}

# -----------------------------------------------------------------------------
# 4. TREIBER & CONNECTION STRINGS
# -----------------------------------------------------------------------------
if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue)) { Install-Package FirebirdSql.Data.FirebirdClient -Force -Confirm:$false | Out-Null }
if (-not (Test-Path $DllPath)) {
    $PotentialDll = Join-Path $ScriptDir $DllPath
    if (Test-Path $PotentialDll) { $DllPath = $PotentialDll } else { $DllPath = (Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse | Select-Object -First 1).FullName }
}
if (-not $DllPath -or -not (Test-Path $DllPath)) { Write-Error "KRITISCH: Firebird Treiber DLL nicht gefunden."; Stop-Transcript; exit 7 }
Add-Type -Path $DllPath

Write-Host "Firebird User=$($FBuser);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);" -ForegroundColor Cyan
Write-Host "SQL Server Server=$MSSQLservername;Database=$MSSQLdatabase;Integrated Security=$MSSQLIntSec;" -ForegroundColor Cyan

$FirebirdConnString = "User=$($FBuser);Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"
if ($MSSQLIntSec) { $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;Integrated Security=True;" }
else { $SqlConnString = "Server=$MSSQLservername;Database=$MSSQLdatabase;User Id=$MSSQLUser;Password=$MSSQLPass;" }

$Tabellen = $Config.Tables
if (-not $Tabellen -or $Tabellen.Count -eq 0) { Write-Error "Keine Tabellen definiert."; Stop-Transcript; exit 8 }


# -----------------------------------------------------------------------------
# 4a. PRE-FLIGHT CHECK (MSSQL) & AUTO-SETUP
# -----------------------------------------------------------------------------
Write-Host "Führe Pre-Flight Checks durch..." -ForegroundColor Cyan

# --- TEIL 1: DATENBANK PRÜFEN / ERSTELLEN (via master) ---
try {
    # Verbindung zur Systemdatenbank 'master'
    if ($MSSQLIntSec) { 
        $MasterConnString = "Server=$MSSQLservername;Database=master;Integrated Security=True;" 
    }
    else { 
        $MasterConnString = "Server=$MSSQLservername;Database=master;User Id=$MSSQLUser;Password=$MSSQLPass;" 
    }

    $MasterConn = New-Object System.Data.SqlClient.SqlConnection($MasterConnString)
    $MasterConn.Open()

    $CreateDbCmd = $MasterConn.CreateCommand()
    # Logik: DB Erstellen + Recovery Simple, falls nicht existent
    $CreateDbCmd.CommandText = @"
    IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'$MSSQLdatabase')
    BEGIN
        CREATE DATABASE [$MSSQLdatabase];
        ALTER DATABASE [$MSSQLdatabase] SET RECOVERY SIMPLE;
        SELECT 1; 
    END
    ELSE
    BEGIN
        SELECT 0;
    END
"@
    $WasCreated = $CreateDbCmd.ExecuteScalar()
    $MasterConn.Close()

    if ($WasCreated -eq 1) {
        Write-Host "INFO: Datenbank '$MSSQLdatabase' wurde ERSTELLT (Recovery: Simple)." -ForegroundColor Yellow
        Start-Sleep -Seconds 2 # Kurz warten, bis SQL Server bereit ist
    }
    else {
        Write-Host "OK: Datenbank '$MSSQLdatabase' ist vorhanden." -ForegroundColor Green
    }
}
catch {
    Write-Error "KRITISCH: Fehler beim Prüfen/Erstellen der Datenbank: $($_.Exception.Message)"
    Stop-Transcript; exit 9
}

# --- TEIL 2: PROZEDUR PRÜFEN / INSTALLIEREN (via Ziel-DB) ---
try {
    # Wir nutzen hier den bereits konfigurierten $SqlConnString (zeigt auf Ziel-DB)
    $TargetConn = New-Object System.Data.SqlClient.SqlConnection($SqlConnString)
    $TargetConn.Open()
    
    # 2a. Prüfen ob SP existiert
    $CheckCmd = $TargetConn.CreateCommand()
    $CheckCmd.CommandText = "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_Merge_Generic]') AND type in (N'P', N'PC')"
    $ProcCount = $CheckCmd.ExecuteScalar()
    
    if ($ProcCount -eq 0) {
        Write-Host "Stored Procedure 'sp_Merge_Generic' fehlt. Starte Installation..." -ForegroundColor Yellow
        
        # Pfad zur SQL Datei
        $SqlFileName = "sql_server_setup.sql"
        $SqlFile = Join-Path $ScriptDir $SqlFileName
        
        if (-not (Test-Path $SqlFile)) {
            throw "Die Datei '$SqlFileName' wurde im Skript-Verzeichnis nicht gefunden! Bitte ablegen."
        }

        # Inhalt lesen
        $SqlContent = Get-Content -Path $SqlFile -Raw

        # --- KOMMENTAR-BEREINIGUNG START ---
        # 1. Block-Kommentare entfernen (/* ... */)
        #    Regex Erklärung: /\* matcht Start, [\s\S]*? matcht alles (auch Newlines) non-greedy, \*/ matcht Ende
        $SqlContent = [System.Text.RegularExpressions.Regex]::Replace($SqlContent, "/\*[\s\S]*?\*/", "")

        # 2. Zeilen-Kommentare entfernen (-- bis Zeilenende)
        #    Multiline Option sorgt dafür, dass $ das Zeilenende matcht
        $SqlContent = [System.Text.RegularExpressions.Regex]::Replace($SqlContent, "--.*$", "", [System.Text.RegularExpressions.RegexOptions]::Multiline)
        # --- KOMMENTAR-BEREINIGUNG ENDE ---

        # WICHTIG: Split am "GO" (case insensitive, eigene Zeile)
        $SqlBatches = [System.Text.RegularExpressions.Regex]::Split($SqlContent, "^\s*GO\s*$", [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        foreach ($Batch in $SqlBatches) {
            # Nur ausführen, wenn nach dem Entfernen von Kommentaren und Whitespace noch Code übrig ist
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
    
    $TargetConn.Close()
}
catch {
    Write-Error "PRE-FLIGHT CHECK (PROCEDURE) FAILED: $($_.Exception.Message)"
    if ($TargetConn) { $TargetConn.Close() }
    Stop-Transcript; exit 9
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
    $ForceFull = $using:ForceFullSync
    $Timeout = $using:GlobalTimeout
    $DoSanity = $using:RunSanityCheck
    $Retries = $using:MaxRetries
    $Delay = $using:RetryDelaySeconds
    
    # NEU: Prefix/Suffix in den Scope holen
    $Prefix = $using:MSSQLPrefix
    $Suffix = $using:MSSQLSuffix
    
    # NEU: Zieltabelle berechnen (Firebird-Name + Prefix/Suffix)
    $TargetTableName = "${Prefix}${Tabelle}${Suffix}"
    
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
            Write-Host "[$Tabelle] Starte Verarbeitung -> Ziel: $TargetTableName" -ForegroundColor DarkGray
        }

        try {
            $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbCS); $FbConn.Open()
            $SqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlCS); $SqlConn.Open()

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
            $CmdCheck = $SqlConn.CreateCommand(); $CmdCheck.CommandTimeout = $Timeout
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
                    
                    # Sauber formatierter Switch
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
                    
                    # WICHTIG: NOT NULL Prüfung
                    # 1. Wenn Quelle NOT NULL ist, übernehmen wir das.
                    # 2. Wenn es die ID Spalte ist, erzwingen wir NOT NULL (für PK).
                    if (-not $AllowDBNull -or $ColName -eq "ID") {
                        $SqlType += " NOT NULL"
                    }
                    
                    $Cols += "[$ColName] $SqlType"
                }
                $CreateSql += [string]::Join(", ", $Cols) + ");"
                
                $CmdCreate = $SqlConn.CreateCommand(); $CmdCreate.CommandTimeout = $Timeout; $CmdCreate.CommandText = $CreateSql
                [void]$CmdCreate.ExecuteNonQuery()
            }

            # C: EXTRAKT (Quelle = $Tabelle)
            $FbCmdData = $FbConn.CreateCommand()
            if ($SyncStrategy -eq "Incremental") {
                $CmdMax = $SqlConn.CreateCommand(); $CmdMax.CommandTimeout = $Timeout
                # NEU: Hole MaxDatum von Zieltabelle ($TargetTableName)
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
                $TruncCmd = $SqlConn.CreateCommand(); $TruncCmd.CommandTimeout = $Timeout
                $TruncCmd.CommandText = "TRUNCATE TABLE $StagingTableName"
                [void]$TruncCmd.ExecuteNonQuery()
            }
            $BulkCopy.WriteToServer($ReaderData); $ReaderData.Close()

            # E: MERGE / STRUKTUR (Ziel = $TargetTableName)
            $RowsCopied = $SqlConn.CreateCommand(); $RowsCopied.CommandTimeout = $Timeout
            $RowsCopied.CommandText = "SELECT COUNT(*) FROM $StagingTableName"
            $Count = $RowsCopied.ExecuteScalar()
            $RowsLoaded = $Count
            
            # Zieltabelle anlegen? (Check auf $TargetTableName)
            $CheckFinal = $SqlConn.CreateCommand(); $CheckFinal.CommandTimeout = $Timeout
            $CheckFinal.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TargetTableName'"
            $FinalTableExists = $CheckFinal.ExecuteScalar() -gt 0
            if (-not $FinalTableExists) {
                $InitCmd = $SqlConn.CreateCommand(); $InitCmd.CommandTimeout = $Timeout
                $InitCmd.CommandText = "SELECT * INTO $TargetTableName FROM $StagingTableName WHERE 1=0;" 
                [void]$InitCmd.ExecuteNonQuery()
            }

            # Index Pflege ($TargetTableName)
            if ($HasID) {
                try {
                    $IdxCheckCmd = $SqlConn.CreateCommand(); $IdxCheckCmd.CommandTimeout = $Timeout
                    $IdxCheckCmd.CommandText = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$TargetTableName') AND is_primary_key = 1"
                    if (($IdxCheckCmd.ExecuteScalar()) -eq 0) {
                        # Repair Nullable ID
                        $AlterColCmd = $SqlConn.CreateCommand(); $AlterColCmd.CommandTimeout = $Timeout
                        $GetTypeCmd = $SqlConn.CreateCommand()
                        $GetTypeCmd.CommandText = "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$TargetTableName' AND COLUMN_NAME = 'ID'"
                        $IdType = $GetTypeCmd.ExecuteScalar()
                        if ($IdType) {
                            $AlterColCmd.CommandText = "ALTER TABLE [$TargetTableName] ALTER COLUMN [ID] $IdType NOT NULL;"
                            try { [void]$AlterColCmd.ExecuteNonQuery() } catch { }
                        }
                        $IdxCmd = $SqlConn.CreateCommand(); $IdxCmd.CommandTimeout = $Timeout
                        # Constraint Name mit TargetTableName um Konflikte zu vermeiden
                        $IdxCmd.CommandText = "ALTER TABLE [$TargetTableName] ADD CONSTRAINT [PK_$TargetTableName] PRIMARY KEY CLUSTERED ([ID] ASC);"
                        [void]$IdxCmd.ExecuteNonQuery()
                        $Message += "(PK created) "
                    }
                }
                catch { $Message += "(PK Err) " }
            }

            # Merge Ausführen
            if ($Count -gt 0) {
                # Staging Index
                if ($HasID) {
                    try {
                        $StgIdxCmd = $SqlConn.CreateCommand(); $StgIdxCmd.CommandTimeout = $Timeout
                        $StgIdxCmd.CommandText = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('$StagingTableName') AND name = 'PK_$StagingTableName'"
                        if (($StgIdxCmd.ExecuteScalar()) -eq 0) {
                            $StgIdxCmd.CommandText = "ALTER TABLE [$StagingTableName] ADD CONSTRAINT [PK_$StagingTableName] PRIMARY KEY CLUSTERED ([ID] ASC);"
                            [void]$StgIdxCmd.ExecuteNonQuery()
                        }
                    }
                    catch { }
                }

                if ($SyncStrategy -eq "Snapshot") {
                    $FinalCmd = $SqlConn.CreateCommand(); $FinalCmd.CommandTimeout = $Timeout
                    # Snapshot auf $TargetTableName
                    $FinalCmd.CommandText = "TRUNCATE TABLE $TargetTableName; INSERT INTO $TargetTableName SELECT * FROM $StagingTableName;"
                    [void]$FinalCmd.ExecuteNonQuery()
                }
                else {
                    if ($ForceFull) {
                        $FinalCmd = $SqlConn.CreateCommand(); $FinalCmd.CommandTimeout = $Timeout
                        $FinalCmd.CommandText = "TRUNCATE TABLE $TargetTableName;" 
                        [void]$FinalCmd.ExecuteNonQuery()
                        
                        $MergeCmd = $SqlConn.CreateCommand(); $MergeCmd.CommandTimeout = $Timeout
                        $MergeCmd.CommandText = "EXEC sp_Merge_Generic @TargetTableName = '$TargetTableName', @StagingTableName = '$StagingTableName'"
                        [void]$MergeCmd.ExecuteNonQuery()
                        
                        $Message += "(Reset & Reload) "
                    }
                    else {
                        # Standard Inkrementell
                        $MergeCmd = $SqlConn.CreateCommand(); $MergeCmd.CommandTimeout = $Timeout
                        # NEU: Aufruf der SP mit expliziten Tabellennamen
                        $MergeCmd.CommandText = "EXEC sp_Merge_Generic @TargetTableName = '$TargetTableName', @StagingTableName = '$StagingTableName'"
                        [void]$MergeCmd.ExecuteNonQuery()
                    }
                }
            }

            # F: SANITY ($TargetTableName prüfen)
            if ($DoSanity) {
                $FbCountCmd = $FbConn.CreateCommand(); $FbCountCmd.CommandText = "SELECT COUNT(*) FROM ""$Tabelle"""
                $FbCount = [int64]$FbCountCmd.ExecuteScalar()
                
                $SqlCountCmd = $SqlConn.CreateCommand(); $SqlCountCmd.CommandTimeout = $Timeout
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
            if ($FbConn) { $FbConn.Close(); $FbConn.Dispose() }
            if ($SqlConn) { $SqlConn.Close(); $SqlConn.Dispose() }
        }
        finally {
            if ($Success) { if ($FbConn) { $FbConn.Close() }; if ($SqlConn) { $SqlConn.Close() } }
        }
    } 

    $TableStopwatch.Stop()
    Write-Host "[$Tabelle] Abschluss: $Status ($SanityStatus)" -ForegroundColor ($Status -eq "Erfolg" ? "Green" : "Red")

    [PSCustomObject]@{
        Tabelle     = $Tabelle
        Target      = $TargetTableName # Info spalte für den Bericht
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
$Results | Format-Table -AutoSize @{Label = "Quelle"; Expression = { $_.Tabelle } },
@{Label = "Ziel"; Expression = { $_.Target } },
@{Label = "Status"; Expression = { $_.Status } },
@{Label = "Sync"; Expression = { $_.RowsLoaded }; Align = "Right" },
@{Label = "FB"; Expression = { $_.FbTotal }; Align = "Right" },
@{Label = "SQL"; Expression = { $_.SqlTotal }; Align = "Right" },
@{Label = "Sanity"; Expression = { $_.SanityCheck } },
@{Label = "Time"; Expression = { $_.Duration.ToString("mm\:ss") } },
@{Label = "Info"; Expression = { $_.Info } }

# -----------------------------------------------------------------------------
# 7. LOG ROTATION (CLEANUP)
# -----------------------------------------------------------------------------

# Lese Einstellung aus Config (Standard: 30 Tage. 0 = Deaktiviert)

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