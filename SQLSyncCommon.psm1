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

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL

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

    # Schema-Validierung (Fail-Fast). -Schema (String) statt -SchemaFile: in allen PowerShell-7-Versionen vorhanden.
    if ($SchemaPath) {
        if (-not (Test-Path $SchemaPath -PathType Leaf)) {
            # Fehlende Schema-Datei bricht bestehende Installationen nicht, ist aber sichtbar
            Write-Warning "Schema-Datei nicht gefunden, Konfiguration wird nicht gegen das Schema geprüft: $SchemaPath"
        }
        else {
            $SchemaErrors = $null
            $IsValid = Test-Json -Json $JsonContent -Schema (Get-Content -Path $SchemaPath -Raw) `
                -ErrorAction SilentlyContinue -ErrorVariable SchemaErrors
            if (-not $IsValid) {
                $Details = @($SchemaErrors | ForEach-Object { $_.Exception.Message }) -join "; "
                throw "Konfiguration verletzt das Schema ($([System.IO.Path]::GetFileName($SchemaPath))): $Details"
            }
        }
    }

    # Defaults anwenden und Hashtable bauen
    $Result = @{
        # General Settings
        GlobalTimeout           = Get-ConfigValue $Config.General "GlobalTimeout" 7200
        RecreateStagingTable    = Get-ConfigValue $Config.General "RecreateStagingTable" $false
        ForceFullSync           = Get-ConfigValue $Config.General "ForceFullSync" $false
        RecreateStoredProcedure = Get-ConfigValue $Config.General "RecreateStoredProcedure" $false
        NumberOfThreads         = Get-ConfigValue $Config.General "NumberOfThreads" 4
        RunSanityCheck          = Get-ConfigValue $Config.General "RunSanityCheck" $true
        MaxRetries              = Get-ConfigValue $Config.General "MaxRetries" 3
        RetryDelaySeconds       = Get-ConfigValue $Config.General "RetryDelaySeconds" 10
        DeleteLogOlderThanDays  = Get-ConfigValue $Config.General "DeleteLogOlderThanDays" 30
        CleanupOrphans          = Get-ConfigValue $Config.General "CleanupOrphans" $false
        OrphanCleanupBatchSize  = Get-ConfigValue $Config.General "OrphanCleanupBatchSize" 50000
        FailOnSanityError       = [bool](Get-ConfigValue $Config.General "FailOnSanityError" $true)
        IncrementalOverlapMinutes = Get-ConfigValue $Config.General "IncrementalOverlapMinutes" 10

        # Column Configuration (NEU in v2.10)
        IdColumn                = Get-ConfigValue $Config.General "IdColumn" "ID"
        TimestampColumns        = @(Get-ConfigValue $Config.General "TimestampColumns" @("GESPEICHERT"))

        # Firebird Settings
        FBServer                = $Config.Firebird.Server
        FBDatabase              = $Config.Firebird.Database
        FBPort                  = Get-ConfigValue $Config.Firebird "Port" 3050
        FBCharset               = Get-ConfigValue $Config.Firebird "Charset" "UTF8"
        DllPath                 = $Config.Firebird.DllPath
        DllSha256               = Get-ConfigValue $Config.Firebird "DllSha256" $null

        # MSSQL Settings
        MSSQLServer             = $Config.MSSQL.Server
        MSSQLDatabase           = $Config.MSSQL.Database
        MSSQLIntSec             = Get-ConfigValue $Config.MSSQL "Integrated Security" $false
        MSSQLPrefix             = Get-ConfigValue $Config.MSSQL "Prefix" ""
        MSSQLSuffix             = Get-ConfigValue $Config.MSSQL "Suffix" ""

        # Tables
        Tables                  = @($Config.Tables)
        
        # Table Overrides (NEU in v2.10)
        TableOverrides          = @{}

        # Raw Config für Zugriff auf weitere Properties
        RawConfig               = $Config
    }
    
    # TableOverrides laden (falls vorhanden)
    if ($Config.PSObject.Properties.Match("TableOverrides").Count -gt 0 -and $null -ne $Config.TableOverrides) {
        foreach ($prop in $Config.TableOverrides.PSObject.Properties) {
            $Result.TableOverrides[$prop.Name] = @{
                IdColumn        = Get-ConfigValue $prop.Value "IdColumn" $null
                TimestampColumn = Get-ConfigValue $prop.Value "TimestampColumn" $null
            }
        }
    }

    # Validierungen
    if ($Result.GlobalTimeout -le 0) {
        throw "GlobalTimeout muss größer als 0 sein."
    }
    if (-not $Result.Tables -or $Result.Tables.Count -eq 0) {
        throw "Keine Tabellen in der Konfiguration definiert."
    }
    if ($Result.OrphanCleanupBatchSize -lt 1000) {
        throw "OrphanCleanupBatchSize muss mindestens 1000 sein."
    }
    if ($Result.IncrementalOverlapMinutes -lt 0 -or $Result.IncrementalOverlapMinutes -gt 1440) {
        throw "IncrementalOverlapMinutes muss zwischen 0 und 1440 liegen."
    }

    # Identifier-Whitelist (Fail-Fast): alle Namen, die in SQL-Text eingesetzt werden
    foreach ($Table in $Result.Tables) { Assert-SqlIdentifier -Name $Table -Field "Tables" }
    Assert-SqlIdentifier -Name $Result.IdColumn -Field "General.IdColumn"
    foreach ($TsCol in $Result.TimestampColumns) { Assert-SqlIdentifier -Name $TsCol -Field "General.TimestampColumns" }
    Assert-SqlIdentifier -Name $Result.MSSQLDatabase -Field "MSSQL.Database" -AllowEmpty
    Assert-SqlIdentifier -Name $Result.MSSQLPrefix -Field "MSSQL.Prefix" -AllowEmpty
    Assert-SqlIdentifier -Name $Result.MSSQLSuffix -Field "MSSQL.Suffix" -AllowEmpty
    foreach ($Key in $Result.TableOverrides.Keys) {
        Assert-SqlIdentifier -Name $Key -Field "TableOverrides"
        Assert-SqlIdentifier -Name $Result.TableOverrides[$Key].IdColumn -Field "TableOverrides.$Key.IdColumn" -AllowEmpty
        Assert-SqlIdentifier -Name $Result.TableOverrides[$Key].TimestampColumn -Field "TableOverrides.$Key.TimestampColumn" -AllowEmpty
    }
    # SQL Server erlaubt 128 Zeichen pro Name; Ziel = Prefix + Tabelle + Suffix
    foreach ($Table in $Result.Tables) {
        $TargetName = "$($Result.MSSQLPrefix)$Table$($Result.MSSQLSuffix)"
        if ($TargetName.Length -gt 128) {
            throw "Ungültiger Name: Zieltabelle '$TargetName' (MSSQL.Prefix + Tables + MSSQL.Suffix) ist länger als 128 Zeichen."
        }
    }

    return $Result
}

<#
.SYNOPSIS
    Löst den Pfad der Konfigurationsdatei auf (gemeinsam für alle Skripte).

.DESCRIPTION
    Reihenfolge: leer -> <ScriptDir>\config.json; existierender Pfad -> vollständiger Pfad;
    Name relativ zum Skriptordner -> <ScriptDir>\<Name>; sonst unverändert
    (die Fehlermeldung "nicht gefunden" kommt dann aus Get-SQLSyncConfig).
#>
function Resolve-SQLSyncConfigPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$ConfigFile,

        [Parameter(Mandatory)]
        [string]$ScriptDir
    )

    if ([string]::IsNullOrWhiteSpace($ConfigFile)) { return (Join-Path $ScriptDir "config.json") }
    if (Test-Path $ConfigFile -PathType Leaf) { return (Convert-Path $ConfigFile) }
    $InScriptDir = Join-Path $ScriptDir $ConfigFile
    if (Test-Path $InScriptDir -PathType Leaf) { return $InScriptDir }
    return $ConfigFile
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

    # 1. Versuch: Credential Manager (Eintrag aus Firebird.CredentialTarget, Default SQLSync_Firebird)
    $Target = Get-ConfigValue $Config.Firebird "CredentialTarget" "SQLSync_Firebird"
    $Cred = Get-StoredCredential -Target $Target
    if ($Cred) {
        Write-Host "[Credentials] Firebird: Credential Manager ($Target)" -ForegroundColor Green
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

    throw "Keine Firebird Credentials gefunden (Credential-Manager-Eintrag '$Target')! Führe Setup_Credentials.ps1 aus."
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

    # 1. Versuch: Credential Manager (Eintrag aus MSSQL.CredentialTarget, Default SQLSync_MSSQL)
    $Target = Get-ConfigValue $Config.MSSQL "CredentialTarget" "SQLSync_MSSQL"
    $Cred = Get-StoredCredential -Target $Target
    if ($Cred) {
        Write-Host "[Credentials] SQL Server: Credential Manager ($Target)" -ForegroundColor Green
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

    throw "Keine SQL Server Credentials gefunden (Credential-Manager-Eintrag '$Target')! Führe Setup_Credentials.ps1 aus oder aktiviere 'Integrated Security'."
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
        [Parameter(Mandatory)]
        [string]$Server,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        $Password,  # Kein Typ-Constraint - akzeptiert String oder SecureString
        
        [int]$Port = 3050,
        
        [string]$Charset = "UTF8"
    )

    # Falls SecureString übergeben wurde, konvertieren
    $PlainPassword = $Password
    if ($Password -is [System.Security.SecureString]) {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }

    # DbConnectionStringBuilder maskiert Werte mit ; = ' " (sonst bricht z. B. ein Passwort mit ";" den String
    # bzw. kann weitere Schlüssel einschleusen). Schlüsselnamen unverändert.
    $Builder = New-Object System.Data.Common.DbConnectionStringBuilder
    $Builder['User'] = $Username
    $Builder['Password'] = $PlainPassword
    $Builder['Database'] = $Database
    $Builder['DataSource'] = $Server
    $Builder['Port'] = $Port
    $Builder['Dialect'] = 3
    $Builder['Charset'] = $Charset
    return $Builder.ConnectionString
}

<#
.SYNOPSIS
    Erstellt einen MSSQL Connection String.
#>
function New-MSSQLConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [AllowEmptyString()]
        [AllowNull()]
        $Username,
        
        [AllowEmptyString()]
        [AllowNull()]
        $Password,  # Kein Typ-Constraint - akzeptiert String oder SecureString
        
        [bool]$IntegratedSecurity = $false
    )

    if ($IntegratedSecurity) {
        return "Server=$Server;Database=$Database;Integrated Security=True;"
    }
    else {
        # Falls SecureString übergeben wurde, konvertieren
        $PlainPassword = $Password
        if ($Password -is [System.Security.SecureString]) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
        $Builder = New-Object System.Data.Common.DbConnectionStringBuilder
        $Builder['Server'] = $Server
        $Builder['Database'] = $Database
        $Builder['User Id'] = $Username
        $Builder['Password'] = $PlainPassword
        return $Builder.ConnectionString
    }
}

#endregion

#region Firebird Driver

# Gemeinsame Treiberdaten für Initialize-FirebirdDriver und Test-FirebirdDriverIntegrity.
# Bei einem Versionswechsel Version, Download-URL und Hashes gemeinsam anpassen.
$script:FirebirdDriver = @{
    PackageName = "FirebirdSql.Data.FirebirdClient"
    Version     = "10.3.4"
    DownloadUrl = "https://globalcdn.nuget.org/packages/firebirdsql.data.firebirdclient.10.3.4.nupkg"
    # SHA-256 der Original-DLLs aus dem NuGet-Paket 10.3.4 (lib\net8.0 bzw. lib\netstandard2.1)
    KnownSha256 = @(
        "7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05"
        "8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A"
    )
}
$script:FirebirdDriver.CentralInstallDir = "$env:ProgramData\SQLSync\Drivers\$($script:FirebirdDriver.PackageName).$($script:FirebirdDriver.Version)"

<#
.SYNOPSIS
    Liefert den ersten vorhandenen Treiberpfad (DllPath, DllPath relativ zum Skriptordner, zentral net8.0, zentral netstandard2.1) oder $null.
#>
function Get-FirebirdDriverCandidatePath([string]$DllPath, [string]$ScriptDir) {
    $Name = "$($script:FirebirdDriver.PackageName).dll"
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($DllPath)) {
        $Candidates += $DllPath
        if ($ScriptDir) { $Candidates += Join-Path $ScriptDir $DllPath }
    }
    $Candidates += Join-Path $script:FirebirdDriver.CentralInstallDir "lib\net8.0\$Name"
    $Candidates += Join-Path $script:FirebirdDriver.CentralInstallDir "lib\netstandard2.1\$Name"
    foreach ($Path in $Candidates) { if (Test-Path $Path) { return $Path } }
    return $null
}

<#
.SYNOPSIS
    Prüft, ob die aktuelle Sitzung Administratorrechte hat (eigene Funktion, damit in Tests mockbar).
#>
function Test-SQLSyncIsAdministrator {
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
    Lädt den Firebird .NET Treiber (Version 10.3.4) – nur nach SHA-256-Prüfung.
    Installiert ihn bei Bedarf systemweit in C:\ProgramData (benötigt Admin-Rechte).

.DESCRIPTION
    Jede DLL wird vor Add-Type gegen ihren SHA-256 geprüft – egal ob frisch heruntergeladen,
    bereits in %ProgramData% vorhanden oder per DllPath konfiguriert. Zulässig sind die
    Original-Hashes der DLLs lib\net8.0 und lib\netstandard2.1 aus dem NuGet-Paket 10.3.4.
    Eine andere DLL (z. B. andere Treiberversion) wird nur mit explizit erwartetem Hash
    (-ExpectedSha256, Konfig: Firebird.DllSha256) geladen; dann gilt ausschließlich dieser Hash.

.PARAMETER DllPath
    Optional: Ein expliziter Pfad zur DLL (überschreibt die Automatik).
.PARAMETER ScriptDir
    Optional: Skript-Verzeichnis für relative Pfade.
.PARAMETER ExpectedSha256
    Optional: erwarteter SHA-256 der DLL (64 Hex-Zeichen). Ersetzt die eingebauten Original-Hashes.

.OUTPUTS
    Der aufgelöste Pfad zur DLL.
#>
function Initialize-FirebirdDriver {
    [CmdletBinding()]
    param(
        [string]$DllPath,
        [string]$ScriptDir,
        [string]$ExpectedSha256
    )

    # Konstanten auf Modulebene ($script:FirebirdDriver)
    $PackageVersion = $script:FirebirdDriver.Version
    $PackageName = $script:FirebirdDriver.PackageName
    $DownloadUrl = $script:FirebirdDriver.DownloadUrl
    $AllowedSha256 = if ($ExpectedSha256) { @($ExpectedSha256.ToUpperInvariant()) } else { $script:FirebirdDriver.KnownSha256 }
    $CentralInstallDir = $script:FirebirdDriver.CentralInstallDir

    function Assert-DriverHash([string]$Path, [string]$Origin) {
        $Actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
        if ($Actual -notin $AllowedSha256) {
            throw ("SHA-256 der Treiber-DLL ({0}) stimmt nicht: {1} (erhalten {2}, erlaubt {3}). Treiber wurde NICHT geladen." -f $Origin, $Path, $Actual, ($AllowedSha256 -join " / "))
        }
    }

    # --- SCHRITT A: Prüfen, ob Assembly schon geladen ist (Verhindert Fehler) ---
    $LoadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -eq $PackageName } |
    Select-Object -First 1

    if ($LoadedAssembly) {
        Write-Host "[Driver] Firebird .NET Provider ist bereits aktiv (aus Speicher)." -ForegroundColor DarkGray
        # Wir nutzen die Version, die schon da ist, um Konflikte zu vermeiden
        return $LoadedAssembly.Location
    }

    # --- SCHRITT B: Pfad suchen (wenn noch nicht geladen) ---
    $ResolvedPath = Get-FirebirdDriverCandidatePath -DllPath $DllPath -ScriptDir $ScriptDir

    # --- SCHRITT C: Installieren (wenn Datei fehlt) ---
    if (-not $ResolvedPath) {
        Write-Host "Firebird Treiber ($PackageVersion) nicht gefunden." -ForegroundColor Yellow

        if (-not (Test-SQLSyncIsAdministrator)) {
            throw "Der Firebird-Treiber fehlt in $CentralInstallDir. Bitte einmalig als ADMINISTRATOR ausführen."
        }

        Write-Host "Starte systemweiten Download..." -ForegroundColor Cyan
        if (-not (Test-Path $CentralInstallDir)) { New-Item -ItemType Directory -Path $CentralInstallDir -Force | Out-Null }

        $ZipPath = Join-Path $CentralInstallDir "package.zip"
        # Prozessweite Einstellung nur für den Download ändern und danach wiederherstellen
        $PreviousProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -ErrorAction Stop
            Expand-Archive -Path $ZipPath -DestinationPath $CentralInstallDir -Force
            Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue

            # Neu aufgelöster Pfad
            $ResolvedPath = Join-Path $CentralInstallDir "lib\net8.0\$PackageName.dll"
        }
        catch {
            throw "Download fehlgeschlagen: $($_.Exception.Message)"
        }
        finally {
            [Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol
        }

        # Integrität des Downloads prüfen; bei Abweichung den Ordner verwerfen
        try { Assert-DriverHash $ResolvedPath "Download" }
        catch {
            Remove-Item -Path $CentralInstallDir -Recurse -Force -ErrorAction SilentlyContinue
            throw
        }
    }
    else {
        # Vorhandene bzw. konfigurierte DLL: vor dem Laden ebenfalls prüfen (S4)
        Assert-DriverHash $ResolvedPath "vorhanden"
    }

    # --- SCHRITT D: Laden ---
    if (-not $ResolvedPath -or -not (Test-Path $ResolvedPath)) {
        throw "Treiber konnte nicht bereitgestellt werden."
    }

    try {
        Add-Type -Path $ResolvedPath
        Write-Host "[Driver] Firebird .NET Provider geladen (SHA-256 geprüft): $ResolvedPath" -ForegroundColor DarkGray
    }
    catch {
        # Falls Add-Type trotz Vorab-Check fehlschlägt (sehr selten)
        throw "Fehler beim Laden der Assembly ($ResolvedPath): $($_.Exception.Message)"
    }

    return $ResolvedPath
}
#endregion

#region Safe Database Operations

<#
.SYNOPSIS
    Schließt und disposed eine Datenbankverbindung sicher.

.DESCRIPTION
    Kann für beliebige Connection-Objekte verwendet werden.
    Fängt alle Exceptions ab um Folgefehler zu vermeiden.
    Empfohlenes Muster für Verbindungen:

        $Conn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($ConnectionString)
        try {
            $Conn.Open()
            # ... Abfragen ...
        }
        finally {
            Close-DatabaseConnection -Connection $Conn
        }

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
        "Error" { "Red" }
        default { "Gray" }
    }

    Write-Host "[$TableName] $Message" -ForegroundColor $Color
}

#endregion

#region Exit Codes

<#
.SYNOPSIS
    Ermittelt den Exit-Code eines Sync-Laufs aus den Tabellenergebnissen.

.DESCRIPTION
    0  = alle Tabellen erfolgreich (Sanity OK, N/A oder WARNUNG)
    10 = mindestens eine Tabelle mit Status "Fehler", keine Ergebnisse oder weniger
         Ergebnisse als ExpectedTableCount
    11 = keine Tabellenfehler, aber mindestens ein Sanity Check "FEHLER (...)"
         (nur wenn FailOnSanityError aktiv ist)

.PARAMETER Results
    Ergebnisobjekte der Tabellenverarbeitung (Eigenschaften Status, SanityCheck).

.PARAMETER FailOnSanityError
    Ob ein Sanity "FEHLER" (Ziel hat weniger Zeilen als Quelle) zu Exit 11 führt.
#>
function Get-SyncExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results,

        [bool]$FailOnSanityError = $true,

        [int]$ExpectedTableCount = 0
    )

    # Fehlende Ergebnisse (z. B. Abbruch eines Parallel-Blocks außerhalb seines try) zählen als Tabellenfehler
    if ($Results.Count -eq 0 -or $Results.Count -lt $ExpectedTableCount) { return 10 }
    if ($Results | Where-Object { $_.Status -ne "Erfolg" }) { return 10 }
    if ($FailOnSanityError -and ($Results | Where-Object { "$($_.SanityCheck)" -like "FEHLER*" })) { return 11 }
    return 0
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

        [int]$Size = 0,

        # NumericPrecision/NumericScale aus GetSchemaTable (können DBNull sein)
        [object]$Precision = $null,

        [object]$Scale = $null
    )

    switch ($DotNetTypeName) {
        "Int16" { return "SMALLINT" }
        "Int32" { return "INT" }
        "Int64" { return "BIGINT" }
        "String" { 
            if ($Size -gt 0 -and $Size -le 4000) { 
                return "NVARCHAR($Size)" 
            } 
            else { 
                return "NVARCHAR(MAX)" 
            } 
        }
        "DateTime" { return "DATETIME2" }
        "TimeSpan" { return "TIME" }
        "Decimal" {
            # Precision/Scale aus dem Firebird-Schema übernehmen (SQL Server: max. 38).
            # Ohne Schema-Info bleibt der bisherige Fallback DECIMAL(18,4).
            $P = if ($null -ne $Precision -and $Precision -isnot [DBNull]) { [int]$Precision } else { 0 }
            $S = if ($null -ne $Scale -and $Scale -isnot [DBNull]) { [int]$Scale } else { -1 }
            if ($P -le 0 -and $S -lt 0) { return "DECIMAL(18,4)" }
            if ($P -le 0) { $P = 38 }
            $P = [Math]::Min($P, 38)
            $S = [Math]::Min([Math]::Max($S, 0), $P)
            return "DECIMAL($P,$S)"
        }
        "Double" { return "FLOAT" }
        "Single" { return "REAL" }
        "Byte[]" { return "VARBINARY(MAX)" }
        "Boolean" { return "BIT" }
        "Guid" { return "UNIQUEIDENTIFIER" }
        default { return "NVARCHAR(MAX)" }
    }
}

#endregion

#region Table Column Configuration

<#
.SYNOPSIS
    Ermittelt die ID- und Timestamp-Spalten für eine Tabelle.

.DESCRIPTION
    Diese Funktion kapselt die gesamte Logik zur Ermittlung der richtigen
    Spalten für die Sync-Strategie:
    1. Prüft TableOverrides für tabellenspezifische Konfiguration
    2. Fällt auf globale Defaults zurück
    3. Prüft welche Spalten tatsächlich in der Tabelle existieren
    4. Leitet die Sync-Strategie ab

.PARAMETER TableName
    Name der zu prüfenden Tabelle.

.PARAMETER Config
    Das Config-Objekt aus Get-SQLSyncConfig.

.PARAMETER ActualColumns
    Array mit den tatsächlichen Spaltennamen der Tabelle.

.OUTPUTS
    Hashtable mit:
    - IdColumn: Name der ID-Spalte (oder $null)
    - TimestampColumn: Name der Timestamp-Spalte (oder $null)
    - HasId: Boolean ob ID-Spalte vorhanden
    - HasTimestamp: Boolean ob Timestamp-Spalte vorhanden
    - SyncStrategy: "Incremental", "FullMerge" oder "Snapshot"
    - IsOverride: Boolean ob Override verwendet wurde

.EXAMPLE
    $colConfig = Get-TableColumnConfig -TableName "BKUNDE" -Config $Config -ActualColumns @("ID", "NAME", "GESPEICHERT")
    # Returns: @{ IdColumn = "ID"; TimestampColumn = "GESPEICHERT"; HasId = $true; HasTimestamp = $true; SyncStrategy = "Incremental" }

.EXAMPLE
    # Mit Override in der Config:
    # "TableOverrides": { "LEGACY_ORDERS": { "IdColumn": "ORDER_ID", "TimestampColumn": "CHANGED_AT" } }
    $colConfig = Get-TableColumnConfig -TableName "LEGACY_ORDERS" -Config $Config -ActualColumns @("ORDER_ID", "NAME", "CHANGED_AT")
    # Returns: @{ IdColumn = "ORDER_ID"; TimestampColumn = "CHANGED_AT"; ... }
#>
function Get-TableColumnConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TableName,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string[]]$ActualColumns
    )

    # Defaults aus Config
    $DefaultIdColumn = $Config.IdColumn
    $DefaultTimestampColumns = $Config.TimestampColumns
    
    # Override prüfen
    $Override = $null
    $IsOverride = $false
    if ($Config.TableOverrides.ContainsKey($TableName)) {
        $Override = $Config.TableOverrides[$TableName]
        $IsOverride = $true
    }
    
    # ID-Spalte bestimmen
    $IdColumn = if ($Override -and $Override.IdColumn) { 
        $Override.IdColumn 
    }
    else { 
        $DefaultIdColumn 
    }
    
    # Timestamp-Spalte bestimmen
    $TimestampColumn = $null
    if ($Override -and $Override.TimestampColumn) {
        # Override hat explizite Timestamp-Spalte
        $TimestampColumn = $Override.TimestampColumn
    }
    else {
        # Erste gefundene aus der TimestampColumns-Liste verwenden
        foreach ($tsCol in $DefaultTimestampColumns) {
            if ($tsCol -in $ActualColumns) {
                $TimestampColumn = $tsCol
                break
            }
        }
    }
    
    # Prüfen ob Spalten existieren
    $HasId = $IdColumn -in $ActualColumns
    $HasTimestamp = $null -ne $TimestampColumn -and $TimestampColumn -in $ActualColumns
    
    # Strategie ableiten
    $SyncStrategy = "Incremental"
    if (-not $HasId) {
        $SyncStrategy = "Snapshot"
    }
    elseif (-not $HasTimestamp) {
        $SyncStrategy = "FullMerge"
    }
    
    return @{
        IdColumn        = if ($HasId) { $IdColumn } else { $null }
        TimestampColumn = if ($HasTimestamp) { $TimestampColumn } else { $null }
        HasId           = $HasId
        HasTimestamp    = $HasTimestamp
        SyncStrategy    = $SyncStrategy
        IsOverride      = $IsOverride
    }
}

#endregion

#region Security Helpers

<#
.SYNOPSIS
    Prüft einen Tabellen-/Spaltennamen (oder Namensteil) gegen die Whitelist ^[A-Za-z0-9_$]+$.

.DESCRIPTION
    Namen aus der Konfiguration bzw. aus Firebird-Metadaten werden in SQL-Text eingesetzt
    (Firebird "..." / SQL Server [...]). Die Whitelist schließt Quote-, Klammer-, Semikolon-
    und Leerzeichen aus, die maximale Länge folgt dem Firebird-Limit (63 Zeichen).
    Bei Verstoß wird geworfen (Fail-Fast) – die Meldung nennt das Konfigurationsfeld.

.PARAMETER Name
    Zu prüfender Name.

.PARAMETER Field
    Konfigurationsfeld für die Fehlermeldung (z. B. "Tables", "MSSQL.Prefix").

.PARAMETER AllowEmpty
    Leerstring zulassen (für Prefix/Suffix).
#>
function Assert-SqlIdentifier {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Field,

        [switch]$AllowEmpty
    )

    if ([string]::IsNullOrEmpty($Name)) {
        if ($AllowEmpty) { return }
        throw "Ungültiger Name in '$Field': leer."
    }
    if ($Name.Length -gt 63) {
        throw "Ungültiger Name in '$Field': '$Name' ist länger als 63 Zeichen."
    }
    if ($Name -cnotmatch '^[A-Za-z0-9_$]+$') {
        throw "Ungültiger Name in '$Field': '$Name' (erlaubt sind nur A-Z, a-z, 0-9, _ und `$)."
    }
}

