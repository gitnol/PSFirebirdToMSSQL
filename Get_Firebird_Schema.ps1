<#
.SYNOPSIS
    Analysiert die Datentypen einer Firebird-Tabelle im Detail.

.DESCRIPTION
    Verbindet sich mit einer angegebenen Firebird-Datenbankdatei und gibt für eine
    spezifische Tabelle die exakten .NET Datentypen zurück, wie sie der Treiber sieht.
    Dies ist hilfreich zum Debuggen von Mapping-Problemen.

.PARAMETER TableName
    Der Name der zu analysierenden Tabelle (z.B. BARTIKEL).

.PARAMETER ConfigFile
    Optional. Konfigurationsdatei (Default: config.json im Skriptordner); relativ zum Skriptordner oder absolut.

.EXAMPLE
    .\Get_Firebird_Schema.ps1 -TableName "BAUF"

.EXAMPLE
    .\Get_Firebird_Schema.ps1 -TableName "BAUF" -ConfigFile "config_weekly_full.json"

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL

#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$TableName,

    [Parameter(Mandatory = $false)]
    [string]$ConfigFile
)

# -----------------------------------------------------------------------------
# 0. MODUL IMPORTIEREN
# -----------------------------------------------------------------------------
$ModulePath = Join-Path $PSScriptRoot "SQLSyncCommon.psm1"
if (-not (Test-Path $ModulePath)) {
    Write-Error "KRITISCH: SQLSyncCommon.psm1 nicht gefunden in $PSScriptRoot"
    exit 1
}
Import-Module $ModulePath -Force

# -----------------------------------------------------------------------------
# 1. KONFIGURATION LADEN
# -----------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
$ConfigPath = Resolve-SQLSyncConfigPath -ConfigFile $ConfigFile -ScriptDir $ScriptDir

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Konfigurationsdatei nicht gefunden: $ConfigPath"
    exit 1
}

try {
    $Config = Get-SQLSyncConfig -ConfigPath $ConfigPath -SchemaPath (Join-Path $ScriptDir "config.schema.json")
}
catch {
    Write-Error "Fehler beim Laden der Konfiguration: $($_.Exception.Message)"
    exit 2
}

# -----------------------------------------------------------------------------
# 2. CREDENTIALS AUFLÖSEN
# -----------------------------------------------------------------------------
try {
    $FbCreds = Resolve-FirebirdCredentials -Config $Config.RawConfig
}
catch {
    Write-Error $_.Exception.Message
    exit 5
}

# -----------------------------------------------------------------------------
# 3. TREIBER LADEN
# -----------------------------------------------------------------------------
try {
    $ResolvedDllPath = Initialize-FirebirdDriver -DllPath $Config.DllPath -ScriptDir $ScriptDir -ExpectedSha256 $Config.DllSha256
}
catch {
    Write-Error $_.Exception.Message
    exit 3
}

# -----------------------------------------------------------------------------
# 4. ANALYSE STARTEN
# -----------------------------------------------------------------------------
$ConnectionString = New-FirebirdConnectionString `
    -Server $Config.FBServer `
    -Database $Config.FBDatabase `
    -Username $FbCreds.Username `
    -Password $FbCreds.Password `
    -Port $Config.FBPort `
    -Charset $Config.FBCharset

Write-Host "Verbinde zu: $($Config.FBServer) : $($Config.FBDatabase)" -ForegroundColor Cyan
Write-Host "Analysiere Tabelle: $TableName" -ForegroundColor Yellow

$FbConn = $null
try {
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($ConnectionString)
    $FbConn.Open()

    $FbCmdSchema = $FbConn.CreateCommand()
    $FbCmdSchema.CommandText = "SELECT FIRST 1 * FROM ""$TableName"""
    
    # ExecuteReader mit SchemaOnly lädt KEINE Daten, nur Metadaten (sehr schnell)
    $ReaderSchema = $FbCmdSchema.ExecuteReader([System.Data.CommandBehavior]::SchemaOnly)
    $SchemaTable = $ReaderSchema.GetSchemaTable()
    $ReaderSchema.Close()

    # -------------------------------------------------------------------------
    # AUSGABE AUFBEREITEN
    # -------------------------------------------------------------------------
    $Result = @()

    foreach ($Row in $SchemaTable) {
        $ColName = $Row.ColumnName
        $DotNetType = $Row.DataType
        $Size = $Row.ColumnSize
        $AllowDBNull = $Row.AllowDBNull
        
        # SQL Server Typ-Vorschlag
        $ProposedSqlType = ConvertTo-SqlServerType -DotNetTypeName $DotNetType.Name -Size $Size `
            -Precision $Row.NumericPrecision -Scale $Row.NumericScale

        $Result += [PSCustomObject]@{
            Column          = $ColName
            ".NET Type"     = $DotNetType.Name
            "Full Type"     = $DotNetType.FullName
            "Size"          = $Size
            "Precision"     = $Row.NumericPrecision
            "Scale"         = $Row.NumericScale
            "Nullable"      = $AllowDBNull
            "Vorschlag SQL" = $ProposedSqlType
        }
    }

    # Ausgabe als formatierte Tabelle
    $Result | Format-Table -AutoSize
    
    Write-Host "Analyse abgeschlossen." -ForegroundColor Green
}
catch {
    Write-Error "Fehler bei der Analyse: $($_.Exception.Message)"
    exit 4
}
finally {
    # WICHTIG: Connection immer aufräumen
    if ($FbConn) {
        try { $FbConn.Close() } catch { }
        try { $FbConn.Dispose() } catch { }
    }
}