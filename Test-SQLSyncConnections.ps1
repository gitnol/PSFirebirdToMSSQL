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

.PARAMETER PreDeploy
    Zusätzliche, rein lesende Prüfungen vor einem Deployment (keine DDL/DML):
    - alle config*.json im Skriptordner gegen Schema und Namensregeln
    - Treiber-DLL gegen die erlaubten SHA-256
    - Firebird-Serverversion gegen bekannte Advisories, Anmeldung als SYSDBA
    - Altbestand: Zielspalten, deren DECIMAL-Typ Werte der Firebird-Quelle kürzt

.EXAMPLE
    .\Test-SQLSyncConnections.ps1
    
.EXAMPLE
    .\Test-SQLSyncConnections.ps1 -ConfigFile "config_prod.json"

.EXAMPLE
    .\Test-SQLSyncConnections.ps1 -ConfigFile "config_prod.json" -PreDeploy

.NOTES
    Version: 2.1 (-PreDeploy)
    Exit-Codes: 0 = OK (mit -PreDeploy: keine FEHLER, WARNUNGEN möglich), 1 = Verbindungstest
    fehlgeschlagen bzw. Modul/Konfig fehlt, 2 = Konfiguration, 3 = Credentials, 4 = Treiber,
    6 = -PreDeploy hat mindestens einen FEHLER gefunden.

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,

    [switch]$PreDeploy
)

# Befunde der Vor-Deployment-Prüfung (nur mit -PreDeploy)
$Findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding([string]$Check, [string]$Status, [string]$Detail) {
    $Findings.Add([PSCustomObject]@{ Pruefung = $Check; Status = $Status; Detail = $Detail })
}
function Write-Findings {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Vor-Deployment-Prüfung (-PreDeploy, nur lesend)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    foreach ($f in $Findings) {
        $Color = switch ($f.Status) { "OK" { "Green" } "WARNUNG" { "Yellow" } default { "Red" } }
        Write-Host ("  {0,-8} {1,-26} {2}" -f $f.Status, $f.Pruefung, $f.Detail) -ForegroundColor $Color
    }
}

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
$ConfigPath = Resolve-SQLSyncConfigPath -ConfigFile $ConfigFile -ScriptDir $ScriptDir

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Konfigurationsdatei nicht gefunden: $ConfigPath"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  SQLSync Connection Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Config: $ConfigPath`n" -ForegroundColor Gray

