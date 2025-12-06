<#
.SYNOPSIS
    Gemeinsames Modul für SQLSync - Firebird to MSSQL Synchronizer.

.DESCRIPTION
    Enthält wiederverwendbare Funktionen für:
    - Credential Manager Zugriff
    - Konfigurationsverwaltung
    - Connection String Building
    - Sichere Datenbankverbindungen mit automatischem Cleanup

.NOTES
    Version: 1.0.0
    Importieren mit: Import-Module (Join-Path $PSScriptRoot "SQLSyncCommon.psm1") -Force
#>

#region Credential Manager

<#
.SYNOPSIS
    Liest Credentials aus dem Windows Credential Manager.

.PARAMETER Target
    Der Name des Credential-Eintrags (z.B. "SQLSync_Firebird").

.OUTPUTS
    PSCustomObject mit Username und Password, oder $null wenn nicht gefunden.

.EXAMPLE
    $cred = Get-StoredCredential -Target "SQLSync_Firebird"
    if ($cred) { Write-Host "User: $($cred.Username)" }
#>
function Get-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target
    )
    
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
        return [PSCustomObject]@{ 
            Username = $Cred.UserName
            Password = $Password 
        }
    }
    finally { 
        [CredManager.Util]::CredFree($CredPtr) 
    }
}

#endregion

#region Configuration

<#
.SYNOPSIS
    Lädt und validiert die SQLSync Konfigurationsdatei.

.PARAMETER ConfigPath
    Pfad zur JSON-Konfigurationsdatei.

.PARAMETER SchemaPath
    Optional: Pfad zur JSON-Schema-Datei für Validierung.

.OUTPUTS
    Hashtable mit allen Konfigurationswerten inkl. aufgelöster Credentials.

.EXAMPLE
    $config = Get-SQLSyncConfig -ConfigPath ".\config.json"
#>
function Get-SQLSyncConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter()]
        [string]$SchemaPath
    )

    # Datei prüfen
    if (-not (Test-Path $ConfigPath)) {
        throw "Konfigurationsdatei nicht gefunden: $ConfigPath"
    }

    # JSON laden
    try {
        $JsonContent = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $Config = $JsonContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Fehler beim Parsen der Konfiguration: $($_.Exception.Message)"
    }

    # Optional: Schema-Validierung (PowerShell 6+)
    if ($SchemaPath -and (Test-Path $SchemaPath)) {
        try {
            $ValidationResult = Test-Json -Json $JsonContent -SchemaFile $SchemaPath -ErrorAction Stop
            if (-not $ValidationResult) {
                throw "Konfiguration entspricht nicht dem Schema."
            }
        }
        catch {
            Write-Warning "Schema-Validierung fehlgeschlagen: $($_.Exception.Message)"
        }
    }

    # Defaults anwenden und Hashtable bauen
    $Result = @{
        # General Settings
        GlobalTimeout         = Get-ConfigValue $Config.General "GlobalTimeout" 7200
        RecreateStagingTable  = Get-ConfigValue $Config.General "RecreateStagingTable" $false
        ForceFullSync         = Get-ConfigValue $Config.General "ForceFullSync" $false
        RunSanityCheck        = Get-ConfigValue $Config.General "RunSanityCheck" $true
        MaxRetries            = Get-ConfigValue $Config.General "MaxRetries" 3
        RetryDelaySeconds     = Get-ConfigValue $Config.General "RetryDelaySeconds" 10
        DeleteLogOlderThanDays = Get-ConfigValue $Config.General "DeleteLogOlderThanDays" 30

        # Firebird Settings
        FBServer   = $Config.Firebird.Server
        FBDatabase = $Config.Firebird.Database
        FBPort     = Get-ConfigValue $Config.Firebird "Port" 3050
        FBCharset  = Get-ConfigValue $Config.Firebird "Charset" "UTF8"
        DllPath    = $Config.Firebird.DllPath

        # MSSQL Settings
        MSSQLServer      = $Config.MSSQL.Server
        MSSQLDatabase    = $Config.MSSQL.Database
        MSSQLIntSec      = Get-ConfigValue $Config.MSSQL "Integrated Security" $false
        MSSQLPrefix      = Get-ConfigValue $Config.MSSQL "Prefix" ""
        MSSQLSuffix      = Get-ConfigValue $Config.MSSQL "Suffix" ""

        # Tables
        Tables = @($Config.Tables)

        # Raw Config für Zugriff auf weitere Properties
        RawConfig = $Config
    }

    # Validierungen
    if ($Result.GlobalTimeout -le 0) {
        throw "GlobalTimeout muss größer als 0 sein."
    }
    if (-not $Result.Tables -or $Result.Tables.Count -eq 0) {
        throw "Keine Tabellen in der Konfiguration definiert."
    }

    return $Result
}