<#
.SYNOPSIS
    Escaped Strings für die Verwendung in Firebird SQL-Statements.
.DESCRIPTION
    Verdoppelt einfache Anführungszeichen, um SQL-Injection und Syntaxfehler zu verhindern.
    Gibt bei leerem Input einen leeren String zurück (kein Fehler), um auch optionale Felder zu unterstützen.
#>
function Protect-SqlString {
    param([string]$InputString)
    
    if ([string]::IsNullOrEmpty($InputString)) { 
        return "" 
    }
    
    # Firebird (und SQL Server) escapen einfache Anführungszeichen durch Verdopplung
    return $InputString -replace "'", "''"
}

#endregion

#region Rollout-Check (I11)

# Firebird-Server-Advisories mit den jeweils ersten behobenen Versionen je Hauptversion
# (Quelle: NVD, abgerufen 2026-10-08/09). Versionen unter 3 gelten als betroffen, über 5 als nicht betroffen.
$script:FirebirdServerAdvisories = @(
    @{ Id = "CVE-2026-34232"; Cvss = "7.5"; Summary = "unauthentifizierter Server-Absturz (op_response)"; Fixed = @{ 3 = "3.0.14"; 4 = "4.0.7"; 5 = "5.0.4" } }
    @{ Id = "CVE-2026-40342"; Cvss = "9.9"; Summary = "Codeausführung über CREATE FUNCTION (ENGINE-Pfad)"; Fixed = @{ 3 = "3.0.14"; 4 = "4.0.7"; 5 = "5.0.4" } }
)

