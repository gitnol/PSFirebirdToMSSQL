# Konfigurationsdatei einlesen
$ConfigPath = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Die Konfigurationsdatei 'config.json' wurde nicht gefunden."
    Write-Host "Bitte kopieren Sie 'config.sample.json' nach 'config.json' und tragen Sie Ihre Werte ein." -ForegroundColor Yellow
    exit
}

# JSON parsen
try {
    $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Fehler beim Lesen der 'config.json'. Ist das JSON-Format valide?"
    exit
}

# Variablen aus Config zuweisen
$FBservername = $Config.Firebird.Server
$FBpassword = $Config.Firebird.Password
$FBdatabase = $Config.Firebird.Database
$FBport = $Config.Firebird.Port
$FBcharset = $Config.Firebird.Charset
$DllPath = $Config.Firebird.DllPath

# -----------------------------------------------------------------------------
# PRÜFUNG & INSTALLATION PAKET
# -----------------------------------------------------------------------------

if (-not (Get-Package FirebirdSql.Data.FirebirdClient -ErrorAction SilentlyContinue)) {
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
    $FirebirdConnString = "User=SYSDBA;Password=$($FBpassword);Database=$($FBdatabase);DataSource=$($FBservername);Port=$($FBport);Dialect=3;Charset=$($FBcharset);"

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