# -----------------------------------------------------------------------------
# SQL SERVER INITIALISIERUNG
# -----------------------------------------------------------------------------
# Dieses Skript liest die config.json und bereitet den SQL Server vor:
# 1. Erstellt die Datenbank (falls nicht vorhanden).
# 2. Setzt Recovery Mode auf SIMPLE.
# 3. Installiert/Aktualisiert die Stored Procedure sp_Merge_Generic.

param(
    [string]$ConfigFile = "config.json"
)

$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir $ConfigFile
$SqlFile = Join-Path $ScriptDir "sp_Merge_Generic.sql"

# 1. Config laden
if (-not (Test-Path $ConfigPath)) { Write-Error "Config '$ConfigPath' fehlt!"; exit }
if (-not (Test-Path $SqlFile)) { Write-Error "SQL Datei '$SqlFile' fehlt!"; exit }

$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

$Server = $Config.MSSQL.Server
$Database = $Config.MSSQL.Database
$IntegratedSecurity = $Config.MSSQL."Integrated Security"

# Connection String für MASTER (um DB zu erstellen)
if ($IntegratedSecurity) {
    $MasterConnStr = "Server=$Server;Database=master;Integrated Security=True;"
}
else {
    # Hinweis: Hier vereinfacht ohne Credential Manager für das Setup-Skript
    # Falls nötig, kopiere die Get-StoredCredential Funktion hier rein.
    $User = $Config.MSSQL.Username
    $Pass = $Config.MSSQL.Password
    $MasterConnStr = "Server=$Server;Database=master;User Id=$User;Password=$Pass;"
}

try {
    Write-Host "Verbinde mit SQL Server '$Server'..." -ForegroundColor Cyan
    $Conn = New-Object System.Data.SqlClient.SqlConnection($MasterConnStr)
    $Conn.Open()

    # 2. Datenbank erstellen
    $Cmd = $Conn.CreateCommand()
    $Cmd.CommandText = "SELECT COUNT(*) FROM sys.databases WHERE name = '$Database'"
    if ($Cmd.ExecuteScalar() -eq 0) {
        Write-Host "Datenbank '$Database' existiert nicht. Erstelle..." -ForegroundColor Yellow
        $Cmd.CommandText = "CREATE DATABASE [$Database]"
        $Cmd.ExecuteNonQuery()
        Write-Host "Datenbank erstellt." -ForegroundColor Green
        
        # Recovery Simple setzen (Best Practice für Staging)
        $Cmd.CommandText = "ALTER DATABASE [$Database] SET RECOVERY SIMPLE"
        $Cmd.ExecuteNonQuery()
    }
    else {
        Write-Host "Datenbank '$Database' existiert bereits." -ForegroundColor Green
    }
    $Conn.Close()

    # 3. Prozedur installieren (In der Ziel-DB)
    # Wir passen den Connection String auf die Ziel-DB an
    $TargetConnStr = $MasterConnStr.Replace("Database=master", "Database=$Database")
    $Conn = New-Object System.Data.SqlClient.SqlConnection($TargetConnStr)
    $Conn.Open()

    $SqlContent = Get-Content -Path $SqlFile -Raw
    
    Write-Host "Installiere 'sp_Merge_Generic' in '$Database'..." -ForegroundColor Cyan
    $Cmd = $Conn.CreateCommand()
    $Cmd.CommandText = $SqlContent
    $Cmd.ExecuteNonQuery()
    
    Write-Host "Erfolgreich abgeschlossen." -ForegroundColor Green
    $Conn.Close()

}
catch {
    Write-Error "Fehler bei der Initialisierung: $($_.Exception.Message)"
}