<#
.SYNOPSIS
    Liefert die bekannten Server-Advisories, von denen eine Firebird-Version betroffen ist.

.PARAMETER EngineVersion
    Wert von rdb$get_context('SYSTEM','ENGINE_VERSION'), z. B. "5.0.3".

.OUTPUTS
    PSCustomObject je betroffener CVE (Id, Cvss, Summary, FixedIn); bei unlesbarer Version ein Eintrag VERSION-UNBEKANNT.
#>
function Get-FirebirdServerAdvisory {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$EngineVersion)

    $Match = [regex]::Match("$EngineVersion", '(\d+)\.(\d+)\.(\d+)')
    if (-not $Match.Success) {
        return [PSCustomObject]@{ Id = "VERSION-UNBEKANNT"; Cvss = ""; Summary = "Serverversion '$EngineVersion' nicht auswertbar – manuell prüfen"; FixedIn = "" }
    }
    $Version = [version]$Match.Value
    foreach ($Advisory in $script:FirebirdServerAdvisories) {
        $Fixed = $Advisory.Fixed[$Version.Major]
        $Affected = if ($Fixed) { $Version -lt [version]$Fixed } else { $Version.Major -lt 3 }
        if ($Affected) {
            [PSCustomObject]@{ Id = $Advisory.Id; Cvss = $Advisory.Cvss; Summary = $Advisory.Summary; FixedIn = ($Advisory.Fixed.Values | Sort-Object) -join " / " }
        }
    }
}

