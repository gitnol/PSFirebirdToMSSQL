#Requires -Version 7.0

<#
.SYNOPSIS
    Testet die Verbindung zu einer Firebird-Datenbank mittels .NET FirebirdClient.dll.

.DESCRIPTION
    Features:
    - Lädt die FirebirdClient.dll dynamisch.
    - Verbindet sich zur Firebird-Datenbank mit konfigurierbaren Parametern.
    - Führt eine einfache Abfrage aus und gibt die Ergebnisse aus.

    

.PARAMETER ConfigFile
    Optional. Der Pfad zur JSON-Konfigurationsdatei.
    Standard: "config.json" im Skript-Verzeichnis.
.EXAMPLE
    .\test_dotnet_firebird.ps1
    Verwendet die Standard-Konfigurationsdatei im Skript-Verzeichnis.

    .\test_dotnet_firebird.ps1 config.json
    
.NOTES
    Version: 1.1 (Prod)
    
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

Write-Host "Konfiguration geladen. Tabellen: $($Tabellen.Count). Retries: $MaxRetries" -ForegroundColor Cyan


# # Variablen aus Config zuweisen
# $FBservername = $Config.Firebird.Server
# $FBpassword = $Config.Firebird.Password
# $FBdatabase = $Config.Firebird.Database
# $FBport = $Config.Firebird.Port
# $FBcharset = $Config.Firebird.Charset
# $DllPath = $Config.Firebird.DllPath

# -----------------------------------------------------------------------------
# PRÜFUNG & INSTALLATION PAKET
# -----------------------------------------------------------------------------

if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue) -and (-not (Test-Path $DllPath))) {
    Write-Host "FirebirdSql.Data.FirebirdClient ist nicht installiert." -ForegroundColor Red
    Write-Host "Installiere FirebirdSql.Data.FirebirdClient..." -ForegroundColor Yellow
    Install-Package FirebirdSql.Data.FirebirdClient -Force -Confirm:$false
    Write-Host "FirebirdSql.Data.FirebirdClient installiert." -ForegroundColor Green
}
else {
    Write-Host "FirebirdSql.Data.FirebirdClient ist bereits installiert." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# HAUPTLOGIK
# -----------------------------------------------------------------------------

try {
    # Schritt 1 - Assembly laden
    if (-not (Test-Path $DllPath)) {
        # Fallback: Versuche den Pfad dynamisch zu finden, falls in Config falsch
        Write-Host "DLL laut Config nicht gefunden. Suche im Standardpfad..." -ForegroundColor Yellow
        $SuchPfad = "C:\Program Files\PackageManagement\NuGet\Packages"
        $GefundeneDll = Get-ChildItem -Path $SuchPfad -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($GefundeneDll) {
            $DllPath = $GefundeneDll.FullName
            Write-Host "DLL automatisch gefunden: $($DllPath)" -ForegroundColor Cyan
        }
        else {
            Throw "Die DLL wurde weder unter dem konfigurierten Pfad noch automatisch gefunden."
        }
    }
    
    Add-Type -Path $DllPath
    Write-Host "Treiber geladen ($DllPath)"

    # Schritt 2 - Verbindung aufbauen
    # Connection String wird nun mit Variablen aus der Config gebaut
    # $FirebirdConnString = "User=SYSDBA;Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"

    $FbConnection = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FirebirdConnString)
    $FbConnection.Open()
    
    Write-Host "Verbindung zu $($FBservername) erfolgreich hergestellt." -ForegroundColor Green

    # Schritt 3 - Abfrage ausführen
    $Query = "SELECT FIRST 1 ID FROM BSA"
    
    $Command = $FbConnection.CreateCommand()
    $Command.CommandText = $Query
    
    $Result = $Command.ExecuteScalar()

    # Schritt 4 - Ergebnis prüfen
    if ($null -ne $Result) {
        Write-Host "Test erfolgreich! Gelesene ID aus BSA: $($Result)" -ForegroundColor Cyan
    }
    else {
        Write-Host "Verbindung OK, aber keine Daten in Tabelle BSA gefunden." -ForegroundColor Yellow
    }

    # Verbindung schließen
    $FbConnection.Close()

}
catch {
    Write-Error "Ein Fehler ist aufgetreten: $($_.Exception.Message)"
    if ($_.Exception.InnerException) {
        Write-Error "Details: $($_.Exception.InnerException.Message)"
    }
}

$TotalStopwatch.Stop()
Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "GESAMTLAUFZEIT: $($TotalStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green
Write-Host "LOGDATEI: $LogFile" -ForegroundColor Gray
Write-Host "--------------------------------------------------------" -ForegroundColor Gray 

Stop-Transcript