<#
.SYNOPSIS
    Hilfsfunktion zum sicheren Auslesen von Config-Werten mit Default.
#>
function Get-ConfigValue {
    param(
        [object]$ConfigSection,
        [string]$PropertyName,
        [object]$DefaultValue
    )
    
    if ($null -eq $ConfigSection) { return $DefaultValue }
    
    if ($ConfigSection.PSObject.Properties.Match($PropertyName).Count -gt 0) {
        $Value = $ConfigSection.$PropertyName
        if ($null -ne $Value) { return $Value }
    }
    
    return $DefaultValue
}

#endregion

#region Credentials Resolution

<#
.SYNOPSIS
    Löst Firebird-Credentials auf (Credential Manager -> Config Fallback).

.PARAMETER Config
    Die geladene Konfiguration (RawConfig).

.OUTPUTS
    Hashtable mit Username und Password.
#>
function Resolve-FirebirdCredentials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    # 1. Versuch: Credential Manager
    $Cred = Get-StoredCredential -Target "SQLSync_Firebird"
    if ($Cred) {
        Write-Host "[Credentials] Firebird: Credential Manager" -ForegroundColor Green
        return @{
            Username = $Cred.Username
            Password = $Cred.Password
            Source   = "CredentialManager"
        }
    }

    # 2. Fallback: config.json
    if ($Config.Firebird.Password) {
        $Username = if ($Config.Firebird.User) { $Config.Firebird.User } else { "SYSDBA" }
        Write-Host "[Credentials] Firebird: config.json (WARNUNG: unsicher!)" -ForegroundColor Yellow
        return @{
            Username = $Username
            Password = $Config.Firebird.Password
            Source   = "ConfigFile"
        }
    }

    throw "Keine Firebird Credentials gefunden! Führe Setup_Credentials.ps1 aus."
}

<#
.SYNOPSIS
    Löst MSSQL-Credentials auf (Windows Auth -> Credential Manager -> Config Fallback).

.PARAMETER Config
    Die geladene Konfiguration (RawConfig).

.OUTPUTS
    Hashtable mit Username, Password und IntegratedSecurity Flag.
#>
function Resolve-MSSQLCredentials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    # Windows Authentication?
    $IntSec = Get-ConfigValue $Config.MSSQL "Integrated Security" $false
    if ($IntSec) {
        Write-Host "[Credentials] SQL Server: Windows Authentication" -ForegroundColor Green
        return @{
            Username           = $null
            Password           = $null
            IntegratedSecurity = $true
            Source             = "WindowsAuth"
        }
    }

    # 1. Versuch: Credential Manager
    $Cred = Get-StoredCredential -Target "SQLSync_MSSQL"
    if ($Cred) {
        Write-Host "[Credentials] SQL Server: Credential Manager" -ForegroundColor Green
        return @{
            Username           = $Cred.Username
            Password           = $Cred.Password
            IntegratedSecurity = $false
            Source             = "CredentialManager"
        }
    }

    # 2. Fallback: config.json
    if ($Config.MSSQL.Password) {
        Write-Host "[Credentials] SQL Server: config.json (WARNUNG: unsicher!)" -ForegroundColor Yellow
        return @{
            Username           = $Config.MSSQL.Username
            Password           = $Config.MSSQL.Password
            IntegratedSecurity = $false
            Source             = "ConfigFile"
        }
    }

    throw "Keine SQL Server Credentials gefunden! Führe Setup_Credentials.ps1 aus oder aktiviere 'Integrated Security'."
}