<#
.SYNOPSIS
    Findet Zielspalten, deren DECIMAL-Typ Werte der Firebird-Quelle kürzen würde (Altbestand vor v2.14).

.PARAMETER SourceColumns
    Objekte mit Table, Column, Precision, Scale (Firebird, Tabellenname ohne Prefix/Suffix).
.PARAMETER TargetColumns
    Objekte mit Table, Column, Precision, Scale (SQL Server, Zieltabellenname).

.OUTPUTS
    PSCustomObject je betroffener Spalte (Table, Target, Column, Source, TargetType).
#>
function Find-SQLSyncDecimalTruncation {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$SourceColumns = @(),
        [AllowEmptyCollection()][object[]]$TargetColumns = @(),
        [AllowEmptyString()][string]$Prefix = "",
        [AllowEmptyString()][string]$Suffix = ""
    )

    $TargetIndex = @{}
    foreach ($c in $TargetColumns) { $TargetIndex["$($c.Table)|$($c.Column)".ToUpperInvariant()] = $c }

    foreach ($s in $SourceColumns) {
        $TargetName = "$Prefix$($s.Table)$Suffix"
        $t = $TargetIndex["$TargetName|$($s.Column)".ToUpperInvariant()]
        if (-not $t) { continue }   # Zieltabelle/-spalte existiert (noch) nicht -> wird korrekt neu angelegt
        if ([int]$t.Scale -lt [int]$s.Scale -or [int]$t.Precision -lt [int]$s.Precision) {
            [PSCustomObject]@{
                Table      = $s.Table
                Target     = $t.Table
                Column     = $s.Column
                Source     = "NUMERIC($($s.Precision),$($s.Scale))"
                TargetType = "DECIMAL($($t.Precision),$($t.Scale))"
            }
        }
    }
}

