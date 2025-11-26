<#
.SYNOPSIS
    Analysiert die Datentypen einer Firebird-Tabelle im Detail.

.DESCRIPTION
    Verbindet sich mit einer angegebenen Firebird-Datenbankdatei und gibt für eine
    spezifische Tabelle die exakten .NET Datentypen zurück, wie sie der Treiber sieht.
    Dies ist hilfreich zum Debuggen von Mapping-Problemen.

.PARAMETER DatabasePath
    Der vollständige Pfad zur .FDB Datei auf dem Server (z.B. D:\DB\Test.fdb).

.PARAMETER TableName
    Der Name der zu analysierenden Tabelle (z.B. BARTIKEL).

.EXAMPLE
    .\Get_Firebird_Schema.ps1 -DatabasePath "D:\DB\LA01_ECHT.FDB" -TableName "BAUF"
#>

param(
    # [Parameter(Mandatory = $true)]
    # [string]$DatabasePath,

    [Parameter(Mandatory = $true)]
    [string]$TableName
)

# -----------------------------------------------------------------------------
# 1. KONFIGURATION LADEN (für Credentials & DLL Pfad)
# -----------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "config.json"

if (-not (Test-Path $ConfigPath)) { Write-Error "config.json fehlt!"; exit }
$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json


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


# -----------------------------------------------------------------------------
# 2. TREIBER LADEN
# -----------------------------------------------------------------------------
if (-not (Test-Path $DllPath)) {
    # Fallback Suche
    $DllPath = (Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse | Select-Object -First 1).FullName
}
if (-not $DllPath) { Write-Error "Treiber nicht gefunden."; exit }
Add-Type -Path $DllPath

# -----------------------------------------------------------------------------
# 3. ANALYSE STARTEN
# -----------------------------------------------------------------------------

# Connection String mit ÜBERSCHRIEBENEM Pfad
$ConnectionString = "User=$($FBuser);Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"

try {
    Write-Host "Verbinde zu: $FBservername : $DatabasePath" -ForegroundColor Cyan
    
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($ConnectionString)
    $FbConn.Open()

    Write-Host "Analysiere Tabelle: $TableName" -ForegroundColor Yellow

    # Der von dir gewünschte Schema-Abruf
    $FbCmdSchema = $FbConn.CreateCommand()
    $FbCmdSchema.CommandText = "SELECT FIRST 1 * FROM ""$TableName"""
    
    # ExecuteReader mit SchemaOnly lädt KEINE Daten, nur Metadaten (sehr schnell)
    $ReaderSchema = $FbCmdSchema.ExecuteReader([System.Data.CommandBehavior]::SchemaOnly)
    $SchemaTable = $ReaderSchema.GetSchemaTable()
    $ReaderSchema.Close()
    $FbConn.Close()

    # -------------------------------------------------------------------------
    # 4. AUSGABE AUFBEREITEN
    # -------------------------------------------------------------------------
    $Result = @()

    foreach ($Row in $SchemaTable) {
        # Hier greifen wir die Rohdaten ab
        $ColName = $Row.ColumnName
        $DotNetType = $Row.DataType      # Das ist der "System.Type" (z.B. System.Int32)
        $Size = $Row.ColumnSize
        # $IsKey entfernt, da ungenutzt und Warnung verursachend
        $AllowDBNull = $Row.AllowDBNull
        
        # Deine Mapping-Logik zur Vorschau (nur zur Info)
        $ProposedSqlType = switch ($DotNetType.Name) {
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
            Default { "NVARCHAR(MAX) [Unknown]" }
        }

        $Result += [PSCustomObject]@{
            Column          = $ColName
            ".NET Type"     = $DotNetType.Name        # z.B. Int32, TimeSpan
            "Full Type"     = $DotNetType.FullName    # z.B. System.TimeSpan
            "Size"          = $Size
            "Nullable"      = $AllowDBNull
            "Vorschlag SQL" = $ProposedSqlType
        }
    }

    # Ausgabe als formatierte Tabelle
    $Result | Format-Table -AutoSize

}
catch {
    Write-Error "Fehler bei der Analyse: $($_.Exception.Message)"
}