#endregion

#region Connection Strings

<#
.SYNOPSIS
    Erstellt einen Firebird Connection String.
#>
function New-FirebirdConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][SecureString]$Password,
        [int]$Port = 3050,
        [string]$Charset = "UTF8"
    )

    $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($Password))
    
    return "User=$Username;Password=$PlainPassword;Database=$Database;DataSource=$Server;Port=$Port;Dialect=3;Charset=$Charset;"
}

<#
.SYNOPSIS
    Erstellt einen MSSQL Connection String.
#>
function New-MSSQLConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Database,
        [string]$Username,
        [SecureString]$Password,
        [bool]$IntegratedSecurity = $false
    )

    if ($IntegratedSecurity) {
        return "Server=$Server;Database=$Database;Integrated Security=True;"
    }
    else {
        $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($Password))
        return "Server=$Server;Database=$Database;User Id=$Username;Password=$PlainPassword;"
    }
}

#endregion

#region Firebird Driver

<#
.SYNOPSIS
    Lädt den Firebird .NET Treiber.

.PARAMETER DllPath
    Konfigurierter Pfad zur DLL.

.PARAMETER ScriptDir
    Skript-Verzeichnis für relative Pfade.

.OUTPUTS
    Der aufgelöste Pfad zur DLL.
#>
function Initialize-FirebirdDriver {
    [CmdletBinding()]
    param(
        [string]$DllPath,
        [string]$ScriptDir
    )

    # Paket installieren falls nötig
    if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue)) {
        Write-Host "Installiere Firebird .NET Provider..." -ForegroundColor Yellow
        Install-Package FirebirdSql.Data.FirebirdClient -Force -Confirm:$false | Out-Null
    }

    # DLL-Pfad auflösen
    $ResolvedPath = $DllPath

    if (-not (Test-Path $ResolvedPath)) {
        # Relativer Pfad?
        if ($ScriptDir) {
            $PotentialPath = Join-Path $ScriptDir $DllPath
            if (Test-Path $PotentialPath) {
                $ResolvedPath = $PotentialPath
            }
        }
    }

    if (-not (Test-Path $ResolvedPath)) {
        # NuGet Packages durchsuchen
        $SearchPaths = @(
            "C:\Program Files\PackageManagement\NuGet\Packages",
            "$env:USERPROFILE\.nuget\packages"
        )
        
        foreach ($SearchPath in $SearchPaths) {
            if (Test-Path $SearchPath) {
                $Found = Get-ChildItem -Path $SearchPath -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse -ErrorAction SilentlyContinue | 
                         Select-Object -First 1
                if ($Found) {
                    $ResolvedPath = $Found.FullName
                    break
                }
            }
        }
    }

    if (-not $ResolvedPath -or -not (Test-Path $ResolvedPath)) {
        throw "Firebird Treiber DLL nicht gefunden. Bitte DllPath in config.json prüfen."
    }

    # Typ laden
    Add-Type -Path $ResolvedPath
    Write-Host "[Driver] Firebird .NET Provider geladen: $ResolvedPath" -ForegroundColor DarkGray

    return $ResolvedPath
}

#endregion

#region Safe Database Operations

<#
.SYNOPSIS
    Führt eine Aktion mit einer Firebird-Verbindung aus und garantiert Cleanup.

.DESCRIPTION
    Öffnet eine Verbindung, führt den ScriptBlock aus und schließt die Verbindung
    im finally-Block - auch bei Fehlern.

.PARAMETER ConnectionString
    Der Firebird Connection String.

.PARAMETER Action
    Der auszuführende ScriptBlock. Erhält $Connection als Parameter.

.EXAMPLE
    Invoke-WithFirebirdConnection -ConnectionString $cs -Action {
        param($conn)
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT * FROM MYTABLE"
        $cmd.ExecuteReader()
    }