<#
.SYNOPSIS
    Prüft die Treiber-DLL wie Initialize-FirebirdDriver, lädt sie aber nicht.

.OUTPUTS
    PSCustomObject mit Status (OK | FEHLER | FEHLT), Path, Sha256, Message.
#>
function Test-FirebirdDriverIntegrity {
    [CmdletBinding()]
    param(
        [string]$DllPath,
        [string]$ScriptDir,
        [string]$ExpectedSha256
    )

    $Allowed = if ($ExpectedSha256) { @($ExpectedSha256.ToUpperInvariant()) } else { $script:FirebirdDriver.KnownSha256 }
    $Path = Get-FirebirdDriverCandidatePath -DllPath $DllPath -ScriptDir $ScriptDir
    if (-not $Path) {
        return [PSCustomObject]@{ Status = "FEHLT"; Path = $null; Sha256 = $null; Message = "Keine Treiber-DLL gefunden (wird beim ersten Lauf als Administrator heruntergeladen)" }
    }
    $Hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    if ($Hash -in $Allowed) {
        return [PSCustomObject]@{ Status = "OK"; Path = $Path; Sha256 = $Hash; Message = "SHA-256 entspricht der erlaubten Liste" }
    }
    return [PSCustomObject]@{ Status = "FEHLER"; Path = $Path; Sha256 = $Hash; Message = "SHA-256 nicht erlaubt (erlaubt: $($Allowed -join ' / '))" }
}