try {
    $Config = Get-SQLSyncConfig -ConfigPath $ConfigPath -SchemaPath (Join-Path $ScriptDir "config.schema.json")
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
# 3b. VOR-DEPLOYMENT: KONFIGS + TREIBER (nur -PreDeploy)
# -----------------------------------------------------------------------------
if ($PreDeploy) {
    $SchemaFile = Join-Path $ScriptDir "config.schema.json"
    $ConfigFiles = Get-ChildItem -Path $ScriptDir -Filter "config*.json" -File |
        Where-Object { $_.Name -notin @("config.schema.json", "config.sample.json") }
    foreach ($f in $ConfigFiles) {
        try {
            $null = Get-SQLSyncConfig -ConfigPath $f.FullName -SchemaPath $SchemaFile -WarningAction SilentlyContinue
            Add-Finding "Konfig $($f.Name)" "OK" "Schema und Namensregeln erfüllt"
        }
        catch { Add-Finding "Konfig $($f.Name)" "FEHLER" $_.Exception.Message }
    }
    if (-not (Test-Path $SchemaFile)) { Add-Finding "Schema-Datei" "WARNUNG" "config.schema.json fehlt – Konfigs werden beim Sync nicht gegen das Schema geprüft" }

    $Driver = Test-FirebirdDriverIntegrity -DllPath $Config.DllPath -ScriptDir $ScriptDir -ExpectedSha256 $Config.DllSha256
    $DriverStatus = if ($Driver.Status -eq "FEHLT") { "WARNUNG" } else { $Driver.Status }
    Add-Finding "Treiber-DLL" $DriverStatus "$($Driver.Message)$(if ($Driver.Path) { ": $($Driver.Path)" })"
    if ($Driver.Status -eq "FEHLER") {
        # Initialize-FirebirdDriver würde die DLL ohnehin ablehnen – Befunde zeigen und abbrechen
        Write-Findings
        exit 6
    }
}

# -----------------------------------------------------------------------------
# 4. TREIBER LADEN
# -----------------------------------------------------------------------------
try {
    $null = Initialize-FirebirdDriver -DllPath $Config.DllPath -ScriptDir $ScriptDir -ExpectedSha256 $Config.DllSha256
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
    
    # Test-Query auf erste konfigurierte Tabelle (nur wenn vorhanden)
    if ($Config.Tables.Count -gt 0) {
        $TestTable = $Config.Tables | Select-Object -First 1
        $TestCmd = $FbConn.CreateCommand()
        $TestCmd.CommandText = 'SELECT COUNT(*) FROM "{0}"' -f $TestTable
        $TestCount = $TestCmd.ExecuteScalar()
    }
    else {
        throw "  Test-Query:  (Übersprungen - Keine Tabellen konfiguriert)"
    }
    
    Write-Host "  Server:      $($Config.FBServer):$($Config.FBPort)" -ForegroundColor White
    Write-Host "  Datenbank:   $($Config.FBDatabase)" -ForegroundColor White
    Write-Host "  Version:     Firebird $FbVersion" -ForegroundColor White
    Write-Host "  Tabellen:    $FbTableCount (gesamt)" -ForegroundColor White
    Write-Host "  Test-Query:  SELECT COUNT(*) FROM $TestTable = $TestCount" -ForegroundColor White
    Write-Host "  Status:      " -NoNewline
    Write-Host "OK" -ForegroundColor Green
    $FbSuccess = $true

    if ($PreDeploy) {
        # Serverversion gegen bekannte Advisories
        $Advisories = @(Get-FirebirdServerAdvisory -EngineVersion "$FbVersion")
        if ($Advisories.Count -eq 0) { Add-Finding "Firebird-Version" "OK" "Firebird $FbVersion – keine bekannte Server-Advisory" }
        foreach ($a in $Advisories) {
            Add-Finding "Firebird-Version" "WARNUNG" "Firebird ${FbVersion}: $($a.Id) (CVSS $($a.Cvss), $($a.Summary)) – behoben ab $($a.FixedIn)"
        }
        # Anmeldung als SYSDBA (hat CREATE FUNCTION, siehe CVE-2026-40342)
        if ("$($FbCreds.Username)" -ieq "SYSDBA") { Add-Finding "Firebird-Konto" "WARNUNG" "Sync meldet sich als SYSDBA an – reines Lesekonto empfohlen (docs/operations/SETUP.md)" }
        else { Add-Finding "Firebird-Konto" "OK" "kein SYSDBA" }

        # Dezimalspalten der konfigurierten Tabellen (Precision/Scale aus den Metadaten)
        $NumCmd = $FbConn.CreateCommand()
        $Names = @(); $i = 0
        foreach ($Table in $Config.Tables) { $Names += "@t$i"; [void]$NumCmd.Parameters.Add("@t$i", "$Table"); $i++ }
        $NumCmd.CommandText = ('SELECT TRIM(rf.RDB$RELATION_NAME), TRIM(rf.RDB$FIELD_NAME), f.RDB$FIELD_PRECISION, -f.RDB$FIELD_SCALE ' +
            'FROM RDB$RELATION_FIELDS rf JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE ' +
            'WHERE f.RDB$FIELD_SCALE < 0 AND TRIM(rf.RDB$RELATION_NAME) IN ({0})') -f ($Names -join ", ")
        $SourceDecimals = @()
        $Reader = $NumCmd.ExecuteReader()
        while ($Reader.Read()) {
            $Prec = if ($Reader.IsDBNull(2)) { 18 } else { [int]$Reader.GetValue(2) }
            $SourceDecimals += [PSCustomObject]@{ Table = $Reader.GetString(0); Column = $Reader.GetString(1); Precision = $Prec; Scale = [int]$Reader.GetValue(3) }
        }
        $Reader.Close()
    }
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

    if ($PreDeploy) {
        # Dezimalspalten der Zieltabellen (nur lesend)
        $DecCmd = $SqlConn.CreateCommand()
        $Names = @(); $i = 0
        foreach ($Table in $Config.Tables) { $Names += "@t$i"; [void]$DecCmd.Parameters.AddWithValue("@t$i", "$Prefix$Table$Suffix"); $i++ }
        $DecCmd.CommandText = "SELECT TABLE_NAME, COLUMN_NAME, NUMERIC_PRECISION, NUMERIC_SCALE FROM INFORMATION_SCHEMA.COLUMNS WHERE DATA_TYPE IN ('decimal', 'numeric') AND TABLE_NAME IN ($($Names -join ', '))"
        $TargetDecimals = @()
        $Reader = $DecCmd.ExecuteReader()
        while ($Reader.Read()) {
            $TargetDecimals += [PSCustomObject]@{ Table = $Reader.GetString(0); Column = $Reader.GetString(1); Precision = [int]$Reader.GetValue(2); Scale = [int]$Reader.GetValue(3) }
        }
        $Reader.Close()
    }
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

    if ($PreDeploy) {
        $Truncations = @(Find-SQLSyncDecimalTruncation -SourceColumns $SourceDecimals -TargetColumns $TargetDecimals -Prefix $Config.MSSQLPrefix -Suffix $Config.MSSQLSuffix)
        if ($Truncations.Count -eq 0) { Add-Finding "Altbestand DECIMAL" "OK" "keine Zielspalte kürzt Nachkommastellen ($(@($SourceDecimals).Count) Dezimalspalten geprüft)" }
        foreach ($tr in $Truncations) {
            Add-Finding "Altbestand DECIMAL" "WARNUNG" "$($tr.Target).$($tr.Column): Ziel $($tr.TargetType) < Quelle $($tr.Source) – Korrektur siehe docs/operations/RUNBOOK.md"
        }
        Write-Findings
        if ($Findings | Where-Object Status -eq "FEHLER") {
            Write-Host "`n  Vor-Deployment-Prüfung: FEHLER gefunden (Exit 6)`n" -ForegroundColor Red
            exit 6
        }
    }
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