#>
function Invoke-WithFirebirdConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionString,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $Connection = $null
    try {
        $Connection = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($ConnectionString)
        $Connection.Open()
        
        # ScriptBlock ausführen mit Connection als Parameter
        & $Action $Connection
    }
    finally {
        if ($Connection) {
            try { $Connection.Close() } catch { }
            try { $Connection.Dispose() } catch { }
        }
    }
}

<#
.SYNOPSIS
    Führt eine Aktion mit einer MSSQL-Verbindung aus und garantiert Cleanup.

.PARAMETER ConnectionString
    Der MSSQL Connection String.

.PARAMETER Action
    Der auszuführende ScriptBlock. Erhält $Connection als Parameter.
#>
function Invoke-WithMSSQLConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionString,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $Connection = $null
    try {
        $Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $Connection.Open()
        
        & $Action $Connection
    }
    finally {
        if ($Connection) {
            try { $Connection.Close() } catch { }
            try { $Connection.Dispose() } catch { }
        }
    }
}

<#
.SYNOPSIS
    Schließt und disposed eine Datenbankverbindung sicher.

.DESCRIPTION
    Kann für beliebige Connection-Objekte verwendet werden.
    Fängt alle Exceptions ab um Folgefehler zu vermeiden.

.PARAMETER Connection
    Das zu schließende Connection-Objekt.
#>
function Close-DatabaseConnection {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Connection
    )

    if ($null -eq $Connection) { return }

    try { $Connection.Close() } catch { }
    try { $Connection.Dispose() } catch { }
}

#endregion

#region Logging Helpers

<#
.SYNOPSIS
    Schreibt eine formatierte Status-Nachricht.
#>
function Write-SyncStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TableName,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $Color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
        default   { "Gray" }
    }

    Write-Host "[$TableName] $Message" -ForegroundColor $Color
}

#endregion

#region Type Mapping

<#
.SYNOPSIS
    Mappt einen .NET-Datentyp auf den entsprechenden SQL Server Datentyp.

.PARAMETER DotNetTypeName
    Der Name des .NET-Typs (z.B. "Int32", "String").

.PARAMETER Size
    Die Spaltengröße (relevant für String-Typen).

.OUTPUTS
    Der SQL Server Datentyp als String.
#>
function ConvertTo-SqlServerType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DotNetTypeName,

        [int]$Size = 0
    )

    switch ($DotNetTypeName) {
        "Int16"    { return "SMALLINT" }
        "Int32"    { return "INT" }
        "Int64"    { return "BIGINT" }
        "String"   { 
            if ($Size -gt 0 -and $Size -le 4000) { 
                return "NVARCHAR($Size)" 
            } 
            else { 
                return "NVARCHAR(MAX)" 
            } 
        }
        "DateTime" { return "DATETIME2" }
        "TimeSpan" { return "TIME" }
        "Decimal"  { return "DECIMAL(18,4)" }
        "Double"   { return "FLOAT" }
        "Single"   { return "REAL" }
        "Byte[]"   { return "VARBINARY(MAX)" }
        "Boolean"  { return "BIT" }
        "Guid"     { return "UNIQUEIDENTIFIER" }
        default    { return "NVARCHAR(MAX)" }
    }
}

#endregion

# Exportiere alle Public Functions
Export-ModuleMember -Function @(
    # Credentials
    'Get-StoredCredential'
    'Resolve-FirebirdCredentials'
    'Resolve-MSSQLCredentials'
    
    # Configuration
    'Get-SQLSyncConfig'
    'Get-ConfigValue'
    
    # Connection Strings
    'New-FirebirdConnectionString'
    'New-MSSQLConnectionString'
    
    # Driver
    'Initialize-FirebirdDriver'
    
    # Safe Operations
    'Invoke-WithFirebirdConnection'
    'Invoke-WithMSSQLConnection'
    'Close-DatabaseConnection'
    
    # Helpers
    'Write-SyncStatus'
    'ConvertTo-SqlServerType'
)