#endregion

#region Incremental Extract (I8)

<#
.SYNOPSIS
    Berechnet die Untergrenze des Incremental-Extrakts: Wasserzeichen minus Überlappungsfenster.

.DESCRIPTION
    Ohne Wasserzeichen (Zieltabelle fehlt oder ist leer) wird ab 1900-01-01 gelesen (Vollabzug).
    Das Überlappungsfenster holt Datensätze nach, die mit einem Zeitstempel <= Wasserzeichen erst nach dem
    letzten Lauf committet wurden (K3). Doppelt gelesene Zeilen sind unkritisch, der MERGE ist idempotent.

.PARAMETER Watermark
    MAX(Zeitstempel) der Zieltabelle oder $null.
.PARAMETER OverlapMinutes
    General.IncrementalOverlapMinutes (>= 0).
#>
function Get-SQLSyncIncrementalLowerBound {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Nullable[datetime]]$Watermark,
        [Parameter(Mandatory)][ValidateRange(0, [int]::MaxValue)][int]$OverlapMinutes
    )

    if ($null -eq $Watermark) { return [datetime]'1900-01-01' }
    return $Watermark.AddMinutes(-$OverlapMinutes)
}

<#
.SYNOPSIS
    Liest das Wasserzeichen (MAX der Zeitstempelspalte) der Zieltabelle.

