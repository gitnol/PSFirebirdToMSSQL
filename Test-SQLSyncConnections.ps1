<#
.SYNOPSIS
    Testet die Verbindungen zu Firebird und SQL Server.

.DESCRIPTION
    Diagnose-Tool für SQLSync:
    - Prüft Firebird-Verbindung und zeigt Server-Version
    - Prüft SQL Server-Verbindung und zeigt Server-Version
    - Zählt konfigurierte vs. verfügbare Tabellen
    - Nutzt SQLSyncCommon.psm1 für Credentials und Connections

.PARAMETER ConfigFile
    Optional. Pfad zur JSON-Konfigurationsdatei.
    Standard: "config.json" im Skript-Verzeichnis.

.EXAMPLE
    .\Test-SQLSyncConnections.ps1
    
.EXAMPLE
    .\Test-SQLSyncConnections.ps1 -ConfigFile "config_prod.json"

.NOTES
    Version: 2.0 (Refactored - Modul-basiert)

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile
)

# -----------------------------------------------------------------------------
# 1. MODUL LADEN
# -----------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
$ModulePath = Join-Path $ScriptDir "SQLSyncCommon.psm1"

if (-not (Test-Path $ModulePath)) {
    Write-Error "KRITISCH: SQLSyncCommon.psm1 nicht gefunden in $ScriptDir"
    exit 1
}
Import-Module $ModulePath -Force

# -----------------------------------------------------------------------------
# 2. KONFIGURATION LADEN
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

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Konfigurationsdatei nicht gefunden: $ConfigPath"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  SQLSync Connection Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Config: $ConfigPath`n" -ForegroundColor Gray

try {
    $Config = Get-SQLSyncConfig -ConfigPath $ConfigPath
}
catch {
    Write-Error "Fehler beim Laden der Konfiguration: $($_.Exception.Message)"
    exit 2
}

# -----------------------------------------------------------------------------
# 3. CREDENTIALS AUFLÖSEN
# -----------------------------------------------------------------------------
try {
    $FbCreds = Resolve-FirebirdCredentials -Config $Config.RawConfig
    $SqlCreds = Resolve-MSSQLCredentials -Config $Config.RawConfig
}
catch {
    Write-Error "Fehler bei Credentials: $($_.Exception.Message)"
    exit 3
}

# -----------------------------------------------------------------------------
# 4. TREIBER LADEN
# -----------------------------------------------------------------------------
try {
    $null = Initialize-FirebirdDriver -DllPath $Config.DllPath -ScriptDir $ScriptDir
}
catch {
    Write-Error "Fehler beim Laden des Firebird-Treibers: $($_.Exception.Message)"
    exit 4
}

# -----------------------------------------------------------------------------
# 5. FIREBIRD TEST
# -----------------------------------------------------------------------------
Write-Host "--- FIREBIRD ---" -ForegroundColor Yellow

$FbConnString = New-FirebirdConnectionString `
    -Server $Config.FBServer `
    -Database $Config.FBDatabase `
    -Username $FbCreds.Username `
    -Password $FbCreds.Password `
    -Port $Config.FBPort `
    -Charset $Config.FBCharset

$FbConn = $null
$FbSuccess = $false

try {
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbConnString)
    $FbConn.Open()
    
    # Server-Version (Literal-String für RDB$-Referenzen)
    $VersionCmd = $FbConn.CreateCommand()
    $VersionCmd.CommandText = 'SELECT rdb$get_context(''SYSTEM'', ''ENGINE_VERSION'') FROM rdb$database'
    $FbVersion = $VersionCmd.ExecuteScalar()
    
    # Tabellen zählen (Literal Here-String für RDB$-Referenzen)
    $CountCmd = $FbConn.CreateCommand()
    $CountCmd.CommandText = @'
        SELECT COUNT(*) FROM RDB$RELATIONS 
        WHERE RDB$SYSTEM_FLAG = 0 AND RDB$VIEW_BLR IS NULL
'@
    $FbTableCount = $CountCmd.ExecuteScalar()
    
    # Test-Query auf erste konfigurierte Tabelle
    $TestTable = $Config.Tables | Select-Object -First 1
    $TestCmd = $FbConn.CreateCommand()
    $TestCmd.CommandText = 'SELECT COUNT(*) FROM "{0}"' -f $TestTable
    $TestCount = $TestCmd.ExecuteScalar()
    
    Write-Host "  Server:      $($Config.FBServer):$($Config.FBPort)" -ForegroundColor White
    Write-Host "  Datenbank:   $($Config.FBDatabase)" -ForegroundColor White
    Write-Host "  Version:     Firebird $FbVersion" -ForegroundColor White
    Write-Host "  Tabellen:    $FbTableCount (gesamt)" -ForegroundColor White
    Write-Host "  Test-Query:  SELECT COUNT(*) FROM $TestTable = $TestCount" -ForegroundColor White
    Write-Host "  Status:      " -NoNewline
    Write-Host "OK" -ForegroundColor Green
    $FbSuccess = $true
}
catch {
    Write-Host "  Server:      $($Config.FBServer):$($Config.FBPort)" -ForegroundColor White
    Write-Host "  Status:      " -NoNewline
    Write-Host "FEHLER" -ForegroundColor Red
    Write-Host "  Details:     $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($FbConn) {
        try { $FbConn.Close() } catch { }
        try { $FbConn.Dispose() } catch { }
    }
}