.DESCRIPTION
    Fehlt die Zieltabelle (Erstlauf) oder ist sie leer, ist Watermark $null und Reason nennt den Grund.
    Scheitert die Abfrage auf eine vorhandene Tabelle (z. B. Zeitstempelspalte fehlt im Ziel), wird
    geworfen – bis v2.16 führte das still zu einem Vollabzug.

.PARAMETER Connection
    Geöffnete SqlConnection (oder ein Objekt mit CreateCommand()).

.OUTPUTS
    PSCustomObject mit Watermark ([datetime] oder $null) und Reason (leer oder Begründung des Vollabzugs).
#>
function Get-SQLSyncIncrementalWatermark {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Connection,
        [Parameter(Mandatory)][string]$TargetTableName,
        [Parameter(Mandatory)][string]$TimestampColumn,
        [int]$Timeout = 30
    )

    # Zielname = Prefix + Tabelle + Suffix: gleiche Zeichen wie die Whitelist, aber bis 128 Zeichen (SQL Server)
    if ($TargetTableName -cnotmatch '^[A-Za-z0-9_$]{1,128}$') { throw "Ungültiger Name in 'Zieltabelle': '$TargetTableName'." }
    Assert-SqlIdentifier -Name $TimestampColumn -Field "Zeitstempelspalte"

    $CheckCmd = $Connection.CreateCommand()
    $CheckCmd.CommandTimeout = $Timeout
    $CheckCmd.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @TableName"
    [void]$CheckCmd.Parameters.AddWithValue("@TableName", $TargetTableName)
    if (-not ($CheckCmd.ExecuteScalar() -gt 0)) {
        return [PSCustomObject]@{ Watermark = $null; Reason = "Erstlauf (Zieltabelle fehlt) - Vollabzug" }
    }

    $MaxCmd = $Connection.CreateCommand()
    $MaxCmd.CommandTimeout = $Timeout
    $MaxCmd.CommandText = "SELECT MAX([$TimestampColumn]) FROM [$TargetTableName]"
    $Value = $MaxCmd.ExecuteScalar()
    if ($null -eq $Value -or $Value -is [DBNull]) {
        return [PSCustomObject]@{ Watermark = $null; Reason = "Kein Wasserzeichen (Zieltabelle leer oder Zeitstempel NULL) - Vollabzug" }
    }
    return [PSCustomObject]@{ Watermark = [datetime]$Value; Reason = "" }
}

<#
.SYNOPSIS
    Liefert die Firebird-Extrakt-Abfrage (Vollabzug oder inkrementell ab @LastDate inklusive).
#>
function Get-SQLSyncExtractQuery {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$TableName,
        [string]$TimestampColumn,
        [switch]$Incremental
    )

    Assert-SqlIdentifier -Name $TableName -Field "Tabelle"
    if (-not $Incremental) { return "SELECT * FROM ""$TableName""" }
    Assert-SqlIdentifier -Name $TimestampColumn -Field "Zeitstempelspalte"
    return "SELECT * FROM ""$TableName"" WHERE ""$TimestampColumn"" >= @LastDate"
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
    'Get-TableColumnConfig'
    'Resolve-SQLSyncConfigPath'
    
    # Connection Strings
    'New-FirebirdConnectionString'
    'New-MSSQLConnectionString'
    
    # Driver
    'Initialize-FirebirdDriver'
    
    # Safe Operations
    # HINWEIS: Invoke-WithFirebirdConnection und Invoke-WithMSSQLConnection wurden entfernt
    # (auch aus dem Code), da $using: in normalen ScriptBlocks nicht funktioniert.
    # Stattdessen direkt try/finally mit Close-DatabaseConnection verwenden (Beispiel dort).
    'Close-DatabaseConnection'
    
    # Helpers
    'Write-SyncStatus'
    'Get-SyncExitCode'
    'ConvertTo-SqlServerType'
    'Protect-SqlString'
    'Assert-SqlIdentifier'
    'Get-FirebirdServerAdvisory'
    'Find-SQLSyncDecimalTruncation'
    'Test-FirebirdDriverIntegrity'
    'Get-SQLSyncIncrementalLowerBound'
    'Get-SQLSyncIncrementalWatermark'
    'Get-SQLSyncExtractQuery'
)