# -----------------------------------------------------------------------------
# 6. SQL SERVER TEST
# -----------------------------------------------------------------------------
Write-Host "`n--- SQL SERVER ---" -ForegroundColor Yellow

$SqlConnString = New-MSSQLConnectionString `
    -Server $Config.MSSQLServer `
    -Database $Config.MSSQLDatabase `
    -Username $SqlCreds.Username `
    -Password $SqlCreds.Password `
    -IntegratedSecurity $SqlCreds.IntegratedSecurity

$SqlConn = $null
$SqlSuccess = $false

try {
    $SqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlConnString)
    $SqlConn.Open()
    
    # Server-Version
    $VersionCmd = $SqlConn.CreateCommand()
    $VersionCmd.CommandText = "SELECT @@VERSION"
    $SqlVersionFull = $VersionCmd.ExecuteScalar()
    $SqlVersion = ($SqlVersionFull -split "`n")[0]
    
    # Tabellen zählen
    $CountCmd = $SqlConn.CreateCommand()
    $CountCmd.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'"
    $SqlTableCount = $CountCmd.ExecuteScalar()
    
    # Sync-Tabellen zählen (mit Prefix/Suffix)
    $Prefix = $Config.MSSQLPrefix
    $Suffix = $Config.MSSQLSuffix
    $Pattern = "${Prefix}%${Suffix}"
    
    $SyncCountCmd = $SqlConn.CreateCommand()
    $SyncCountCmd.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_NAME LIKE @Pattern"
    $SyncCountCmd.Parameters.AddWithValue("@Pattern", $Pattern) | Out-Null
    $SyncTableCount = $SyncCountCmd.ExecuteScalar()
    
    # SP prüfen
    $SpCmd = $SqlConn.CreateCommand()
    $SpCmd.CommandText = "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_Merge_Generic]') AND type in (N'P', N'PC')"
    $SpExists = $SpCmd.ExecuteScalar() -gt 0
    
    $AuthMethod = if ($SqlCreds.IntegratedSecurity) { "Windows Auth" } else { "SQL Auth ($($SqlCreds.Username))" }
    
    Write-Host "  Server:      $($Config.MSSQLServer)" -ForegroundColor White
    Write-Host "  Datenbank:   $($Config.MSSQLDatabase)" -ForegroundColor White
    Write-Host "  Auth:        $AuthMethod" -ForegroundColor White
    Write-Host "  Version:     $SqlVersion" -ForegroundColor White
    Write-Host "  Tabellen:    $SqlTableCount (gesamt), $SyncTableCount (Sync: $Pattern)" -ForegroundColor White
    Write-Host "  SP Merge:    $(if ($SpExists) { 'Installiert' } else { 'FEHLT!' })" -ForegroundColor $(if ($SpExists) { 'White' } else { 'Red' })
    Write-Host "  Status:      " -NoNewline
    Write-Host "OK" -ForegroundColor Green
    $SqlSuccess = $true
}
catch {
    Write-Host "  Server:      $($Config.MSSQLServer)" -ForegroundColor White
    Write-Host "  Status:      " -NoNewline
    Write-Host "FEHLER" -ForegroundColor Red
    Write-Host "  Details:     $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($SqlConn) {
        try { $SqlConn.Close() } catch { }
        try { $SqlConn.Dispose() } catch { }
    }
}

# -----------------------------------------------------------------------------
# 7. ZUSAMMENFASSUNG
# -----------------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Zusammenfassung" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "  Konfigurierte Tabellen: $($Config.Tables.Count)" -ForegroundColor White

if ($FbSuccess -and $SqlSuccess) {
    Write-Host "`n  Ergebnis: " -NoNewline
    Write-Host "ALLE TESTS ERFOLGREICH" -ForegroundColor Green
    Write-Host "`n  Der Sync kann gestartet werden:`n  .\Sync_Firebird_MSSQL_AutoSchema.ps1`n" -ForegroundColor Gray
    exit 0
}
else {
    Write-Host "`n  Ergebnis: " -NoNewline
    Write-Host "FEHLER AUFGETRETEN" -ForegroundColor Red
    
    if (-not $FbSuccess) {
        Write-Host "  - Firebird-Verbindung prüfen" -ForegroundColor Yellow
    }
    if (-not $SqlSuccess) {
        Write-Host "  - SQL Server-Verbindung prüfen" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 1
}